-- lua/CW/store.lua
-- JSON persistence for favorites, tree state, etc.
-- Storage root: stdpath("cache")/vscode-workspace/

local path = require("vscode-workspace.path")

local M = {}

local function get_storage_dir()
    return path.join(vim.fn.stdpath("cache"), "vscode-workspace")
end

--- Return the full storage path for a given workspace safe-name and key.
--- safe_name is expected to be in the form "{wsname}_{sha256_16}" (see workspace.lua).
---@param ws_safe_name string
---@param key string  e.g. "favorites", "tree_state"
---@return string
function M.get_path(ws_safe_name, key)
    return path.join(get_storage_dir(), ws_safe_name .. "_" .. key .. ".json")
end

--- Load JSON data from a file. Returns {} on missing/invalid file.
---@param file_path string
---@return table
function M.load(file_path)
    if vim.fn.filereadable(file_path) == 0 then
        return {}
    end
    local ok, lines = pcall(vim.fn.readfile, file_path)
    if not ok or not lines then return {} end
    local text = table.concat(lines, "\n")
    if text == "" then return {} end
    local dok, data = pcall(vim.json.decode, text)
    if dok and type(data) == "table" then
        return data
    end
    return {}
end

--- Save data as JSON to a file. Creates parent directories as needed.
---@param file_path string
---@param data table
---@return boolean
function M.save(file_path, data)
    vim.fn.mkdir(vim.fn.fnamemodify(file_path, ":h"), "p")
    local ok, text = pcall(vim.json.encode, data)
    if not ok then return false end
    local wok = pcall(vim.fn.writefile, vim.split(text, "\n"), file_path)
    return wok
end

--- Load workspace-scoped data.
---@param ws_safe_name string
---@param key string
---@return table
function M.load_ws(ws_safe_name, key)
    return M.load(M.get_path(ws_safe_name, key))
end

--- Save workspace-scoped data.
---@param ws_safe_name string
---@param key string
---@param data table
---@return boolean
function M.save_ws(ws_safe_name, key, data)
    return M.save(M.get_path(ws_safe_name, key), data)
end

return M
