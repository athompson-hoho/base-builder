-- Base Builder Turtle Inventory Management
-- Handles AE2 integration for material pull and deposit

local Config = require("shared.config")
local Logging = require("shared.logging")
local Movement = require("turtle.movement")

local Inventory = {}

-- ============================================================================
-- SLOT CONFIGURATION
-- ============================================================================

local FUEL_SLOT = 1
local MATERIAL_SLOTS = {2, 3, 4}
local LADDER_SLOT = 5
local MINING_SLOTS = {6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16}

-- ============================================================================
-- ME INTERFACE INTEGRATION
-- ============================================================================

--- Get ME Interface peripheral
-- @return table|nil: ME Interface peripheral or nil if not found
function Inventory.get_me_interface()
    local side = Config.ME_INTERFACE_SIDE or "front"
    if peripheral.isPresent(side) then
        local p = peripheral.wrap(side)
        -- Check if it's an ME Interface (has pushItems or list method)
        if p and (p.pushItems or p.list) then
            return p
        end
    end
    Logging.warn("ME Interface not found on " .. side)
    return nil
end

--- Navigate to home base position
-- @return boolean: true if arrived at home base
function Inventory.navigate_to_home()
    local home_x = Config.HOME_BASE_X or 0
    local home_y = Config.HOME_BASE_Y or 64
    local home_z = Config.HOME_BASE_Z or 0

    Logging.info("Navigating to home base (" .. home_x .. ", " .. home_y .. ", " .. home_z .. ")")

    local nav_ok, nav_err = Movement.navigate_to(home_x, home_y, home_z)
    if not nav_ok then
        Logging.error("Failed to navigate to home base: " .. (nav_err or "unknown"))
        return false
    end

    Logging.info("Arrived at home base")
    return true
end

--- Face the ME Interface direction
-- @return boolean: true if facing ME Interface
function Inventory.face_me_interface()
    local side = Config.ME_INTERFACE_SIDE or "front"

    -- Map side to facing direction
    -- Assuming turtle arrives at home base facing north (direction 0)
    -- Adjust facing based on which side ME Interface is on
    if side == "front" then
        -- Already facing correct direction
        return true
    elseif side == "back" then
        Movement.face(2)  -- Face south (opposite of north)
    elseif side == "left" then
        Movement.face(3)  -- Face west
    elseif side == "right" then
        Movement.face(1)  -- Face east
    end

    return true
end

-- ============================================================================
-- SLOT MANAGEMENT
-- ============================================================================

--- Count empty material slots
-- @return number: count of empty material slots
function Inventory.count_empty_material_slots()
    local count = 0
    for _, slot in ipairs(MATERIAL_SLOTS) do
        if turtle.getItemCount(slot) == 0 then
            count = count + 1
        end
    end
    return count
end

--- Count total materials in inventory
-- @return number: total count of building materials
function Inventory.count_materials()
    local target = Config.BUILDING_MATERIAL or "minecraft:deepslate_bricks"
    local count = 0
    for _, slot in ipairs(MATERIAL_SLOTS) do
        local detail = turtle.getItemDetail(slot)
        if detail and detail.name == target then
            count = count + turtle.getItemCount(slot)
        end
    end
    return count
end

--- Check if material slots need refilling
-- @return boolean: true if any material slot is empty
function Inventory.needs_materials()
    return Inventory.count_empty_material_slots() > 0
end

--- Get space available in material slots
-- @return number: total empty space in material slots
function Inventory.get_material_space()
    local space = 0
    for _, slot in ipairs(MATERIAL_SLOTS) do
        local current = turtle.getItemCount(slot)
        space = space + (64 - current)  -- Assuming max stack is 64
    end
    return space
end

-- ============================================================================
-- MATERIAL PULL (Story 5.1)
-- ============================================================================

--- Pull materials from ME Interface
-- @param target_count number: Target number of items per slot (default 64)
-- @return boolean: true if materials received
-- @return string|nil: error reason if failed
function Inventory.pull_materials(target_count)
    target_count = target_count or Config.MATERIAL_PULL_AMOUNT or 64
    local target_material = Config.BUILDING_MATERIAL or "minecraft:deepslate_bricks"

    local me = Inventory.get_me_interface()
    if not me then
        return false, "no_me_interface"
    end

    local total_pulled = 0

    -- Pull to each material slot
    for _, slot in ipairs(MATERIAL_SLOTS) do
        local current = turtle.getItemCount(slot)
        local needed = target_count - current

        if needed > 0 then
            turtle.select(slot)

            -- Try different ME Interface methods depending on the mod
            local pulled = 0

            -- Method 1: pushItems (most common)
            if me.pushItems then
                -- pushItems(toName, item, count, toSlot)
                -- toName is the name of the target inventory (turtle)
                local turtle_name = "turtle_" .. os.getComputerID()

                -- Some mods use different signatures
                local ok, result = pcall(function()
                    return me.pushItems(turtle_name, target_material, needed, slot)
                end)

                if ok and result and result > 0 then
                    pulled = result
                end
            end

            -- Method 2: exportItem (AE2 Things style)
            if pulled == 0 and me.exportItem then
                local ok, result = pcall(function()
                    return me.exportItem({name = target_material, count = needed}, "up")
                end)
                if ok and result and result.count then
                    pulled = result.count
                end
            end

            -- Method 3: Direct suck from ME Interface block
            if pulled == 0 then
                -- Fallback: try turtle.suck() if ME exports automatically
                local ok, result = pcall(function()
                    return turtle.suck(needed)
                end)
                if ok and result then
                    -- Check what we got
                    local detail = turtle.getItemDetail(slot)
                    if detail and detail.name == target_material then
                        pulled = turtle.getItemCount(slot) - current
                    end
                end
            end

            if pulled > 0 then
                total_pulled = total_pulled + pulled
                Logging.debug("Pulled " .. pulled .. " items to slot " .. slot)
            end
        end
    end

    if total_pulled > 0 then
        Logging.info("Pulled " .. total_pulled .. " " .. target_material)
        return true
    else
        Logging.warn("No materials available in ME system")
        return false, "no_materials"
    end
end

--- Request materials with retry logic
-- @return boolean: true if sufficient materials obtained
-- @return string|nil: error reason if failed
function Inventory.request_materials()
    local retries = Config.MATERIAL_PULL_RETRIES or 3
    local delay = Config.MATERIAL_PULL_DELAY or 5

    for attempt = 1, retries do
        Logging.info("Material request attempt " .. attempt .. "/" .. retries)

        local pulled, err = Inventory.pull_materials()
        if pulled then
            local count = Inventory.count_materials()
            Logging.info("Material slots now have " .. count .. " items")
            return true
        end

        if err == "no_me_interface" then
            Logging.error("Cannot access ME Interface")
            return false, err
        end

        if attempt < retries then
            Logging.info("Waiting " .. delay .. "s before retry...")
            os.sleep(delay)
        end
    end

    Logging.error("Material shortage after " .. retries .. " attempts")
    return false, "material_shortage"
end

--- Full material refill sequence
-- Navigates home, pulls materials, returns success
-- @return boolean: true if materials obtained
-- @return string|nil: error reason if failed
function Inventory.refill_materials()
    -- Navigate to home base
    local arrived = Inventory.navigate_to_home()
    if not arrived then
        return false, "navigation_failed"
    end

    -- Face ME Interface
    Inventory.face_me_interface()

    -- Request materials with retries
    local success, err = Inventory.request_materials()
    return success, err
end

-- ============================================================================
-- RESOURCE DEPOSIT (Story 5.2)
-- ============================================================================

--- Deposit items from a slot to ME Interface
-- @param slot number: Slot to deposit from
-- @return boolean: true if slot emptied
-- @return number: items deposited
function Inventory.deposit_slot(slot)
    local count = turtle.getItemCount(slot)
    if count == 0 then
        return true, 0
    end

    turtle.select(slot)
    local me = Inventory.get_me_interface()
    if not me then
        -- Fallback: try turtle.drop() directly
        local ok = turtle.drop(count)
        if ok then
            local remaining = turtle.getItemCount(slot)
            return remaining == 0, count - remaining
        end
        return false, 0
    end

    local deposited = 0

    -- Try different ME Interface methods
    -- Method 1: pullItems (ME pulls from turtle)
    if me.pullItems then
        local turtle_name = "turtle_" .. os.getComputerID()
        local ok, result = pcall(function()
            return me.pullItems(turtle_name, slot, count)
        end)
        if ok and result and result > 0 then
            deposited = result
        end
    end

    -- Method 2: importItem (AE2 Things style)
    if deposited == 0 and me.importItem then
        local detail = turtle.getItemDetail(slot)
        if detail then
            local ok, result = pcall(function()
                return me.importItem({name = detail.name, count = count}, "up")
            end)
            if ok and result and result.count then
                deposited = result.count
            end
        end
    end

    -- Method 3: turtle.drop() if ME has hopper/input mode
    if deposited == 0 then
        local ok, result = pcall(function()
            return turtle.drop(count)
        end)
        if ok and result then
            deposited = count - turtle.getItemCount(slot)
        end
    end

    local remaining = turtle.getItemCount(slot)
    return remaining == 0, deposited
end

--- Keep coal for fuel reserve
-- Moves coal from mining slots to fuel slot (up to 64)
-- @return number: coal moved to fuel slot
function Inventory.keep_fuel_coal()
    local fuel_slot = FUEL_SLOT
    local current_fuel = turtle.getItemCount(fuel_slot)
    local space = 64 - current_fuel
    local coal_moved = 0

    if space <= 0 then
        return 0
    end

    -- Check mining slots for coal
    for _, slot in ipairs(MINING_SLOTS) do
        local detail = turtle.getItemDetail(slot)
        if detail and detail.name == "minecraft:coal" then
            local to_move = math.min(turtle.getItemCount(slot), space - coal_moved)
            if to_move > 0 then
                turtle.select(slot)
                turtle.transferTo(fuel_slot, to_move)
                coal_moved = coal_moved + to_move
            end
        end
        if coal_moved >= space then
            break
        end
    end

    if coal_moved > 0 then
        Logging.info("Kept " .. coal_moved .. " coal for fuel")
    end
    return coal_moved
end

--- Deposit all mining slots to ME Interface
-- @return boolean: true if all items deposited
-- @return number: total items deposited
function Inventory.deposit_items()
    local total_deposited = 0
    local all_empty = true

    for _, slot in ipairs(MINING_SLOTS) do
        local emptied, count = Inventory.deposit_slot(slot)
        total_deposited = total_deposited + count
        if not emptied then
            all_empty = false
            Logging.warn("Could not fully deposit slot " .. slot)
        end
    end

    if total_deposited > 0 then
        Logging.info("Deposited " .. total_deposited .. " items to ME")
    end

    return all_empty, total_deposited
end

--- Check if mining slots are full
-- @return boolean: true if all mining slots have items
function Inventory.is_inventory_full()
    for _, slot in ipairs(MINING_SLOTS) do
        if turtle.getItemCount(slot) == 0 then
            return false
        end
    end
    return true
end

--- Count items in mining slots
-- @return number: total items in mining slots
function Inventory.count_mining_items()
    local count = 0
    for _, slot in ipairs(MINING_SLOTS) do
        count = count + turtle.getItemCount(slot)
    end
    return count
end

--- Full deposit sequence
-- Navigates home, keeps coal, deposits items
-- @return boolean: true if deposit successful
-- @return string|nil: error reason if failed
function Inventory.deposit_resources()
    -- Navigate to home base
    local arrived = Inventory.navigate_to_home()
    if not arrived then
        return false, "navigation_failed"
    end

    -- Face ME Interface
    Inventory.face_me_interface()

    -- Keep coal for fuel reserve
    Inventory.keep_fuel_coal()

    -- Deposit all mining items
    local success, count = Inventory.deposit_items()
    if not success then
        Logging.warn("Some items could not be deposited")
    end

    Logging.info("Deposit complete")
    return success, nil
end

-- ============================================================================
-- SLOT ACCESSORS
-- ============================================================================

--- Get material slot numbers
-- @return table: array of material slot numbers
function Inventory.get_material_slots()
    return MATERIAL_SLOTS
end

--- Get mining slot numbers
-- @return table: array of mining slot numbers
function Inventory.get_mining_slots()
    return MINING_SLOTS
end

--- Get fuel slot number
-- @return number: fuel slot number
function Inventory.get_fuel_slot()
    return FUEL_SLOT
end

--- Get ladder slot number
-- @return number: ladder slot number
function Inventory.get_ladder_slot()
    return LADDER_SLOT
end

-- ============================================================================
-- INVENTORY MANAGEMENT (Story 5.3)
-- ============================================================================

--- Get slot configuration summary
-- @return table: slot assignments
function Inventory.get_slot_config()
    return {
        fuel_slot = FUEL_SLOT,
        material_slots = MATERIAL_SLOTS,
        ladder_slot = LADDER_SLOT,
        mining_slots = MINING_SLOTS
    }
end

--- Compact inventory by consolidating same-item stacks
-- Moves items to fill partial stacks before creating new ones
-- @return number: slots freed by compaction
function Inventory.compact_inventory()
    local slots_freed = 0

    -- Build item index: which slots have which items
    local item_slots = {}  -- item_name -> {slot, slot, ...}

    for _, slot in ipairs(MINING_SLOTS) do
        local detail = turtle.getItemDetail(slot)
        if detail then
            if not item_slots[detail.name] then
                item_slots[detail.name] = {}
            end
            table.insert(item_slots[detail.name], slot)
        end
    end

    -- For each item type, consolidate stacks
    for item_name, slots in pairs(item_slots) do
        if #slots > 1 then
            -- Sort slots by count (ascending) so we move from smaller to larger
            table.sort(slots, function(a, b)
                return turtle.getItemCount(a) < turtle.getItemCount(b)
            end)

            -- Try to consolidate into later slots (larger stacks)
            for i = 1, #slots - 1 do
                local from_slot = slots[i]
                local from_count = turtle.getItemCount(from_slot)

                if from_count > 0 and from_count < 64 then
                    -- Try to move to a later slot with same item
                    for j = i + 1, #slots do
                        local to_slot = slots[j]
                        local to_count = turtle.getItemCount(to_slot)
                        local space = 64 - to_count

                        if space > 0 then
                            turtle.select(from_slot)
                            local transferred = turtle.transferTo(to_slot, math.min(from_count, space))
                            if transferred then
                                from_count = turtle.getItemCount(from_slot)
                                if from_count == 0 then
                                    slots_freed = slots_freed + 1
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if slots_freed > 0 then
        Logging.debug("Compacted inventory, freed " .. slots_freed .. " slots")
    end

    return slots_freed
end

--- Check if inventory should trigger a deposit trip
-- Compacts inventory first to maximize space
-- @return boolean: true if deposit trip needed
function Inventory.should_deposit()
    -- First compact to free space
    Inventory.compact_inventory()

    -- Then check if full
    return Inventory.is_inventory_full()
end

--- Save inventory state to file
-- @return boolean: true if saved successfully
function Inventory.save_inventory_state()
    local state = {
        timestamp = os.epoch("utc"),
        slots = {}
    }

    -- Record all slots
    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)
        if detail then
            state.slots[slot] = {
                name = detail.name,
                count = turtle.getItemCount(slot)
            }
        end
    end

    -- Ensure state directory exists
    if not fs.exists("state") then
        fs.makeDir("state")
    end

    local file = fs.open("state/inventory.dat", "w")
    if file then
        file.write(textutils.serialize(state))
        file.close()
        return true
    end

    Logging.warn("Could not save inventory state")
    return false
end

--- Load inventory state from file
-- @return table|nil: saved state or nil if not found
function Inventory.load_inventory_state()
    if not fs.exists("state/inventory.dat") then
        return nil
    end

    local file = fs.open("state/inventory.dat", "r")
    if file then
        local content = file.readAll()
        file.close()
        local ok, state = pcall(textutils.unserialize, content)
        if ok and state then
            return state
        end
    end

    Logging.warn("Could not load inventory state")
    return nil
end

return Inventory
