-- Base Builder Controller Main Program
-- Entry point after startup checks complete
-- Manages command loop and swarm coordination with parallel event handling

-- Load dependencies
local Config = require("shared.config")
local Logging = require("shared.logging")
local Commands = require("controller.commands")

-- ============================================================================
-- SWARM STATE
-- ============================================================================

local Swarm = {
    turtles = {},           -- Registered turtles: {id = {state, position, last_heartbeat}}
    controller_id = os.getComputerID()
}

-- State persistence file path
local SWARM_STATE_FILE = "/state/swarm_state.dat"

-- ============================================================================
-- STATE PERSISTENCE
-- ============================================================================

--- Save swarm state to disk
-- Persists turtle roster so controller can recover after restart
local function save_swarm_state()
    -- Prepare serializable state (exclude non-persistent fields)
    local save_data = {
        version = "1.0",
        saved_at = os.clock(),
        controller_id = Swarm.controller_id,
        turtles = {}
    }

    for id, turtle in pairs(Swarm.turtles) do
        save_data.turtles[id] = {
            state = turtle.state,
            position = turtle.position,
            label = turtle.label,
            -- Don't save last_heartbeat - will be refreshed on reconnect
            -- Don't save update_ready/complete/failed - transient
        }
    end

    -- Ensure state directory exists
    if not fs.exists("/state") then
        fs.makeDir("/state")
    end

    -- Write to file
    local file = fs.open(SWARM_STATE_FILE, "w")
    if file then
        file.write(textutils.serialize(save_data))
        file.close()
        Logging.debug("Saved swarm state (" .. Commands.get_turtle_count() .. " turtles)")
        return true
    else
        Logging.error("Failed to save swarm state")
        return false
    end
end

--- Load swarm state from disk
-- Restores turtle roster after controller restart
-- Turtles will be marked TIMEOUT until they send new heartbeats
local function load_swarm_state()
    if not fs.exists(SWARM_STATE_FILE) then
        Logging.debug("No saved swarm state found")
        return false
    end

    local file = fs.open(SWARM_STATE_FILE, "r")
    if not file then
        Logging.error("Failed to open swarm state file")
        return false
    end

    local content = file.readAll()
    file.close()

    local save_data = textutils.unserialize(content)
    if not save_data or type(save_data) ~= "table" then
        Logging.error("Invalid swarm state file format")
        return false
    end

    -- Restore turtles with TIMEOUT state (until they reconnect)
    local restored_count = 0
    if save_data.turtles then
        for id, turtle in pairs(save_data.turtles) do
            Swarm.turtles[id] = {
                state = "TIMEOUT",  -- Mark as timeout until heartbeat received
                position = turtle.position or {x = 0, y = 0, z = 0},
                label = turtle.label or ("Turtle-" .. id),
                last_heartbeat = 0  -- Will be updated on first heartbeat
            }
            restored_count = restored_count + 1
        end
    end

    if restored_count > 0 then
        Logging.info("Restored " .. restored_count .. " turtles from saved state")
        Logging.info("Turtles will recover from TIMEOUT when they send heartbeats")
    end

    return true
end

-- ============================================================================
-- MESSAGE HANDLERS
-- ============================================================================

--- Handle incoming message from a turtle
-- @param sender number: Turtle's computer ID
-- @param message table: Message data with type field
local function handle_message(sender, message)
    if type(message) ~= "table" or not message.type then
        Logging.debug("Invalid message from " .. tostring(sender))
        return
    end

    local msg_type = message.type

    if msg_type == "REGISTER" then
        -- Turtle registration (Story 1.1)
        Logging.info("Turtle " .. sender .. " requesting registration")
        Swarm.turtles[sender] = {
            state = "IDLE",
            position = message.position or {x = 0, y = 0, z = 0},
            last_heartbeat = os.clock(),
            label = message.label or ("Turtle-" .. sender)
        }
        -- Send acknowledgment
        rednet.send(sender, {
            type = "REGISTER_ACK",
            controller_id = Swarm.controller_id,
            success = true
        })
        Logging.info("Turtle " .. sender .. " registered successfully")
        save_swarm_state()  -- Persist roster change

    elseif msg_type == "HEARTBEAT" then
        -- Heartbeat update (Story 1.3)
        if Swarm.turtles[sender] then
            Swarm.turtles[sender].position = message.position or Swarm.turtles[sender].position
            Swarm.turtles[sender].state = message.state or Swarm.turtles[sender].state
            Swarm.turtles[sender].last_heartbeat = os.clock()
            Logging.debug("Heartbeat from turtle " .. sender)
        else
            Logging.warn("Heartbeat from unregistered turtle " .. sender)
        end

    elseif msg_type == "UPDATE_READY" then
        -- Turtle ready for update (Story 0.3)
        Logging.info("Turtle " .. sender .. " ready for update")
        if Swarm.turtles[sender] then
            Swarm.turtles[sender].update_ready = true
        end

    elseif msg_type == "UPDATE_COMPLETE" then
        -- Turtle completed update (Story 0.3)
        Logging.info("Turtle " .. sender .. " completed update")
        if Swarm.turtles[sender] then
            Swarm.turtles[sender].update_complete = true
        end

    elseif msg_type == "UPDATE_FAILED" then
        -- Turtle failed update (Story 0.3)
        Logging.error("Turtle " .. sender .. " update failed: " .. (message.error or "unknown"))
        if Swarm.turtles[sender] then
            Swarm.turtles[sender].update_failed = true
            Swarm.turtles[sender].update_error = message.error
        end

    else
        Logging.debug("Unknown message type: " .. msg_type .. " from " .. sender)
    end
end

--- Check for turtles that have timed out (no heartbeat)
local function check_timeouts()
    local current_time = os.clock()
    for id, turtle in pairs(Swarm.turtles) do
        local elapsed = current_time - turtle.last_heartbeat
        if elapsed > Config.HEARTBEAT_TIMEOUT then
            if turtle.state ~= "TIMEOUT" then
                Logging.warn("Turtle " .. id .. " timeout - last seen " .. math.floor(elapsed) .. " seconds ago")
                turtle.state = "TIMEOUT"
            end
        elseif turtle.state == "TIMEOUT" then
            -- Turtle recovered
            Logging.info("Turtle " .. id .. " recovered from timeout")
            turtle.state = "IDLE"
        end
    end
end

-- ============================================================================
-- PARALLEL EVENT LOOPS
-- ============================================================================

--- Display startup banner with version and turtle count
local function display_startup_banner()
    local turtle_count = 0
    for _ in pairs(Swarm.turtles) do
        turtle_count = turtle_count + 1
    end

    print("")
    print("========================================")
    print("   BASE BUILDER CONTROLLER v" .. Config.VERSION)
    print("========================================")
    print("")
    print("Controller ID: " .. Swarm.controller_id)
    print("Registered Turtles: " .. turtle_count)
    print("")
    print("Type 'help' for available commands")
    print("")
end

--- Command input loop - handles user commands
local function command_loop()
    display_startup_banner()

    while true do
        write("> ")
        local input = read()

        if input and input ~= "" then
            -- Pass swarm state to commands module for status/swarm operations
            Commands.set_swarm(Swarm)
            if not Commands.execute(input) then
                Logging.error("Command failed or not recognized: " .. input)
            end
        end
    end
end

--- Message listener loop - handles incoming rednet messages
local function message_listener()
    -- Ensure rednet is open
    if not rednet.isOpen() then
        local modem_side = Config.MODEM_SIDE
        if peripheral.isPresent(modem_side) then
            rednet.open(modem_side)
        else
            -- Try to find a modem
            local sides = {"top", "bottom", "left", "right", "front", "back"}
            for _, side in ipairs(sides) do
                if peripheral.isPresent(side) and peripheral.getType(side) == "modem" then
                    rednet.open(side)
                    Logging.info("Opened modem on " .. side)
                    break
                end
            end
        end
    end

    Logging.debug("Message listener started")

    while true do
        local sender, message, protocol = rednet.receive(Config.HEARTBEAT_INTERVAL)
        if sender then
            handle_message(sender, message)
        end
        -- Check for timeouts periodically
        check_timeouts()
    end
end

-- ============================================================================
-- MAIN ENTRY POINT
-- ============================================================================

-- Load any saved swarm state from previous session
load_swarm_state()

-- Run both loops in parallel
-- If either loop exits, the program exits
parallel.waitForAny(command_loop, message_listener)

-- Save state before shutdown
save_swarm_state()
Logging.info("Controller shutdown")
