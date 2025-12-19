-- Base Builder Controller Main Program
-- Entry point after startup checks complete
-- Manages command loop and swarm coordination

-- Load dependencies
local Config = require("shared.config")
local Logging = require("shared.logging")
local Commands = require("controller.commands")

-- ============================================================================
-- MAIN COMMAND LOOP
-- ============================================================================

Logging.info("Base Builder Controller ready")
Logging.info("Type 'help' for available commands")

-- Main command loop
while true do
    write("> ")
    local input = read()

    if input and input ~= "" then
        if not Commands.execute(input) then
            Logging.error("Command failed or not recognized: " .. input)
        end
    end
end
