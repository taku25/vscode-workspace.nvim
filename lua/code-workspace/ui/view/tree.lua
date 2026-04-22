-- lua/CW/ui/view/tree.lua
-- Unified view: ★ Favorites root + multi-root workspace folder tree in one panel.
-- Favorites are shown as a collapsible root at the top, mixed with folder roots.

local Tree     = require("nui.tree")
local renderer = require("code-workspace.ui.renderer")
local filter   = require("code-workspace.filter")
local path     = require("code-workspace.path")
local store    = require("code-workspace.store")

local M = {}

local HARD_IGNORE = { [".git"] = true, [".vs"] = true }

-- ── Filesystem scanner ────────────────────────────────────────────────────────

local function scan_dir(dir_path, is_excluded, ignore_dirs)
    local nodes = {}
    local handle = vim.loop.fs_scandir(dir_path)
    if not handle then return nodes end
    while true do
        local name, ftype = vim.loop.fs_scandir_next(handle)
        if not name then break end
        if name:sub(1, 1) == "." then goto continue end
        local full = path.join(dir_path, name)
        if HARD_IGNORE[name] then goto continue end
        if ftype == "directory" and ignore_dirs[name] then goto continue end
        if is_excluded(name, full) then goto continue end
        local is_dir = ftype == "directory"
        table.insert(nodes, Tree.Node({
            text = name, id = full, path = full,
            type = is_dir and "directory" or "file",
            _has_children = is_dir,
        }))
        ::continue::
    end
    table.sort(nodes, function(a, b)
        if a.type == "directory" and b.type ~= "directory" then return true end
        if a.type ~= "directory" and b.type == "directory" then return false end
        return (a.text or ""):lower() < (b.text or ""):lower()
    end)
    return nodes
end

-- ── Favorites helpers ─────────────────────────────────────────────────────────

--- Build nui.tree Nodes for the favorites subtree.
---@param fav_data table[]  Favorites list from store
---@return NuiTree.Node[]   folder-level nodes (each has file children)
local function build_fav_folder_nodes(fav_data)
    -- Collect folder names in insertion order
    local folder_order = { "Default" }
    local folder_set   = { Default = true }
    local folder_files = { Default = {} }

    for _, item in ipairs(fav_data) do
        if item.is_folder then
            if not folder_set[item.name] then
                table.insert(folder_order, item.name)
                folder_set[item.name]  = true
                folder_files[item.name] = {}
            end
        end
    end
    for _, item in ipairs(fav_data) do
        if not item.is_folder then
            local fname = item.folder or "Default"
            if not folder_files[fname] then
                folder_files[fname] = {}
                if not folder_set[fname] then
                    table.insert(folder_order, fname)
                    folder_set[fname] = true
                end
            end
            table.insert(folder_files[fname], item)
        end
    end

    local folder_nodes = {}
    for _, fname in ipairs(folder_order) do
        local files = folder_files[fname] or {}
        local file_nodes = vim.tbl_map(function(item)
            return Tree.Node({
                text  = item.name or path.basename(item.path),
                id    = "fav_file:" .. item.path,
                path  = item.path,
                type  = "file",
                extra = { cw_type = "fav_file" },
            })
        end, files)
        table.insert(folder_nodes, Tree.Node({
            text          = fname,
            id            = "fav_folder:" .. fname,
            type          = "fav_folder",
            _has_children = #file_nodes > 0,
            extra         = { cw_type = "fav_folder", folder_name = fname },
        }, #file_nodes > 0 and file_nodes or nil))
    end
    return folder_nodes
end

-- ── View factory ──────────────────────────────────────────────────────────────

---@param buf integer  Buffer to render into
---@param ws  table    Workspace object
---@return table       View { tree, ws, buf, expand_node, toggle_favorite,
---                          get_paths, refresh, save_state }
function M.new(buf, ws)
    local conf = require("code-workspace.config").get()

    local ignore_dirs = {}
    for _, d in ipairs(conf.ignore_dirs or {}) do ignore_dirs[d] = true end
    local is_excluded = filter.make_matcher(ws.exclude_map or {})

    -- ── Initial node list: favorites root + workspace folder roots ────────────

    local fav_root_node = Tree.Node({
        text          = "★ Favorites",
        id            = "__favorites__",
        type          = "fav_root",
        _has_children = true,
        extra         = { cw_type = "fav_root" },
    })

    local all_roots = { fav_root_node }
    for _, folder in ipairs(ws.folders or {}) do
        if path.exists(folder.path) then
            table.insert(all_roots, Tree.Node({
                text          = folder.name,
                id            = folder.path,
                path          = folder.path,
                type          = "directory",
                _has_children = true,
                extra         = { cw_type = "root", is_uefn = ws.is_uefn },
            }))
        end
    end

    -- ── Restore saved expansion state ─────────────────────────────────────────

    local saved_state = store.load_ws(ws.safe_name, "tree_state")
    local expanded_ids = {}
    for _, id in ipairs((saved_state or {}).expanded or {}) do
        expanded_ids[id] = true
    end

    -- ── Create tree ───────────────────────────────────────────────────────────

    local tree = Tree({
        bufnr        = buf,
        nodes        = all_roots,
        prepare_node = renderer.prepare_node,
        get_node_id  = function(node) return node.id end,
    })

    -- ── Favorites data (mutable) ──────────────────────────────────────────────

    local fav_data = store.load_ws(ws.safe_name, "favorites") or {}

    --- Rebuild the favorites subtree in-place, preserving expansion where possible.
    local function rebuild_favorites()
        local fav_root = tree:get_node("__favorites__")
        if not fav_root then return end

        -- Remember which folders were expanded
        local open_folders = {}
        for _, id in ipairs(fav_root:get_child_ids() or {}) do
            local n = tree:get_node(id)
            if n and n:is_expanded() then open_folders[n.text] = true end
        end
        local root_was_open = fav_root:is_expanded()

        -- Rebuild folder nodes with children
        local folder_nodes = build_fav_folder_nodes(fav_data)
        tree:set_nodes(folder_nodes, "__favorites__")

        -- Restore expansion
        for _, fn in ipairs(folder_nodes) do
            local n = tree:get_node(fn.id)
            if n and n:has_children() and open_folders[fn.text] then
                n:expand()
            end
        end
        if root_was_open then
            local fr = tree:get_node("__favorites__")
            if fr then fr:expand() end
        end
    end

    -- ── Populate favorites on first open ──────────────────────────────────────

    local folder_nodes = build_fav_folder_nodes(fav_data)
    tree:set_nodes(folder_nodes, "__favorites__")
    -- Auto-expand folders that have files
    for _, fn in ipairs(folder_nodes) do
        local n = tree:get_node(fn.id)
        if n and n:has_children() then n:expand() end
    end
    -- Expand favorites root by default
    local fr = tree:get_node("__favorites__")
    if fr then fr:expand() end

    -- Restore directory expansion state
    for id, _ in pairs(expanded_ids) do
        local n = tree:get_node(id)
        if n then n:expand() end
    end

    -- ── View object ───────────────────────────────────────────────────────────

    local view = { tree = tree, ws = ws, buf = buf }

    --- Expand a node lazily.
    --- fav_root / fav_folder: children already loaded, nothing to do.
    --- directory: lazy filesystem scan.
    function view.expand_node(node)
        if node.type == "fav_root" or node.type == "fav_folder" then return end
        if not node._has_children then return end
        if node:has_children() then return end  -- already scanned

        local children = scan_dir(node.path, is_excluded, ignore_dirs)
        tree:set_nodes(children, node.id)
        for _, child in ipairs(children) do
            if expanded_ids[child.id] then
                local cn = tree:get_node(child.id)
                if cn then cn:expand() end
            end
        end
    end

    --- Toggle a file in favorites; returns true if added, false if removed.
    ---@param file_path string
    ---@return boolean added
    function view.toggle_favorite(file_path)
        local norm  = path.normalize(file_path)
        local added = true
        for i, item in ipairs(fav_data) do
            if not item.is_folder and path.normalize(item.path) == norm then
                table.remove(fav_data, i)
                added = false
                break
            end
        end
        if added then
            table.insert(fav_data, {
                path     = file_path,
                name     = path.basename(file_path),
                folder   = "Default",
                added_at = os.time(),
            })
        end
        store.save_ws(ws.safe_name, "favorites", fav_data)
        rebuild_favorites()
        tree:render()
        return added
    end

    --- Return all favorite file paths.
    ---@return string[]
    function view.get_paths()
        local result = {}
        for _, item in ipairs(fav_data) do
            if not item.is_folder then table.insert(result, item.path) end
        end
        return result
    end

    --- Refresh: clear lazy-loaded directory children and re-render.
    function view.refresh()
        for id, _ in pairs(expanded_ids) do
            local n = tree:get_node(id)
            if n and n.type == "directory" then
                tree:set_nodes({}, id)
            end
        end
        rebuild_favorites()
        tree:render()
    end

    --- Save expanded directory state to persistent store.
    function view.save_state()
        local expanded = {}
        local function walk(node_ids)
            for _, id in ipairs(node_ids or {}) do
                local n = tree:get_node(id)
                if n then
                    if n:is_expanded() and n.type == "directory" then
                        table.insert(expanded, n.id)
                    end
                    walk(n:get_child_ids())
                end
            end
        end
        walk(tree.nodes.root_ids)
        store.save_ws(ws.safe_name, "tree_state", { expanded = expanded })
    end

    tree:render()
    return view
end

return M
