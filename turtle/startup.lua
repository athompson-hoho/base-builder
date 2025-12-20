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

-- Open modem on configured side, or auto-detect if not found
local modem_side = nil

-- Check configured side first
if peripheral.isPresent(Config.MODEM_SIDE) and peripheral.getType(Config.MODEM_SIDE) == "modem" then
    modem_side = Config.MODEM_SIDE
else
    -- Auto-detect modem on any side if not on configured side
    for _, side in ipairs({"top", "bottom", "left", "right", "front", "back"}) do
        if peripheral.isPresent(side) and peripheral.getType(side) == "modem" then
            modem_side = side
            Logging.debug("Auto-detected modem on side: " .. side)
            break
        end
    end
end

if modem_side then
    if not rednet.isOpen(modem_side) then
        rednet.open(modem_side)
        Logging.debug("Opened modem on side: " .. modem_side)
    end
else
    Logging.error("No modem found on any side! Startup failed.")
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
