-- lua/CW/ui/renderer.lua
-- nui.line based node renderer (shared between tree and favorites views)

local Line = require("nui.line")
local has_devicons, devicons = pcall(require, "nvim-web-devicons")

local M = {}

local function get_conf()
    return require("vscode-workspace.config").get()
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
        -- Workspace root folder entry: try devicons for known folder names, else workspace icon
        local ws_icon = (node.extra and node.extra.is_uefn) and icons.uefn or nil
        if ws_icon then
            icon_text = ws_icon .. " "
            icon_hl   = "CWRootName"
        elseif has_devicons then
            local d_icon, d_hl = devicons.get_icon(node.text, nil, { default = false })
            if d_icon then
                icon_text = d_icon .. " "
                icon_hl   = d_hl or "CWRootName"
            else
                icon_text = icons.workspace .. " "
                icon_hl   = "CWRootName"
            end
        else
            icon_text = icons.workspace .. " "
            icon_hl   = "CWRootName"
        end
    elseif node.type == "directory" then
        -- Try devicons for well-known directory names (e.g. ".git", "src", "node_modules")
        if has_devicons then
            local d_icon, d_hl = devicons.get_icon(node.text, nil, { default = false })
            if d_icon then
                icon_text = d_icon .. " "
                icon_hl   = d_hl or "CWDirectoryIcon"
            else
                icon_text = (node:is_expanded() and icons.folder_open or icons.folder_closed) .. " "
                icon_hl   = "CWDirectoryIcon"
            end
        else
            icon_text = (node:is_expanded() and icons.folder_open or icons.folder_closed) .. " "
            icon_hl   = "CWDirectoryIcon"
        end
    elseif extra_type == "fav_root" then
        icon_text = "★ "
        icon_hl   = "CWRootName"
    elseif extra_type == "fav_folder" then
        -- Use devicons for well-known names, otherwise folder open/closed icons
        if has_devicons then
            local d_icon, d_hl = devicons.get_icon(node.text, nil, { default = false })
            if d_icon then
                icon_text = d_icon .. " "
                icon_hl   = d_hl or "CWDirectoryIcon"
            else
                icon_text = (node:is_expanded() and icons.folder_open or icons.folder_closed) .. " "
                icon_hl   = "CWDirectoryIcon"
            end
        else
            icon_text = (node:is_expanded() and icons.folder_open or icons.folder_closed) .. " "
            icon_hl   = "CWDirectoryIcon"
        end
    elseif node.path then
        if has_devicons then
            local ext    = node.path:match("%.([^./\\]+)$") or ""
            local d_icon, d_hl = devicons.get_icon(node.text, ext, { default = true })
            icon_text = (d_icon or icons.default_file) .. " "
            icon_hl   = d_hl or "CWFileIcon"
        end
    end

    line:append(icon_text, icon_hl)

    -- Name
    local name_hl = (extra_type == "root" or extra_type == "fav_root") and "CWRootName" or "CWFileName"
    line:append(node.text, name_hl)

    return line
end

return M
