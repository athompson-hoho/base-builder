-- Base Builder Turtle Startup
-- Runs on startup to check for updates, register with controller, then load main.lua

-- Load the module system first
dofile("/shared/loader.lua")

-- Load dependencies
local Config = require("shared.config")
local Logging = require("shared.logging")
local Updater = require("shared.updater")

-- ============================================================================
-- STARTUP SEQUENCE
-- ============================================================================

-- Open modem - auto-detect from all available peripherals
local modem_side = nil

-- Get all available peripherals (includes sides and built-in)
local peripherals = peripheral.getNames()
Logging.debug("Available peripherals: " .. table.concat(peripherals, ", "))

-- Check configured side first
if peripheral.isPresent(Config.MODEM_SIDE) and peripheral.getType(Config.MODEM_SIDE) == "modem" then
    modem_side = Config.MODEM_SIDE
    Logging.debug("Found modem on configured side: " .. modem_side)
else
    -- Search all peripherals for a modem
    for _, name in ipairs(peripherals) do
        if peripheral.getType(name) == "modem" then
            modem_side = name
            Logging.debug("Auto-detected modem: " .. name)
            break
        end
    end
end

if modem_side then
    if not rednet.isOpen(modem_side) then
        rednet.open(modem_side)
        Logging.debug("Opened modem: " .. modem_side)
    end
else
    Logging.error("No modem found! Available peripherals: " .. table.concat(peripherals, ", "))
    error("No modem detected")
end

-- Check for updates
Logging.debug("Checking for updates...")
local should_update = Updater.check_and_prompt("turtle")

if should_update then
    Logging.info("Updating turtle...")
    local success, err = Updater.apply_update("turtle")
    if success then
        Logging.info("Update complete - rebooting...")
        sleep(1)
        os.reboot()
    else
        Logging.error(err or "Unknown error during update")
        Logging.info("Continuing with current version...")
    end
end

-- All startup checks complete - load main program
Logging.debug("Startup complete - loading main.lua")
dofile("turtle/main.lua")
