-- lua/CW/ui/view/tree.lua
-- Unified view: ★ Favorites root + multi-root workspace folder tree in one panel.
-- Favorites are shown as a collapsible root at the top, mixed with folder roots.

local Tree     = require("nui.tree")
local renderer = require("vscode-workspace.ui.renderer")
local filter   = require("vscode-workspace.filter")
local path     = require("vscode-workspace.path")
local store    = require("vscode-workspace.store")
local picker   = require("vscode-workspace.picker")

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

--- Build nui.tree children for the ★ Favorites root.
--- Files with folder=nil are placed directly under the root.
--- Folders support nesting via item.parent.
---@param fav_data table[]
---@return NuiTree.Node[]
local function build_fav_nodes(fav_data)
    -- Folder metadata map: name → { parent, files=[] }
    local folder_map   = {}
    local folder_order = {}

    for _, item in ipairs(fav_data) do
        if item.is_folder and not folder_map[item.name] then
            folder_map[item.name] = { parent = item.parent or nil, icon = item.icon or nil, files = {} }
            table.insert(folder_order, item.name)
        end
    end

    -- Distribute file entries: known folder → that folder, otherwise → root
    local root_files = {}
    for _, item in ipairs(fav_data) do
        if not item.is_folder then
            local target = item.folder
            if target and folder_map[target] then
                table.insert(folder_map[target].files, item)
            else
                table.insert(root_files, item)
            end
        end
    end

    local function make_item_node(item)
        local is_dir = item.is_dir or (item.path and vim.fn.isdirectory(item.path) == 1)
        return Tree.Node({
            text          = item.name or path.basename(item.path),
            id            = "fav_item:" .. item.path,
            path          = item.path,
            type          = is_dir and "directory" or "file",
            _has_children = is_dir and true or false,
            extra         = { cw_type = "fav_item" },
        })
    end

    -- Recursively build folder nodes whose parent matches parent_name
    local function make_folder_nodes(parent_name)
        local nodes = {}
        for _, fname in ipairs(folder_order) do
            local fd = folder_map[fname]
            if fd.parent == parent_name then
                local file_nodes = vim.tbl_map(make_item_node, fd.files)
                local sub_nodes  = make_folder_nodes(fname)
                local all_ch = {}
                vim.list_extend(all_ch, sub_nodes)
                vim.list_extend(all_ch, file_nodes)
                local has_ch = #all_ch > 0
                table.insert(nodes, Tree.Node({
                    text          = fname,
                    id            = "fav_folder:" .. fname,
                    type          = "fav_folder",
                    _has_children = has_ch,
                    extra         = { cw_type = "fav_folder", folder_name = fname, icon = folder_map[fname].icon },
                }, has_ch and all_ch or nil))
            end
        end
        return nodes
    end

    -- Top-level: root folders first, then root-level items
    local top = make_folder_nodes(nil)
    for _, item in ipairs(root_files) do
        table.insert(top, make_item_node(item))
    end
    return top
end

-- ── View factory ──────────────────────────────────────────────────────────────

---@param buf integer  Buffer to render into
---@param ws  table    Workspace object
---@return table       View { tree, ws, buf, expand_node, toggle_favorite,
---                          get_paths, refresh, save_state }
function M.new(buf, ws)
    local conf = require("vscode-workspace.config").get()

    local ignore_dirs = {}
    for _, d in ipairs(conf.ignore_dirs or {}) do ignore_dirs[d] = true end
    local is_excluded = filter.make_matcher(ws.exclude_map or {})

    local RECENT_MAX = (conf.recent_files and conf.recent_files.max) or 20

    -- ── Initial node list: favorites root + recent root + workspace folder roots ────────────

    local fav_root_node = Tree.Node({
        text          = "Favorites",
        id            = "__favorites__",
        type          = "fav_root",
        _has_children = true,
        extra         = { cw_type = "fav_root" },
    })

    local recent_root_node = Tree.Node({
        text          = "Recent",
        id            = "__recent__",
        type          = "recent_root",
        _has_children = true,
        extra         = { cw_type = "recent_root" },
    })

    -- .code-workspace file node (for quick access / editing)
    local ws_file_node = Tree.Node({
        text  = vim.fn.fnamemodify(ws.ws_path, ":t"),
        id    = ws.ws_path,
        path  = ws.ws_path,
        type  = "file",
        extra = { cw_type = "ws_file" },
    })

    local all_roots = { fav_root_node, recent_root_node, ws_file_node }
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

        -- Collect all expanded fav-folder names recursively
        local open_folders = {}
        local function collect_open(node_ids)
            for _, id in ipairs(node_ids or {}) do
                local n = tree:get_node(id)
                if n and n.type == "fav_folder" then
                    if n:is_expanded() then
                        open_folders[n.text] = true
                        collect_open(n:get_child_ids())
                    end
                end
            end
        end
        collect_open(fav_root:get_child_ids())
        local root_was_open = fav_root:is_expanded()

        -- Rebuild nodes
        local top_nodes = build_fav_nodes(fav_data)
        tree:set_nodes(top_nodes, "__favorites__")

        -- Restore expansion recursively
        local function restore_open(node_ids)
            for _, id in ipairs(node_ids or {}) do
                local n = tree:get_node(id)
                if n and n.type == "fav_folder" then
                    if n:has_children() and open_folders[n.text] then
                        n:expand()
                        restore_open(n:get_child_ids())
                    end
                end
            end
        end

        local fr2 = tree:get_node("__favorites__")
        if fr2 then
            restore_open(fr2:get_child_ids())
            if root_was_open then fr2:expand() end
        end
    end

    -- ── Recent files data (mutable) ───────────────────────────────────────────

    local recent_data = store.load_ws(ws.safe_name, "recent_files") or {}

    --- Build nui.tree children for the Recent root.
    local function build_recent_nodes()
        local nodes = {}
        for _, item in ipairs(recent_data) do
            if path.exists(item.path) then
                table.insert(nodes, Tree.Node({
                    text  = path.basename(item.path),
                    id    = "recent_item:" .. item.path,
                    path  = item.path,
                    type  = "file",
                    extra = { cw_type = "recent_item" },
                }))
            end
        end
        return nodes
    end

    --- Rebuild the recent subtree in-place, preserving expansion state.
    local function rebuild_recent()
        local rr = tree:get_node("__recent__")
        if not rr then return end
        local was_open = rr:is_expanded()
        tree:set_nodes(build_recent_nodes(), "__recent__")
        local rr2 = tree:get_node("__recent__")
        if rr2 and was_open then rr2:expand() end
    end

    -- ── Populate favorites on first open ──────────────────────────────────────

    local top_nodes = build_fav_nodes(fav_data)
    tree:set_nodes(top_nodes, "__favorites__")
    -- Auto-expand folders that have children
    for _, fn in ipairs(top_nodes) do
        local n = tree:get_node(fn.id)
        if n and n.type == "fav_folder" and n:has_children() then n:expand() end
    end
    -- Expand favorites root by default
    local fr = tree:get_node("__favorites__")
    if fr then fr:expand() end

    -- ── Populate recent files on first open ───────────────────────────────────

    tree:set_nodes(build_recent_nodes(), "__recent__")
    -- Recent root starts collapsed to avoid clutter

    -- ── View object ───────────────────────────────────────────────────────────

    local view = { tree = tree, ws = ws, buf = buf }

    --- Expand a node lazily.
    --- fav_root / fav_folder: children already loaded, nothing to do.
    --- directory: lazy filesystem scan. Recursively restores saved expansion state.
    function view.expand_node(node)
        if node.type == "fav_root" or node.type == "fav_folder" or node.type == "recent_root" then return end
        if not node._has_children then return end
        if node:has_children() then return end  -- already scanned

        local children = scan_dir(node.path, is_excluded, ignore_dirs)
        tree:set_nodes(children, node.id)
        for _, child in ipairs(children) do
            if expanded_ids[child.id] then
                local cn = tree:get_node(child.id)
                if cn then
                    -- scan children FIRST (sets _child_ids), THEN expand
                    -- nui.tree's expand() is a no-op when _child_ids is nil
                    view.expand_node(cn)
                    cn:expand()
                end
            end
        end
    end

    --- Return folder display pathsfor picker: [{display="Work/Sub", name="Sub"}, ...]
    local function get_folder_paths()
        local folder_defs = {}
        for _, item in ipairs(fav_data) do
            if item.is_folder then table.insert(folder_defs, item) end
        end
        if #folder_defs == 0 then return {} end

        local function get_full(name)
            if not name then return "" end
            for _, f in ipairs(folder_defs) do
                if f.name == name then
                    local pp = get_full(f.parent)
                    return pp == "" and name or (pp .. "/" .. name)
                end
            end
            return name
        end

        local result = {}
        for _, f in ipairs(folder_defs) do
            table.insert(result, { display = get_full(f.name), name = f.name })
        end
        table.sort(result, function(a, b) return a.display:lower() < b.display:lower() end)
        return result
    end

    --- Toggle a file in favorites.
    --- When removing: synchronous. When adding and folders exist: async (picker).
    --- on_done(added: boolean) is called after the operation completes.
    ---@param file_path string
    ---@param on_done? fun(added: boolean)
    function view.toggle_favorite(file_path, on_done)
        local norm = path.normalize(file_path)
        -- Remove if already present
        for i, item in ipairs(fav_data) do
            if not item.is_folder and path.normalize(item.path) == norm then
                table.remove(fav_data, i)
                store.save_ws(ws.safe_name, "favorites", fav_data)
                rebuild_favorites()
                tree:render()
                if on_done then on_done(false) end
                return false
            end
        end

        -- Adding: detect if it's a directory
        local is_dir = vim.fn.isdirectory(file_path) == 1
        local folder_paths = get_folder_paths()
        local function do_add(folder_name)
            table.insert(fav_data, {
                path     = file_path,
                name     = path.basename(file_path),
                is_dir   = is_dir or nil,   -- store only when true to keep JSON clean
                folder   = folder_name,
                added_at = os.time(),
            })
            store.save_ws(ws.safe_name, "favorites", fav_data)
            rebuild_favorites()
            tree:render()
            if on_done then on_done(true) end
        end

        if #folder_paths == 0 then
            do_add(nil)
            return true
        end

        local choices = { "(Root level)" }
        for _, fp in ipairs(folder_paths) do table.insert(choices, fp.display) end
        picker.select(choices, { prompt = "Add to favorites folder:", on_submit = function(choice)
            if not choice then return end
            if choice == "(Root level)" then
                do_add(nil)
            else
                local parts = vim.split(choice, "/", { plain = true })
                do_add(parts[#parts])
            end
        end })
        return true  -- async; caller should use on_done
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

    --- Add a file to recent files if it belongs to this workspace.
    --- Also re-renders the tree (for current-file highlight).
    ---@param file_path string
    function view.add_recent(file_path)
        if not vim.api.nvim_buf_is_valid(buf) then return end
        local norm = path.normalize(file_path)
        -- Check if file is under any workspace folder
        local in_ws = false
        for _, folder in ipairs(ws.folders or {}) do
            local fp = folder.path  -- already normalized (no trailing slash)
            if path.equal(norm:sub(1, #fp), fp) then
                local next_char = norm:sub(#fp + 1, #fp + 1)
                if next_char == "/" or next_char == "" then
                    in_ws = true; break
                end
            end
        end

        if in_ws then
            -- Remove existing entry to move it to front
            for i, item in ipairs(recent_data) do
                if path.equal(item.path, file_path) then
                    table.remove(recent_data, i); break
                end
            end
            table.insert(recent_data, 1, { path = file_path, time = os.time() })
            -- Trim to configured max
            while #recent_data > RECENT_MAX do table.remove(recent_data) end
            store.save_ws(ws.safe_name, "recent_files", recent_data)
            rebuild_recent()
        end

        -- Always re-render so current-file highlight updates
        tree:render()
    end

    --- Set a custom icon for a favorite folder.
    ---@param node table  nui.tree node (must be fav_folder type)
    function view.set_fav_folder_icon(node)
        if not node or node.type ~= "fav_folder" then
            vim.notify("[CW] Cursor is not on a favorites folder", vim.log.levels.WARN)
            return
        end
        local fname = node.extra and node.extra.folder_name
        local current_icon = node.extra and node.extra.icon or ""
        vim.ui.input({ prompt = "Icon for '" .. fname .. "' (empty to reset): ",
                       default = current_icon }, function(icon_str)
            if icon_str == nil then return end  -- cancelled
            for _, item in ipairs(fav_data) do
                if item.is_folder and item.name == fname then
                    item.icon = (icon_str ~= "") and icon_str or nil
                    break
                end
            end
            store.save_ws(ws.safe_name, "favorites", fav_data)
            rebuild_favorites()
            tree:render()
        end)
    end

    --- Refresh: recursively rescan all currently-expanded real directories.
    function view.refresh()
        local function rescan_node(n)
            if not n then return end
            if n.type ~= "directory" then return end
            -- Skip fav virtual folders
            local ct = n.extra and n.extra.cw_type
            if ct == "fav_folder" or ct == "fav_root" then return end
            if not n:has_children() then return end  -- not yet loaded; skip

            -- Remember which children were expanded before clearing
            local was_open = {}
            for _, cid in ipairs(n:get_child_ids() or {}) do
                local cn = tree:get_node(cid)
                if cn and cn:is_expanded() then was_open[cid] = true end
            end

            local children = scan_dir(n.path, is_excluded, ignore_dirs)
            tree:set_nodes(children, n.id)

            for _, child in ipairs(children) do
                if was_open[child.id] then
                    local cn = tree:get_node(child.id)
                    if cn then
                        cn:expand()
                        rescan_node(cn)
                    end
                end
            end
        end

        for _, id in ipairs(tree.nodes.root_ids or {}) do
            rescan_node(tree:get_node(id))
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

    -- ── Favorites folder operations ───────────────────────────────────────────

    --- Add a new folder. Parent is auto-detected from cursor: if on a fav_folder node,
    --- new folder is created as a child of that folder; otherwise at root level.
    function view.add_fav_folder(node)
        local parent_name = nil
        if node and node.type == "fav_folder" then
            parent_name = node.extra and node.extra.folder_name
        end
        local prompt = parent_name
            and ("New folder under '" .. parent_name .. "': ")
            or "New favorites folder: "
        vim.ui.input({ prompt = prompt }, function(name)
            if not name or name == "" then return end
            for _, item in ipairs(fav_data) do
                if item.is_folder and item.name == name and item.parent == parent_name then
                    vim.notify("[CW] Folder '" .. name .. "' already exists here", vim.log.levels.WARN)
                    return
                end
            end
            table.insert(fav_data, {
                is_folder = true,
                name      = name,
                parent    = parent_name,
                added_at  = os.time(),
            })
            store.save_ws(ws.safe_name, "favorites", fav_data)
            rebuild_favorites()
            tree:render()
            vim.notify("[CW] Added folder: " .. name, vim.log.levels.INFO)
        end)
    end

    function view.rename_fav_folder(node)
        if not node or node.type ~= "fav_folder" then
            vim.notify("[CW] Cursor is not on a favorites folder", vim.log.levels.WARN)
            return
        end
        local old_name = node.extra and node.extra.folder_name
        vim.ui.input({ prompt = "Rename folder: ", default = old_name }, function(new_name)
            if not new_name or new_name == "" or new_name == old_name then return end
            for _, item in ipairs(fav_data) do
                if item.is_folder     and item.name   == old_name then item.name   = new_name end
                if item.is_folder     and item.parent == old_name then item.parent = new_name end
                if not item.is_folder and item.folder == old_name then item.folder = new_name end
            end
            store.save_ws(ws.safe_name, "favorites", fav_data)
            rebuild_favorites()
            tree:render()
        end)
    end

    function view.remove_fav_folder(node)
        if not node or node.type ~= "fav_folder" then
            vim.notify("[CW] Cursor is not on a favorites folder", vim.log.levels.WARN)
            return
        end
        local fname = node.extra and node.extra.folder_name
        vim.ui.select({ "Yes", "No" }, {
            prompt = "Remove folder '" .. fname .. "'? (files moved to root)",
        }, function(choice)
            if choice ~= "Yes" then return end
            local new_data = {}
            for _, item in ipairs(fav_data) do
                if not (item.is_folder and item.name == fname) then
                    if not item.is_folder and item.folder == fname then
                        item.folder = nil  -- move to Favorites root
                    end
                    -- Re-parent any child folders whose parent was fname → promote to root
                    if item.is_folder and item.parent == fname then
                        item.parent = nil
                    end
                    table.insert(new_data, item)
                end
            end
            fav_data = new_data
            store.save_ws(ws.safe_name, "favorites", fav_data)
            rebuild_favorites()
            tree:render()
            vim.notify("[CW] Removed folder: " .. fname, vim.log.levels.INFO)
        end)
    end

    function view.move_to_fav_folder(node)
        if not node then return end
        local ct = node.extra and node.extra.cw_type
        local is_fav_folder_node = (ct == "fav_folder")
        local is_fav_item_node   = false
        local norm = node.path and path.normalize(node.path)

        if not is_fav_folder_node then
            if not norm then
                vim.notify("[CW] Cursor is not on a favorites item or folder", vim.log.levels.WARN)
                return
            end
            for _, item in ipairs(fav_data) do
                if not item.is_folder and path.normalize(item.path) == norm then
                    is_fav_item_node = true; break
                end
            end
        end

        if not is_fav_folder_node and not is_fav_item_node then
            vim.notify("[CW] Cursor is not on a favorites item or folder", vim.log.levels.WARN)
            return
        end

        local self_name    = is_fav_folder_node and (node.extra and node.extra.folder_name) or nil
        local folder_paths = get_folder_paths()

        -- Build choices: (Root level) + all folders except self
        local choices = { { display = "(Root level)", name = nil } }
        for _, fp in ipairs(folder_paths) do
            if fp.name ~= self_name then table.insert(choices, fp) end
        end
        local display_choices = vim.tbl_map(function(c) return c.display end, choices)

        picker.select(display_choices, { prompt = "Move to:", on_submit = function(choice)
            if not choice then return end
            local target_name = nil
            for _, c in ipairs(choices) do
                if c.display == choice then target_name = c.name; break end
            end
            if is_fav_folder_node then
                for _, item in ipairs(fav_data) do
                    if item.is_folder and item.name == self_name then
                        item.parent = target_name; break
                    end
                end
            else
                for _, item in ipairs(fav_data) do
                    if not item.is_folder and path.normalize(item.path) == norm then
                        item.folder = target_name; break
                    end
                end
            end
            store.save_ws(ws.safe_name, "favorites", fav_data)
            rebuild_favorites()
            tree:render()
        end })
    end

    -- ── File system operations ────────────────────────────────────────────────

    local function get_target_dir(node)
        if not node then return nil end
        local ct = node.extra and node.extra.cw_type
        if node.type == "directory" or ct == "root" then
            return node.path
        elseif node.type == "file" and node.path then
            return path.parent(node.path)
        end
        return nil
    end

    function view.create_file(node)
        local dir = get_target_dir(node)
        if not dir then
            vim.notify("[CW] Place cursor on a directory or file first", vim.log.levels.WARN)
            return
        end
        vim.ui.input({ prompt = "New file (in " .. path.basename(dir) .. "/): " }, function(name)
            if not name or name == "" then return end
            local full       = path.join(dir, name)
            local parent_dir = path.parent(full)
            vim.fn.mkdir(parent_dir, "p")
            local f = io.open(full, "w")
            if f then
                f:close()
                view.refresh()
                vim.notify("[CW] Created: " .. full, vim.log.levels.INFO)
            else
                vim.notify("[CW] Failed to create: " .. full, vim.log.levels.ERROR)
            end
        end)
    end

    function view.create_dir(node)
        local dir = get_target_dir(node)
        if not dir then
            vim.notify("[CW] Place cursor on a directory or file first", vim.log.levels.WARN)
            return
        end
        vim.ui.input({ prompt = "New directory (in " .. path.basename(dir) .. "/): " }, function(name)
            if not name or name == "" then return end
            local full = path.join(dir, name)
            if vim.fn.mkdir(full, "p") == 1 then
                view.refresh()
                vim.notify("[CW] Created directory: " .. full, vim.log.levels.INFO)
            else
                vim.notify("[CW] Failed to create directory: " .. full, vim.log.levels.ERROR)
            end
        end)
    end

    function view.delete_node(node)
        if not node or not node.path then return end
        local ct = node.extra and node.extra.cw_type
        if ct == "root" or ct == "fav_root" or ct == "fav_folder" then
            vim.notify("[CW] Cannot delete workspace roots or favorite folders here", vim.log.levels.WARN)
            return
        end
        local name = path.basename(node.path)
        vim.ui.select({ "Yes", "No" }, { prompt = "Delete '" .. name .. "'?" }, function(choice)
            if choice ~= "Yes" then return end
            local stat = vim.loop.fs_stat(node.path)
            if not stat then view.refresh(); return end
            local result = (stat.type == "directory")
                and vim.fn.delete(node.path, "rf")
                or  vim.fn.delete(node.path)
            if result == 0 then
                view.refresh()
                vim.notify("[CW] Deleted: " .. name, vim.log.levels.INFO)
            else
                vim.notify("[CW] Failed to delete: " .. name, vim.log.levels.ERROR)
            end
        end)
    end

    function view.rename_node(node)
        if not node or not node.path then return end
        local ct = node.extra and node.extra.cw_type
        if ct == "root" or ct == "fav_root" or ct == "fav_folder" then return end
        local old_name = path.basename(node.path)
        vim.ui.input({ prompt = "Rename: ", default = old_name }, function(new_name)
            if not new_name or new_name == "" or new_name == old_name then return end
            local new_full = path.join(path.parent(node.path), new_name)
            local ok, err  = vim.loop.fs_rename(node.path, new_full)
            if ok then
                -- Update favorites entry if this file was bookmarked
                local old_norm = path.normalize(node.path)
                local changed  = false
                for _, item in ipairs(fav_data) do
                    if not item.is_folder and path.normalize(item.path) == old_norm then
                        item.path = new_full
                        item.name = new_name
                        changed   = true
                    end
                end
                if changed then store.save_ws(ws.safe_name, "favorites", fav_data) end
                view.refresh()
                vim.notify("[CW] Renamed: " .. old_name .. " → " .. new_name, vim.log.levels.INFO)
            else
                vim.notify("[CW] Rename failed: " .. (err or "unknown"), vim.log.levels.ERROR)
            end
        end)
    end

    tree:render()

    -- ── Restore directory expansion state (deferred) ─────────────────────────
    -- vim.schedule ensures nui.tree's internal state is fully settled after the
    -- first render before we scan subdirectories and call set_nodes / get_node.
    -- Same pattern as UNX.nvim restore_expansion_explicit.
    if not vim.tbl_isempty(expanded_ids) then
        vim.schedule(function()
            if not vim.api.nvim_buf_is_valid(buf) then return end
            for _, root_node in ipairs(tree:get_nodes()) do
                if root_node.type == "directory" and expanded_ids[root_node.id] then
                    -- scan children FIRST (sets _child_ids), THEN expand
                    -- nui.tree's expand() is a no-op when _child_ids is nil
                    view.expand_node(root_node)
                    root_node:expand()
                end
            end
            tree:render()
        end)
    end

    return view
end

return M
