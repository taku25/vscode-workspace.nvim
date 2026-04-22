-- lua/CW/cmd/favorite_current.lua

local M = {}

function M.execute()
    local file_path = vim.fn.expand("%:p")
    if file_path == "" then
        vim.notify("[CW] No file in current buffer", vim.log.levels.WARN)
        return
    end
    require("code-workspace.ui.explorer").toggle_favorite(file_path)
end

return M
