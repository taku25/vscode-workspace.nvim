-- lua/CW/ui/view/favorites.lua
-- Favorites tab view
-- Data format (stored in JSON):
--   [ { path, name, folder, added_at }        -- file item
--     { is_folder=true, name, parent, added_at } -- folder grouping ]

local Tree     = require("nui.tree")
local renderer = require("code-workspace.ui.renderer")
local store    = require("code-workspace.store")
local path_mod = require("code-workspace.path")

local M = {}
M.ROOT_TYPE = "fav_root"

--- Load favorites for a workspace.
---@param ws table
---@return table[]
local function load(ws)
    return store.load_ws(ws.safe_name, "favorites")
end

--- Save favorites for a workspace.
---@param ws table
---@param data table[]
local function save(ws, data)
    store.save_ws(ws.safe_name, "favorites", data)
end

--- Build nui.tree nodes from favorites data.
---@param favorites table[]
---@return NuiTree.Node[]
local function build_nodes(favorites)
    -- Collect defined folder names
    local folder_names = {}   -- name -> true
    folder_names["Default"] = true

    for _, item in ipairs(favorites) do
        if item.is_folder then
            folder_names[item.name] = true
        end
    end

    -- Second pass: build file item nodes per folder
    local folder_children = {}  -- folder_name -> list of nodes
    for _, item in ipairs(favorites) do
        if not item.is_folder then
            local folder = item.folder or "Default"
            if not folder_children[folder] then
                folder_children[folder] = {}
            end
            table.insert(folder_children[folder], Tree.Node({
                text  = item.name or path_mod.basename(item.path),
                id    = "fav_file:" .. item.path,
                path  = item.path,
                type  = "file",
                extra = { cw_type = "fav_file", added_at = item.added_at },
            }))
        end
    end

    -- Build top-level folder nodes (children passed to constructor)
    local top = {}
    for fname, _ in pairs(folder_names) do
        table.insert(top, fname)
    end
    table.sort(top, function(a, b)
        if a == "Default" then return true end
        if b == "Default" then return false end
        return a:lower() < b:lower()
    end)

    local result = {}
    for _, fname in ipairs(top) do
        local children = folder_children[fname] or {}
        local fnode = Tree.Node({
            text  = fname,
            id    = "fav_folder:" .. fname,
            type  = "directory",
            extra = { cw_type = "fav_folder", folder_name = fname },
            _has_children = #children > 0,
        }, #children > 0 and children or nil)
        table.insert(result, fnode)
    end
    return result
end

--- Create a new favorites view state.
---@param buf integer
---@param ws table
---@return table
function M.new(buf, ws)
    local favorites = load(ws)

    local tree = Tree({
        bufnr        = buf,
        nodes        = build_nodes(favorites),
        prepare_node = renderer.prepare_node,
        get_node_id  = function(node) return node.id end,
    })

    local view = { tree = tree, ws = ws, buf = buf }

    function view.reload()
        favorites = load(ws)
        tree:set_nodes(build_nodes(favorites))
        tree:render()
    end

    --- Toggle a file path in favorites.
    ---@param file_path string
    ---@param folder_name? string
    ---@return boolean added
    function view.toggle(file_path, folder_name)
        folder_name = folder_name or "Default"
        local norm = path_mod.normalize(file_path)
        for i, item in ipairs(favorites) do
            if not item.is_folder and path_mod.normalize(item.path) == norm then
                table.remove(favorites, i)
                save(ws, favorites)
                view.reload()
                return false
            end
        end
        table.insert(favorites, {
            path     = file_path,
            name     = path_mod.basename(file_path),
            folder   = folder_name,
            added_at = os.time(),
        })
        save(ws, favorites)
        view.reload()
        return true
    end

    --- Add a folder grouping.
    ---@param folder_name string
    function view.add_folder(folder_name)
        if not folder_name or folder_name == "" then return false end
        for _, item in ipairs(favorites) do
            if item.is_folder and item.name == folder_name then return false end
        end
        table.insert(favorites, { is_folder = true, name = folder_name, parent = nil, added_at = os.time() })
        save(ws, favorites)
        view.reload()
        return true
    end

    --- Remove a folder (items inside are moved to Default).
    ---@param folder_name string
    function view.remove_folder(folder_name)
        local new_list = {}
        for _, item in ipairs(favorites) do
            if item.is_folder and item.name == folder_name then
                -- skip (delete the folder)
            else
                if not item.is_folder and item.folder == folder_name then
                    item.folder = "Default"
                end
                table.insert(new_list, item)
            end
        end
        favorites = new_list
        save(ws, favorites)
        view.reload()
    end

    --- Rename a folder.
    function view.rename_folder(old_name, new_name)
        if not new_name or new_name == "" or old_name == new_name then return false end
        for _, item in ipairs(favorites) do
            if item.is_folder and item.name == old_name then item.name = new_name end
            if not item.is_folder and item.folder == old_name then item.folder = new_name end
        end
        save(ws, favorites)
        view.reload()
        return true
    end

    --- Move a file to a different folder.
    function view.move_to_folder(file_path, dest_folder)
        local norm = path_mod.normalize(file_path)
        for _, item in ipairs(favorites) do
            if not item.is_folder and path_mod.normalize(item.path) == norm then
                item.folder = dest_folder
                break
            end
        end
        save(ws, favorites)
        view.reload()
    end

    --- Get a flat list of all favorite file paths.
    ---@return string[]
    function view.get_paths()
        local result = {}
        for _, item in ipairs(favorites) do
            if not item.is_folder then table.insert(result, item.path) end
        end
        return result
    end

    return view
end

return M
