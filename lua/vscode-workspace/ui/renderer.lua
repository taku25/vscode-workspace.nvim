-- lua/CW/ui/renderer.lua
-- nui.line based node renderer (shared between tree and favorites views)

local Line = require("nui.line")
local has_devicons, devicons = pcall(require, "nvim-web-devicons")
local path = require("vscode-workspace.path")

local M = {}

-- Path of the currently active (non-explorer) buffer.
-- Set by explorer.lua on BufEnter; used to highlight the active file in the tree.
M._current_file = nil

-- Set of selected paths (normalized). { [norm_path] = original_path }
-- Updated by view.toggle_selected / view.clear_selected in tree.lua.
M._selected_paths = {}

local function get_conf()
    return require("vscode-workspace.config").get()
end

--- Return icon + highlight for a directory/folder node, with devicons fallback.
---@param name string  display name of the node
---@param is_expanded boolean
---@param icons table  config icon table
---@return string, string  icon_text, icon_hl
local function dir_icon(name, is_expanded, icons)
    if has_devicons then
        local d_icon, d_hl = devicons.get_icon(name, nil, { default = false })
        if d_icon then
            return d_icon .. " ", d_hl or "CWDirectoryIcon"
        end
    end
    return (is_expanded and icons.folder_open or icons.folder_closed) .. " ", "CWDirectoryIcon"
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
        icon_text, icon_hl = dir_icon(node.text, node:is_expanded(), icons)
    elseif extra_type == "fav_root" then
        icon_text = (icons.favorites or "★") .. " "
        icon_hl   = "CWRootName"
    elseif extra_type == "recent_root" then
        icon_text = (icons.recent or "") .. " "
        icon_hl   = "CWRootName"
    elseif extra_type == "fav_folder" then
        local custom_icon = node.extra and node.extra.icon
        if custom_icon and custom_icon ~= "" then
            icon_text = custom_icon .. " "
            icon_hl   = "CWDirectoryIcon"
        else
            icon_text, icon_hl = dir_icon(node.text, node:is_expanded(), icons)
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

    -- Name: use CWCurrentFile when this node is the active buffer, CWSelectedFile when selected
    local is_current  = M._current_file ~= nil
        and node.path ~= nil
        and path.equal(node.path, M._current_file)
    local is_selected = node.path ~= nil
        and M._selected_paths[path.normalize(node.path)] ~= nil
    local name_hl
    if extra_type == "root" or extra_type == "fav_root" or extra_type == "recent_root" then
        name_hl = "CWRootName"
    elseif is_selected then
        name_hl = "CWSelectedFile"
    elseif is_current then
        name_hl = "CWCurrentFile"
    else
        name_hl = "CWFileName"
    end

    -- Selection marker (〇) shown just before the file name
    if is_selected then
        line:append("〇 ", "CWSelectedFile")
    end
    line:append(node.text, name_hl)

    return line
end

return M
