-- Module Loader
-- Provides a require() function for loading and caching modules

---@diagnostic disable: undefined-global

-- Module cache to prevent reloading
local modules = {}

--- Load a module from the filesystem
-- @param module_path string: Module path like "shared.config" or "controller.commands"
-- @return table|function: The loaded module
local function require(module_path)
    -- Check if already loaded
    if modules[module_path] then
        return modules[module_path]
    end

    -- Convert module path to file path
    -- "shared.config" -> "/shared/config.lua"
    local file_path = "/" .. module_path:gsub("%.", "/") .. ".lua"

    -- Load the file
    local file = fs.open(file_path, "r")
    if not file then
        error("Module not found: " .. module_path .. " (expected at " .. file_path .. ")")
    end

    local content = file.readAll()
    file.close()

    if not content then
        error("Failed to read module: " .. module_path)
    end

    -- Execute the module in a protected environment
    local env = {
        -- Provide standard globals
        _G = _G,
        require = require,  -- Allow modules to require other modules
        print = print,
        write = write,
        read = read,
        readLine = readLine,
        sleep = sleep,
        os = os,
        math = math,
        table = table,
        string = string,
        textutils = textutils,
        fs = fs,
        peripheral = peripheral,
        rednet = rednet,
        http = http,
        term = term,
        parallel = parallel,
        coroutine = coroutine,
        -- Standard Lua functions
        tonumber = tonumber,
        tostring = tostring,
        type = type,
        pairs = pairs,
        ipairs = ipairs,
        next = next,
        error = error,
        pcall = pcall,
        xpcall = xpcall,
        assert = assert,
        select = select,
        getmetatable = getmetatable,
        setmetatable = setmetatable,
        rawget = rawget,
        rawset = rawset,
        rawequal = rawequal,
        unpack = unpack or table.unpack,
    }

    local chunk, err = load(content, "@" .. file_path, "t", env)
    if not chunk then
        error("Failed to parse module " .. module_path .. ": " .. (err or "unknown error"))
    end

    -- Execute and cache the result
    local result = chunk()
    modules[module_path] = result or true

    return modules[module_path]
end

-- Export the require function globally
_G.require = require

return require
