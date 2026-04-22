-- lua/CW/api.lua
-- Public API

local M = {}

function M.explorer_open(opts)    require("code-workspace.ui.explorer").open(opts) end
function M.explorer_close()       require("code-workspace.ui.explorer").close() end
function M.explorer_toggle(opts)  require("code-workspace.ui.explorer").toggle(opts) end
function M.explorer_focus()       require("code-workspace.ui.explorer").focus() end
function M.explorer_refresh()     require("code-workspace.ui.explorer").refresh() end

-- Pass the already-loaded workspace (if any) so commands don't have to re-discover it.
local function current_ws()
    return require("code-workspace.ui.explorer").current_ws()
end

function M.files(ws)   require("code-workspace.cmd.work_files").execute(ws or current_ws()) end
function M.grep(ws)    require("code-workspace.cmd.work_grep").execute(ws or current_ws()) end

function M.favorite_current()   require("code-workspace.cmd.favorite_current").execute() end
function M.add_favorites()      require("code-workspace.cmd.add_favorites").execute() end
function M.favorites_files()    require("code-workspace.cmd.favorites_files").execute() end

return M
