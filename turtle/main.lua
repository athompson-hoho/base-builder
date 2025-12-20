-- Base Builder Turtle Main Program
-- Entry point after startup checks complete
-- Handles registration, heartbeats, and command execution with parallel event handling

-- Load dependencies
local Config = require("shared.config")
local Logging = require("shared.logging")
local Updater = require("shared.updater")

-- ============================================================================
-- TURTLE STATE
-- ============================================================================

local TurtleState = {
    id = os.getComputerID(),
    label = os.getComputerLabel() or ("Turtle-" .. os.getComputerID()),
    state = "IDLE",             -- IDLE, TRAVELING, EXCAVATING, BUILDING, RETURNING, UPDATING, TIMEOUT
    position = {x = 0, y = 0, z = 0},
    controller_id = nil,        -- Set after registration
    registered = false,
    last_task = nil,
    current_sector = nil,       -- Assigned sector from TASK_ASSIGN
    saved_sector = nil          -- Saved sector for resume after RECALL
}

-- ============================================================================
-- POSITION TRACKING
-- ============================================================================

--- Get current position using GPS if available, or tracked position
-- @return table: Position {x, y, z} or nil if unknown
local function get_position()
    -- Try GPS first
    local x, y, z = gps.locate(2)  -- 2 second timeout
    if x then
        TurtleState.position = {x = x, y = y, z = z}
        return TurtleState.position
    end

    -- Fall back to tracked position (from movement commands)
    -- For now, return last known position
    return TurtleState.position
end

-- ============================================================================
-- MESSAGE HANDLERS
-- ============================================================================

--- Handle incoming message from controller
-- @param sender number: Controller's computer ID
-- @param message table: Message data with type field
local function handle_message(sender, message)
    if type(message) ~= "table" or not message.type then
        Logging.debug("Invalid message from " .. tostring(sender))
        return
    end

    local msg_type = message.type

    if msg_type == "REGISTER_ACK" then
        -- Registration acknowledgment (Story 1.1)
        if message.success then
            TurtleState.controller_id = sender
            TurtleState.registered = true
            Logging.info("Registered with controller (ID: " .. sender .. ")")
        else
            Logging.error("Registration rejected by controller")
        end

    elseif msg_type == "UPDATE_PREPARE" then
        -- Prepare for swarm update (Story 0.3)
        Logging.info("Update v" .. (message.version or "?") .. " preparing...")
        TurtleState.state = "UPDATING"
        -- Send ready response
        rednet.send(sender, {
            type = "UPDATE_READY",
            turtle_id = TurtleState.id,
            version = Updater.get_local_version()
        })
        Logging.debug("Sent UPDATE_READY to controller")

    elseif msg_type == "UPDATE_APPLY" then
        -- Apply swarm update (Story 0.3)
        Logging.info("Applying update...")
        local manifest = message.manifest
        if manifest then
            local success, err = Updater.apply_update("turtle", manifest)
            if success then
                rednet.send(sender, {
                    type = "UPDATE_COMPLETE",
                    turtle_id = TurtleState.id,
                    version = manifest.version
                })
                Logging.info("Update complete. Rebooting...")
                sleep(2)
                os.reboot()
            else
                rednet.send(sender, {
                    type = "UPDATE_FAILED",
                    turtle_id = TurtleState.id,
                    error = err or "Unknown error"
                })
                Logging.error("Update failed: " .. (err or "Unknown error"))
                TurtleState.state = "IDLE"
            end
        else
            Logging.error("UPDATE_APPLY missing manifest")
            TurtleState.state = "IDLE"
        end

    elseif msg_type == "TASK_ASSIGN" then
        -- Receive sector assignment (Story 2.2)
        local sector = message.sector
        if sector then
            Logging.info("Received sector " .. (sector.id or "?") .. " assignment")
            Logging.info("  X: " .. sector.x_start .. " to " .. sector.x_end)
            Logging.info("  Z: " .. sector.z_start .. " to " .. sector.z_end)
            Logging.info("  Y: " .. sector.y_bottom .. " to " .. sector.y_top)

            -- Store task info
            TurtleState.current_sector = sector
            TurtleState.last_task = {
                type = message.build_type or "room",
                sector = sector
            }
            TurtleState.state = "TRAVELING"

            -- Send acknowledgment
            rednet.send(sender, {
                type = "TASK_ACK",
                turtle_id = TurtleState.id,
                sector_id = sector.id
            })
            Logging.debug("Sent TASK_ACK for sector " .. sector.id)

            -- Actual excavation/building will be implemented in Epic 3
            Logging.info("[Epic 3] Sector execution not yet implemented")
        else
            Logging.error("TASK_ASSIGN missing sector data")
        end

    elseif msg_type == "RECALL" then
        -- Recall to home (Story 2.5)
        Logging.info("Recall command received from controller")
        Logging.info("Reason: " .. (message.reason or "unknown"))

        -- Save current task for resume
        if TurtleState.current_sector then
            TurtleState.saved_sector = TurtleState.current_sector
            TurtleState.current_sector = nil
        end

        -- Transition to RETURNING state
        TurtleState.state = "RETURNING"

        -- Navigation to home base will be implemented in Epic 3
        Logging.info("[Epic 3] Home navigation not yet implemented")
        Logging.info("Turtle will remain at current position until navigation is available")

    elseif msg_type == "PAUSE" then
        -- Pause operations (Story 2.6)
        Logging.info("Pause command received from controller")

        -- Save current sector but don't clear it (different from recall)
        -- Turtle stays in place and waits for resume

        -- Transition to IDLE state
        TurtleState.state = "IDLE"

        Logging.info("Turtle paused at current position")
        Logging.info("Waiting for resume command...")

    elseif msg_type == "RESUME" then
        -- Resume operations (Story 2.7)
        Logging.info("Resume command received")
        -- Resume logic will be implemented in Epic 2

    else
        Logging.debug("Unknown message type: " .. msg_type .. " from " .. sender)
    end
end

-- ============================================================================
-- REGISTRATION
-- ============================================================================

--- Attempt to register with controller
-- @return boolean: true if registration successful
local function register_with_controller()
    Logging.info("Attempting to register with controller...")

    -- Broadcast registration request
    local position = get_position()
    rednet.broadcast({
        type = "REGISTER",
        turtle_id = TurtleState.id,
        label = TurtleState.label,
        position = position,
        state = TurtleState.state
    })

    -- Wait for acknowledgment with timeout
    local timeout = os.startTimer(5)
    while true do
        local event, p1, p2, p3 = os.pullEvent()
        if event == "rednet_message" then
            local sender, message = p1, p2
            if type(message) == "table" and message.type == "REGISTER_ACK" then
                handle_message(sender, message)
                os.cancelTimer(timeout)
                return TurtleState.registered
            end
        elseif event == "timer" and p1 == timeout then
            Logging.warn("Registration timeout - no controller response")
            return false
        end
    end
end

-- ============================================================================
-- PARALLEL EVENT LOOPS
-- ============================================================================

--- Heartbeat sender loop - sends periodic heartbeats to controller
local function heartbeat_sender()
    while true do
        os.sleep(Config.HEARTBEAT_INTERVAL)

        if TurtleState.registered and TurtleState.controller_id then
            local position = get_position()
            rednet.send(TurtleState.controller_id, {
                type = "HEARTBEAT",
                turtle_id = TurtleState.id,
                position = position,
                state = TurtleState.state,
                fuel = turtle.getFuelLevel()
            })
            Logging.debug("Sent heartbeat to controller")
        end
    end
end

--- Message listener loop - handles incoming rednet messages
local function message_listener()
    Logging.debug("Message listener started")

    while true do
        local sender, message, protocol = rednet.receive()
        if sender then
            handle_message(sender, message)
        end
    end
end

--- User input handler - allows local control via keyboard
local function input_handler()
    while true do
        local event, key = os.pullEvent("key")
        if key == keys.q then
            Logging.info("Shutdown requested (Q pressed)")
            return  -- Exit parallel loop
        elseif key == keys.r then
            -- Manual re-registration
            Logging.info("Manual re-registration requested")
            TurtleState.registered = false
            register_with_controller()
        elseif key == keys.s then
            -- Status display
            Logging.info("")
            Logging.info("=== TURTLE STATUS ===")
            Logging.info("ID: " .. TurtleState.id)
            Logging.info("Label: " .. TurtleState.label)
            Logging.info("State: " .. TurtleState.state)
            Logging.info("Registered: " .. tostring(TurtleState.registered))
            Logging.info("Controller: " .. tostring(TurtleState.controller_id or "None"))
            local pos = TurtleState.position
            Logging.info("Position: (" .. pos.x .. ", " .. pos.y .. ", " .. pos.z .. ")")
            Logging.info("Fuel: " .. turtle.getFuelLevel())
            Logging.info("=====================")
        end
    end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

--- Initialize rednet and modem
local function initialize_network()
    -- Ensure rednet is open
    if not rednet.isOpen() then
        local modem_side = Config.MODEM_SIDE
        if peripheral.isPresent(modem_side) then
            rednet.open(modem_side)
            Logging.info("Opened modem on " .. modem_side)
        else
            -- Try to find a modem
            local sides = {"top", "bottom", "left", "right", "front", "back"}
            for _, side in ipairs(sides) do
                if peripheral.isPresent(side) and peripheral.getType(side) == "modem" then
                    rednet.open(side)
                    Logging.info("Opened modem on " .. side)
                    return true
                end
            end
            Logging.error("No modem found! Turtle cannot communicate.")
            return false
        end
    end
    return true
end

-- ============================================================================
-- MAIN ENTRY POINT
-- ============================================================================

Logging.info("Base Builder Turtle starting...")
Logging.info("Turtle ID: " .. TurtleState.id)
Logging.info("Label: " .. TurtleState.label)

-- Initialize network
if not initialize_network() then
    Logging.error("Failed to initialize network. Exiting.")
    return
end

-- Get initial position
get_position()
Logging.info("Position: (" .. TurtleState.position.x .. ", " .. TurtleState.position.y .. ", " .. TurtleState.position.z .. ")")

-- Attempt initial registration
Logging.info("")
local reg_attempts = 0
local max_attempts = 3
while not TurtleState.registered and reg_attempts < max_attempts do
    reg_attempts = reg_attempts + 1
    Logging.info("Registration attempt " .. reg_attempts .. "/" .. max_attempts)
    if register_with_controller() then
        break
    end
    if reg_attempts < max_attempts then
        Logging.info("Retrying in 5 seconds...")
        os.sleep(5)
    end
end

if not TurtleState.registered then
    Logging.warn("Could not register with controller.")
    Logging.info("Will continue and retry when controller becomes available.")
    Logging.info("Press [R] to manually retry registration.")
end

Logging.info("")
Logging.info("Turtle ready. Press [S] for status, [R] to re-register, [Q] to quit.")
Logging.info("Waiting for commands from controller...")

-- Run all loops in parallel
-- If any loop exits (e.g., Q pressed), program exits
parallel.waitForAny(heartbeat_sender, message_listener, input_handler)

Logging.info("Turtle shutdown complete")
