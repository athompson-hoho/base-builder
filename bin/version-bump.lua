#!/usr/bin/env lua
-- Version Bumper Script
-- Automatically increments version based on commit message
-- Usage: lua bin/version-bump.lua [major|minor|patch|auto]

local function read_file(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local content = file:read("*a")
    file:close()
    return content
end

local function write_file(path, content)
    local file = io.open(path, "w")
    if not file then return false end
    file:write(content)
    file:close()
    return true
end

local function parse_version(version_str)
    local major, minor, patch = version_str:match("(%d+)%.(%d+)%.(%d+)")
    return tonumber(major), tonumber(minor), tonumber(patch)
end

local function bump_version(major, minor, patch, bump_type)
    if bump_type == "major" then
        return major + 1, 0, 0
    elseif bump_type == "minor" then
        return major, minor + 1, 0
    else  -- patch or auto
        return major, minor, patch + 1
    end
end

-- Read current versions
local config_content = read_file("shared/config.lua")
local manifest_content = read_file("manifest.json")

if not config_content or not manifest_content then
    error("Could not read config.lua or manifest.json")
end

-- Extract current version
local current_version = config_content:match('Config%.VERSION = "([^"]+)"')
if not current_version then
    error("Could not parse version from config.lua")
end

print("Current version: " .. current_version)

-- Determine bump type from command line or auto-detect
local bump_type = arg[1] or "patch"

-- Parse current version
local major, minor, patch = parse_version(current_version)
if not major then
    error("Invalid version format: " .. current_version)
end

-- Calculate new version
local new_major, new_minor, new_patch = bump_version(major, minor, patch, bump_type)
local new_version = string.format("%d.%d.%d", new_major, new_minor, new_patch)

print("New version: " .. new_version)

-- Update config.lua
local new_config = config_content:gsub(
    'Config%.VERSION = "[^"]+"',
    'Config.VERSION = "' .. new_version .. '"'
)

-- Update manifest.json
local new_manifest = manifest_content:gsub(
    '"version": "[^"]+"',
    '"version": "' .. new_version .. '"'
)

-- Write updated files
if not write_file("shared/config.lua", new_config) then
    error("Could not write config.lua")
end

if not write_file("manifest.json", new_manifest) then
    error("Could not write manifest.json")
end

print("✓ Version bumped successfully!")
print("  Files updated: shared/config.lua, manifest.json")
print("  Don't forget to git add and commit these changes")

return 0
