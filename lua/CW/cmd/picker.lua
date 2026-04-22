-- lua/CW/cmd/picker.lua
-- Run fd/rg ourselves and feed results directly to the picker backend.
-- Avoids all search_dirs / path-with-spaces issues on Windows.

local M = {}

-- ── Backend detection ────────────────────────────────────────────────────────

local function has(mod) return pcall(require, mod) end

local function get_backend()
    if has("telescope") then return "telescope" end
    if has("fzf-lua")   then return "fzf-lua" end
    if has("snacks")    then return "snacks" end
    return "native"
end

-- ── fd runner ────────────────────────────────────────────────────────────────

--- Run `fd --type f` across multiple directories.
--- Uses vim.fn.systemlist() (synchronous) to avoid jobstart/Windows async issues.
---@param folders string[]
---@param on_results fun(results: string[])
local function run_fd(folders, on_results)
    if #folders == 0 then
        vim.schedule(function() on_results({}) end)
        return
    end

    local fd_exe = vim.fn.exepath("fd")
    if fd_exe == "" then
        local winget = vim.fn.expand("$LOCALAPPDATA") .. "\\Microsoft\\WinGet\\Links\\fd.exe"
        if vim.fn.filereadable(winget) == 1 then
            fd_exe = winget
        else
            vim.notify("[CW] fd not found in PATH. Install fd-find.", vim.log.levels.ERROR)
            on_results({})
            return
        end
    end

    local all = {}
    for _, dir in ipairs(folders) do
        local native_dir = dir:gsub("/", "\\")
        -- fd syntax: fd [PATTERN] [PATH]  -- pattern "" matches everything
        -- Using --search-path avoids positional ambiguity with Windows drive paths
        local cmd = { fd_exe, "--type", "f", "--hidden", "--follow",
                      "--exclude", ".git",
                      "--search-path", native_dir,
                      "." }
        local lines = vim.fn.systemlist(cmd)
        for _, line in ipairs(lines) do
            if line ~= "" then table.insert(all, line) end
        end
    end

    vim.notify("[CW debug] fd total results: " .. #all, vim.log.levels.INFO)
    on_results(all)
end

-- ── File search ──────────────────────────────────────────────────────────────

--- Open a file picker with results collected by fd.
---@param folders string[]
---@param opts?   table  { prompt? }
function M.find_files(folders, opts)
    opts = opts or {}
    if #folders == 0 then
        vim.notify("[CW] No folders to search", vim.log.levels.WARN)
        return
    end
    local title   = opts.prompt or "CW Files"
    local backend = get_backend()

    run_fd(folders, function(results)
        if #results == 0 then
            vim.notify("[CW] No files found in workspace folders", vim.log.levels.WARN)
            return
        end

        if backend == "telescope" then
            local pickers    = require("telescope.pickers")
            local finders    = require("telescope.finders")
            local conf_t     = require("telescope.config").values
            local make_entry = require("telescope.make_entry")

            pickers.new({}, {
                prompt_title = title,
                finder = finders.new_table({
                    results     = results,
                    entry_maker = make_entry.gen_from_file({}),
                }),
                sorter    = conf_t.file_sorter({}),
                previewer = conf_t.file_previewer({}),
            }):find()

        elseif backend == "fzf-lua" then
            require("fzf-lua").fzf_exec(results, {
                prompt    = title .. "> ",
                previewer = "builtin",
                actions   = require("fzf-lua").defaults.actions.files,
            })

        elseif backend == "snacks" then
            require("snacks").picker.pick({
                title  = title,
                items  = vim.tbl_map(function(p) return { text = p, file = p } end, results),
                format = "file",
            })

        else
            vim.ui.select(results, { prompt = title }, function(choice)
                if choice then vim.cmd("edit " .. vim.fn.fnameescape(choice)) end
            end)
        end
    end)
end

-- ── Live grep ────────────────────────────────────────────────────────────────

--- Open a live grep across multiple root folders.
--- Paths are passed as explicit positional args to rg (jobstart list, no shell quoting).
---@param folders string[]
---@param opts?   table  { prompt? }
function M.live_grep(folders, opts)
    opts = opts or {}
    if #folders == 0 then
        vim.notify("[CW] No folders to search", vim.log.levels.WARN)
        return
    end
    local title   = opts.prompt or "CW Grep"
    local backend = get_backend()

    -- Build rg base args; directories appended as positional args (safe for spaces).
    local rg_base = {
        "rg", "--color=never", "--no-heading", "--with-filename",
        "--line-number", "--column", "--smart-case",
        "--hidden", "--follow", "-g", "!.git", "--",
    }
    local rg_with_dirs = vim.list_extend(vim.deepcopy(rg_base), folders)

    if backend == "telescope" then
        require("telescope.builtin").live_grep(vim.tbl_extend("force", {
            prompt_title       = title,
            vimgrep_arguments  = rg_with_dirs,
        }, opts.telescope or {}))

    elseif backend == "fzf-lua" then
        -- fzf-lua: pass dirs as separate rg args
        local rg_opts_str = "--hidden --follow --column --line-number --no-heading "
                         .. "--color=always -g '!.git' -- "
                         .. table.concat(vim.tbl_map(vim.fn.shellescape, folders), " ")
        require("fzf-lua").live_grep(vim.tbl_extend("force", {
            prompt   = title .. "> ",
            rg_opts  = rg_opts_str,
        }, opts.fzf_lua or {}))

    elseif backend == "snacks" then
        require("snacks").picker.grep(vim.tbl_extend("force", {
            title = title,
            dirs  = folders,
        }, opts.snacks or {}))

    else
        vim.ui.input({ prompt = "Grep pattern: " }, function(pattern)
            if not pattern or pattern == "" then return end
            local cmd = "grep -rn " .. vim.fn.shellescape(pattern)
                     .. " " .. table.concat(vim.tbl_map(vim.fn.shellescape, folders), " ")
            vim.fn.setqflist({}, "r", { title = "CW Grep",
                lines = vim.fn.systemlist(cmd) })
            vim.cmd("copen")
        end)
    end
end

return M
