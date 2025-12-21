-- Base Builder Turtle Movement Module
-- Handles navigation, pathfinding, and collision avoidance

local Config = require("shared.config")
local Logging = require("shared.logging")

local Movement = {}

-- ============================================================================
-- POSITION AND ORIENTATION TRACKING
-- ============================================================================

-- Facing directions: 0=North (-Z), 1=East (+X), 2=South (+Z), 3=West (-X)
local facing = 0
local position = {x = 0, y = 0, z = 0}
local last_move_time = os.clock()

-- Direction vectors for each facing
local DIRECTION_VECTORS = {
    [0] = {x = 0, z = -1},   -- North
    [1] = {x = 1, z = 0},    -- East
    [2] = {x = 0, z = 1},    -- South
    [3] = {x = -1, z = 0}    -- West
}

-- ============================================================================
-- POSITION MANAGEMENT
-- ============================================================================

--- Set current position (usually from GPS)
-- @param x number: X coordinate
-- @param y number: Y coordinate
-- @param z number: Z coordinate
function Movement.set_position(x, y, z)
    position.x = x
    position.y = y
    position.z = z
end

--- Get current position
-- @return table: {x, y, z}
function Movement.get_position()
    return {x = position.x, y = position.y, z = position.z}
end

--- Set facing direction
-- @param dir number: 0=North, 1=East, 2=South, 3=West
function Movement.set_facing(dir)
    facing = dir % 4
end

--- Get facing direction
-- @return number: 0=North, 1=East, 2=South, 3=West
function Movement.get_facing()
    return facing
end

-- ============================================================================
-- BASIC MOVEMENT WITH RETRY
-- ============================================================================

local MAX_RETRIES = 5
local RETRY_DELAY = 1

--- Move forward with obstruction handling
-- @return boolean: true if move succeeded
-- @return string|nil: error message if failed
function Movement.forward()
    for attempt = 1, MAX_RETRIES do
        if turtle.forward() then
            -- Update position based on facing
            local vec = DIRECTION_VECTORS[facing]
            position.x = position.x + vec.x
            position.z = position.z + vec.z
            last_move_time = os.clock()
            return true, nil
        end

        -- Check what's blocking us
        local blocked, block_info = turtle.inspect()
        if blocked then
            Logging.debug("Blocked by " .. (block_info.name or "unknown") .. " (attempt " .. attempt .. "/" .. MAX_RETRIES .. ")")

            -- If blocked by a turtle, yield
            if block_info.name == "computercraft:turtle_normal" or
               block_info.name == "computercraft:turtle_advanced" then
                Logging.debug("Blocked by another turtle, yielding...")
                os.sleep(RETRY_DELAY)
            else
                -- Solid block - can't move through
                Logging.debug("Blocked by solid block")
                break
            end
        else
            -- No block detected but move failed (entity?)
            os.sleep(RETRY_DELAY)
        end
    end

    return false, "blocked_after_retries"
end

--- Move up with obstruction handling
-- @return boolean: true if move succeeded
-- @return string|nil: error message if failed
function Movement.up()
    for attempt = 1, MAX_RETRIES do
        if turtle.up() then
            position.y = position.y + 1
            last_move_time = os.clock()
            return true, nil
        end

        local blocked, block_info = turtle.inspectUp()
        if blocked then
            Logging.debug("Blocked above by " .. (block_info.name or "unknown"))
            if block_info.name == "computercraft:turtle_normal" or
               block_info.name == "computercraft:turtle_advanced" then
                os.sleep(RETRY_DELAY)
            else
                break
            end
        else
            os.sleep(RETRY_DELAY)
        end
    end

    return false, "blocked_above"
end

--- Move down with obstruction handling
-- @return boolean: true if move succeeded
-- @return string|nil: error message if failed
function Movement.down()
    for attempt = 1, MAX_RETRIES do
        if turtle.down() then
            position.y = position.y - 1
            last_move_time = os.clock()
            return true, nil
        end

        local blocked, block_info = turtle.inspectDown()
        if blocked then
            Logging.debug("Blocked below by " .. (block_info.name or "unknown"))
            if block_info.name == "computercraft:turtle_normal" or
               block_info.name == "computercraft:turtle_advanced" then
                os.sleep(RETRY_DELAY)
            else
                break
            end
        else
            os.sleep(RETRY_DELAY)
        end
    end

    return false, "blocked_below"
end

--- Move backward
-- @return boolean: true if move succeeded
function Movement.back()
    if turtle.back() then
        local vec = DIRECTION_VECTORS[facing]
        position.x = position.x - vec.x
        position.z = position.z - vec.z
        last_move_time = os.clock()
        return true
    end
    return false
end

--- Turn left
function Movement.turn_left()
    turtle.turnLeft()
    facing = (facing - 1) % 4
end

--- Turn right
function Movement.turn_right()
    turtle.turnRight()
    facing = (facing + 1) % 4
end

-- ============================================================================
-- ALTERNATE ROUTE HANDLING
-- ============================================================================

--- Attempt to go over an obstacle (up, forward, down)
-- @return boolean: true if bypass succeeded
function Movement.bypass_obstacle()
    Logging.debug("Attempting obstacle bypass (up/over/down)")

    -- Try to go up
    local up_ok, up_err = Movement.up()
    if not up_ok then
        Logging.debug("Bypass failed: cannot go up")
        return false
    end

    -- Try to go forward at higher level
    local fwd_ok, fwd_err = Movement.forward()
    if not fwd_ok then
        -- Go back down
        Movement.down()
        Logging.debug("Bypass failed: cannot go forward at higher level")
        return false
    end

    -- Try to go back down
    local down_ok, down_err = Movement.down()
    if not down_ok then
        Logging.debug("Bypass partial: stayed at higher level")
        -- Still succeeded in moving forward, just at higher Y
    end

    Logging.debug("Obstacle bypass successful")
    return true
end

-- ============================================================================
-- FACING CONTROL
-- ============================================================================

--- Turn to face a specific direction
-- @param target_dir number: 0=North, 1=East, 2=South, 3=West
function Movement.face(target_dir)
    target_dir = target_dir % 4

    -- Calculate shortest turn direction
    local diff = (target_dir - facing) % 4

    if diff == 0 then
        -- Already facing correct direction
    elseif diff == 1 then
        Movement.turn_right()
    elseif diff == 2 then
        Movement.turn_right()
        Movement.turn_right()
    elseif diff == 3 then
        Movement.turn_left()
    end
end

--- Calculate direction to face to move from current position toward target
-- @param target_x number: Target X coordinate
-- @param target_z number: Target Z coordinate
-- @return number: Direction to face (0-3)
function Movement.direction_to(target_x, target_z)
    local dx = target_x - position.x
    local dz = target_z - position.z

    -- Prioritize X movement if larger
    if math.abs(dx) >= math.abs(dz) then
        if dx > 0 then return 1 end  -- East
        if dx < 0 then return 3 end  -- West
    end

    if dz > 0 then return 2 end  -- South
    if dz < 0 then return 0 end  -- North

    return facing  -- Already at target
end

-- ============================================================================
-- NAVIGATION
-- ============================================================================

--- Navigate to a target position
-- @param target_x number: Target X coordinate
-- @param target_y number: Target Y coordinate
-- @param target_z number: Target Z coordinate
-- @return boolean: true if navigation succeeded
-- @return string|nil: error message if failed
function Movement.navigate_to(target_x, target_y, target_z)
    Logging.info("Navigating to (" .. target_x .. ", " .. target_y .. ", " .. target_z .. ")")

    local max_iterations = 1000  -- Safety limit
    local iterations = 0

    while iterations < max_iterations do
        iterations = iterations + 1

        -- Check if we've arrived
        if position.x == target_x and position.y == target_y and position.z == target_z then
            Logging.info("Arrived at destination")
            return true, nil
        end

        -- Check for deadlock (stuck for >10 seconds)
        if os.clock() - last_move_time > 10 then
            Logging.warn("Deadlock detected - stuck for 10+ seconds")
            return false, "deadlock"
        end

        -- Move in Y first (safer to be at right height)
        if position.y < target_y then
            local ok, err = Movement.up()
            if not ok then
                Logging.warn("Cannot move up: " .. (err or "unknown"))
                return false, "blocked_vertical"
            end
        elseif position.y > target_y then
            local ok, err = Movement.down()
            if not ok then
                Logging.warn("Cannot move down: " .. (err or "unknown"))
                return false, "blocked_vertical"
            end
        else
            -- At correct Y level, move in X/Z
            local dir = Movement.direction_to(target_x, target_z)
            Movement.face(dir)

            local ok, err = Movement.forward()
            if not ok then
                -- Try bypass
                if not Movement.bypass_obstacle() then
                    Logging.warn("Navigation blocked, cannot bypass")
                    return false, "blocked"
                end
            end
        end
    end

    Logging.error("Navigation exceeded max iterations")
    return false, "max_iterations"
end

-- ============================================================================
-- DEADLOCK DETECTION
-- ============================================================================

--- Check if turtle is in deadlock (no movement for extended time)
-- @return boolean: true if deadlocked
function Movement.is_deadlocked()
    return (os.clock() - last_move_time) > 10
end

--- Get time since last successful movement
-- @return number: seconds since last move
function Movement.time_since_move()
    return os.clock() - last_move_time
end

-- ============================================================================
-- FUEL RESERVE CALCULATION (Story 5.6)
-- ============================================================================

--- Calculate required fuel reserve to return home
-- @param pos table: Current position {x, y, z} (default: current position)
-- @param home table: Home base position {x, y, z} (default: config)
-- @return number: Required fuel to return home (with safety margin)
function Movement.calculate_fuel_reserve(pos, home)
    pos = pos or Movement.get_position()
    home = home or {
        x = Config.HOME_BASE_X or 0,
        y = Config.HOME_BASE_Y or 64,
        z = Config.HOME_BASE_Z or 0
    }

    -- Calculate Manhattan distance
    local distance = math.abs(pos.x - home.x) +
                     math.abs(pos.y - home.y) +
                     math.abs(pos.z - home.z)

    -- Apply safety margin (1.5x distance) and enforce minimum
    local reserve = math.max(distance * 1.5, 100)

    Logging.debug("Fuel reserve needed: " .. math.ceil(reserve) ..
                  " (distance: " .. distance .. ")")

    return reserve
end

--- Check if turtle has enough fuel to continue operating
-- @param safety_margin number: Additional fuel to keep safe (default 50)
-- @return boolean: true if can continue, false if should RTB
function Movement.has_fuel_to_continue(safety_margin)
    safety_margin = safety_margin or 50

    local pos = Movement.get_position()
    if not pos then
        Logging.warn("Could not determine position for fuel check")
        return false  -- Conservative: assume stranded
    end

    local current_fuel = turtle.getFuelLevel()
    local reserve = Movement.calculate_fuel_reserve(pos)
    local needed = reserve + safety_margin

    if current_fuel < needed then
        local shortfall = needed - current_fuel
        Logging.warn("Fuel low: " .. current_fuel .. " / " .. needed ..
                     " (need " .. shortfall .. " more)")
        return false
    end

    -- Log status if fuel margin is low
    local fuel_remaining = current_fuel - needed
    if fuel_remaining < (reserve * 0.5) then
        Logging.info("Fuel margin: " .. fuel_remaining .. " (threshold: " .. math.ceil(reserve * 0.5) .. ")")
    end

    return true
end

return Movement
