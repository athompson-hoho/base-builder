-- Base Builder Logging
-- Consistent logging helpers for controller and turtles

local Logging = {}

-- Debug mode flag - set to true for verbose output
local DEBUG = false

--- Print info message (normal)
-- @param message string: The message to print
function Logging.info(message)
    print(message)
end

--- Print warning message (prefixed with [!])
-- @param message string: The warning message
function Logging.warn(message)
    print("[!] " .. message)
end

--- Print error message (prefixed with [ERROR])
-- @param message string: The error message
function Logging.error(message)
    print("[ERROR] " .. message)
end

--- Print debug message (only if DEBUG enabled)
-- @param message string: The debug message
function Logging.debug(message)
    if DEBUG then
        print("[DEBUG] " .. message)
    end
end

--- Enable or disable debug output
-- @param enabled boolean: Set to true to enable debug output
function Logging.set_debug(enabled)
    DEBUG = enabled
end

return Logging
