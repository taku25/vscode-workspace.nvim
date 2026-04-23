-- lua/CW/cmd/add_favorites.lua
-- Add files/directories to Favorites via picker (UNX.nvim compatible command)

local picker = require("vscode-workspace.picker")
local M = {}

function M.execute()
    local explorer = require("vscode-workspace.ui.explorer")
    local ws = explorer.current_ws()

    if not ws then
        vim.notify("[CW] No workspace loaded. Open the explorer first.", vim.log.levels.WARN)
        return
    end

    local workspace = require("vscode-workspace.workspace")
    local folders   = workspace.get_folder_paths(ws)
    if #folders == 0 then
        vim.notify("[CW] No accessible folders in workspace", vim.log.levels.WARN)
        return
    end

    -- Collect all files and let the user multi-select (or single-select).
    -- After selection, toggle each one into favorites.
    picker.find_files(folders, {
        prompt    = "Add to Favorites",
        on_submit = function(selected_path)
            if selected_path and selected_path ~= "" then
                explorer.toggle_favorite(selected_path)
            end
        end,
    })
end

return M
