--[[
  CC-Remote Technical Spike - Agent

  Tests:
  1. WebSocket connectivity (http.websocket)
  2. Print interception (override _G.print)
  3. Remote code execution (load())

  Copy this to a CC:Tweaked computer and run it.
  Make sure the server is running first!

  Usage in CC:Tweaked:
    wget http://YOUR_SERVER_IP:3000/spike-agent.lua spike
    spike
--]]

-- Configuration
local SERVER_URL = "ws://cc-spike.thathohoguy.com"

-- State
local ws = nil
local original_print = print
local captured_lines = {}

-- JSON encoding (CC:Tweaked has textutils.serializeJSON)
local function encode(tbl)
  return textutils.serializeJSON(tbl)
end

local function decode(str)
  return textutils.unserializeJSON(str)
end

-- Override print to capture output
local function setup_print_capture()
  _G.print = function(...)
    -- Call original print so we see output
    original_print(...)

    -- Capture the output
    local parts = {}
    for i = 1, select("#", ...) do
      parts[i] = tostring(select(i, ...))
    end
    local line = table.concat(parts, "\t")
    table.insert(captured_lines, line)

    -- Keep buffer limited
    while #captured_lines > 100 do
      table.remove(captured_lines, 1)
    end
  end
  original_print("[SPIKE] Print capture installed")
end

-- Send captured print lines to server
local function send_captured_prints()
  if #captured_lines > 0 and ws then
    local lines_to_send = {}
    for i, line in ipairs(captured_lines) do
      table.insert(lines_to_send, line)
    end
    captured_lines = {}

    local ok, err = pcall(function()
      ws.send(encode({
        type = "print_captured",
        lines = lines_to_send
      }))
    end)
    if not ok then
      original_print("[SPIKE] Failed to send prints:", err)
    end
  end
end

-- Execute code received from server
local function execute_code(request)
  original_print("[SPIKE] Executing code:", request.code)

  local result = {
    type = "result",
    id = request.id,
    success = false,
    stdout = {},
    return_value = nil,
    error = nil
  }

  -- Capture stdout during execution
  local exec_prints = {}
  local saved_print = _G.print
  _G.print = function(...)
    saved_print(...)
    local parts = {}
    for i = 1, select("#", ...) do
      parts[i] = tostring(select(i, ...))
    end
    table.insert(exec_prints, table.concat(parts, "\t"))
  end

  -- Try to load and execute the code
  local fn, load_err = load(request.code, "remote", "t", _ENV)

  if not fn then
    result.error = "Load error: " .. tostring(load_err)
    original_print("[SPIKE] Load error:", load_err)
  else
    local ok, ret = pcall(fn)
    if ok then
      result.success = true
      result.return_value = ret
      original_print("[SPIKE] Execution succeeded, returned:", ret)
    else
      result.error = "Runtime error: " .. tostring(ret)
      original_print("[SPIKE] Runtime error:", ret)
    end
  end

  -- Restore print and save stdout
  _G.print = saved_print
  result.stdout = exec_prints

  -- Send result back
  local ok, err = pcall(function()
    ws.send(encode(result))
  end)
  if not ok then
    original_print("[SPIKE] Failed to send result:", err)
  end
end

-- Handle incoming messages
local function handle_message(raw)
  original_print("[SPIKE] Received:", raw)

  local ok, msg = pcall(decode, raw)
  if not ok then
    original_print("[SPIKE] Failed to decode JSON:", msg)
    return
  end

  if msg.type == "welcome" then
    original_print("[SPIKE] Server says:", msg.message)

  elseif msg.type == "test_print" then
    -- Test print capture
    original_print("[SPIKE] Testing print capture...")
    print("This is a captured print statement!")
    print("And another one with numbers:", 1, 2, 3)
    send_captured_prints()

  elseif msg.type == "execute" then
    execute_code(msg)

  elseif msg.type == "echo" then
    original_print("[SPIKE] Echo:", textutils.serialize(msg))

  else
    original_print("[SPIKE] Unknown message type:", msg.type)
  end
end

-- Main connection loop
local function main()
  original_print("==========================================")
  original_print("CC-Remote Technical Spike - Agent")
  original_print("==========================================")
  original_print("")
  original_print("Server URL:", SERVER_URL)
  original_print("Machine ID:", os.getComputerID())
  original_print("Machine Label:", os.getComputerLabel() or "(none)")
  original_print("")

  -- Setup print capture
  setup_print_capture()

  -- Connect to server
  print("[SPIKE] Connecting to server...")

  local err
  ws, err = http.websocket(SERVER_URL)

  if not ws then
    print("[SPIKE] CONNECTION FAILED!")
    print("[SPIKE] Error:", err)
    print("")
    print("Troubleshooting:")
    print("- Is the server running? (npm start)")
    print("- Is the URL correct?", SERVER_URL)
    print("- Can Minecraft reach localhost:3000?")
    print("- Check Minecraft's config for HTTP whitelist")
    return false
  end

  print("[SPIKE] Connected!")
  print("")

  -- Send hello message
  ws.send(encode({
    type = "hello",
    machine_id = "computer_" .. os.getComputerID(),
    label = os.getComputerLabel(),
    machine_type = turtle and "turtle" or (pocket and "pocket" or "computer")
  }))

  -- Message loop
  print("[SPIKE] Entering message loop (Ctrl+T to exit)")

  while true do
    local event, url, msg = os.pullEvent()

    if event == "websocket_message" then
      handle_message(msg)

    elseif event == "websocket_closed" then
      print("[SPIKE] Connection closed by server")
      break

    elseif event == "terminate" then
      print("[SPIKE] Terminated by user")
      break
    end
  end

  -- Cleanup
  if ws then
    ws.close()
  end

  -- Restore original print
  _G.print = original_print

  print("[SPIKE] Spike agent stopped")
  return true
end

-- Run
main()
