-- lua/CW/init.lua

local M = {}

---@param opts? table  See CW.config for available options
function M.setup(opts)
    require("code-workspace.config").setup(opts or {})
end

return M
