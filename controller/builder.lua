-- Base Builder Room Construction Module
-- Handles sector calculation and task assignment

local Config = require("shared.config")
local Logging = require("shared.logging")

local Builder = {}

-- ============================================================================
-- SECTOR CALCULATION
-- ============================================================================

--- Calculate sectors for a room build
-- Divides room into N vertical columns (one per turtle)
-- @param width number: Room width
-- @param length number: Room length
-- @param height number: Room height (excavation depth)
-- @param origin table: {x, y, z} build origin
-- @param turtle_count number: Number of available turtles
-- @return table: Array of sector definitions
function Builder.calculate_sectors(width, length, height, origin, turtle_count)
    if turtle_count <= 0 then
        Logging.error("Cannot calculate sectors with 0 turtles")
        return {}
    end

    local sectors = {}

    -- If more turtles than columns, limit to width
    local effective_turtle_count = math.min(turtle_count, width)

    local base_width = math.floor(width / effective_turtle_count)
    local remainder = width % effective_turtle_count

    local x_offset = 0
    for i = 1, effective_turtle_count do
        local sector_width = base_width
        -- Last turtle gets any remainder blocks
        if i == effective_turtle_count then
            sector_width = sector_width + remainder
        end

        local sector = {
            id = i,
            x_start = origin.x + x_offset,
            x_end = origin.x + x_offset + sector_width - 1,
            z_start = origin.z,
            z_end = origin.z + length - 1,
            y_top = origin.y + height - 1,
            y_bottom = origin.y,
            status = "pending",      -- pending, assigned, in_progress, complete
            assigned_to = nil,       -- turtle ID when assigned
            progress = 0             -- blocks completed
        }
        table.insert(sectors, sector)
        x_offset = x_offset + sector_width
    end

    Logging.info("Calculated " .. #sectors .. " sectors for " .. width .. "x" .. length .. " room")
    return sectors
end

-- ============================================================================
-- SECTOR ASSIGNMENT
-- ============================================================================

--- Assign sectors to available turtles
-- @param sectors table: Array of sector definitions
-- @param turtles table: Map of turtle_id -> turtle_data
-- @param send_func function: Function to send messages (rednet.send)
-- @return table: assignments map {turtle_id -> sector}
-- @return table: pending sectors not yet assigned
function Builder.assign_sectors(sectors, turtles, send_func)
    local assignments = {}
    local pending = {}
    local sector_index = 1

    -- Get list of available (non-TIMEOUT) turtles
    local available_turtles = {}
    for turtle_id, turtle in pairs(turtles) do
        if turtle.state ~= "TIMEOUT" then
            table.insert(available_turtles, {id = turtle_id, data = turtle})
        end
    end

    -- Assign one sector per available turtle
    for _, turtle_entry in ipairs(available_turtles) do
        if sector_index <= #sectors then
            local sector = sectors[sector_index]
            local turtle_id = turtle_entry.id

            -- Mark sector as assigned
            sector.assigned_to = turtle_id
            sector.status = "assigned"

            -- Track assignment
            assignments[turtle_id] = sector

            -- Send TASK_ASSIGN message to turtle
            local task_message = {
                type = "TASK_ASSIGN",
                sector = {
                    id = sector.id,
                    x_start = sector.x_start,
                    x_end = sector.x_end,
                    z_start = sector.z_start,
                    z_end = sector.z_end,
                    y_top = sector.y_top,
                    y_bottom = sector.y_bottom
                },
                build_type = "room"
            }

            -- Send task assignment
            Builder.send_task(turtle_id, task_message, send_func)

            Logging.info("Assigned sector " .. sector.id .. " to turtle " .. turtle_id)
            sector_index = sector_index + 1
        end
    end

    -- Remaining sectors go to pending queue
    for i = sector_index, #sectors do
        table.insert(pending, sectors[i])
    end

    if #pending > 0 then
        Logging.info(#pending .. " sectors queued for turtles that finish early")
    end

    return assignments, pending
end

--- Send message (single attempt)
-- Note: Full ACK-based retry would require async tracking which complicates MVP.
-- For now, we send once. The controller's SECTOR_COMPLETE handler will reassign
-- if a turtle fails to complete its sector.
-- @param turtle_id number: Target turtle ID
-- @param message table: Message to send
-- @param send_func function: Send function (rednet.send)
-- @return boolean: true if sent successfully
function Builder.send_task(turtle_id, message, send_func)
    send_func(turtle_id, message)
    Logging.debug("Sent " .. message.type .. " to turtle " .. turtle_id)
    return true
end

-- ============================================================================
-- SECTOR QUEUE MANAGEMENT
-- ============================================================================

--- Get next pending sector from queue
-- @param pending table: Array of pending sectors
-- @return table|nil: Next sector or nil if none available
function Builder.get_next_pending_sector(pending)
    if #pending > 0 then
        return table.remove(pending, 1)
    end
    return nil
end

--- Handle sector completion and reassignment
-- @param turtle_id number: Turtle that completed sector
-- @param sector_id number: Completed sector ID
-- @param sectors table: All sectors
-- @param pending table: Pending sector queue
-- @param send_func function: Send function
-- @return table|nil: New sector assigned, or nil if none available
function Builder.handle_sector_complete(turtle_id, sector_id, sectors, pending, send_func)
    -- Mark completed sector
    for _, sector in ipairs(sectors) do
        if sector.id == sector_id then
            sector.status = "complete"
            Logging.info("Sector " .. sector_id .. " completed by turtle " .. turtle_id)
            break
        end
    end

    -- Try to assign next pending sector
    local next_sector = Builder.get_next_pending_sector(pending)
    if next_sector then
        next_sector.assigned_to = turtle_id
        next_sector.status = "assigned"

        local task_message = {
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
        }

        send_func(turtle_id, task_message)
        Logging.info("Assigned next sector " .. next_sector.id .. " to turtle " .. turtle_id)
        return next_sector
    end

    Logging.info("No more sectors to assign to turtle " .. turtle_id)
    return nil
end

--- Check if all sectors are complete
-- @param sectors table: All sectors
-- @return boolean: true if all complete (false if no sectors)
function Builder.all_sectors_complete(sectors)
    if not sectors or #sectors == 0 then
        return false
    end
    for _, sector in ipairs(sectors) do
        if sector.status ~= "complete" then
            return false
        end
    end
    return true
end

--- Get build progress percentage
-- @param sectors table: All sectors
-- @return number: Progress percentage (0-100)
function Builder.get_progress(sectors)
    if not sectors or #sectors == 0 then
        return 0
    end
    local completed = 0
    for _, sector in ipairs(sectors) do
        if sector.status == "complete" then
            completed = completed + 1
        end
    end
    return math.floor((completed / #sectors) * 100)
end

return Builder
