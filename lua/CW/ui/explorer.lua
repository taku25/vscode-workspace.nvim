-- lua/CW/ui/explorer.lua
-- Single-pane explorer: ★ Favorites + workspace folder tree in one view.
-- Winbar shows the workspace name (no tab switching needed).

local Split     = require("nui.split")
local ViewTree  = require("CW.ui.view.tree")
local workspace = require("CW.workspace")

local M = {}

-- ── State ────────────────────────────────────────────────────────────────────

local state = {
    split = nil,  -- nui.split instance
    win   = nil,  -- window id
    ws    = nil,  -- current workspace
    view  = nil,  -- ViewTree instance
}

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function get_conf()
    return require("CW.config").get()
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
                   or node.type == "fav_folder" or node._has_children
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
        -- Try cursor node first; fall back to alternate buffer
        local node = state.view.tree and state.view.tree:get_node()
        local file_path = (node and node.path and node.type == "file")
                          and node.path or vim.fn.expand("#:p")
        if file_path and file_path ~= "" then
            local added = state.view.toggle_favorite(file_path)
            vim.notify(added and "Added to Favorites" or "Removed from Favorites",
                vim.log.levels.INFO)
        end
    end)

    map(km.find_files, function()
        require("CW.cmd.work_files").execute(state.ws)
    end)

    map(km.live_grep, function()
        require("CW.cmd.work_grep").execute(state.ws)
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

        vim.api.nvim_create_autocmd("WinClosed", {
            pattern  = tostring(state.win),
            once     = true,
            callback = function()
                if state.view then state.view.save_state() end
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
            local added = state.view.toggle_favorite(file_path)
            vim.notify(added and "Added to Favorites" or "Removed from Favorites",
                vim.log.levels.INFO)
            return
        end
        -- Panel not open: update store directly
        local s     = require("CW.store")
        local p     = require("CW.path")
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
        local s    = require("CW.store")
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

return M
