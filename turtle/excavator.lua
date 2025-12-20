-- Base Builder Turtle Excavation Module
-- Handles top-down layer-by-layer excavation of assigned sectors

local Config = require("shared.config")
local Logging = require("shared.logging")
local Movement = require("turtle.movement")

local Excavator = {}

-- ============================================================================
-- STATE PERSISTENCE (Story 3.2)
-- ============================================================================

local STATE_FILE = "/state/excavation.dat"

-- ============================================================================
-- EXCAVATION STATE
-- ============================================================================

local excavation_state = {
    sector = nil,
    current_y = 0,
    current_x = 0,
    current_z = 0,
    blocks_excavated = 0,
    direction = 1,  -- 1 = increasing X, -1 = decreasing X
    controller_id = nil,
    should_stop = false,        -- Flag to stop excavation (set by PAUSE/RECALL)
    last_progress_update = 0,   -- Track last update to avoid skipping intervals
    completed_layers = {}       -- Track which Y layers are done (Story 3.2)
}

-- ============================================================================
-- DIG WITH RETRY (GRAVEL/SAND HANDLING)
-- ============================================================================

--- Dig with retry for falling blocks (gravel/sand)
-- @param direction string: "forward", "up", or "down"
-- @return boolean: true if successfully cleared
-- @return number: blocks dug
function Excavator.dig_with_retry(direction)
    local max_attempts = Config.DIG_RETRY_MAX or 10
    local retry_delay = Config.DIG_RETRY_DELAY or 0.3
    local blocks_dug = 0

    local dig_func, inspect_func
    if direction == "forward" then
        dig_func = turtle.dig
        inspect_func = turtle.inspect
    elseif direction == "up" then
        dig_func = turtle.digUp
        inspect_func = turtle.inspectUp
    elseif direction == "down" then
        dig_func = turtle.digDown
        inspect_func = turtle.inspectDown
    else
        Logging.error("Invalid dig direction: " .. tostring(direction))
        return false, 0
    end

    for attempt = 1, max_attempts do
        -- Check if there's a block
        local has_block, block_info = inspect_func()
        if not has_block then
            -- No block, we're done
            return true, blocks_dug
        end

        -- Try to dig
        if dig_func() then
            blocks_dug = blocks_dug + 1
            -- Wait briefly for falling blocks
            os.sleep(retry_delay)
        else
            -- Dig failed - might be bedrock or protected
            if attempt >= max_attempts then
                Logging.warn("Failed to dig " .. direction .. " after " .. max_attempts .. " attempts")
                Logging.warn("Block: " .. (block_info.name or "unknown"))
                return false, blocks_dug
            end
            os.sleep(retry_delay)
        end
    end
    -- Loop completed all attempts successfully
    return true, blocks_dug
end

-- ============================================================================
-- STOP CONTROL (for PAUSE/RECALL handling)
-- ============================================================================

--- Request excavation to stop gracefully
-- Called by main.lua when PAUSE or RECALL received
function Excavator.stop()
    excavation_state.should_stop = true
    Logging.info("Excavation stop requested")
end

--- Check if excavation should continue
-- @return boolean: true if should continue, false if should stop
local function should_continue()
    return not excavation_state.should_stop
end

-- ============================================================================
-- STATE PERSISTENCE FUNCTIONS (Story 3.2)
-- ============================================================================

--- Save excavation state to file
-- Called every PROGRESS_UPDATE_INTERVAL blocks and on stop
-- @return boolean: true if save successful
function Excavator.save_state()
    -- Ensure state directory exists
    if not fs.exists("/state") then
        fs.makeDir("/state")
    end

    local state = {
        sector = excavation_state.sector,
        current_y = excavation_state.current_y,
        current_x = excavation_state.current_x,
        current_z = excavation_state.current_z,
        blocks_excavated = excavation_state.blocks_excavated,
        direction = excavation_state.direction,  -- M1 fix: persist snake direction
        completed_layers = excavation_state.completed_layers or {}
    }

    local file = fs.open(STATE_FILE, "w")
    if file then
        file.write(textutils.serialize(state))
        file.close()
        Logging.debug("Saved excavation state to " .. STATE_FILE)
        return true
    end
    Logging.warn("Failed to save excavation state")
    return false
end

--- Load excavation state from file
-- @return table|nil: Saved state or nil if none exists
function Excavator.load_state()
    if not fs.exists(STATE_FILE) then
        return nil
    end

    local file = fs.open(STATE_FILE, "r")
    if file then
        local data = file.readAll()
        file.close()
        local state = textutils.unserialize(data)
        if state then
            Logging.debug("Loaded excavation state from " .. STATE_FILE)
            return state
        end
    end
    Logging.warn("Failed to load excavation state")
    return nil
end

--- Clear saved state (on successful completion)
function Excavator.clear_state()
    if fs.exists(STATE_FILE) then
        fs.delete(STATE_FILE)
        Logging.debug("Cleared excavation state file")
    end
end

-- ============================================================================
-- LAYER EXCAVATION
-- ============================================================================

--- Excavate a single layer (X-Z plane at current Y)
-- Uses snake pattern for efficiency
-- @param sector table: Sector bounds
-- @return boolean: true if completed, false if stopped
function Excavator.excavate_layer(sector)
    local pos = Movement.get_position()

    Logging.info("Excavating layer at Y=" .. pos.y)

    -- Snake pattern: alternate X direction each Z row
    -- M1 fix: use persisted direction for resume consistency
    local x_direction = excavation_state.direction or 1
    local start_x, end_x

    for z = sector.z_start, sector.z_end do
        -- Check for stop request (H1 fix)
        if not should_continue() then
            Logging.info("Layer excavation stopped at Z=" .. z)
            return false
        end

        -- Determine X traversal direction
        if x_direction == 1 then
            start_x = sector.x_start
            end_x = sector.x_end
        else
            start_x = sector.x_end
            end_x = sector.x_start
        end

        -- Move along X
        local x = start_x
        while true do
            -- Check for stop request (H1 fix)
            if not should_continue() then
                Logging.info("Layer excavation stopped at (" .. x .. ", " .. z .. ")")
                return false
            end

            -- Navigate to position if not there
            if pos.x ~= x or pos.z ~= z then
                local ok, err = Movement.navigate_to(x, pos.y, z)
                if not ok then
                    Logging.warn("Failed to navigate to (" .. x .. ", " .. pos.y .. ", " .. z .. "): " .. (err or "unknown"))
                end
                -- Always sync position after navigation attempt (M4 fix)
                pos = Movement.get_position()
            end

            -- Dig below (main excavation)
            local dig_ok, dug_count = Excavator.dig_with_retry("down")

            -- Update progress
            excavation_state.blocks_excavated = excavation_state.blocks_excavated + dug_count
            excavation_state.current_x = x
            excavation_state.current_z = z

            -- Send progress update when interval reached (M1 fix)
            local update_interval = Config.PROGRESS_UPDATE_INTERVAL or 10
            if excavation_state.blocks_excavated - excavation_state.last_progress_update >= update_interval then
                if excavation_state.controller_id then
                    Excavator.send_progress_update()
                end
                excavation_state.last_progress_update = excavation_state.blocks_excavated
                -- Save state periodically (Story 3.2 - AC3)
                Excavator.save_state()
            end

            -- Move to next X position
            if x_direction == 1 then
                if x >= end_x then break end
                x = x + 1
            else
                if x <= end_x then break end
                x = x - 1
            end

            -- Navigate to next X (might need to dig forward)
            Excavator.dig_with_retry("forward")
            Movement.forward()
            pos = Movement.get_position()
        end

        -- Move to next Z row
        if z < sector.z_end then
            -- Face south and move
            Movement.face(2)  -- South = +Z
            Excavator.dig_with_retry("forward")
            Movement.forward()
            pos = Movement.get_position()

            -- Reverse X direction for next row
            x_direction = x_direction * -1
            excavation_state.direction = x_direction  -- M1 fix: persist direction changes
        end
    end

    -- Reset direction for next layer
    excavation_state.direction = 1
    return true
end

-- ============================================================================
-- SECTOR EXCAVATION
-- ============================================================================

--- Excavate an entire sector top-down
-- @param sector table: Sector bounds {x_start, x_end, z_start, z_end, y_top, y_bottom}
-- @param controller_id number: Controller ID for progress messages
-- @return boolean: true if complete, false if interrupted
function Excavator.excavate_sector(sector, controller_id)
    Logging.info("Starting sector excavation")
    Logging.info("  Sector ID: " .. (sector.id or "?"))
    Logging.info("  X: " .. sector.x_start .. " to " .. sector.x_end)
    Logging.info("  Z: " .. sector.z_start .. " to " .. sector.z_end)
    Logging.info("  Y: " .. sector.y_top .. " to " .. sector.y_bottom)

    -- Check for saved state to resume (Story 3.2 - AC4)
    local saved_state = Excavator.load_state()
    local resuming = false
    if saved_state and saved_state.sector and saved_state.sector.id == sector.id then
        Logging.info("Resuming excavation from saved state")
        Logging.info("  Last position: (" .. saved_state.current_x .. ", " ..
                    saved_state.current_y .. ", " .. saved_state.current_z .. ")")
        Logging.info("  Blocks already excavated: " .. saved_state.blocks_excavated)

        -- Restore state
        excavation_state.sector = sector
        excavation_state.current_y = saved_state.current_y
        excavation_state.current_x = saved_state.current_x
        excavation_state.current_z = saved_state.current_z
        excavation_state.blocks_excavated = saved_state.blocks_excavated
        excavation_state.direction = saved_state.direction or 1  -- M1 fix: restore snake direction
        excavation_state.completed_layers = saved_state.completed_layers or {}
        resuming = true
    else
        -- Fresh start - initialize state
        excavation_state.sector = sector
        excavation_state.current_y = sector.y_top
        excavation_state.current_x = sector.x_start
        excavation_state.current_z = sector.z_start
        excavation_state.blocks_excavated = 0
        excavation_state.completed_layers = {}  -- Story 3.2 - AC5
    end

    excavation_state.controller_id = controller_id
    excavation_state.should_stop = false  -- Reset stop flag (H1 fix)
    excavation_state.last_progress_update = 0  -- Reset progress tracking

    -- Fuel check before starting (M2 fix)
    local fuel_level = turtle.getFuelLevel()
    if fuel_level ~= "unlimited" then
        local sector_width = sector.x_end - sector.x_start + 1
        local sector_length = sector.z_end - sector.z_start + 1
        local sector_height = sector.y_top - sector.y_bottom + 1
        local estimated_moves = sector_width * sector_length * sector_height * 2  -- Rough estimate
        if fuel_level < estimated_moves then
            Logging.warn("Low fuel warning: " .. fuel_level .. " fuel, estimated " .. estimated_moves .. " moves needed")
        end
        if fuel_level < Config.FUEL_RESERVE then
            Logging.error("Fuel critically low (" .. fuel_level .. "), aborting excavation")
            return false
        end
    end

    -- Navigate to starting position
    local start_x, start_y, start_z
    if resuming then
        -- Resume from saved position
        start_x = excavation_state.current_x
        start_y = excavation_state.current_y
        start_z = excavation_state.current_z
        Logging.info("Navigating to resume position...")
    else
        -- Fresh start at top-left corner
        start_x = sector.x_start
        start_y = sector.y_top
        start_z = sector.z_start
        Logging.info("Navigating to sector start position...")
    end

    local nav_ok, nav_err = Movement.navigate_to(start_x, start_y, start_z)
    if not nav_ok then
        Logging.error("Failed to reach position: " .. (nav_err or "unknown"))
        return false
    end

    -- Excavate layer by layer from top to bottom
    for y = sector.y_top, sector.y_bottom, -1 do
        -- Check for stop request (H1 fix)
        if not should_continue() then
            Logging.info("Sector excavation stopped at Y=" .. y)
            Excavator.send_progress_update()
            Excavator.save_state()  -- Story 3.2 - save on stop
            return false
        end

        -- Skip completed layers (Story 3.2 - AC5)
        if excavation_state.completed_layers[y] then
            Logging.info("Skipping completed layer Y=" .. y)
        else
            excavation_state.current_y = y

            Logging.info("Excavating layer " .. (sector.y_top - y + 1) .. "/" ..
                        (sector.y_top - sector.y_bottom + 1) .. " (Y=" .. y .. ")")

            -- Move to this Y level
            local pos = Movement.get_position()
            if pos.y ~= y then
                local move_ok, move_err = Movement.navigate_to(pos.x, y, pos.z)
                if not move_ok then
                    Logging.error("Failed to move to layer Y=" .. y)
                    Excavator.save_state()  -- Save before failing
                    return false
                end
            end

            -- Excavate the layer (M3 fix: handle return value)
            local layer_complete = Excavator.excavate_layer(sector)
            if not layer_complete then
                Logging.info("Layer excavation interrupted")
                Excavator.send_progress_update()
                Excavator.save_state()  -- Story 3.2 - save on interrupt
                return false
            end

            -- Mark layer as complete (Story 3.2 - AC5)
            excavation_state.completed_layers[y] = true
            Excavator.save_state()  -- Save after layer completion
        end

        -- Move down for next layer (except on last layer)
        if y > sector.y_bottom then
            Excavator.dig_with_retry("down")
            Movement.down()
        end
    end

    -- Sector complete
    Logging.info("Sector excavation complete!")
    Logging.info("Total blocks excavated: " .. excavation_state.blocks_excavated)

    -- Send final progress update
    Excavator.send_progress_update()

    -- Clear state file on successful completion (Story 3.2 - Task 4)
    Excavator.clear_state()

    -- Send SECTOR_COMPLETE
    if controller_id then
        rednet.send(controller_id, {
            type = "SECTOR_COMPLETE",
            sector_id = sector.id,
            turtle_id = os.getComputerID(),
            blocks_excavated = excavation_state.blocks_excavated
        })
        Logging.debug("Sent SECTOR_COMPLETE to controller")
    end

    return true
end

-- ============================================================================
-- PROGRESS REPORTING
-- ============================================================================

--- Send progress update to controller
function Excavator.send_progress_update()
    if not excavation_state.controller_id then
        return
    end

    rednet.send(excavation_state.controller_id, {
        type = "PROGRESS_UPDATE",
        turtle_id = os.getComputerID(),
        sector_id = excavation_state.sector and excavation_state.sector.id or nil,
        blocks_completed = excavation_state.blocks_excavated,
        current_y = excavation_state.current_y,
        phase = "EXCAVATING"
    })
    Logging.debug("Sent PROGRESS_UPDATE: " .. excavation_state.blocks_excavated .. " blocks")
end

-- ============================================================================
-- STATE ACCESS
-- ============================================================================

--- Get current excavation state
-- @return table: Current state
function Excavator.get_state()
    return {
        sector = excavation_state.sector,
        current_y = excavation_state.current_y,
        current_x = excavation_state.current_x,
        current_z = excavation_state.current_z,
        blocks_excavated = excavation_state.blocks_excavated,
        direction = excavation_state.direction,  -- M1 fix: include direction
        completed_layers = excavation_state.completed_layers  -- Story 3.2
    }
end

--- Set excavation state (for resume)
-- @param state table: State to restore
function Excavator.set_state(state)
    if state.sector then excavation_state.sector = state.sector end
    if state.current_y then excavation_state.current_y = state.current_y end
    if state.current_x then excavation_state.current_x = state.current_x end
    if state.current_z then excavation_state.current_z = state.current_z end
    if state.blocks_excavated then excavation_state.blocks_excavated = state.blocks_excavated end
    if state.direction then excavation_state.direction = state.direction end  -- L1 fix
    if state.completed_layers then excavation_state.completed_layers = state.completed_layers end  -- L1 fix
end

return Excavator
