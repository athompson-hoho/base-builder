-- Base Builder Updater
-- Handles version checking, manifest fetching, and update logic

local Updater = {}

-- Load dependencies
local Config = require("shared.config")
local Logging = require("shared.logging")

-- ============================================================================
-- INTERNAL HELPERS
-- ============================================================================

--- Fetch manifest.json from GitHub with timeout
-- @return table|nil: parsed manifest or nil on failure
-- @return string|nil: error message if failed
local function fetch_manifest()
    local manifest_url = Config.REPO_URL .. "/manifest.json"

    Logging.debug("Fetching manifest from: " .. manifest_url)

    local response = http.get(manifest_url)
    if not response then
        return nil, "Failed to fetch manifest - check internet connection"
    end

    local content = response.readAll()
    response.close()

    if not content then
        return nil, "Failed to read manifest content"
    end

    local manifest = textutils.unserializeJSON(content)
    if not manifest then
        return nil, "Failed to parse manifest JSON"
    end

    -- Validate required fields
    if not manifest.version then
        return nil, "Invalid manifest: missing 'version' field"
    end
    if not manifest.files then
        return nil, "Invalid manifest: missing 'files' field"
    end

    Logging.debug("Manifest loaded successfully - version: " .. manifest.version)
    return manifest, nil
end

--- Get locally installed version
-- @return string|nil: version string or nil if not found
local function read_version_file()
    if not fs.exists(Config.VERSION_FILE) then
        return nil
    end

    local file = fs.open(Config.VERSION_FILE, "r")
    if not file then
        return nil
    end

    local version = file.readAll()
    file.close()

    return version or nil
end

--- Check if /state/build_state.dat exists and is valid
-- @return boolean: true if active build exists, false otherwise
local function has_active_build_state()
    if not fs.exists(Config.BUILD_STATE_FILE) then
        return false
    end

    -- Try to read and parse to verify validity
    local file = fs.open(Config.BUILD_STATE_FILE, "r")
    if not file then
        return false
    end

    local content = file.readAll()
    file.close()

    if not content or content == "" then
        return false
    end

    -- If file has content, treat as active build state
    return true
end

--- Prompt user to update with timeout
-- @param remote_version string: The new version available
-- @param timeout_seconds number: How long to wait for user input
-- @return boolean: true if user chose update, false if skip or timeout
local function prompt_for_update(remote_version, timeout_seconds)
    Logging.info("")
    Logging.info("Update v" .. remote_version .. " available!")
    write("\n[U]pdate or [S]kip? (" .. timeout_seconds .. "s timeout): ")

    local timer_id = os.startTimer(timeout_seconds)

    while true do
        local event, param = os.pullEvent()

        if event == "key" then
            if param == keys.u then
                os.cancelTimer(timer_id)
                print("u")  -- Echo user input
                Logging.info("User chose UPDATE")
                return true
            elseif param == keys.s then
                os.cancelTimer(timer_id)
                print("s")  -- Echo user input
                Logging.info("User chose SKIP")
                return false
            end
        elseif event == "timer" and param == timer_id then
            print("[timeout - skipping]")
            Logging.info("Update prompt timeout - defaulting to SKIP")
            return false
        end
    end
end

--- Download a single file from GitHub with retry logic
-- @param manifest table: parsed manifest with repo_base and version
-- @param file_type string: "controller", "turtle", or "shared"
-- @param filename string: name of file to download (e.g., "main.lua")
-- @return boolean: success status
-- @return string|nil: error message if failed
local function download_file(manifest, file_type, filename)
    local repo_url = manifest.repo_base or Config.REPO_URL

    -- Validate repo URL - ensure it's from trusted source
    if manifest.repo_base and not manifest.repo_base:match("github%.com") then
        return false, "Invalid repository URL in manifest"
    end

    local file_url = repo_url .. "/" .. file_type .. "/" .. filename

    -- Determine destination path
    local dest_dir
    if file_type == "shared" then
        dest_dir = "shared"
    else
        dest_dir = file_type
    end

    -- Create directory if needed
    if not fs.exists(dest_dir) then
        fs.makeDir(dest_dir)
    end

    local dest_path = dest_dir .. "/" .. filename

    -- Try to download with retry logic (3 attempts)
    local max_retries = 3
    for attempt = 1, max_retries do
        Logging.debug("Downloading " .. filename .. " (attempt " .. attempt .. "/" .. max_retries .. ")")

        local response = http.get(file_url)
        if response then
            local content = response.readAll()
            response.close()

            if content and string.len(content) > 0 then
                -- Validate file content for Lua files
                if filename:match("%.lua$") then
                    if not (content:match("^%-%-") or content:match("^local") or content:match("^function")) then
                        return false, "Invalid Lua file content: " .. filename
                    end
                end

                -- Write to file
                local file = fs.open(dest_path, "w")
                if file then
                    file.write(content)
                    file.close()
                    Logging.debug("Downloaded " .. filename .. " (" .. string.len(content) .. " bytes)")
                    return true, nil
                else
                    return false, "Failed to write " .. dest_path
                end
            else
                return false, "Empty response for " .. filename
            end
        else
            if attempt < max_retries then
                Logging.debug("Download failed, retrying...")
                sleep(1)
            end
        end
    end

    return false, "Failed to download " .. filename .. " after " .. max_retries .. " attempts"
end

--- Save version string to /state/version.dat
-- @param version string: version string to save (e.g., "1.0.0")
-- @return boolean: success status
local function save_version(version)
    if not fs.exists("/state") then
        fs.makeDir("/state")
    end

    local file = fs.open(Config.VERSION_FILE, "w")
    if not file then
        return false
    end

    file.write(version)
    file.close()

    Logging.debug("Saved version " .. version .. " to " .. Config.VERSION_FILE)
    return true
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--- Get locally installed version
-- @return string: version string (e.g., "1.0.0") or "unknown"
function Updater.get_local_version()
    local version = read_version_file()
    if version then
        return version
    end
    return "unknown"
end

--- Fetch manifest from GitHub
-- @return table|nil: parsed manifest or nil on failure
-- @return string|nil: error message if failed
function Updater.fetch_manifest()
    return fetch_manifest()
end

--- Check if update is available
-- @return boolean: has_update (true if newer version available)
-- @return string|nil: remote_version (new version string) or nil if no update
-- @return string|nil: error message if failed (e.g., offline)
function Updater.check_version()
    Logging.debug("Starting version check...")

    local manifest, err = fetch_manifest()
    if not manifest then
        -- GitHub unreachable - this is not an error, just offline
        Logging.debug("GitHub unreachable: " .. (err or "unknown error"))
        return false, nil, err
    end

    local local_version = read_version_file()
    if not local_version then
        Logging.debug("Local version not found")
        return false, nil, "No local version file"
    end

    Logging.debug("Local version: " .. local_version .. ", Remote version: " .. manifest.version)

    if manifest.version ~= local_version then
        Logging.debug("Update available: " .. local_version .. " → " .. manifest.version)
        return true, manifest.version, nil
    end

    Logging.debug("No update available")
    return false, nil, nil
end

--- Download and apply update for this computer
-- @param computer_type string: "controller" or "turtle"
-- @param manifest table|nil: parsed manifest from fetch_manifest() (optional, will fetch if nil)
-- @return boolean: success status
-- @return string|nil: error message if failed
function Updater.apply_update(computer_type, manifest)
    if not computer_type then
        return false, "computer_type required"
    end

    -- Fetch manifest if not provided
    if not manifest then
        local err
        manifest, err = fetch_manifest()
        if not manifest then
            return false, "Failed to fetch manifest: " .. (err or "unknown error")
        end
    end

    -- Validate manifest
    if not manifest.files then
        return false, "Invalid manifest: missing 'files' field"
    end

    if type(manifest.files) ~= "table" then
        return false, "Invalid manifest: 'files' must be a table"
    end

    if not (manifest.files.shared or manifest.files.controller or manifest.files.turtle) then
        return false, "Invalid manifest: no files defined for any type"
    end

    -- Determine which file types to download
    local file_types = {}
    if manifest.files.shared then
        table.insert(file_types, "shared")
    end

    if computer_type == "controller" then
        if manifest.files.controller then
            table.insert(file_types, "controller")
        else
            return false, "Invalid manifest: no 'controller' files defined"
        end
    elseif computer_type == "turtle" then
        if manifest.files.turtle then
            table.insert(file_types, "turtle")
        else
            return false, "Invalid manifest: no 'turtle' files defined"
        end
    else
        return false, "Invalid computer_type: " .. computer_type
    end

    -- Download all required files
    for _, file_type in ipairs(file_types) do
        local files = manifest.files[file_type]
        if files then
            for _, filename in ipairs(files) do
                local success, err = download_file(manifest, file_type, filename)
                if not success then
                    return false, "Failed to download " .. filename .. ": " .. (err or "unknown error")
                end
            end
        end
    end

    -- Save new version to state file
    local version_saved = save_version(manifest.version)
    if not version_saved then
        return false, "Failed to save version file"
    end

    Logging.info("Update to v" .. manifest.version .. " applied successfully")
    return true, nil
end

--- Check for update and optionally prompt user
-- @param computer_type string: "controller" or "turtle"
-- @return boolean: true if should apply update, false if skip/no update
function Updater.check_and_prompt(computer_type)
    local has_update, remote_version, err = Updater.check_version()

    if err then
        -- GitHub unreachable
        Logging.warn("Update check failed (offline)")
        return false
    end

    if not has_update then
        -- No update available
        return false
    end

    -- Update available - check for active build state
    if computer_type == "controller" then
        if has_active_build_state() then
            Logging.warn("Update v" .. remote_version .. " available")
            Logging.info("Complete or resume build first, then run 'update' command")
            return false
        end
    end

    -- Prompt user with timeout
    return prompt_for_update(remote_version, Config.UPDATE_PROMPT_TIMEOUT)
end

return Updater
