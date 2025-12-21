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
    controller_id = os.getComputerID(),
    build = nil,            -- Current build definition (set by Commands.build)
    sectors = {},           -- Sector definitions for current build
    pending_sectors = {},   -- Sectors waiting to be assigned
    assignments = {}        -- Current turtle -> sector assignments
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

--- Recover sector assignment for a reconnected turtle (Story 6.4)
-- @param turtle_id number: Turtle reconnecting
local function recover_turtle_assignment(turtle_id)
    local turtle = Swarm.turtles[turtle_id]
    if not turtle then return end

    -- Try to restore previous assignment
    local restored_sector = nil
    for sector_id, assignment in pairs(Swarm.assignments or {}) do
        if assignment.turtle_id == turtle_id and not assignment.completed then
            restored_sector = sector_id
            break
        end
    end

    -- If previous sector no longer available, find next incomplete
    if not restored_sector then
        for _, sector in ipairs(Swarm.sectors or {}) do
            if not sector.completed and sector.status ~= "assigned" then
                restored_sector = sector.id
                break
            end
        end
    end

    if restored_sector then
        -- Assign sector to reconnected turtle
        local sector = Swarm.sectors[restored_sector] or {}
        Swarm.assignments[turtle_id] = {
            sector_id = restored_sector,
            turtle_id = turtle_id,
            start_x = sector.start_x,
            start_z = sector.start_z,
            size = sector.size,
            assigned_at = os.clock()
        }

        -- Send task assignment
        rednet.send(turtle_id, {
            type = "TASK_ASSIGN",
            sector_id = restored_sector,
            start_x = sector.start_x,
            start_z = sector.start_z,
            size = sector.size,
            depth = sector.depth or 64
        })

        Logging.info("Reassigned sector " .. restored_sector .. " to turtle " .. turtle_id ..
                     " on reconnection")
    else
        Logging.warn("No incomplete sectors to reassign to turtle " .. turtle_id)
        turtle.state = "IDLE"
    end
end

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
        -- Heartbeat update (Story 1.3) with reconnection detection (Story 6.4)
        if Swarm.turtles[sender] then
            local was_offline = Swarm.turtles[sender].state == "TIMEOUT"

            Swarm.turtles[sender].position = message.position or Swarm.turtles[sender].position
            Swarm.turtles[sender].state = message.state or Swarm.turtles[sender].state
            Swarm.turtles[sender].last_heartbeat = os.clock()
            Logging.debug("Heartbeat from turtle " .. sender)

            -- Detect reconnection and recover assignments (Story 6.4)
            if was_offline then
                Logging.info("[RECONNECT] Turtle " .. sender .. " coming online - recovering work")
                if Swarm.build and Swarm.build.phase == "BUILDING" then
                    recover_turtle_assignment(sender)
                elseif Swarm.build and Swarm.build.phase == "PAUSED" then
                    Logging.info("Build paused - turtle " .. sender .. " ready for resume")
                end
            end
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

    elseif msg_type == "TASK_ACK" then
        -- Turtle acknowledged task assignment (Story 2.2)
        local sector_id = message.sector_id
        Logging.info("Turtle " .. sender .. " acknowledged sector " .. (sector_id or "?"))
        if Swarm.turtles[sender] then
            Swarm.turtles[sender].task_acked = true
            Swarm.turtles[sender].state = "TRAVELING"
        end

    elseif msg_type == "SECTOR_COMPLETE" then
        -- Turtle completed assigned sector (Story 2.2)
        local sector_id = message.sector_id
        Logging.info("Turtle " .. sender .. " completed sector " .. (sector_id or "?"))

        -- Mark sector as complete
        for _, sector in ipairs(Swarm.sectors) do
            if sector.id == sector_id then
                sector.status = "complete"
                break
            end
        end

        -- Try to assign next pending sector
        if #Swarm.pending_sectors > 0 then
            local next_sector = table.remove(Swarm.pending_sectors, 1)
            next_sector.assigned_to = sender
            next_sector.status = "assigned"
            Swarm.assignments[sender] = next_sector

            rednet.send(sender, {
                type = "TASK_ASSIGN",
                sector = {
                    id = next_sector.id,
                    x_start = next_sector.x_start,
                    x_end = next_sector.x_end,
                    z_start = next_sector.z_start,
                    z_end = next_sector.z_end,
                    y_top = next_sector.y_top,
                    y_bottom = next_sector.y_bottom
                },
                build_type = "room"
            })
            Logging.info("Assigned next sector " .. next_sector.id .. " to turtle " .. sender)
        else
            -- No more sectors - turtle goes idle
            if Swarm.turtles[sender] then
                Swarm.turtles[sender].state = "IDLE"
            end
            Swarm.assignments[sender] = nil

            -- Check if all sectors are complete (Story 2.3 AC6)
            local all_complete = true
            local sectors_completed = 0
            for _, sector in ipairs(Swarm.sectors) do
                if sector.status == "complete" then
                    sectors_completed = sectors_completed + 1
                else
                    all_complete = false
                end
            end

            if all_complete and #Swarm.sectors > 0 then
                Logging.info("")
                Logging.info("========================================")
                Logging.info("  ROOM COMPLETE!")
                Logging.info("========================================")
                Logging.info("All " .. #Swarm.sectors .. " sectors finished.")
                if Swarm.build then
                    Swarm.build.phase = "COMPLETE"
                    Swarm.build.sectors_completed = sectors_completed
                    Swarm.build.progress = 100

                    -- Persist completed build state
                    local Config = require("shared.config")
                    local file = fs.open(Config.BUILD_STATE_FILE, "w")
                    if file then
                        file.write(textutils.serialize(Swarm.build))
                        file.close()
                    end
                end
                Logging.info("")
            end
        end

    elseif msg_type == "PROGRESS_UPDATE" then
        -- Track block-level progress from turtles (Story 2.3 AC2)
        local sector_id = message.sector_id
        local blocks = message.blocks_completed or 0

        if Swarm.build then
            Swarm.build.blocks_completed = (Swarm.build.blocks_completed or 0) + blocks
            -- Recalculate progress percentage
            if Swarm.build.total_blocks and Swarm.build.total_blocks > 0 then
                Swarm.build.progress = math.floor(
                    (Swarm.build.blocks_completed / Swarm.build.total_blocks) * 100
                )
            end
            Logging.debug("Progress: " .. Swarm.build.blocks_completed .. "/" ..
                         (Swarm.build.total_blocks or 0) .. " blocks")
        end

    elseif msg_type == "MATERIAL_SHORTAGE" then
        -- Handle material shortage notification (Story 5.4)
        local turtle_id = sender
        local material = message.material or "unknown"

        Logging.warn("Material shortage reported by turtle " .. turtle_id .. ": " .. material)

        -- Pause build due to shortage
        if Swarm.build and Swarm.build.phase ~= "COMPLETE" and Swarm.build.phase ~= "PAUSED" then
            Swarm.build.phase = "PAUSED"
            Swarm.build.pause_reason = "material_shortage"
            Swarm.build.paused_material = material

            -- Persist paused state
            local file = fs.open(Config.BUILD_STATE_FILE, "w")
            if file then
                file.write(textutils.serialize(Swarm.build))
                file.close()
            end

            print("")
            print("[!] Build paused: " .. material .. " low. Refill AE2 to continue.")
            print("")

            -- Start polling for material availability
            Swarm.material_polling = {
                enabled = true,
                material = material,
                next_poll = os.clock()
            }
        end

    elseif msg_type == "HAZARD_DETECTED" then
        -- Turtle detected environmental hazard (Story 6.2)
        local turtle_id = sender
        local hazard_type = message.hazard_type or "unknown"
        local block_name = message.block_name or "?"
        local position = message.position or {x = "?", y = "?", z = "?"}

        Logging.error("[HAZARD] Turtle " .. turtle_id .. " encountered " .. hazard_type ..
                      " (" .. block_name .. ") at (" .. position.x .. "," .. position.y ..
                      "," .. position.z .. ")")

        -- Pause build on hazard
        if Swarm.build and Swarm.build.phase ~= "COMPLETE" then
            Swarm.build.phase = "PAUSED"
            Swarm.build.pause_reason = "hazard_detected"
            Swarm.build.hazard = {
                turtle_id = turtle_id,
                type = hazard_type,
                block = block_name,
                position = position,
                detected_at = os.clock()
            }

            -- Save paused state
            local file = fs.open(Config.BUILD_STATE_FILE, "w")
            if file then
                file.write(textutils.serialize(Swarm.build))
                file.close()
            end

            print("")
            print("[!] Build paused due to hazard at (" .. position.x .. "," .. position.y ..
                  "," .. position.z .. "): " .. block_name)
            print("[!] Review location and use 'skip_hazard' to continue.")
            print("")
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

--- Check material polling status and auto-resume if materials available
-- For MVP, this checks if admin has manually refilled AE2
-- In a full implementation, this would query the ME system directly
local function check_material_polling()
    if not Swarm.material_polling or not Swarm.material_polling.enabled then
        return
    end

    local current_time = os.clock()
    local poll_interval = Config.MATERIAL_POLL_INTERVAL or 30  -- 30 seconds between polls

    -- Check if it's time to poll
    if current_time < Swarm.material_polling.next_poll then
        return
    end

    -- Update next poll time
    Swarm.material_polling.next_poll = current_time + poll_interval

    local material = Swarm.material_polling.material
    Logging.debug("Polling for material availability: " .. material)

    -- For MVP: just wait for admin to refill manually
    -- Full implementation would query ME system or check a designated turtle
    -- For now, we show a status message but don't auto-resume
    -- (Admin must explicitly type 'resume' after refilling AE2)
end

-- ============================================================================
-- PERIODIC STATE PERSISTENCE (Story 6.6)
-- ============================================================================

local last_state_save = 0
local state_save_interval = 30  -- Save every 30 seconds

--- Save all persistent state to disk (Story 6.6)
-- Called periodically to prevent loss of progress on crash
local function save_all_state()
    local current_time = os.clock()

    -- Only save if interval elapsed
    if current_time < last_state_save + state_save_interval then
        return
    end

    -- Save build state (if active)
    if Swarm.build then
        -- Ensure state directory exists
        if not fs.exists("/state") then
            fs.makeDir("/state")
        end

        -- Atomic save: write to temp, then move
        local temp_file = Config.BUILD_STATE_FILE .. ".tmp"
        local file = fs.open(temp_file, "w")
        if file then
            file.write(textutils.serialize(Swarm.build))
            file.close()

            -- Backup existing file before overwrite
            if fs.exists(Config.BUILD_STATE_FILE) then
                local backup_file = Config.BUILD_STATE_FILE .. ".bak"
                if fs.exists(backup_file) then
                    fs.delete(backup_file)
                end
                fs.copy(Config.BUILD_STATE_FILE, backup_file)
            end

            -- Atomic rename
            if fs.exists(Config.BUILD_STATE_FILE) then
                fs.delete(Config.BUILD_STATE_FILE)
            end
            fs.move(temp_file, Config.BUILD_STATE_FILE)

            Logging.debug("Saved build state periodically")
        else
            Logging.warn("Failed to save build state")
        end
    end

    -- Save swarm state (turtle roster)
    save_swarm_state()

    last_state_save = current_time
end

-- ============================================================================
-- SERVER RESTART RECOVERY (Story 6.7)
-- ============================================================================

--- Display recovery status on startup (Story 6.7)
local function display_recovery_status()
    print("")
    print("================================================")
    print("         RECOVERY IN PROGRESS")
    print("================================================")
    print("")

    -- Display state
    local turtle_count = 0
    for _ in pairs(Swarm.turtles) do
        turtle_count = turtle_count + 1
    end

    if Swarm.build then
        local progress = Swarm.build.progress or 0
        local sectors_done = Swarm.build.sectors_completed or 0
        print("Build Progress: " .. progress .. "%")
        print("Sectors Complete: " .. sectors_done)
        print("Build ID: " .. (Swarm.build.id or "unknown"))
    end

    print("Expected Turtles: " .. turtle_count)
    print("")
    print("Waiting for turtles to reconnect... (60 second grace period)")
    print("")
end

--- Wait for turtles to reconnect during startup (Story 6.7)
local function wait_for_reconnection_grace_period()
    local grace_start = os.clock()
    local grace_period = 60  -- 60 seconds

    while true do
        local elapsed = os.clock() - grace_start
        if elapsed >= grace_period then
            break
        end

        -- Accept messages (heartbeats trigger reconnection)
        local sender, message = rednet.receive(1)
        if sender then
            handle_message(sender, message)
        end

        -- Show progress every 10 seconds
        if math.floor(elapsed) % 10 == 0 and elapsed > 0 then
            local connected = 0
            for _, turtle in pairs(Swarm.turtles) do
                if turtle.state == "IDLE" or turtle.state == "ONLINE" then
                    connected = connected + 1
                end
            end
            local expected = 0
            for _ in pairs(Swarm.turtles) do
                expected = expected + 1
            end
            if connected > 0 then
                Logging.info("Reconnection progress: " .. connected .. "/" .. expected .. " turtles online")
            end
        end
    end

    -- Grace period complete - show final status
    local connected = 0
    local expected = 0
    for _, turtle in pairs(Swarm.turtles) do
        expected = expected + 1
        if turtle.state == "IDLE" or turtle.state == "ONLINE" or turtle.state ~= "TIMEOUT" then
            connected = connected + 1
        end
    end

    print("")
    print("================================================")
    print("   RECONNECTION GRACE PERIOD COMPLETE")
    print("================================================")
    print("Connected: " .. connected .. "/" .. expected .. " turtles")
    print("")

    if Swarm.build and Swarm.build.phase == "PAUSED" then
        print("Paused Build Status:")
        if Swarm.build.pause_reason then
            print("  Reason: " .. Swarm.build.pause_reason)
        end
        print("")
    end

    print("OPTIONS:")
    print("  'resume'  - Continue build from saved state")
    print("  'recall'  - Cancel paused build")
    print("  'status'  - Show current status")
    print("")
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
    -- Display recovery status if we have saved state (Story 6.7)
    if next(Swarm.turtles) ~= nil or Swarm.build then
        display_recovery_status()
        wait_for_reconnection_grace_period()
    end

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
        -- Check material polling status
        check_material_polling()
        -- Periodic state persistence (Story 6.6)
        save_all_state()
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
