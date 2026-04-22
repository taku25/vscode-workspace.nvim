-- lua/CW/api.lua
-- Public API

local M = {}

function M.explorer_open(opts)    require("CW.ui.explorer").open(opts) end
function M.explorer_close()       require("CW.ui.explorer").close() end
function M.explorer_toggle(opts)  require("CW.ui.explorer").toggle(opts) end
function M.explorer_focus()       require("CW.ui.explorer").focus() end
function M.explorer_refresh()     require("CW.ui.explorer").refresh() end

-- Pass the already-loaded workspace (if any) so commands don't have to re-discover it.
local function current_ws()
    return require("CW.ui.explorer").current_ws()
end

function M.files(ws)   require("CW.cmd.work_files").execute(ws or current_ws()) end
function M.grep(ws)    require("CW.cmd.work_grep").execute(ws or current_ws()) end

function M.favorite_current()   require("CW.cmd.favorite_current").execute() end
function M.favorites_files()    require("CW.cmd.favorites_files").execute() end

return M
