-- Base Builder Configuration
-- Shared constants used by controller and turtles

local Config = {}

-- ============================================================================
-- VERSION INFORMATION
-- ============================================================================

Config.VERSION = "1.0.0"

-- ============================================================================
-- REPOSITORY & UPDATE CONFIGURATION
-- ============================================================================

Config.REPO_URL = "https://raw.githubusercontent.com/athompson-hoho/base-builder/main"
Config.VERSION_FILE = "/state/version.dat"
Config.COMPUTER_TYPE_FILE = "/state/computer_type.dat"
Config.BUILD_STATE_FILE = "/state/build_state.dat"

-- ============================================================================
-- UPDATE SYSTEM CONFIGURATION
-- ============================================================================

Config.UPDATE_CHECK_TIMEOUT = 5      -- Seconds to wait for GitHub response
Config.UPDATE_PROMPT_TIMEOUT = 10    -- Seconds before auto-skip on startup prompt
Config.UPDATE_WAIT_TIMEOUT = 30      -- Seconds to wait for turtle UPDATE_READY/COMPLETE responses

-- ============================================================================
-- COMMUNICATION CONFIGURATION
-- ============================================================================

Config.MODEM_SIDE = "right"           -- Default modem side (can be auto-detected)
Config.REDNET_CHANNEL = 1             -- Single Rednet channel for swarm
Config.HEARTBEAT_INTERVAL = 5         -- Seconds between heartbeats
Config.HEARTBEAT_TIMEOUT = 30         -- Seconds before turtle marked offline
Config.TASK_ACK_TIMEOUT = 5           -- Seconds to wait for TASK_ACK
Config.TASK_ACK_RETRIES = 3           -- Times to retry TASK_ASSIGN

-- ============================================================================
-- FUEL CONFIGURATION
-- ============================================================================

Config.FUEL_RESERVE = 1000            -- Minimum fuel to keep in reserve
Config.REFUEL_THRESHOLD = 2000        -- Fuel level to trigger refueling

-- ============================================================================
-- BUILD CONFIGURATION
-- ============================================================================

Config.ROOM_HEIGHT = 9                -- Total excavation height (7 walls + 2 crawl)
Config.WALL_HEIGHT = 7                -- Height of room walls
Config.MAX_ROOM_WIDTH = 64            -- Maximum room width
Config.MAX_ROOM_LENGTH = 64           -- Maximum room length

-- Build origin fallback (used if GPS unavailable)
Config.BUILD_ORIGIN_X = 0
Config.BUILD_ORIGIN_Y = 64
Config.BUILD_ORIGIN_Z = 0

return Config
