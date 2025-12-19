-- Base Builder Installer
-- Bootstrap script for installing base-builder on ComputerCraft computers
-- Run with: wget run https://raw.githubusercontent.com/USERNAME/base-builder/main/install.lua

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local REPO_URL = "https://raw.githubusercontent.com/athompson-hoho/base-builder/main"
local VERSION_FILE = "/state/version.dat"
local TYPE_FILE = "/state/computer_type.dat"
local MAX_RETRIES = 3

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

--- Download a file from URL to local path with retry logic
-- @param url string: The URL to download from
-- @param local_path string: The local file path to save to
-- @return boolean: success status
-- @return string|nil: error message if failed
local function download_file(url, local_path)
    for attempt = 1, MAX_RETRIES do
        print("  Downloading: " .. local_path .. " (attempt " .. attempt .. ")")

        local response = http.get(url)
        if response then
            local content = response.readAll()
            response.close()

            if content then
                -- Ensure parent directory exists
                local parent_dir = local_path:match("(.+)/[^/]+$")
                if parent_dir and not fs.exists(parent_dir) then
                    fs.makeDir(parent_dir)
                end

                -- Write file
                local file = fs.open(local_path, "w")
                if file then
                    file.write(content)
                    file.close()
                    return true, nil
                else
                    return false, "Failed to open file for writing: " .. local_path
                end
            end
        end

        if attempt < MAX_RETRIES then
            print("    Retry in 1 second...")
            sleep(1)
        end
    end

    return false, "Failed to download after " .. MAX_RETRIES .. " attempts: " .. url
end

--- Fetch and parse the manifest.json file
-- @return table|nil: parsed manifest or nil on failure
-- @return string|nil: error message if failed
local function fetch_manifest()
    local manifest_url = REPO_URL .. "/manifest.json"
    print("Fetching manifest from: " .. manifest_url)

    local response = http.get(manifest_url)
    if not response then
        return nil, "Failed to fetch manifest.json - check your internet connection"
    end

    local content = response.readAll()
    response.close()

    if not content then
        return nil, "Failed to read manifest content"
    end

    local manifest = textutils.unserializeJSON(content)
    if not manifest then
        return nil, "Failed to parse manifest.json - invalid JSON"
    end

    -- Validate required fields
    if not manifest.version then
        return nil, "Invalid manifest: missing 'version' field"
    end
    if not manifest.files then
        return nil, "Invalid manifest: missing 'files' field"
    end
    if not manifest.files.controller then
        return nil, "Invalid manifest: missing 'files.controller' field"
    end
    if not manifest.files.turtle then
        return nil, "Invalid manifest: missing 'files.turtle' field"
    end
    if not manifest.files.shared then
        return nil, "Invalid manifest: missing 'files.shared' field"
    end

    return manifest, nil
end

--- Download all files for a specific type (controller or turtle)
-- @param manifest table: The parsed manifest
-- @param computer_type string: "controller" or "turtle"
-- @return boolean: success status
-- @return string|nil: error message if failed
local function download_type_files(manifest, computer_type)
    local type_files = manifest.files[computer_type]
    local type_dir = "/" .. computer_type

    print("\nDownloading " .. computer_type .. " files...")

    for _, filename in ipairs(type_files) do
        local url = REPO_URL .. "/" .. computer_type .. "/" .. filename
        local local_path = type_dir .. "/" .. filename

        local ok, err = download_file(url, local_path)
        if not ok then
            return false, err
        end
    end

    return true, nil
end

--- Download all shared files
-- @param manifest table: The parsed manifest
-- @return boolean: success status
-- @return string|nil: error message if failed
local function download_shared_files(manifest)
    print("\nDownloading shared files...")

    for _, filename in ipairs(manifest.files.shared) do
        local url = REPO_URL .. "/shared/" .. filename
        local local_path = "/shared/" .. filename

        local ok, err = download_file(url, local_path)
        if not ok then
            return false, err
        end
    end

    return true, nil
end

--- Create state directory and save version/type information
-- @param manifest table: The parsed manifest
-- @param computer_type string: "controller" or "turtle"
-- @return boolean: success status
-- @return string|nil: error message if failed
local function create_state_files(manifest, computer_type)
    print("\nCreating state files...")

    -- Create state directory if needed
    if not fs.exists("/state") then
        fs.makeDir("/state")
    end

    -- Write version file
    local version_file = fs.open(VERSION_FILE, "w")
    if not version_file then
        return false, "Failed to create version file"
    end
    version_file.write(manifest.version)
    version_file.close()
    print("  Saved version: " .. manifest.version)

    -- Write computer type file
    local type_file = fs.open(TYPE_FILE, "w")
    if not type_file then
        return false, "Failed to create computer type file"
    end
    type_file.write(computer_type)
    type_file.close()
    print("  Saved type: " .. computer_type)

    return true, nil
end

--- Copy startup.lua to root for auto-run
-- @param computer_type string: "controller" or "turtle"
-- @return boolean: success status
-- @return string|nil: error message if failed
local function setup_startup(computer_type)
    print("\nSetting up startup...")

    local source_path = "/" .. computer_type .. "/startup.lua"
    local dest_path = "/startup.lua"

    -- Remove existing startup.lua if present
    if fs.exists(dest_path) then
        fs.delete(dest_path)
    end

    -- Copy type-specific startup to root
    if fs.exists(source_path) then
        fs.copy(source_path, dest_path)
        print("  Copied " .. source_path .. " to " .. dest_path)
        return true, nil
    else
        return false, "Source startup.lua not found: " .. source_path
    end
end

--- Prompt user for computer type with validation
-- @return string: "controller" or "turtle"
local function get_computer_type()
    while true do
        print("\nWhat type of computer is this?")
        print("  [C] Controller")
        print("  [T] Turtle")
        write("\nEnter choice: ")

        local input = read()
        input = input:lower()

        if input == "c" then
            return "controller"
        elseif input == "t" then
            return "turtle"
        else
            print("\n[!] Invalid input. Please enter 'C' for Controller or 'T' for Turtle.")
        end
    end
end

-- ============================================================================
-- MAIN INSTALLER
-- ============================================================================

local function main()
    -- Clear screen and show banner
    term.clear()
    term.setCursorPos(1, 1)

    print("========================================")
    print("       Base Builder Installer")
    print("========================================")
    print("")
    print("This will install the base-builder swarm")
    print("construction system on this computer.")
    print("")

    -- Check HTTP API availability
    if not http then
        print("[ERROR] HTTP API is not available!")
        print("Enable HTTP in ComputerCraft config.")
        return
    end

    -- Get computer type from user
    local computer_type = get_computer_type()
    print("\nInstalling as: " .. computer_type:upper())

    -- Fetch manifest
    local manifest, err = fetch_manifest()
    if not manifest then
        print("\n[ERROR] " .. err)
        return
    end
    print("  Manifest version: " .. manifest.version)

    -- Download type-specific files
    local ok, err = download_type_files(manifest, computer_type)
    if not ok then
        print("\n[ERROR] " .. err)
        return
    end

    -- Download shared files
    ok, err = download_shared_files(manifest)
    if not ok then
        print("\n[ERROR] " .. err)
        return
    end

    -- Create state directory and files
    ok, err = create_state_files(manifest, computer_type)
    if not ok then
        print("\n[ERROR] " .. err)
        return
    end

    -- Setup startup.lua
    ok, err = setup_startup(computer_type)
    if not ok then
        print("\n[ERROR] " .. err)
        return
    end

    -- Success!
    print("\n========================================")
    print("    Installation complete. Rebooting...")
    print("========================================")

    sleep(2)
    os.reboot()
end

-- Run the installer
main()
