-- lua/vscode-workspace/picker/init.lua
-- Public API: find_files / live_grep / select
-- Routing priority:
--   1. conf.picker_function  (user-supplied custom function, receives spec)
--   2. conf.picker           (explicit backend name)
--   3. auto-detect           (telescope > fzf-lua > snacks)
--   4. native fallback

local M = {}

-- ── Backend resolution ────────────────────────────────────────────────────────

local BACKENDS = {
    telescope = "vscode-workspace.picker.telescope",
    ["fzf-lua"] = "vscode-workspace.picker.fzf_lua",
    snacks    = "vscode-workspace.picker.snacks",
    native    = "vscode-workspace.picker.native",
}

local function has(mod) return pcall(require, mod) end

local function resolve_backend()
    local conf = require("vscode-workspace.config").get()
    if conf.picker then return conf.picker end
    if has("telescope") then return "telescope" end
    if has("fzf-lua")   then return "fzf-lua"   end
    if has("snacks")    then return "snacks"     end
    return "native"
end

-- ── Dispatch ─────────────────────────────────────────────────────────────────

---@param spec { type: string, prompt: string, dirs?: string[], items?: string[], is_excluded?: fun(), on_submit?: fun() }
local function dispatch(spec)
    local conf = require("vscode-workspace.config").get()

    -- 1. User-supplied custom function takes full control
    if type(conf.picker_function) == "function" then
        conf.picker_function(spec)
        return
    end

    -- 2. Named or auto-detected backend
    local backend_name = resolve_backend()
    local mod_path     = BACKENDS[backend_name]
    if not mod_path then
        vim.notify("[CW] Unknown picker backend: " .. tostring(backend_name), vim.log.levels.ERROR)
        return
    end

    local ok, backend = pcall(require, mod_path)
    if not ok then
        vim.notify("[CW] Failed to load picker backend '" .. backend_name .. "': " .. backend, vim.log.levels.ERROR)
        return
    end

    local fn = backend[spec.type]
    if type(fn) ~= "function" then
        vim.notify("[CW] Backend '" .. backend_name .. "' has no handler for type=" .. spec.type, vim.log.levels.ERROR)
        return
    end

    fn(spec)
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- Open a file picker across the given directories.
---@param dirs  string[]
---@param opts? { prompt?: string, is_excluded?: fun(name:string, full:string):boolean, on_submit?: fun(path:string) }
function M.find_files(dirs, opts)
    opts = opts or {}
    if #dirs == 0 then
        vim.notify("[CW] No folders to search", vim.log.levels.WARN)
        return
    end
    dispatch({
        type        = "files",
        prompt      = opts.prompt or "CW Files",
        dirs        = dirs,
        is_excluded = opts.is_excluded,
        on_submit   = opts.on_submit,
    })
end

--- Open a live-grep picker across the given directories.
---@param dirs  string[]
---@param opts? { prompt?: string }
function M.live_grep(dirs, opts)
    opts = opts or {}
    if #dirs == 0 then
        vim.notify("[CW] No folders to search", vim.log.levels.WARN)
        return
    end
    dispatch({
        type   = "grep",
        prompt = opts.prompt or "CW Grep",
        dirs   = dirs,
    })
end

--- Show a static list of strings in the picker.
--- on_submit receives the selected string (or nil on cancel).
---@param items  string[]
---@param opts   { prompt?: string, on_submit: fun(choice: string|nil) }
function M.select(items, opts)
    opts = opts or {}
    dispatch({
        type      = "static",
        prompt    = opts.prompt or "Select",
        items     = items,
        on_submit = opts.on_submit or function() end,
    })
end

return M
