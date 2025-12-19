-- Base Builder Turtle Main Program
-- Entry point after startup checks complete
-- Executes mining turtle tasks

-- Load dependencies
local Config = require("shared.config")
local Logging = require("shared.logging")

-- ============================================================================
-- TURTLE INITIALIZATION
-- ============================================================================

Logging.info("Turtle " .. os.getComputerLabel() .. " ready")
Logging.info("Waiting for commands from controller...")

-- ============================================================================
-- MAIN EVENT LOOP
-- ============================================================================

-- Placeholder: Event loop will be implemented in Epic 1 (Swarm Foundation)
-- Turtle will listen for rednet messages from controller:
-- - REGISTER: Send registration with ID and position
-- - UPDATE_PREPARE: Prepare for swarm update
-- - BUILD_TASK: Receive work assignment
-- - HEARTBEAT: Respond with status
-- - RECALL: Return to home position

Logging.debug("Starting main event loop...")
while true do
    local event, param = os.pullEvent()

    if event == "rednet_message" then
        Logging.debug("Received message: " .. tostring(param))
        -- Message handling will be implemented in Story 1.1 (Turtle Registration)
    elseif event == "key" and param == keys.q then
        Logging.info("Shutting down (Q pressed)")
        break
    end
end

Logging.info("Turtle shutdown complete")
