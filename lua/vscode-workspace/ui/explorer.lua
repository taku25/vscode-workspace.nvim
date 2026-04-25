-- lua/CW/ui/explorer.lua
-- Single-pane explorer: ★ Favorites + workspace folder tree in one view.
-- Winbar shows the workspace name (no tab switching needed).

local Split     = require("nui.split")
local ViewTree  = require("vscode-workspace.ui.view.tree")
local workspace = require("vscode-workspace.workspace")
local renderer  = require("vscode-workspace.ui.renderer")
local store     = require("vscode-workspace.store")
local path      = require("vscode-workspace.path")

local M = {}

-- ── State ────────────────────────────────────────────────────────────────────

local state = {
    split         = nil,  -- nui.split instance
    win           = nil,  -- window id
    ws            = nil,  -- current workspace
    view          = nil,  -- ViewTree instance
    autocmd_group = nil,  -- augroup id for lifecycle autocmds
}

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function get_conf()
    return require("vscode-workspace.config").get()
end

local function is_open()
    return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

local function update_winbar()
    if not is_open() then return end
    local name = state.ws and state.ws.name or "code-workspace"
    pcall(vim.api.nvim_win_set_option, state.win, "winbar",
        "%#CWTabActive# 󰉋 " .. name .. " %#Normal#")
end

local function open_node_at_cursor(target_win)
    if not (state.view and state.view.tree) then return end
    local node = state.view.tree:get_node()
    if not node then return end

    local is_dir = node.type == "directory" or node.type == "fav_root"
                   or node.type == "fav_folder" or node.type == "recent_root"
                   or node._has_children
    if is_dir then
        if node:is_expanded() then
            node:collapse()
        else
            state.view.expand_node(node)
            node:expand()
        end
        state.view.save_state()
        state.view.tree:render()
    elseif node.path then
        local win = target_win
        if not (win and vim.api.nvim_win_is_valid(win)) then
            win = vim.fn.win_getid(vim.fn.winnr("#"))
        end
        vim.api.nvim_set_current_win(win)
        vim.cmd("edit " .. vim.fn.fnameescape(node.path))
    end
end

local function setup_keymaps(buf)
    local km = get_conf().keymaps
    local prev_win = nil

    local function map(keys, fn)
        if type(keys) == "string" then keys = { keys } end
        for _, k in ipairs(keys) do
            vim.keymap.set("n", k, fn, { buffer = buf, nowait = true, silent = true })
        end
    end

    map(km.close, function() M.close() end)

    map(km.open, function()
        if not prev_win or not vim.api.nvim_win_is_valid(prev_win) then
            prev_win = vim.fn.win_getid(vim.fn.winnr("#"))
        end
        open_node_at_cursor(prev_win)
    end)

    map(km.vsplit, function()
        local node = state.view and state.view.tree and state.view.tree:get_node()
        if node and node.path and node.type == "file" then
            vim.cmd("vsplit " .. vim.fn.fnameescape(node.path))
        end
    end)

    map(km.split, function()
        local node = state.view and state.view.tree and state.view.tree:get_node()
        if node and node.path and node.type == "file" then
            vim.cmd("split " .. vim.fn.fnameescape(node.path))
        end
    end)

    map(km.refresh, function()
        if state.view and state.view.refresh then state.view.refresh() end
    end)

    map(km.toggle_favorite, function()
        if not state.view then return end
        local node = state.view.tree and state.view.tree:get_node()
        -- Allow files and real directories (not workspace roots or fav virtual nodes)
        local cw_type = node and node.extra and node.extra.cw_type
        local is_real = cw_type ~= "root" and cw_type ~= "fav_root"
                        and cw_type ~= "fav_folder" and cw_type ~= "recent_root"
        local file_path = (node and node.path and is_real)
                          and node.path or vim.fn.expand("#:p")
        if file_path and file_path ~= "" then
            state.view.toggle_favorite(file_path, function(added)
                vim.notify(added and "Added to Favorites" or "Removed from Favorites",
                    vim.log.levels.INFO)
            end)
        end
    end)

    map(km.find_files, function()
        require("vscode-workspace.cmd.work_files").execute(state.ws)
    end)

    map(km.live_grep, function()
        require("vscode-workspace.cmd.work_grep").execute(state.ws)
    end)

    -- Favorites folder operations
    map(km.fav_add_folder, function()
        if not state.view then return end
        local node = state.view.tree and state.view.tree:get_node()
        state.view.add_fav_folder(node)
    end)

    map(km.fav_rename_folder, function()
        if not state.view then return end
        local node = state.view.tree and state.view.tree:get_node()
        state.view.rename_fav_folder(node)
    end)

    map(km.fav_remove_folder, function()
        if not state.view then return end
        local node = state.view.tree and state.view.tree:get_node()
        state.view.remove_fav_folder(node)
    end)

    map(km.fav_move, function()
        if not state.view then return end
        local node = state.view.tree and state.view.tree:get_node()
        state.view.move_to_fav_folder(node)
    end)

    -- File system operations
    map(km.file_create, function()
        if not state.view then return end
        local node = state.view.tree and state.view.tree:get_node()
        state.view.create_file(node)
    end)

    map(km.dir_create, function()
        if not state.view then return end
        local node = state.view.tree and state.view.tree:get_node()
        state.view.create_dir(node)
    end)

    map(km.file_delete, function()
        if not state.view then return end
        local node = state.view.tree and state.view.tree:get_node()
        state.view.delete_node(node)
    end)

    map(km.file_rename, function()
        if not state.view then return end
        local node = state.view.tree and state.view.tree:get_node()
        state.view.rename_node(node)
    end)

    map(km.fav_set_icon, function()
        if not state.view then return end
        local node = state.view.tree and state.view.tree:get_node()
        state.view.set_fav_folder_icon(node)
    end)

    map(km.switch_workspace, function()
        M.workspaces()
    end)

    map("<2-LeftMouse>", function()
        local mouse = vim.fn.getmousepos()
        if mouse.winid ~= state.win or mouse.line == 0 then return end
        pcall(vim.api.nvim_win_set_cursor, state.win, { mouse.line, 0 })
        open_node_at_cursor()
    end)
end

-- ── Public API ────────────────────────────────────────────────────────────────

function M.open(opts)
    opts = opts or {}
    if is_open() then
        vim.api.nvim_set_current_win(state.win)
        return
    end

    local function do_open(ws)
        if not ws then
            vim.notify("[CW] No .code-workspace file found", vim.log.levels.WARN)
            return
        end
        state.ws = ws
        require("vscode-workspace.lsp").setup(ws)

        -- ── Track recently used workspaces globally ───────────────────────────
        local recent_wss = store.load_ws("_global", "recent_workspaces") or {}
        local ws_norm    = path.normalize(ws.ws_path)
        for i, item in ipairs(recent_wss) do
            if path.equal(item.path, ws_norm) then table.remove(recent_wss, i); break end
        end
        table.insert(recent_wss, 1, { path = ws_norm, name = ws.name, time = os.time() })
        while #recent_wss > 20 do table.remove(recent_wss) end
        store.save_ws("_global", "recent_workspaces", recent_wss)

        -- ── Capture current file before mounting so it can be highlighted ─────
        local pre_open_buf = vim.api.nvim_get_current_buf()
        local pre_open_name = vim.api.nvim_buf_get_name(pre_open_buf)
        if pre_open_name ~= "" then
            local btype = vim.api.nvim_get_option_value("buftype", { buf = pre_open_buf })
            if btype == "" then
                renderer._current_file = path.normalize(pre_open_name)
            end
        end

        local conf = get_conf()
        state.split = Split({
            relative  = "editor",
            position  = conf.window.position,
            size      = conf.window.width,
            win_options = {
                number         = false,
                relativenumber = false,
                wrap           = false,
                signcolumn     = "no",
                foldcolumn     = "0",
                statuscolumn   = "",
            },
            buf_options = {
                buftype    = "nofile",
                bufhidden  = "hide",
                filetype   = "cw-explorer",
                modifiable = false,
                swapfile   = false,
            },
        })
        state.split:mount()
        state.win = state.split.winid
        local buf = state.split.bufnr

        state.view = ViewTree.new(buf, ws)
        setup_keymaps(buf)
        update_winbar()

        -- ── Autocmd group for this explorer session ───────────────────────────
        state.autocmd_group = vim.api.nvim_create_augroup(
            "CWExplorer_" .. buf, { clear = true })

        -- Track current file for highlight and recent files list on every BufEnter.
        vim.api.nvim_create_autocmd("BufEnter", {
            group    = state.autocmd_group,
            callback = function(ev)
                local bname = vim.api.nvim_buf_get_name(ev.buf)
                local ok, btype = pcall(vim.api.nvim_get_option_value, "buftype", { buf = ev.buf })
                if not ok or btype ~= "" or bname == "" then return end
                renderer._current_file = path.normalize(bname)
                if is_open() and state.view then
                    state.view.add_recent(bname)
                    -- add_recent already calls tree:render(); no extra call needed
                end
            end,
        })

        vim.api.nvim_create_autocmd("WinClosed", {
            pattern  = tostring(state.win),
            once     = true,
            callback = function()
                if state.view then state.view.save_state() end
                if state.autocmd_group then
                    pcall(vim.api.nvim_del_augroup_by_id, state.autocmd_group)
                    state.autocmd_group = nil
                end
                state.split = nil
                state.win   = nil
                state.view  = nil
            end,
        })
    end

    if opts.ws then
        do_open(opts.ws)
    else
        workspace.find(nil, do_open)
    end
end

function M.close()
    if not is_open() then return end
    if state.view then state.view.save_state() end
    if state.autocmd_group then
        pcall(vim.api.nvim_del_augroup_by_id, state.autocmd_group)
        state.autocmd_group = nil
    end
    pcall(function() state.split:unmount() end)
    state.split = nil
    state.win   = nil
    state.view  = nil
end

function M.toggle(opts)
    if is_open() then M.close() else M.open(opts) end
end

function M.focus()
    if not is_open() then M.open() return end
    vim.api.nvim_set_current_win(state.win)
end

function M.refresh()
    if not is_open() then return end
    if state.view and state.view.refresh then state.view.refresh() end
end

--- Toggle favorite for a given path (callable without the panel open).
---@param file_path string
function M.toggle_favorite(file_path)
    local function do_toggle(ws)
        if not ws then return end
        state.ws = ws
        if state.view then
            state.view.toggle_favorite(file_path, function(added)
                vim.notify(added and "Added to Favorites" or "Removed from Favorites",
                    vim.log.levels.INFO)
            end)
            return
        end
        -- Panel not open: update store directly
        local s     = require("vscode-workspace.store")
        local p     = require("vscode-workspace.path")
        local favs  = s.load_ws(ws.safe_name, "favorites") or {}
        local norm  = p.normalize(file_path)
        local added = true
        for i, item in ipairs(favs) do
            if not item.is_folder and p.normalize(item.path) == norm then
                table.remove(favs, i); added = false; break
            end
        end
        if added then
            table.insert(favs, { path = file_path, name = p.basename(file_path),
                                  folder = "Default", added_at = os.time() })
        end
        s.save_ws(ws.safe_name, "favorites", favs)
        vim.notify(added and "Added to Favorites" or "Removed from Favorites",
            vim.log.levels.INFO)
    end
    if state.ws then do_toggle(state.ws) else workspace.find(nil, do_toggle) end
end

--- Return all favorite paths via callback.
---@param on_result fun(paths: string[])
function M.get_favorites(on_result)
    local function do_get(ws)
        if not ws then on_result({}) return end
        state.ws = ws
        if state.view then
            on_result(state.view.get_paths())
            return
        end
        local s    = require("vscode-workspace.store")
        local favs = s.load_ws(ws.safe_name, "favorites") or {}
        local out  = {}
        for _, item in ipairs(favs) do
            if not item.is_folder then table.insert(out, item.path) end
        end
        on_result(out)
    end
    if state.ws then do_get(state.ws) else workspace.find(nil, do_get) end
end

--- Return the currently loaded workspace.
---@return table|nil
function M.current_ws()
    return state.ws
end

--- Show saved workspaces picker (cd to workspace dir + reload explorer).
function M.workspaces()
    local recent_wss = store.load_ws("_global", "recent_workspaces") or {}
    if #recent_wss == 0 then
        vim.notify("[CW] No saved workspaces yet. Open a workspace first.", vim.log.levels.INFO)
        return
    end

    -- Build display labels (name only for readability)
    local labels = {}
    for _, w in ipairs(recent_wss) do
        table.insert(labels, w.name .. "  [" .. w.path .. "]")
    end

    require("vscode-workspace.picker").select(labels, {
        prompt    = "Workspaces:",
        on_submit = function(choice)
            if not choice then return end
            for i, label in ipairs(labels) do
                if label == choice then
                    local entry  = recent_wss[i]
                    local new_ws = workspace.parse(entry.path)
                    if not new_ws then
                        vim.notify("[CW] Failed to load workspace: " .. entry.path,
                            vim.log.levels.ERROR)
                        return
                    end
                    -- Change cwd to the workspace directory
                    vim.cmd("cd " .. vim.fn.fnameescape(new_ws.ws_dir))
                    M.close()
                    M.open({ ws = new_ws })
                    return
                end
            end
        end,
    })
end

return M
