-- lua/CW/cmd/work_grep.lua

local workspace = require("code-workspace.workspace")
local picker    = require("code-workspace.cmd.picker")

local M = {}

--- Open live grep across all workspace folders.
---@param ws? table  Workspace object (auto-detected if nil)
function M.execute(ws)
    if ws then
        local conf    = require("code-workspace.config").get()
        local folders = workspace.get_folder_paths(ws)
        if #folders == 0 then
            vim.notify("[CW] No accessible folders in workspace", vim.log.levels.WARN)
            return
        end
        if type(conf.work_grep) == "function" then
            conf.work_grep(folders)
        else
            picker.live_grep(folders, { prompt = ws.name .. " Grep" })
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
