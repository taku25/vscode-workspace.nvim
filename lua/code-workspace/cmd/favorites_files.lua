-- lua/CW/cmd/favorites_files.lua
-- Open favorites in a picker

local picker = require("code-workspace.cmd.picker")
local M = {}

function M.execute()
    require("code-workspace.ui.explorer").get_favorites(function(paths)
        if #paths == 0 then
            vim.notify("[CW] No favorites yet. Use 'b' in the explorer or :CW favorite_current to add files.", vim.log.levels.INFO)
            return
        end
        picker.find_files(paths, { prompt = "CW Favorites" })
    end)
end

return M
