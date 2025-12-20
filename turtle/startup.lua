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

-- Open modem on configured side
if not rednet.isOpen(Config.MODEM_SIDE) then
    rednet.open(Config.MODEM_SIDE)
    Logging.debug("Opened modem on side: " .. Config.MODEM_SIDE)
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
