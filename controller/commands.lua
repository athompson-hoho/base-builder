-- Base Builder Controller Commands
-- Implements controller commands: update, build, status, recall, pause, resume, cancel

local Commands = {}

-- Load dependencies
local Config = require("shared.config")
local Logging = require("shared.logging")
local Updater = require("shared.updater")
local Builder = require("controller.builder")

-- Swarm state (set by main.lua)
local Swarm = nil

--- Set the swarm state reference (called by main.lua)
-- @param swarm_state table: Reference to swarm state from main
function Commands.set_swarm(swarm_state)
    Swarm = swarm_state
end

--- Get registered turtle count
-- @return number: Count of registered turtles
function Commands.get_turtle_count()
    if not Swarm or not Swarm.turtles then
        return 0
    end
    local count = 0
    for _ in pairs(Swarm.turtles) do
        count = count + 1
    end
    return count
end

-- ============================================================================
-- COMMAND HANDLERS
-- ============================================================================

--- Update the controller and all turtles to latest version
-- Usage: update [--force]
-- @param args table: command arguments (may be nil)
--   args[1] = optional "--force" flag to skip build state check
function Commands.update(args)
    args = args or {}
    local force = args[1] == "--force"

    Logging.info("Checking for updates...")

    -- Check for active build state (unless --force flag)
    if not force then
        if fs.exists(Config.BUILD_STATE_FILE) then
            local file = fs.open(Config.BUILD_STATE_FILE, "r")
            if file then
                local content = file.readAll()
                file.close()
                if content and content ~= "" then
                    Logging.warn("Build in progress - cannot update")
                    Logging.info("Complete the build first: type 'recall' to bring turtles home, or 'cancel' to abort")
                    return
                end
            end
        end
    end

    -- Fetch manifest and check version
    local manifest, err = Updater.fetch_manifest()
    if not manifest then
        Logging.error("Failed to fetch manifest: " .. (err or "unknown error"))
        Logging.info("Check your internet connection and try again")
        return
    end

    local local_version = Updater.get_local_version()

    -- Check if update is available
    if manifest.version == local_version then
        Logging.info("Already on latest (v" .. local_version .. ")")
        return
    end

    -- Update available - proceed with download and apply
    Logging.info("Update v" .. manifest.version .. " available (current: v" .. local_version .. ")")
    Logging.info("Downloading...")

    local success, apply_err = Updater.apply_update("controller", manifest)
    if not success then
        Logging.error("Failed to apply update: " .. (apply_err or "unknown error"))
        return
    end

    -- Update successful - prepare for swarm update
    Logging.info("")
    Logging.info("============================================")
    Logging.info("UPDATE SEQUENCE:")
    Logging.info("1. Broadcasting UPDATE_PREPARE to all turtles...")

    -- Broadcast UPDATE_PREPARE to all turtles
    -- This will be fully implemented in Story 1.1 (turtle registration)
    -- For Story 0.3, we'll document the message structure and stub the implementation
    local update_prepare_message = {
        type = "UPDATE_PREPARE",
        version = manifest.version
    }
    Logging.debug("UPDATE_PREPARE message: " .. textutils.serialize(update_prepare_message))
    Logging.info("   (waiting for UPDATE_READY from turtles...)")

    -- Wait for UPDATE_READY responses (timeout configurable)
    -- This will be fully implemented when we have turtle message handling (Story 1.1)
    -- For now, we'll log that we're waiting
    Logging.debug("Waiting " .. Config.UPDATE_WAIT_TIMEOUT .. "s for UPDATE_READY responses...")
    sleep(1)  -- Placeholder - actual implementation will use timer and event loop

    -- Broadcast UPDATE_APPLY with manifest
    Logging.info("2. Broadcasting UPDATE_APPLY to all turtles...")
    local update_apply_message = {
        type = "UPDATE_APPLY",
        version = manifest.version,
        manifest = manifest
    }
    Logging.debug("UPDATE_APPLY message (manifest included)")

    -- Wait for UPDATE_COMPLETE responses (timeout configurable)
    -- This will be fully implemented in Story 1.1
    Logging.info("   (waiting for UPDATE_COMPLETE from turtles...)")
    Logging.debug("Waiting " .. Config.UPDATE_WAIT_TIMEOUT .. "s for UPDATE_COMPLETE responses...")
    sleep(1)  -- Placeholder - actual implementation will use timer and event loop

    -- Display final status
    Logging.info("")
    Logging.info("Update sequence complete")
    Logging.info("Rebooting in 5 seconds...")

    -- Sleep before reboot
    for i = 5, 1, -1 do
        sleep(1)
    end

    Logging.info("Rebooting now...")
    os.reboot()
end

--- Build command handler
-- Usage: build room <width> <length>
-- @param args table: {"room", width, length}
function Commands.build(args)
    args = args or {}

    -- Check subcommand (AC1)
    if not args[1] or args[1] ~= "room" then
        Logging.info("Usage: build room <width> <length>")
        return
    end

    -- Parse dimensions (AC2)
    local width_raw = tonumber(args[2])
    local length_raw = tonumber(args[3])

    if not width_raw or not length_raw then
        Logging.error("Width and length must be positive integers")
        Logging.info("Usage: build room <width> <length>")
        return
    end

    -- Ensure integer dimensions
    local width = math.floor(width_raw)
    local length = math.floor(length_raw)

    if width <= 0 or length <= 0 then
        Logging.error("Width and length must be positive integers")
        Logging.info("Usage: build room <width> <length>")
        return
    end

    -- Validate maximum size
    if width > Config.MAX_ROOM_WIDTH or length > Config.MAX_ROOM_LENGTH then
        Logging.error("Room too large. Maximum size: " .. Config.MAX_ROOM_WIDTH .. "x" .. Config.MAX_ROOM_LENGTH)
        return
    end

    -- Validate turtle count (AC3)
    local turtle_count = Commands.get_turtle_count()
    if turtle_count == 0 then
        Logging.error("No turtles registered. Start turtles first.")
        return
    end

    -- Check for existing build in progress
    if fs.exists(Config.BUILD_STATE_FILE) then
        local existing_file = fs.open(Config.BUILD_STATE_FILE, "r")
        if existing_file then
            local content = existing_file.readAll()
            existing_file.close()
            if content and content ~= "" then
                local existing_build = textutils.unserialize(content)
                if existing_build and existing_build.phase ~= "COMPLETE" then
                    Logging.error("Build already in progress (" .. existing_build.width .. "x" .. existing_build.length .. ")")
                    Logging.info("Use 'cancel' to abort the current build first")
                    return
                end
            end
        end
    end

    -- Get build origin - GPS or config fallback (AC5)
    local origin_x, origin_y, origin_z = gps.locate(5)
    if not origin_x then
        -- Fall back to configured origin
        origin_x = Config.BUILD_ORIGIN_X or 0
        origin_y = Config.BUILD_ORIGIN_Y or 64
        origin_z = Config.BUILD_ORIGIN_Z or 0
        Logging.warn("GPS unavailable, using configured origin")
    end

    -- Calculate total blocks for progress tracking (Story 2.3 AC1)
    local total_blocks = width * length * Config.ROOM_HEIGHT

    -- Create build definition (AC4)
    local build_definition = {
        type = "room",
        width = width,
        length = length,
        height = Config.ROOM_HEIGHT,  -- 7-high walls + 2-high crawl space = 9
        origin = {
            x = origin_x,
            y = origin_y,
            z = origin_z
        },
        started_at = os.clock(),
        progress = 0,
        phase = "PENDING",  -- PENDING → EXCAVATING → BUILDING → COMPLETE
        -- Progress tracking (Story 2.3)
        total_blocks = total_blocks,
        blocks_completed = 0,
        sectors_completed = 0,
        total_sectors = 0  -- Set after sector calculation
    }

    -- Save build state
    if not fs.exists("/state") then
        fs.makeDir("/state")
    end
    local file = fs.open(Config.BUILD_STATE_FILE, "w")
    if file then
        file.write(textutils.serialize(build_definition))
        file.close()
        Logging.debug("Build state saved to " .. Config.BUILD_STATE_FILE)
    else
        Logging.error("Failed to save build state")
        return
    end

    -- Confirm to user (AC4)
    Logging.info("")
    Logging.info("Starting room build: " .. width .. "x" .. length .. " at GPS (" ..
                 origin_x .. ", " .. origin_y .. ", " .. origin_z .. ")")
    Logging.info("Room height: " .. build_definition.height .. " blocks (7 walls + 2 crawl)")
    Logging.info("Turtles available: " .. turtle_count)
    Logging.info("")

    -- Calculate sectors for parallel work distribution (AC5)
    local sectors = Builder.calculate_sectors(
        width,
        length,
        build_definition.height,
        build_definition.origin,
        turtle_count
    )

    if #sectors == 0 then
        Logging.error("Failed to calculate sectors")
        return
    end

    -- Verify swarm state is available
    if not Swarm or not Swarm.turtles then
        Logging.error("Swarm state unavailable")
        return
    end

    -- Update total_sectors now that we know how many
    build_definition.total_sectors = #sectors

    -- Store sectors in swarm state for tracking
    Swarm.sectors = sectors
    Swarm.build = build_definition

    -- Assign sectors to available turtles (AC6)
    local assignments, pending = Builder.assign_sectors(sectors, Swarm.turtles, rednet.send)

    -- Store assignments and pending queue in swarm state
    Swarm.assignments = assignments
    Swarm.pending_sectors = pending

    -- Update build phase
    build_definition.phase = "EXCAVATING"

    -- Save updated build state
    local phase_file = fs.open(Config.BUILD_STATE_FILE, "w")
    if phase_file then
        phase_file.write(textutils.serialize(build_definition))
        phase_file.close()
    end

    -- Summary
    local assigned_count = 0
    for _ in pairs(assignments) do
        assigned_count = assigned_count + 1
    end
    Logging.info("Assigned " .. assigned_count .. " sectors to turtles")
    if #pending > 0 then
        Logging.info(#pending .. " sectors queued for turtles that finish early")
    end
    Logging.info("Build phase: EXCAVATING")
end

--- Display swarm status
function Commands.status(args)
    local turtle_count = Commands.get_turtle_count()

    -- Count online vs timeout turtles (Story 2.4 AC1)
    local online_count = 0
    local timeout_count = 0
    local alerts = {}

    if Swarm and Swarm.turtles then
        for id, turtle in pairs(Swarm.turtles) do
            if turtle.state == "TIMEOUT" then
                timeout_count = timeout_count + 1
                table.insert(alerts, "Turtle " .. id .. " is not responding")
            else
                online_count = online_count + 1
            end
        end
    end

    Logging.info("")
    Logging.info("============ SWARM STATUS ============")
    Logging.info("Controller ID: " .. (Swarm and Swarm.controller_id or os.getComputerID()))
    Logging.info("Turtles: " .. online_count .. "/" .. turtle_count .. " online")
    Logging.info("")

    -- Build progress (Story 2.3 AC4)
    if Swarm and Swarm.build then
        local build = Swarm.build
        local progress = Builder.get_progress(Swarm.sectors or {})
        local sectors_complete = 0
        local total_sectors = build.total_sectors or 0

        if Swarm.sectors then
            for _, sector in ipairs(Swarm.sectors) do
                if sector.status == "complete" then
                    sectors_complete = sectors_complete + 1
                end
            end
        end

        Logging.info("--- BUILD STATUS ---")
        Logging.info("Type: " .. build.type .. " (" .. build.width .. "x" .. build.length .. ")")
        Logging.info("Phase: " .. (build.phase or "UNKNOWN"))
        Logging.info("Build: " .. progress .. "% complete (" .. sectors_complete .. "/" .. total_sectors .. " sectors)")
        Logging.info("Total blocks: " .. (build.total_blocks or 0))
        Logging.info("")
    else
        Logging.info("No active build")
        Logging.info("")
    end

    -- Turtle list (Story 2.4 AC2)
    if turtle_count == 0 then
        Logging.info("No turtles registered yet.")
        Logging.info("Start turtles to have them auto-register.")
    else
        Logging.info("--- TURTLES ---")
        Logging.info("ID       STATE      POSITION           TASK")
        Logging.info("-------- ---------- ------------------ ----------------")
        for id, turtle in pairs(Swarm.turtles) do
            local pos = turtle.position or {x = "?", y = "?", z = "?"}
            local pos_str = string.format("(%s, %s, %s)", pos.x, pos.y, pos.z)
            local state = turtle.state or "UNKNOWN"

            -- Show current task/sector (Story 2.4 AC2)
            local task = "-"
            if Swarm.assignments and Swarm.assignments[id] then
                local sector = Swarm.assignments[id]
                task = "Sector " .. sector.id
            end

            Logging.info(string.format("%-8s %-10s %-18s %s", id, state, pos_str, task))
        end
    end

    -- Alerts section (Story 2.4 AC5)
    if #alerts > 0 then
        Logging.info("")
        Logging.info("--- ALERTS ---")
        for _, alert in ipairs(alerts) do
            Logging.info("[!] " .. alert)
        end
    end

    Logging.info("")
    Logging.info("=======================================")
end

--- Recall all turtles to home base
-- Usage: recall
function Commands.recall(args)
    if not Swarm or not Swarm.turtles then
        Logging.error("No swarm state available")
        return
    end

    local turtle_count = Commands.get_turtle_count()
    if turtle_count == 0 then
        Logging.info("No turtles registered to recall")
        return
    end

    -- Count non-timeout turtles
    local recall_count = 0
    for id, turtle in pairs(Swarm.turtles) do
        if turtle.state ~= "TIMEOUT" then
            -- Send RECALL message
            rednet.send(id, {
                type = "RECALL",
                reason = "user_command"
            })
            recall_count = recall_count + 1
        end
    end

    -- Update build phase if active build
    if Swarm.build and Swarm.build.phase ~= "COMPLETE" then
        Swarm.build.phase = "PAUSED"

        -- Persist paused state
        local file = fs.open(Config.BUILD_STATE_FILE, "w")
        if file then
            file.write(textutils.serialize(Swarm.build))
            file.close()
        end
        Logging.info("Build paused at " .. Builder.get_progress(Swarm.sectors or {}) .. "%")
    end

    Logging.info("Recall issued to " .. recall_count .. " turtles")
    Logging.info("Turtles will return to home base")
end

--- Pause all working turtles (stay in place)
-- Usage: pause
function Commands.pause(args)
    if not Swarm or not Swarm.turtles then
        Logging.error("No swarm state available")
        return
    end

    -- Check if there's an active build
    if not Swarm.build or Swarm.build.phase == "COMPLETE" then
        Logging.info("No active build to pause")
        return
    end

    if Swarm.build.phase == "PAUSED" then
        Logging.info("Build is already paused")
        return
    end

    -- Send PAUSE to all working turtles
    local pause_count = 0
    for id, turtle in pairs(Swarm.turtles) do
        if turtle.state ~= "TIMEOUT" and turtle.state ~= "IDLE" then
            rednet.send(id, {
                type = "PAUSE"
            })
            pause_count = pause_count + 1
        end
    end

    -- Update build phase
    Swarm.build.phase = "PAUSED"

    -- Persist paused state
    local file = fs.open(Config.BUILD_STATE_FILE, "w")
    if file then
        file.write(textutils.serialize(Swarm.build))
        file.close()
    end

    local progress = Builder.get_progress(Swarm.sectors or {})
    Logging.info("Build paused at " .. progress .. "%")
    Logging.info("Sent pause to " .. pause_count .. " working turtles")
    Logging.info("Turtles will stay in current position")
    Logging.info("Use 'resume' to continue or 'recall' to return turtles")
end

--- Resume a paused or interrupted build
-- Usage: resume
function Commands.resume(args)
    if not Swarm then
        Logging.error("No swarm state available")
        return
    end

    -- Check for paused build in memory first
    local build = Swarm.build

    -- If not in memory, try to load from file
    if not build then
        if fs.exists(Config.BUILD_STATE_FILE) then
            local file = fs.open(Config.BUILD_STATE_FILE, "r")
            if file then
                local content = file.readAll()
                file.close()
                if content and content ~= "" then
                    build = textutils.unserialize(content)
                end
            end
        end
    end

    -- Check if there's a build to resume
    if not build then
        Logging.info("No paused build found")
        return
    end

    if build.phase == "COMPLETE" then
        Logging.info("Build already complete. Use 'build room' to start new build.")
        return
    end

    if build.phase ~= "PAUSED" then
        Logging.info("Build is not paused (phase: " .. (build.phase or "unknown") .. ")")
        return
    end

    -- Check for available turtles
    local turtle_count = Commands.get_turtle_count()
    if turtle_count == 0 then
        Logging.error("No turtles available to resume build")
        return
    end

    -- Restore build state
    Swarm.build = build

    -- Re-calculate sectors if not present
    if not Swarm.sectors or #Swarm.sectors == 0 then
        Swarm.sectors = Builder.calculate_sectors(
            build.width,
            build.length,
            build.height,
            build.origin,
            turtle_count
        )
    end

    -- Re-assign incomplete sectors to available turtles
    local incomplete_sectors = {}
    for _, sector in ipairs(Swarm.sectors) do
        if sector.status ~= "complete" then
            sector.status = "pending"
            sector.assigned_to = nil
            table.insert(incomplete_sectors, sector)
        end
    end

    if #incomplete_sectors == 0 then
        Logging.info("All sectors already complete!")
        build.phase = "COMPLETE"
        return
    end

    -- Assign sectors to available turtles
    local assignments, pending = Builder.assign_sectors(incomplete_sectors, Swarm.turtles, rednet.send)
    Swarm.assignments = assignments
    Swarm.pending_sectors = pending

    -- Update build phase
    build.phase = "EXCAVATING"

    -- Persist resumed state
    local file = fs.open(Config.BUILD_STATE_FILE, "w")
    if file then
        file.write(textutils.serialize(build))
        file.close()
    end

    local progress = Builder.get_progress(Swarm.sectors)
    local assigned_count = 0
    for _ in pairs(assignments) do
        assigned_count = assigned_count + 1
    end

    Logging.info("Resuming build from " .. progress .. "%")
    Logging.info("Re-assigned " .. assigned_count .. " sectors to turtles")
    if #pending > 0 then
        Logging.info(#pending .. " sectors queued for turtles that finish early")
    end
end

--- Placeholder for cancel command
function Commands.cancel(args)
    Logging.info("[Future] Cancel command not yet implemented")
end

--- Display help information
function Commands.help(args)
    Logging.info("")
    Logging.info("============ BASE BUILDER COMMANDS ============")
    Logging.info("")
    Logging.info("  build room <width> <length>  - Start room construction")
    Logging.info("  status                       - Show swarm status and turtle positions")
    Logging.info("  update [--force]             - Update controller and all turtles")
    Logging.info("  recall                       - [Not yet implemented] Recall all turtles")
    Logging.info("  pause                        - [Not yet implemented] Pause operations")
    Logging.info("  resume                       - [Not yet implemented] Resume operations")
    Logging.info("  cancel                       - [Not yet implemented] Cancel current build")
    Logging.info("  help                         - Show this help message")
    Logging.info("")
    Logging.info("================================================")
end

-- ============================================================================
-- COMMAND DISPATCHER
-- ============================================================================

--- Dispatch a command to its handler
-- @param input string: full input line from user (e.g., "update" or "build 10 20")
-- @return boolean: true if command was recognized and executed
function Commands.execute(input)
    if not input or input == "" then
        return false
    end

    -- Parse command and arguments
    local parts = {}
    for part in string.gmatch(input, "%S+") do
        table.insert(parts, part)
    end

    local cmd = parts[1]
    local args = {}
    for i = 2, #parts do
        table.insert(args, parts[i])
    end

    -- Dispatch to handler
    if Commands[cmd] then
        Commands[cmd](args)
        return true
    else
        Logging.error("Unknown command: " .. cmd)
        return false
    end
end

return Commands
