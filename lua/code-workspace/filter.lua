-- lua/CW/filter.lua
-- Glob-pattern-based path filter (portable, no external dependencies)
-- Compatible with VS Code's files.exclude glob syntax.
--
-- Supported patterns:
--   "**/*.ext"   → any file whose basename matches "*.ext"
--   "**/name"    → any path component named exactly "name"
--   "name"       → any path component named exactly "name" (same as above)
--   "*.ext"      → basename matches (treated same as **/*.ext)
--   "prefix*"    → basename starts with prefix
--   "**"         → matches everything (exclude all)
--
-- This module is intentionally self-contained so it can be copied to
-- other plugins (e.g. UNL.nvim) without modification.

local M = {}

--- Convert a single glob segment (no slashes) to a Lua pattern.
---@param segment string  e.g. "*.uasset", "_INT", "prefix*"
---@return string  Lua pattern
local function segment_to_pattern(segment)
    -- Escape magic chars except * and ?
    local p = segment:gsub("([%.%+%-%^%$%(%)%[%]%%])", "%%%1")
    -- Convert glob wildcards
    p = p:gsub("%*", ".*")
    p = p:gsub("%?", ".")
    return "^" .. p .. "$"
end

--- Parse a VS Code glob pattern into a normalized descriptor.
---@param glob string  e.g. "**/*.uasset", "_INT", "**/__ExternalActors__"
---@return table  { type: "basename"|"component"|"full", pattern: string }
local function parse_glob(glob)
    -- "**" alone → matches everything
    if glob == "**" then
        return { type = "all", pattern = nil }
    end

    -- Strip leading "**/" prefix
    local stripped = glob:match("^%*%*/(.+)$") or glob

    -- If the remaining part has no slash and contains a wildcard → basename match
    -- e.g. "*.uasset", "prefix*"
    if not stripped:find("/") and stripped:find("%*") then
        return { type = "basename", pattern = segment_to_pattern(stripped) }
    end

    -- If the remaining part has no slash and no wildcard → path component name
    -- e.g. "_INT", "Collections", "node_modules"
    if not stripped:find("/") and not stripped:find("%*") then
        return { type = "component", pattern = segment_to_pattern(stripped) }
    end

    -- Has a slash → treat as full path suffix pattern (less common)
    local p = stripped:gsub("([%.%+%-%^%$%(%)%[%]%%])", "%%%1"):gsub("%*", ".*"):gsub("%?", ".")
    return { type = "suffix", pattern = p .. "$" }
end

--- Build a compiled filter list from a VS Code files.exclude table.
---@param exclude_map table  { ["**/*.uasset"] = true, ["_INT"] = false, ... }
---@return table[]  List of compiled descriptors (only value==true entries)
function M.compile(exclude_map)
    local compiled = {}
    for glob, enabled in pairs(exclude_map or {}) do
        if enabled == true then
            local desc = parse_glob(glob)
            desc.source = glob
            table.insert(compiled, desc)
        end
    end
    return compiled
end

--- Test if a single path component (name) matches the compiled filter list.
---@param name string       File or directory name (basename), e.g. "MyFile.uasset"
---@param full_path string  Full normalized path, e.g. "/project/Content/MyFile.uasset"
---@param compiled table[]  Result of M.compile()
---@return boolean
function M.matches(name, full_path, compiled)
    for _, desc in ipairs(compiled) do
        if desc.type == "all" then
            return true
        elseif desc.type == "basename" then
            if name:match(desc.pattern) then return true end
        elseif desc.type == "component" then
            -- Match against any path component
            local norm = full_path:gsub("\\", "/")
            for component in norm:gmatch("[^/]+") do
                if component:match(desc.pattern) then return true end
            end
        elseif desc.type == "suffix" then
            local norm = full_path:gsub("\\", "/")
            if norm:match(desc.pattern) then return true end
        end
    end
    return false
end

--- Convenience: build compiled filter and return a closure.
---@param exclude_map table
---@return fun(name: string, full_path: string): boolean
function M.make_matcher(exclude_map)
    local compiled = M.compile(exclude_map)
    if #compiled == 0 then
        return function() return false end
    end
    return function(name, full_path)
        return M.matches(name, full_path, compiled)
    end
end

return M
