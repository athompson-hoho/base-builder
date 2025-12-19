-- Base Builder Controller Commands
-- Implements controller commands: update, build, status, recall, pause, resume, cancel

local Commands = {}

-- Load dependencies
local Config = require("shared.config")
local Logging = require("shared.logging")
local Updater = require("shared.updater")

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

--- Placeholder for build command
function Commands.build(args)
    Logging.info("[Story 2.1] Build command not yet implemented")
end

--- Display swarm status
function Commands.status(args)
    local turtle_count = Commands.get_turtle_count()

    Logging.info("")
    Logging.info("============ SWARM STATUS ============")
    Logging.info("Controller ID: " .. (Swarm and Swarm.controller_id or os.getComputerID()))
    Logging.info("Registered Turtles: " .. turtle_count)
    Logging.info("")

    if turtle_count == 0 then
        Logging.info("No turtles registered yet.")
        Logging.info("Start turtles to have them auto-register.")
    else
        Logging.info("ID       STATE      POSITION           LABEL")
        Logging.info("-------- ---------- ------------------ ----------------")
        for id, turtle in pairs(Swarm.turtles) do
            local pos = turtle.position or {x = "?", y = "?", z = "?"}
            local pos_str = string.format("(%s, %s, %s)", pos.x, pos.y, pos.z)
            local state = turtle.state or "UNKNOWN"
            local label = turtle.label or ("Turtle-" .. id)
            Logging.info(string.format("%-8s %-10s %-18s %s", id, state, pos_str, label))
        end
    end
    Logging.info("")
    Logging.info("=======================================")
end

--- Placeholder for recall command
function Commands.recall(args)
    Logging.info("[Story 2.5] Recall command not yet implemented")
end

--- Placeholder for pause command
function Commands.pause(args)
    Logging.info("[Story 2.6] Pause command not yet implemented")
end

--- Placeholder for resume command
function Commands.resume(args)
    Logging.info("[Story 2.7] Resume command not yet implemented")
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
    Logging.info("  status          - Show swarm status and turtle positions")
    Logging.info("  update [--force] - Update controller and all turtles")
    Logging.info("  build           - [Not yet implemented] Start a build")
    Logging.info("  recall          - [Not yet implemented] Recall all turtles")
    Logging.info("  pause           - [Not yet implemented] Pause operations")
    Logging.info("  resume          - [Not yet implemented] Resume operations")
    Logging.info("  cancel          - [Not yet implemented] Cancel current build")
    Logging.info("  help            - Show this help message")
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
