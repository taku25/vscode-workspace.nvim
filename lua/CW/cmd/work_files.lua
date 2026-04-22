-- lua/CW/cmd/work_files.lua

local workspace = require("CW.workspace")
local picker    = require("CW.cmd.picker")

local M = {}

--- Convert VS Code files.exclude map to a simple is_excluded predicate.
--- Handles the common `**/*.ext` and `**/DirName` patterns.
---@param exclude_map table<string, boolean>
---@return fun(name: string, full: string): boolean
local function make_exclude_fn(exclude_map)
    local ext_exclude = {}  -- e.g. ".uasset" → true
    local dir_exclude = {}  -- e.g. "DerivedDataCache" → true

    for pattern, enabled in pairs(exclude_map) do
        if enabled then
            -- **/*.ext  →  extension check
            local ext = pattern:match("^%*%*/(%*%..+)$")
            if ext then
                local e = ext:match("^%*%.(.+)$")
                if e then ext_exclude["." .. e] = true end
            -- **/DirName  or  **/DirName/**
            else
                local dir = pattern:match("^%*%*/([^%*]+)/?%*?%*?$")
                if dir then dir_exclude[dir:gsub("/$", "")] = true end
            end
        end
    end

    return function(name, _full)
        -- check exact directory name
        if dir_exclude[name] then return true end
        -- check file extension
        local dot = name:find("%.[^./]+$")
        if dot then
            local e = name:sub(dot)
            if ext_exclude[e] then return true end
        end
        return false
    end
end

--- Open file picker across all workspace folders.
---@param ws? table  Workspace object (auto-detected if nil)
function M.execute(ws)
    if ws then
        local conf    = require("CW.config").get()
        local folders = workspace.get_folder_paths(ws)
        if #folders == 0 then
            vim.notify("[CW] No accessible folders in workspace", vim.log.levels.WARN)
            return
        end
        if type(conf.work_files) == "function" then
            conf.work_files(folders)
        else
            local is_excluded = make_exclude_fn(ws.exclude_map or {})
            picker.find_files(folders, {
                prompt      = ws.name .. " Files",
                is_excluded = is_excluded,
            })
        end
        return
    end

    workspace.find(nil, function(found_ws)
        if not found_ws then
            vim.notify("[CW] No .code-workspace found", vim.log.levels.WARN)
            return
        end
        M.execute(found_ws)
    end)
end

return M
