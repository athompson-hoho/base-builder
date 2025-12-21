--[[
  CC-Remote Agent

  Lua agent for CC:Tweaked machines (turtles, computers, pocket computers).
  Connects to cc-remote-server via WebSocket for remote debugging and control.

  Features:
  - WebSocket connection to server
  - Token-based authentication
  - Print/error interception and streaming (Story 2.1-2.2)
  - Remote code execution via load() (Story 3.2)
  - Heartbeat for liveness detection (Story 1.4)
  - Auto-reconnect with exponential backoff (Story 5.1)

  Usage:
    1. Download: wget http://server:3000/install/TOKEN agent.lua
    2. Run: agent
    3. (Optional) Install startup: agent --install-startup
--]]

-- Configuration (embedded by installer - replaced during download)
local CONFIG = {
  server_url = "ws://localhost:3000",
  token = "YOUR_TOKEN_HERE",
  heartbeat_interval = 10,
  buffer_size = 100,
  reconnect_max_backoff = 60
}

-- ============================================================================
-- Utility Functions
-- ============================================================================

--- Get the machine type (turtle, computer, or pocket)
local function getMachineType()
  if turtle then
    return "turtle"
  elseif pocket then
    return "pocket"
  else
    return "computer"
  end
end

--- Get the machine ID in format "{type}_{computerID}"
local function getMachineId()
  return getMachineType() .. "_" .. os.getComputerID()
end

--- Get fuel information (for turtles only)
local function getFuelInfo()
  if not turtle then
    return nil, nil
  end
  return turtle.getFuelLevel(), turtle.getFuelLimit()
end

--- Safe JSON encode using textutils
local function jsonEncode(data)
  return textutils.serialiseJSON(data)
end

--- Safe JSON decode using textutils
local function jsonDecode(text)
  if not text then
    return nil, "No data to decode"
  end
  local ok, result = pcall(textutils.unserialiseJSON, text)
  if ok then
    return result, nil
  else
    return nil, "Invalid JSON: " .. tostring(result)
  end
end

--- Print with prefix (uses originalPrint to avoid infinite recursion after capture setup)
-- Note: Agent's own log messages are NOT captured to avoid flooding the console buffer
-- with agent internal messages. Only user program output is captured.
local function log(level, message)
  local prefix = "[cc-remote]"
  if level == "error" then
    prefix = "[cc-remote] ERROR:"
  elseif level == "warn" then
    prefix = "[cc-remote] WARN:"
  end
  -- Use originalPrint if available (after print capture setup), otherwise use print
  local printFn = originalPrint or print
  printFn(prefix .. " " .. tostring(message))
end

-- ============================================================================
-- Connection State
-- ============================================================================

local ws = nil              -- WebSocket connection handle
local running = true        -- Main loop flag
local connected = false     -- Connection status
local machineId = nil       -- Our machine ID
local machineType = nil     -- Our machine type
local heartbeatTimer = nil  -- Timer ID for heartbeat
local console_buffer = {}   -- Ring buffer for captured console output

-- ============================================================================
-- Print Capture System (Story 2.1)
-- ============================================================================

-- Store original print function BEFORE any override
local originalPrint = _G.print

--- Format print arguments into tab-separated string (matches CC:Tweaked behavior)
-- @param ... Variable arguments passed to print()
-- @return string The formatted output string
local function formatPrintArgs(...)
  local argc = select("#", ...)
  if argc == 0 then
    return ""
  end

  local args = {...}
  local parts = {}
  for i = 1, argc do
    parts[i] = tostring(args[i])
  end
  return table.concat(parts, "\t")
end

--- Add a line to the console buffer (ring buffer with max size)
-- @param text string The captured text
-- @param level string The log level ("info", "error", "warn")
local function addToConsoleBuffer(text, level)
  local line = {
    text = text,
    timestamp = os.epoch("utc"),  -- Milliseconds
    level = level or "info"
  }

  table.insert(console_buffer, line)

  -- Ring buffer: remove oldest if exceeding max size
  if #console_buffer > CONFIG.buffer_size then
    table.remove(console_buffer, 1)
  end
end

--- Send console buffer to server
-- Sends all buffered lines and clears the buffer on success
local function sendConsole()
  if not ws or not connected then
    return
  end

  if #console_buffer == 0 then
    return
  end

  -- Copy buffer and clear it
  local linesToSend = {}
  for i, line in ipairs(console_buffer) do
    linesToSend[i] = line
  end

  local message = {
    type = "console",
    lines = linesToSend
  }

  local json = jsonEncode(message)
  if json then
    local ok = pcall(function()
      ws.send(json)
    end)

    if ok then
      -- Clear buffer after successful send
      console_buffer = {}
    end
  end
end

--- Capture print output (wrapper around original print)
-- Captures output to buffer and calls original print so output still shows on screen
local function capturedPrint(...)
  -- Format the arguments
  local text = formatPrintArgs(...)

  -- Add to buffer with timestamp
  addToConsoleBuffer(text, "info")

  -- Send immediately if connected (batching is Story 2.3)
  sendConsole()

  -- Call original print so output still displays on screen
  return originalPrint(...)
end

--- Setup print capture by overriding _G.print
-- Must be called AFTER storing originalPrint
local function setupPrintCapture()
  _G.print = capturedPrint
end

--- Restore original print function (for cleanup)
local function restorePrint()
  _G.print = originalPrint
end

-- ============================================================================
-- Authentication
-- ============================================================================

--- Build authentication message
local function buildAuthMessage()
  local fuelLevel, fuelLimit = getFuelInfo()

  return {
    type = "auth",
    token = CONFIG.token,
    machine_id = machineId,
    label = os.getComputerLabel(),
    machine_type = machineType,
    fuel_level = fuelLevel,
    fuel_limit = fuelLimit
  }
end

--- Send authentication message
local function authenticate()
  if not ws then
    return false, "No connection"
  end

  local authMsg = buildAuthMessage()
  local json = jsonEncode(authMsg)

  if not json then
    return false, "Failed to encode auth message"
  end

  ws.send(json)
  log("info", "Authenticating as " .. machineId .. "...")

  -- Wait for acknowledgment (with timeout)
  local startTime = os.clock()
  local timeout = 10 -- seconds

  while os.clock() - startTime < timeout do
    local event, url, msg = os.pullEvent()

    if event == "websocket_message" and url == CONFIG.server_url then
      local response, err = jsonDecode(msg)
      if err then
        return false, "Invalid server response: " .. err
      end

      if response.type == "ack" then
        return true, response.message or "Authenticated"
      elseif response.type == "error" then
        return false, response.message or ("Error code: " .. tostring(response.code))
      end
    elseif event == "websocket_closed" then
      return false, "Connection closed during authentication"
    elseif event == "terminate" then
      running = false
      return false, "Terminated by user"
    end
  end

  return false, "Authentication timeout"
end

-- ============================================================================
-- Connection Management
-- ============================================================================

--- Display troubleshooting hints
local function showTroubleshootingHints(errorMsg)
  log("error", errorMsg)
  print("[cc-remote] Troubleshooting:")
  print("  - Is the server running? (npm start on your computer)")
  print("  - Is the URL correct? (" .. CONFIG.server_url .. ")")
  print("  - Can this computer reach the network?")
  print("  - Is the token valid? (check server logs)")
end

--- Connect to the server
local function connect()
  log("info", "Connecting to " .. CONFIG.server_url .. "...")

  -- Attempt WebSocket connection
  local handle, err = http.websocket(CONFIG.server_url)

  if not handle then
    return false, err or "Connection failed"
  end

  ws = handle

  -- Authenticate
  local authOk, authErr = authenticate()
  if not authOk then
    if ws then
      ws.close()
      ws = nil
    end
    return false, authErr or "Authentication failed"
  end

  connected = true
  log("info", "Connected! Machine ID: " .. machineId)

  -- Start heartbeat timer
  startHeartbeatTimer()

  return true
end

--- Disconnect from the server
local function disconnect(reason)
  if ws then
    -- Try to send disconnect message
    pcall(function()
      ws.send(jsonEncode({
        type = "disconnect",
        reason = reason or "Client disconnect"
      }))
    end)

    pcall(function()
      ws.close()
    end)

    ws = nil
  end

  connected = false
  log("info", "Disconnected" .. (reason and (": " .. reason) or ""))
end

-- ============================================================================
-- Message Handling
-- ============================================================================

--- Handle incoming message from server
local function handleMessage(msg)
  local data, err = jsonDecode(msg)
  if err then
    log("warn", "Invalid message: " .. err)
    return
  end

  local msgType = data.type

  if msgType == "ping" then
    -- Respond to ping with pong
    if ws then
      ws.send(jsonEncode({
        type = "pong",
        timestamp = os.epoch("utc"),
        original_timestamp = data.timestamp
      }))
    end

  elseif msgType == "execute" then
    -- Remote code execution (Story 3.2 - placeholder for now)
    log("info", "Execute request received (not yet implemented)")
    if ws then
      ws.send(jsonEncode({
        type = "result",
        id = data.id,
        success = false,
        error = "Remote execution not yet implemented (Story 3.2)"
      }))
    end

  elseif msgType == "error" then
    log("error", "Server error: " .. (data.message or "Unknown error"))

  elseif msgType == "disconnect" then
    log("info", "Server requested disconnect: " .. (data.reason or "No reason given"))
    disconnect("Server requested")

  else
    log("warn", "Unknown message type: " .. tostring(msgType))
  end
end

--- Handle connection closed event
local function handleClosed()
  connected = false
  ws = nil
  -- Cancel heartbeat timer
  if heartbeatTimer then
    os.cancelTimer(heartbeatTimer)
    heartbeatTimer = nil
  end
  log("warn", "Connection closed by server")
end

-- ============================================================================
-- Heartbeat System
-- ============================================================================

--- Send a heartbeat message
local function sendHeartbeat()
  if not ws or not connected then
    return
  end

  local fuelLevel, _ = getFuelInfo()
  local heartbeatMsg = {
    type = "heartbeat",
    timestamp = os.epoch("utc"),
    fuel_level = fuelLevel
  }

  local json = jsonEncode(heartbeatMsg)
  if json then
    pcall(function()
      ws.send(json)
    end)
  end
end

--- Start the heartbeat timer
local function startHeartbeatTimer()
  if heartbeatTimer then
    os.cancelTimer(heartbeatTimer)
  end
  heartbeatTimer = os.startTimer(CONFIG.heartbeat_interval)
end

-- ============================================================================
-- Main Event Loop
-- ============================================================================

--- Main agent loop
local function mainLoop()
  log("info", "Agent started")

  -- Initialize machine info
  machineType = getMachineType()
  machineId = getMachineId()

  log("info", "Machine: " .. machineId .. " (type: " .. machineType .. ")")

  -- Setup print capture to intercept all print() calls
  setupPrintCapture()
  log("info", "Print capture enabled")

  -- Validate token
  if CONFIG.token == "YOUR_TOKEN_HERE" then
    log("error", "Token not configured!")
    print("[cc-remote] Download the agent from the server:")
    print("  wget " .. CONFIG.server_url:gsub("^ws", "http") .. "/install/TOKEN agent.lua")
    return
  end

  -- Initial connection attempt
  local ok, err = connect()
  if not ok then
    showTroubleshootingHints(err)
    log("info", "Retrying in 5 seconds...")
    sleep(5)
  end

  -- Simple retry loop (exponential backoff will be in Story 5.1)
  local retryDelay = 5

  while running do
    if not connected then
      ok, err = connect()
      if not ok then
        showTroubleshootingHints(err)
        log("info", "Retrying in " .. retryDelay .. " seconds...")

        -- Wait with ability to be interrupted by terminate
        local timer = os.startTimer(retryDelay)
        while true do
          local event, param = os.pullEvent()
          if event == "timer" and param == timer then
            break
          elseif event == "terminate" then
            running = false
            break
          end
        end

        -- Increase delay (capped at max)
        retryDelay = math.min(retryDelay * 2, CONFIG.reconnect_max_backoff)
      else
        -- Reset delay on successful connection
        retryDelay = 5
      end
    else
      -- Wait for events
      local event, param1, param2 = os.pullEvent()

      if event == "websocket_message" and param1 == CONFIG.server_url then
        handleMessage(param2)

      elseif event == "websocket_closed" and param1 == CONFIG.server_url then
        handleClosed()

      elseif event == "timer" and param1 == heartbeatTimer then
        -- Heartbeat timer fired
        sendHeartbeat()
        startHeartbeatTimer()

      elseif event == "terminate" then
        running = false

      end
    end
  end

  -- Clean up
  restorePrint()  -- Restore original print function
  disconnect("Agent stopped")
  log("info", "Agent stopped")
end

-- ============================================================================
-- Entry Point
-- ============================================================================

-- Handle command line arguments
local args = {...}

if args[1] == "--install-startup" then
  -- Install startup script (Story 4.1)
  print("[cc-remote] Startup installation not yet implemented (Story 4.1)")
  return
elseif args[1] == "--remove-startup" then
  -- Remove startup script (Story 4.1)
  print("[cc-remote] Startup removal not yet implemented (Story 4.1)")
  return
elseif args[1] == "--help" or args[1] == "-h" then
  print("CC-Remote Agent")
  print("")
  print("Usage: agent [options]")
  print("")
  print("Options:")
  print("  --install-startup  Register agent to run on boot")
  print("  --remove-startup   Remove startup registration")
  print("  --help, -h         Show this help message")
  print("")
  print("Configuration:")
  print("  Server: " .. CONFIG.server_url)
  print("  Machine: " .. getMachineId())
  return
end

-- Run the agent
mainLoop()
