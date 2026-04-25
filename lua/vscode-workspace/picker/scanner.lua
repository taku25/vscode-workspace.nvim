-- lua/vscode-workspace/picker/scanner.lua
-- File scanner with three tiers:
--   1. fd / fdfind  – fastest, native .gitignore support
--   2. rg --files   – also very fast, native .gitignore support
--   3. Pure-Lua BFS – fallback when neither tool is available (no gitignore)
--
-- config.scanner.files → controls file enumeration (CW files / add_favorites)
-- config.scanner.grep  → controls grep command passed to picker backends (CW grep)

local M = {}

local HARD_SKIP = { [".git"] = true, [".vs"] = true, ["node_modules"] = true }

-- ── Default argument sets ─────────────────────────────────────────────────────

local DEFAULT_FILES_ARGS = {
    fd     = { "--type", "f", "--hidden", "--follow", "--color", "never", "--absolute-path" },
    fdfind = { "--type", "f", "--hidden", "--follow", "--color", "never", "--absolute-path" },
    rg     = { "--files", "--hidden", "--follow", "--color", "never", "--glob", "!.git" },
}

-- Grep args: these are EXTRA flags appended to the picker's base command.
-- Do NOT include output-format flags (--column, --line-number, --no-heading, --color)
-- because telescope/fzf-lua already set those.
local DEFAULT_GREP_ARGS = {
    rg   = { "--hidden", "--follow", "--smart-case" },
    grep = { "-rn" },
}

-- ── Config-aware tool resolution ──────────────────────────────────────────────

local _resolved_files = nil
local _resolved_grep  = nil

local function resolve_files()
    if _resolved_files ~= nil then return _resolved_files end

    local conf = require("vscode-workspace.config").get()
    local sc   = (conf.scanner and conf.scanner.files) or {}

    if sc.cmd == false then
        _resolved_files = { cmd = false, args = {} }
        return _resolved_files
    end

    local function try(cmd)
        if cmd and vim.fn.executable(cmd) == 1 then
            -- Use full path for jobstart (important on Windows where PATH may differ)
            local full = vim.fn.exepath(cmd)
            local resolved_cmd = (full and full ~= "") and full or cmd
            local base = cmd:match("([^/\\]+)$") or cmd
            -- Strip .exe suffix for arg lookup
            base = base:gsub("%.exe$", "")
            local args = sc.args or DEFAULT_FILES_ARGS[base] or DEFAULT_FILES_ARGS["fd"]
            _resolved_files = { cmd = resolved_cmd, args = vim.deepcopy(args) }
            return true
        end
    end

    if sc.cmd then
        if not try(sc.cmd) then
            vim.notify("[CW] scanner.files.cmd '" .. sc.cmd .. "' not executable – falling back to Lua",
                vim.log.levels.WARN)
            _resolved_files = { cmd = false, args = {} }
        end
    else
        if not try("fd") then
            if not try("fdfind") then
                try("rg")
            end
        end
        if not _resolved_files then
            _resolved_files = { cmd = false, args = {} }
        end
    end

    return _resolved_files
end

--- Resolve the grep command + args from config.scanner.grep.
--- Returns { cmd: string, args: string[], is_rg: boolean }
--- `is_rg` hints backends whether to use rg-specific options.
local function resolve_grep()
    if _resolved_grep ~= nil then return _resolved_grep end

    local conf = require("vscode-workspace.config").get()
    local sc   = (conf.scanner and conf.scanner.grep) or {}

    if sc.cmd == false then
        -- Explicitly disabled – backends will use their own default grep
        _resolved_grep = { cmd = false, args = {}, is_rg = false }
        return _resolved_grep
    end

    local function try(cmd)
        if cmd and vim.fn.executable(cmd) == 1 then
            local full = vim.fn.exepath(cmd)
            local resolved_cmd = (full and full ~= "") and full or cmd
            local base = cmd:match("([^/\\]+)$") or cmd
            base = base:gsub("%.exe$", "")
            local args = sc.args or DEFAULT_GREP_ARGS[base] or DEFAULT_GREP_ARGS["grep"]
            _resolved_grep = {
                cmd   = resolved_cmd,
                args  = vim.deepcopy(args),
                is_rg = (base == "rg"),
            }
            return true
        end
    end

    if sc.cmd then
        if not try(sc.cmd) then
            vim.notify("[CW] scanner.grep.cmd '" .. sc.cmd .. "' not executable – using picker default",
                vim.log.levels.WARN)
            _resolved_grep = { cmd = false, args = {}, is_rg = false }
        end
    else
        -- Auto-detect: rg is the standard; fall back to system grep
        if not try("rg") then
            try("grep")
        end
        if not _resolved_grep then
            _resolved_grep = { cmd = false, args = {}, is_rg = false }
        end
    end

    return _resolved_grep
end

--- Reset cached tool resolution. Call after config.setup() so that changes to
--- scanner.files.cmd / scanner.grep.cmd are picked up on the next use.
function M.reset()
    _resolved_files = nil
    _resolved_grep  = nil
end

-- ── Public accessors ─────────────────────────────────────────────────────────

--- Which files-scan backend will be used.
---@return string  "fd" | "fdfind" | "rg" | "lua"
function M.backend()
    local r = resolve_files()
    if not r.cmd then return "lua" end
    return r.cmd:match("([^/\\]+)$") or r.cmd
end

--- Build a jobstart-safe argv for the given resolved tool on Windows.
--- On Windows, .bat shims (e.g. scoop) cannot be launched directly by
--- vim.fn.jobstart (which uses CreateProcess without a shell).  Wrapping in
--- "cmd.exe /C" lets cmd.exe resolve the .bat through PATHEXT.
---@param r          { cmd:string, args:string[] }
---@param extra_args string[]   directories or other trailing args
---@return string[]
local function build_argv(r, extra_args)
    local base
    if vim.fn.has("win32") == 1 then
        local full = vim.fn.exepath(r.cmd)
        if full ~= "" and full:lower():match("%.bat$") then
            -- .bat shim – must go through cmd.exe
            base = { "cmd.exe", "/C", r.cmd }
        elseif full ~= "" then
            base = { full }
        else
            base = { r.cmd }
        end
    else
        base = { r.cmd }
    end
    vim.list_extend(base, r.args)
    vim.list_extend(base, extra_args)
    return base
end

--- Returns the full command array ready for jobstart / new_oneshot_job.
--- Returns nil when no external tool is available (use M.collect fallback).
---@param dirs string[]
---@return string[]|nil
function M.files_cmd(dirs)
    local r = resolve_files()
    if not r.cmd then return nil end
    return build_argv(r, dirs)
end

--- Resolved grep config for picker backends.
---@return { cmd: string|false, args: string[], is_rg: boolean }
function M.grep_config()
    return resolve_grep()
end

-- ── Job-based async scan (fd / rg) ───────────────────────────────────────────

local function scan_with_job(r, dirs, on_chunk, on_done)
    local argv = build_argv(r, dirs)

    local stderr_buf = {}
    local job_id = vim.fn.jobstart(argv, {
        stdout_buffered = false,
        on_stdout = function(_, data)
            if not data then return end
            local chunk = {}
            for _, line in ipairs(data) do
                local l = line:gsub("\\", "/"):match("^%s*(.-)%s*$")
                if l and l ~= "" then table.insert(chunk, l) end
            end
            if #chunk > 0 then
                vim.schedule(function() on_chunk(chunk) end)
            end
        end,
        on_stderr = function(_, data)
            if data then
                for _, line in ipairs(data) do
                    if line and line ~= "" then table.insert(stderr_buf, line) end
                end
            end
        end,
        on_exit = function(_, code)
            vim.schedule(function()
                if code ~= 0 and #stderr_buf > 0 then
                    vim.notify("[CW scanner] error (exit " .. code .. "): "
                        .. table.concat(stderr_buf, " | "), vim.log.levels.ERROR)
                elseif code ~= 0 then
                    vim.notify("[CW scanner] job exited with code " .. code
                        .. "  cmd: " .. argv[1], vim.log.levels.WARN)
                end
                if on_done then on_done() end
            end)
        end,
    })
    if job_id <= 0 then
        vim.notify("[CW scanner] failed to start job (id=" .. job_id
            .. ") for: " .. table.concat(argv, " "):sub(1, 120), vim.log.levels.ERROR)
        if on_done then vim.schedule(on_done) end
    end
end

-- ── Pure-Lua BFS fallback ─────────────────────────────────────────────────────

local function scan_lua_recursive(dir, is_excluded, results, depth, max_depth)
    if depth > max_depth then return end
    local handle = vim.loop.fs_scandir(dir)
    if not handle then return end
    while true do
        local name, ftype = vim.loop.fs_scandir_next(handle)
        if not name then break end
        if name:sub(1, 1) == "." then goto continue end
        if HARD_SKIP[name] then goto continue end
        local full = dir .. "/" .. name
        if is_excluded and is_excluded(name, full) then goto continue end
        if ftype == "directory" then
            scan_lua_recursive(full, is_excluded, results, depth + 1, max_depth)
        elseif ftype == "file" then
            table.insert(results, full)
        end
        ::continue::
    end
end

local function scan_lua_async(dirs, is_excluded, on_chunk, on_done)
    local queue = {}
    for _, d in ipairs(dirs) do table.insert(queue, d) end

    local function step()
        if #queue == 0 then
            if on_done then on_done() end
            return
        end
        local dir = table.remove(queue, 1)
        local handle = vim.loop.fs_scandir(dir)
        local chunk = {}
        if handle then
            while true do
                local name, ftype = vim.loop.fs_scandir_next(handle)
                if not name then break end
                if name:sub(1, 1) == "." then goto continue end
                if HARD_SKIP[name] then goto continue end
                local full = dir .. "/" .. name
                if is_excluded and is_excluded(name, full) then goto continue end
                if ftype == "directory" then
                    table.insert(queue, full)
                elseif ftype == "file" then
                    table.insert(chunk, full)
                end
                ::continue::
            end
        end
        if #chunk > 0 then on_chunk(chunk) end
        vim.schedule(step)
    end

    vim.schedule(step)
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- Async scan. Uses the tool configured in scanner.files (fd/rg/lua).
---@param dirs        string[]
---@param is_excluded fun(name:string, full:string):boolean|nil  (Lua fallback only)
---@param on_chunk    fun(chunk: string[])
---@param on_done     fun()|nil
function M.scan_async(dirs, is_excluded, on_chunk, on_done)
    if #dirs == 0 then
        if on_done then on_done() end
        return
    end
    local r = resolve_files()
    if r.cmd then
        scan_with_job(r, dirs, on_chunk, on_done)
    else
        vim.notify("[CW] fd/rg not found – using pure-Lua scanner (.gitignore not respected)",
            vim.log.levels.WARN)
        scan_lua_async(dirs, is_excluded, on_chunk, on_done)
    end
end

--- Synchronous collect – used only by the native vim.ui.select fallback.
---@param dirs       string[]
---@param is_excluded fun(name:string, full:string):boolean|nil
---@return string[]
function M.collect(dirs, is_excluded)
    local results = {}
    for _, dir in ipairs(dirs) do
        scan_lua_recursive(dir, is_excluded, results, 0, 20)
    end
    return results
end

return M
