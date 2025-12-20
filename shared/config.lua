-- Base Builder Configuration
-- Shared constants used by controller and turtles

local Config = {}

-- ============================================================================
-- VERSION INFORMATION
-- ============================================================================

Config.VERSION = "1.0.1"

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
Config.BUILDING_MATERIAL = "minecraft:deepslate_bricks"  -- Default wall material

-- Build origin fallback (used if GPS unavailable)
Config.BUILD_ORIGIN_X = 0
Config.BUILD_ORIGIN_Y = 64
Config.BUILD_ORIGIN_Z = 0

-- ============================================================================
-- HOME BASE & AE2 CONFIGURATION
-- ============================================================================

-- Home base position (where ME Interface is located)
Config.HOME_BASE_X = 0
Config.HOME_BASE_Y = 64
Config.HOME_BASE_Z = 0

-- ME Interface is in front of turtle at home base
Config.ME_INTERFACE_SIDE = "front"

-- Material pull settings
Config.MATERIAL_PULL_AMOUNT = 64      -- Items to pull per slot
Config.MATERIAL_PULL_RETRIES = 3      -- Retry attempts before shortage
Config.MATERIAL_PULL_DELAY = 5        -- Seconds between retries

-- Fuel chest location (for refueling, Story 5.7)
Config.FUEL_CHEST_X = Config.HOME_BASE_X or 0
Config.FUEL_CHEST_Y = Config.HOME_BASE_Y or 64
Config.FUEL_CHEST_Z = (Config.HOME_BASE_Z or 0) + 1  -- One block away from home

-- Material polling settings (Story 5.4)
Config.MATERIAL_POLL_INTERVAL = 30    -- Seconds between material availability checks

-- ============================================================================
-- EXCAVATION CONFIGURATION
-- ============================================================================

Config.DIG_RETRY_MAX = 10             -- Max retries for gravel/sand falling blocks
Config.DIG_RETRY_DELAY = 0.3          -- Seconds between dig retries
Config.PROGRESS_UPDATE_INTERVAL = 10  -- Blocks between progress updates

return Config
