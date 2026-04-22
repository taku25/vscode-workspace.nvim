-- lua/CW/cmd/add_favorites.lua
-- Add files/directories to Favorites via picker (UNX.nvim compatible command)

local picker = require("code-workspace.cmd.picker")
local M = {}

function M.execute()
    local explorer = require("code-workspace.ui.explorer")
    local ws = explorer.current_ws()

    if not ws then
        vim.notify("[CW] No workspace loaded. Open the explorer first.", vim.log.levels.WARN)
        return
    end

    local workspace = require("code-workspace.workspace")
    local folders   = workspace.get_folder_paths(ws)
    if #folders == 0 then
        vim.notify("[CW] No accessible folders in workspace", vim.log.levels.WARN)
        return
    end

    -- Collect all files and let the user multi-select (or single-select).
    -- After selection, toggle each one into favorites.
    picker.find_files(folders, {
        prompt      = "Add to Favorites",
        on_select   = function(selected_paths)
            for _, p in ipairs(selected_paths) do
                explorer.toggle_favorite(p)
            end
        end,
    })
end

return M
