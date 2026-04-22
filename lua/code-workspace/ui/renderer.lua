-- lua/CW/ui/renderer.lua
-- nui.line based node renderer (shared between tree and favorites views)

local Line = require("nui.line")
local has_devicons, devicons = pcall(require, "nvim-web-devicons")

local M = {}

local function get_conf()
    return require("code-workspace.config").get()
end

--- Render a tree node into a nui.Line.
---@param node table  nui.tree Node with fields: text, type, _has_children, path, extra
---@return NuiLine
function M.prepare_node(node)
    local conf = get_conf()
    local icons = conf.icon
    local line = Line()

    -- Indent
    line:append(string.rep("  ", node:get_depth() - 1))

    -- Expander
    local has_children = node:has_children() or node._has_children
    if has_children then
        local exp = node:is_expanded() and icons.expander_open or icons.expander_closed
        line:append(exp .. " ", "CWIndentMarker")
    else
        line:append("  ")
    end

    -- Icon
    local icon_text, icon_hl = icons.default_file .. " ", "CWFileIcon"
    local extra_type = node.extra and node.extra.cw_type

    if extra_type == "root" then
        -- Workspace root folder entry
        local ws_icon = (node.extra and node.extra.is_uefn) and icons.uefn or icons.workspace
        icon_text = ws_icon .. " "
        icon_hl = "CWRootName"
    elseif node.type == "directory" then
        icon_text = (node:is_expanded() and icons.folder_open or icons.folder_closed) .. " "
        icon_hl = "CWDirectoryIcon"
    elseif extra_type == "fav_folder" then
        icon_text = " "
        icon_hl = "CWDirectoryIcon"
    elseif has_devicons and node.path then
        local ext = node.path:match("^.+%.(.+)$") or ""
        local d_icon, d_hl = devicons.get_icon(node.text, ext, { default = true })
        icon_text = (d_icon or icons.default_file) .. " "
        icon_hl = d_hl or "CWFileIcon"
    end

    line:append(icon_text, icon_hl)

    -- Name
    local name_hl = (extra_type == "root") and "CWRootName" or "CWFileName"
    line:append(node.text, name_hl)

    return line
end

return M
