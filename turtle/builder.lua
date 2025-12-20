-- Base Builder Turtle Construction Module
-- Handles block placement for walls, floor, ceiling

local Config = require("shared.config")
local Logging = require("shared.logging")
local Movement = require("turtle.movement")

local Builder = {}

-- ============================================================================
-- INVENTORY SLOT CONFIGURATION
-- ============================================================================

local MATERIAL_SLOTS = {2, 3, 4}  -- Slots 2-4 for building materials (slot 1 reserved for fuel)
local LADDER_SLOT = 5              -- Slot 5 for ladders

-- ============================================================================
-- BUILD STATE
-- ============================================================================

local build_state = {
    sector = nil,
    blocks_placed = 0,
    controller_id = nil,
    should_stop = false,
    last_progress_update = 0
}

-- ============================================================================
-- STOP CONTROL (for PAUSE/RECALL handling)
-- ============================================================================

--- Request build to stop gracefully
function Builder.stop()
    build_state.should_stop = true
    Logging.info("Build stop requested")
end

--- Check if build should continue
-- @return boolean: true if should continue, false if should stop
local function should_continue()
    return not build_state.should_stop
end

-- ============================================================================
-- WALL POSITION DETECTION (Task 2)
-- ============================================================================

--- Check if position is on wall perimeter
-- @param x number: X position relative to room origin (0-indexed)
-- @param z number: Z position relative to room origin (0-indexed)
-- @param width number: Room width
-- @param length number: Room length
-- @return boolean: true if wall position
function Builder.is_wall_position(x, z, width, length)
    -- Wall positions are on edges: x=0, x=width-1, z=0, z=length-1
    local on_x_edge = (x == 0 or x == width - 1)
    local on_z_edge = (z == 0 or z == length - 1)
    return on_x_edge or on_z_edge
end

-- ============================================================================
-- FLOOR/CENTER POSITION DETECTION (Story 4.2)
-- ============================================================================

--- Check if position is the center (for ladder shaft)
-- @param x number: X position relative to room origin
-- @param z number: Z position relative to room origin
-- @param width number: Room width
-- @param length number: Room length
-- @return boolean: true if center position
function Builder.is_center_position(x, z, width, length)
    local center_x = math.floor(width / 2)
    local center_z = math.floor(length / 2)
    return x == center_x and z == center_z
end

-- ============================================================================
-- MATERIAL CHECKING
-- ============================================================================

--- Check if turtle has building material in inventory
-- @return boolean: true if material available
-- @return number|nil: slot number with material
function Builder.has_building_material()
    local target_material = Config.BUILDING_MATERIAL or "minecraft:deepslate_bricks"

    for _, slot in ipairs(MATERIAL_SLOTS) do
        if turtle.getItemCount(slot) > 0 then
            local detail = turtle.getItemDetail(slot)
            if detail and detail.name == target_material then
                return true, slot
            end
        end
    end
    return false, nil
end

--- Select slot with building material
-- @return boolean: true if material selected
function Builder.select_building_material()
    local has_mat, slot = Builder.has_building_material()
    if has_mat then
        turtle.select(slot)
        return true
    end
    return false
end

--- Count total building materials in inventory
-- @return number: total count of building materials
function Builder.count_building_materials()
    local target_material = Config.BUILDING_MATERIAL or "minecraft:deepslate_bricks"
    local count = 0

    for _, slot in ipairs(MATERIAL_SLOTS) do
        local detail = turtle.getItemDetail(slot)
        if detail and detail.name == target_material then
            count = count + turtle.getItemCount(slot)
        end
    end
    return count
end

-- ============================================================================
-- LADDER HANDLING (Story 4.4)
-- ============================================================================

--- Check if turtle has ladders in inventory
-- @return boolean: true if ladders available
-- @return number|nil: slot number with ladders
function Builder.has_ladders()
    if turtle.getItemCount(LADDER_SLOT) > 0 then
        local detail = turtle.getItemDetail(LADDER_SLOT)
        if detail and detail.name == "minecraft:ladder" then
            return true, LADDER_SLOT
        end
    end
    return false, nil
end

--- Select slot with ladders
-- @return boolean: true if ladders selected
function Builder.select_ladders()
    local has_lad, slot = Builder.has_ladders()
    if has_lad then
        turtle.select(slot)
        return true
    end
    return false
end

--- Place a ladder in a direction
-- @param direction string: "forward", "up", or "down"
-- @return boolean: true if placed successfully
-- @return string|nil: error reason if failed
function Builder.place_ladder(direction)
    if not Builder.select_ladders() then
        Logging.warn("No ladders available")
        return false, "no_ladders"
    end

    local max_attempts = 3
    local place_func

    if direction == "forward" then
        place_func = turtle.place
    elseif direction == "up" then
        place_func = turtle.placeUp
    elseif direction == "down" then
        place_func = turtle.placeDown
    else
        Logging.error("Invalid place direction: " .. tostring(direction))
        return false
    end

    for attempt = 1, max_attempts do
        if place_func() then
            return true
        end
        if attempt < max_attempts then
            os.sleep(0.2)
        end
    end

    Logging.warn("Failed to place ladder " .. direction .. " after " .. max_attempts .. " attempts")
    return false
end

-- ============================================================================
-- MATERIAL REFILL (Story 5.1)
-- ============================================================================

--- Check and refill materials if needed
-- @param controller_id number: Controller ID for messages
-- @return boolean: true if materials available
function Builder.check_and_refill_materials(controller_id)
    -- Check if we have materials
    if Builder.has_building_material() then
        return true
    end

    Logging.info("Material slots empty, going to refill")

    -- Lazy load Inventory to avoid circular dependency
    local Inventory = require("turtle.inventory")

    -- Navigate to home and pull materials
    local success, err = Inventory.refill_materials()

    if not success then
        -- Report shortage to controller
        if controller_id and err == "material_shortage" then
            rednet.send(controller_id, {
                type = "MATERIAL_SHORTAGE",
                turtle_id = os.getComputerID(),
                material = Config.BUILDING_MATERIAL or "minecraft:deepslate_bricks"
            })
            Logging.error("Sent MATERIAL_SHORTAGE to controller")
        end
        return false
    end

    return true
end

-- ============================================================================
-- BLOCK PLACEMENT
-- ============================================================================

--- Place a single block in a direction with retry
-- @param direction string: "forward", "up", or "down"
-- @return boolean: true if placed successfully
-- @return string|nil: error reason if failed
function Builder.place_block(direction)
    if not Builder.select_building_material() then
        Logging.warn("No building material available")
        return false, "no_material"
    end

    local max_attempts = 3
    local place_func

    if direction == "forward" then
        place_func = turtle.place
    elseif direction == "up" then
        place_func = turtle.placeUp
    elseif direction == "down" then
        place_func = turtle.placeDown
    else
        Logging.error("Invalid place direction: " .. tostring(direction))
        return false
    end

    for attempt = 1, max_attempts do
        if place_func() then
            return true
        end

        -- Wait briefly and retry
        if attempt < max_attempts then
            os.sleep(0.2)
        end
    end

    Logging.warn("Failed to place block " .. direction .. " after " .. max_attempts .. " attempts")
    return false
end

--- Place a wall column at a specific position
-- Turtle navigates adjacent to wall position and places blocks upward
-- @param wall_x number: Wall X position (absolute coords)
-- @param y_bottom number: Bottom Y of wall
-- @param y_top number: Top Y of wall
-- @param wall_z number: Wall Z position (absolute coords)
-- @param sector table: Sector info for determining which side to approach from
-- @return boolean: true if column placed successfully
-- @return number: blocks placed
function Builder.place_wall_column(wall_x, y_bottom, y_top, wall_z, sector)
    local blocks_placed = 0

    -- Determine approach position and facing based on wall position
    -- We need to be adjacent to the wall and facing it
    local approach_x, approach_z, face_dir

    -- Check which edge this wall is on
    local rel_x = wall_x - sector.x_start
    local rel_z = wall_z - sector.z_start
    local width = sector.x_end - sector.x_start + 1
    local length = sector.z_end - sector.z_start + 1

    if rel_x == 0 then
        -- West wall - approach from inside (east), face west
        approach_x = wall_x + 1
        approach_z = wall_z
        face_dir = 3  -- West
    elseif rel_x == width - 1 then
        -- East wall - approach from inside (west), face east
        approach_x = wall_x - 1
        approach_z = wall_z
        face_dir = 1  -- East
    elseif rel_z == 0 then
        -- North wall - approach from inside (south), face north
        approach_x = wall_x
        approach_z = wall_z + 1
        face_dir = 0  -- North
    elseif rel_z == length - 1 then
        -- South wall - approach from inside (north), face south
        approach_x = wall_x
        approach_z = wall_z - 1
        face_dir = 2  -- South
    else
        Logging.error("Position is not on wall perimeter")
        return false, 0
    end

    -- Place blocks from bottom to top
    for y = y_bottom, y_top do
        if not should_continue() then
            Logging.info("Wall column stopped at Y=" .. y)
            return false, blocks_placed
        end

        -- Navigate to position adjacent to wall at this Y level
        local nav_ok, nav_err = Movement.navigate_to(approach_x, y, approach_z)
        if not nav_ok then
            Logging.warn("Failed to navigate to wall position: " .. (nav_err or "unknown"))
            return false, blocks_placed
        end

        -- Face the wall
        Movement.face(face_dir)

        -- Place block
        local placed, err = Builder.place_block("forward")
        if placed then
            blocks_placed = blocks_placed + 1
        elseif err == "no_material" then
            -- M2 fix: Material shortage - halt build gracefully
            Logging.error("Material shortage at (" .. wall_x .. ", " .. y .. ", " .. wall_z .. ")")
            return false, blocks_placed, "no_material"
        else
            Logging.warn("Failed to place wall block at (" .. wall_x .. ", " .. y .. ", " .. wall_z .. ")")
        end
    end

    return true, blocks_placed, nil
end

-- ============================================================================
-- FULL WALL BUILDING (Task 5)
-- ============================================================================

--- Build all walls for a sector
-- @param sector table: Sector bounds {x_start, x_end, z_start, z_end, y_bottom, y_top}
-- @param controller_id number: Controller ID for progress messages
-- @return boolean: true if complete, false if interrupted
function Builder.build_walls(sector, controller_id)
    Logging.info("Starting wall placement")
    Logging.info("  Sector X: " .. sector.x_start .. " to " .. sector.x_end)
    Logging.info("  Sector Z: " .. sector.z_start .. " to " .. sector.z_end)

    build_state.sector = sector
    build_state.blocks_placed = 0
    build_state.controller_id = controller_id
    build_state.should_stop = false
    build_state.last_progress_update = 0

    local width = sector.x_end - sector.x_start + 1
    local length = sector.z_end - sector.z_start + 1
    local wall_height = Config.WALL_HEIGHT or 7
    local y_bottom = sector.y_bottom or sector.y_start
    local y_top = y_bottom + wall_height - 1

    Logging.info("  Wall Y: " .. y_bottom .. " to " .. y_top)

    -- Track which positions we've placed walls at (to avoid corner duplicates)
    local placed_positions = {}

    -- Helper to mark position as placed
    local function mark_placed(x, z)
        placed_positions[x .. "," .. z] = true
    end

    local function is_placed(x, z)
        return placed_positions[x .. "," .. z] == true
    end

    -- Place walls on all four edges
    -- North wall (Z = z_start)
    for x = sector.x_start, sector.x_end do
        if not should_continue() then
            Logging.info("Wall building stopped")
            Builder.send_progress_update()
            return false
        end

        local z = sector.z_start
        if not is_placed(x, z) then
            local ok, count, err = Builder.place_wall_column(x, y_bottom, y_top, z, sector)
            build_state.blocks_placed = build_state.blocks_placed + count
            mark_placed(x, z)

            -- M2/L4 fix: Check for material shortage
            if err == "no_material" then
                Logging.error("Wall building halted: material shortage")
                Builder.send_progress_update()
                return false
            end

            -- Progress update
            if build_state.blocks_placed - build_state.last_progress_update >= Config.PROGRESS_UPDATE_INTERVAL then
                Builder.send_progress_update()
                build_state.last_progress_update = build_state.blocks_placed
            end
        end
    end

    -- South wall (Z = z_end)
    for x = sector.x_start, sector.x_end do
        if not should_continue() then
            Builder.send_progress_update()
            return false
        end

        local z = sector.z_end
        if not is_placed(x, z) then
            local ok, count, err = Builder.place_wall_column(x, y_bottom, y_top, z, sector)
            build_state.blocks_placed = build_state.blocks_placed + count
            mark_placed(x, z)

            if err == "no_material" then
                Logging.error("Wall building halted: material shortage")
                Builder.send_progress_update()
                return false
            end

            if build_state.blocks_placed - build_state.last_progress_update >= Config.PROGRESS_UPDATE_INTERVAL then
                Builder.send_progress_update()
                build_state.last_progress_update = build_state.blocks_placed
            end
        end
    end

    -- West wall (X = x_start), excluding corners already placed
    for z = sector.z_start + 1, sector.z_end - 1 do
        if not should_continue() then
            Builder.send_progress_update()
            return false
        end

        local x = sector.x_start
        if not is_placed(x, z) then
            local ok, count, err = Builder.place_wall_column(x, y_bottom, y_top, z, sector)
            build_state.blocks_placed = build_state.blocks_placed + count
            mark_placed(x, z)

            if err == "no_material" then
                Logging.error("Wall building halted: material shortage")
                Builder.send_progress_update()
                return false
            end

            if build_state.blocks_placed - build_state.last_progress_update >= Config.PROGRESS_UPDATE_INTERVAL then
                Builder.send_progress_update()
                build_state.last_progress_update = build_state.blocks_placed
            end
        end
    end

    -- East wall (X = x_end), excluding corners already placed
    for z = sector.z_start + 1, sector.z_end - 1 do
        if not should_continue() then
            Builder.send_progress_update()
            return false
        end

        local x = sector.x_end
        if not is_placed(x, z) then
            local ok, count, err = Builder.place_wall_column(x, y_bottom, y_top, z, sector)
            build_state.blocks_placed = build_state.blocks_placed + count
            mark_placed(x, z)

            if err == "no_material" then
                Logging.error("Wall building halted: material shortage")
                Builder.send_progress_update()
                return false
            end

            if build_state.blocks_placed - build_state.last_progress_update >= Config.PROGRESS_UPDATE_INTERVAL then
                Builder.send_progress_update()
                build_state.last_progress_update = build_state.blocks_placed
            end
        end
    end

    -- Wall building complete
    Logging.info("Wall placement complete!")
    Logging.info("Total blocks placed: " .. build_state.blocks_placed)

    Builder.send_progress_update()

    -- Send completion message
    if controller_id then
        rednet.send(controller_id, {
            type = "PHASE_COMPLETE",
            phase = "WALLS",
            turtle_id = os.getComputerID(),
            blocks_placed = build_state.blocks_placed
        })
        Logging.debug("Sent PHASE_COMPLETE (WALLS) to controller")
    end

    return true
end

-- ============================================================================
-- FULL FLOOR BUILDING (Story 4.2)
-- ============================================================================

--- Build floor for a sector
-- @param sector table: Sector bounds {x_start, x_end, z_start, z_end, y_bottom}
-- @param controller_id number: Controller ID for progress messages
-- @return boolean: true if complete, false if interrupted
function Builder.build_floor(sector, controller_id)
    Logging.info("Starting floor placement")
    Logging.info("  Sector X: " .. sector.x_start .. " to " .. sector.x_end)
    Logging.info("  Sector Z: " .. sector.z_start .. " to " .. sector.z_end)

    -- Initialize build state
    build_state.sector = sector
    build_state.blocks_placed = 0
    build_state.controller_id = controller_id
    build_state.should_stop = false
    build_state.last_progress_update = 0

    local width = sector.x_end - sector.x_start + 1
    local length = sector.z_end - sector.z_start + 1
    local y_floor = sector.y_bottom or sector.y_start

    Logging.info("  Floor Y: " .. y_floor)
    Logging.info("  Room dimensions: " .. width .. "x" .. length)

    -- M1 fix: Check for rooms too small to have interior floor
    if width <= 2 or length <= 2 then
        Logging.warn("Room too small for interior floor (need at least 3x3)")
        Logging.info("Floor placement complete (no interior positions)")
        if controller_id then
            rednet.send(controller_id, {
                type = "PHASE_COMPLETE",
                phase = "FLOOR",
                turtle_id = os.getComputerID(),
                blocks_placed = 0
            })
        end
        return true
    end

    -- Iterate interior positions (excluding walls)
    for rel_x = 1, width - 2 do
        for rel_z = 1, length - 2 do
            if not should_continue() then
                Logging.info("Floor building stopped")
                Builder.send_progress_update()
                return false
            end

            local abs_x = sector.x_start + rel_x
            local abs_z = sector.z_start + rel_z

            -- Skip center for ladder shaft (Story 4.4)
            if Builder.is_center_position(rel_x, rel_z, width, length) then
                Logging.debug("Skipping center (" .. abs_x .. ", " .. abs_z .. ") for ladder shaft")
            else
                -- Navigate above floor position (one block above floor level)
                local nav_ok, nav_err = Movement.navigate_to(abs_x, y_floor + 1, abs_z)
                if not nav_ok then
                    Logging.warn("Failed to navigate to floor position: " .. (nav_err or "unknown"))
                    -- Continue to next position rather than failing completely
                else
                    -- Place floor block below
                    local placed, err = Builder.place_block("down")
                    if placed then
                        build_state.blocks_placed = build_state.blocks_placed + 1
                    elseif err == "no_material" then
                        Logging.error("Floor building halted: material shortage")
                        Builder.send_progress_update()
                        return false
                    else
                        Logging.warn("Failed to place floor block at (" .. abs_x .. ", " .. y_floor .. ", " .. abs_z .. ")")
                    end
                end

                -- Progress update
                if build_state.blocks_placed - build_state.last_progress_update >= Config.PROGRESS_UPDATE_INTERVAL then
                    Builder.send_progress_update()
                    build_state.last_progress_update = build_state.blocks_placed
                end
            end
        end
    end

    -- Floor building complete
    Logging.info("Floor placement complete!")
    Logging.info("Total blocks placed: " .. build_state.blocks_placed)

    Builder.send_progress_update()

    -- Send completion message
    if controller_id then
        rednet.send(controller_id, {
            type = "PHASE_COMPLETE",
            phase = "FLOOR",
            turtle_id = os.getComputerID(),
            blocks_placed = build_state.blocks_placed
        })
        Logging.debug("Sent PHASE_COMPLETE (FLOOR) to controller")
    end

    return true
end

-- ============================================================================
-- FULL CEILING BUILDING (Story 4.3)
-- ============================================================================

--- Build ceiling for a sector
-- @param sector table: Sector bounds {x_start, x_end, z_start, z_end, y_bottom}
-- @param controller_id number: Controller ID for progress messages
-- @return boolean: true if complete, false if interrupted
function Builder.build_ceiling(sector, controller_id)
    Logging.info("Starting ceiling placement")
    Logging.info("  Sector X: " .. sector.x_start .. " to " .. sector.x_end)
    Logging.info("  Sector Z: " .. sector.z_start .. " to " .. sector.z_end)

    -- Initialize build state
    build_state.sector = sector
    build_state.blocks_placed = 0
    build_state.controller_id = controller_id
    build_state.should_stop = false
    build_state.last_progress_update = 0

    local width = sector.x_end - sector.x_start + 1
    local length = sector.z_end - sector.z_start + 1
    local wall_height = Config.WALL_HEIGHT or 7
    local y_ceiling = (sector.y_bottom or sector.y_start) + wall_height  -- Y = origin + 7

    Logging.info("  Ceiling Y: " .. y_ceiling)
    Logging.info("  Room dimensions: " .. width .. "x" .. length)

    -- Check for rooms too small
    if width < 1 or length < 1 then
        Logging.warn("Room too small for ceiling")
        if controller_id then
            rednet.send(controller_id, {
                type = "PHASE_COMPLETE",
                phase = "CEILING",
                turtle_id = os.getComputerID(),
                blocks_placed = 0
            })
        end
        return true
    end

    -- Iterate ALL positions in room footprint (including walls)
    for rel_x = 0, width - 1 do
        for rel_z = 0, length - 1 do
            if not should_continue() then
                Logging.info("Ceiling building stopped")
                Builder.send_progress_update()
                return false
            end

            local abs_x = sector.x_start + rel_x
            local abs_z = sector.z_start + rel_z

            -- Skip center for ladder shaft (Story 4.4)
            if Builder.is_center_position(rel_x, rel_z, width, length) then
                Logging.debug("Skipping center (" .. abs_x .. ", " .. abs_z .. ") for ladder shaft")
            else
                -- Navigate below ceiling position (one block below ceiling level)
                local nav_ok, nav_err = Movement.navigate_to(abs_x, y_ceiling - 1, abs_z)
                if not nav_ok then
                    Logging.warn("Failed to navigate to ceiling position: " .. (nav_err or "unknown"))
                else
                    -- Place ceiling block above
                    local placed, err = Builder.place_block("up")
                    if placed then
                        build_state.blocks_placed = build_state.blocks_placed + 1
                    elseif err == "no_material" then
                        Logging.error("Ceiling building halted: material shortage")
                        Builder.send_progress_update()
                        return false
                    else
                        Logging.warn("Failed to place ceiling block at (" .. abs_x .. ", " .. y_ceiling .. ", " .. abs_z .. ")")
                    end
                end

                -- Progress update
                if build_state.blocks_placed - build_state.last_progress_update >= Config.PROGRESS_UPDATE_INTERVAL then
                    Builder.send_progress_update()
                    build_state.last_progress_update = build_state.blocks_placed
                end
            end
        end
    end

    -- Ceiling building complete
    Logging.info("Ceiling placement complete!")
    Logging.info("Total blocks placed: " .. build_state.blocks_placed)

    Builder.send_progress_update()

    -- Send completion message
    if controller_id then
        rednet.send(controller_id, {
            type = "PHASE_COMPLETE",
            phase = "CEILING",
            turtle_id = os.getComputerID(),
            blocks_placed = build_state.blocks_placed
        })
        Logging.debug("Sent PHASE_COMPLETE (CEILING) to controller")
    end

    return true
end

-- ============================================================================
-- LADDER SHAFT BUILDING (Story 4.4)
-- ============================================================================

--- Build ladder shaft for a sector
-- @param sector table: Sector bounds {x_start, x_end, z_start, z_end, y_bottom}
-- @param controller_id number: Controller ID for progress messages
-- @return boolean: true if complete, false if interrupted
function Builder.build_ladder_shaft(sector, controller_id)
    Logging.info("Starting ladder shaft construction")
    Logging.info("  Sector X: " .. sector.x_start .. " to " .. sector.x_end)
    Logging.info("  Sector Z: " .. sector.z_start .. " to " .. sector.z_end)

    -- Initialize build state
    build_state.sector = sector
    build_state.blocks_placed = 0
    build_state.controller_id = controller_id
    build_state.should_stop = false
    build_state.last_progress_update = 0

    local width = sector.x_end - sector.x_start + 1
    local length = sector.z_end - sector.z_start + 1
    local wall_height = Config.WALL_HEIGHT or 7
    local y_floor = sector.y_bottom or sector.y_start
    local y_crawl_top = y_floor + wall_height + 1  -- Y = origin + 8

    -- Calculate center position
    local center_rel_x = math.floor(width / 2)
    local center_rel_z = math.floor(length / 2)
    local center_x = sector.x_start + center_rel_x
    local center_z = sector.z_start + center_rel_z

    Logging.info("  Center position: (" .. center_x .. ", " .. center_z .. ")")
    Logging.info("  Shaft Y range: " .. y_floor .. " to " .. y_crawl_top)

    -- Check for rooms too small for ladder shaft
    if width < 3 or length < 3 then
        Logging.warn("Room too small for center ladder shaft (need at least 3x3)")
        if controller_id then
            rednet.send(controller_id, {
                type = "PHASE_COMPLETE",
                phase = "LADDER_SHAFT",
                turtle_id = os.getComputerID(),
                blocks_placed = 0
            })
        end
        return true
    end

    -- ========================================
    -- Phase 1: Place shaft walls (4 blocks around center)
    -- ========================================
    Logging.info("Phase 1: Placing shaft walls")

    -- Shaft wall positions relative to center: N, S, E, W
    local shaft_wall_offsets = {
        {0, -1, 0},   -- North of center (face_dir = 0)
        {0, 1, 2},    -- South of center (face_dir = 2)
        {1, 0, 1},    -- East of center (face_dir = 1)
        {-1, 0, 3},   -- West of center (face_dir = 3)
    }

    -- Place shaft walls from Y=origin+1 (above floor) to Y=origin+8 (crawl space)
    for y = y_floor + 1, y_crawl_top do
        if not should_continue() then
            Logging.info("Ladder shaft building stopped")
            Builder.send_progress_update()
            return false
        end

        for _, offset in ipairs(shaft_wall_offsets) do
            local dx, dz, face_dir = offset[1], offset[2], offset[3]
            local wall_x = center_x + dx
            local wall_z = center_z + dz

            -- Navigate to center at this Y level
            local nav_ok, nav_err = Movement.navigate_to(center_x, y, center_z)
            if not nav_ok then
                Logging.warn("Failed to navigate to center: " .. (nav_err or "unknown"))
            else
                -- Face the wall position
                Movement.face(face_dir)

                -- Place shaft wall block
                local placed, err = Builder.place_block("forward")
                if placed then
                    build_state.blocks_placed = build_state.blocks_placed + 1
                elseif err == "no_material" then
                    Logging.error("Shaft building halted: material shortage")
                    Builder.send_progress_update()
                    return false
                else
                    Logging.warn("Failed to place shaft wall at (" .. wall_x .. ", " .. y .. ", " .. wall_z .. ")")
                end
            end
        end

        -- Progress update
        if build_state.blocks_placed - build_state.last_progress_update >= Config.PROGRESS_UPDATE_INTERVAL then
            Builder.send_progress_update()
            build_state.last_progress_update = build_state.blocks_placed
        end
    end

    -- ========================================
    -- Phase 2: Place ladders on north wall
    -- ========================================
    Logging.info("Phase 2: Placing ladders")

    -- Ladders go from Y=origin (floor level) to Y=origin+8 (crawl space top)
    -- We place them on the south face of the north wall
    -- Turtle needs to be at center, facing north, to place ladder on north wall

    for y = y_floor, y_crawl_top do
        if not should_continue() then
            Logging.info("Ladder placement stopped")
            Builder.send_progress_update()
            return false
        end

        -- Navigate to center at this Y level
        local nav_ok, nav_err = Movement.navigate_to(center_x, y, center_z)
        if not nav_ok then
            Logging.warn("Failed to navigate for ladder: " .. (nav_err or "unknown"))
        else
            -- Face north (toward the north shaft wall)
            Movement.face(0)  -- North

            -- Place ladder
            local placed, err = Builder.place_ladder("forward")
            if placed then
                build_state.blocks_placed = build_state.blocks_placed + 1
                Logging.debug("Placed ladder at Y=" .. y)
            elseif err == "no_ladders" then
                Logging.error("Ladder shaft halted: no ladders")
                Builder.send_progress_update()
                return false
            else
                Logging.warn("Failed to place ladder at Y=" .. y)
            end
        end
    end

    -- Ladder shaft complete
    Logging.info("Ladder shaft construction complete!")
    Logging.info("Total blocks/ladders placed: " .. build_state.blocks_placed)

    Builder.send_progress_update()

    -- Send completion message
    if controller_id then
        rednet.send(controller_id, {
            type = "PHASE_COMPLETE",
            phase = "LADDER_SHAFT",
            turtle_id = os.getComputerID(),
            blocks_placed = build_state.blocks_placed
        })
        Logging.debug("Sent PHASE_COMPLETE (LADDER_SHAFT) to controller")
    end

    return true
end

-- ============================================================================
-- PROGRESS REPORTING
-- ============================================================================

--- Send progress update to controller
function Builder.send_progress_update()
    if not build_state.controller_id then
        return
    end

    rednet.send(build_state.controller_id, {
        type = "PROGRESS_UPDATE",
        turtle_id = os.getComputerID(),
        sector_id = build_state.sector and build_state.sector.id or nil,
        blocks_completed = build_state.blocks_placed,
        phase = "BUILDING"
    })
    Logging.debug("Sent PROGRESS_UPDATE: " .. build_state.blocks_placed .. " blocks placed")
end

-- ============================================================================
-- STATE ACCESS
-- ============================================================================

--- Get current build state
-- @return table: Current state
function Builder.get_state()
    return {
        sector = build_state.sector,
        blocks_placed = build_state.blocks_placed
    }
end

return Builder
