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

--- Run `fd --type f` across multiple directories asynchronously.
--- Each directory is a separate jobstart so spaces in paths are safe.
---@param folders string[]
---@param on_results fun(results: string[])
local function run_fd(folders, on_results)
    if #folders == 0 then
        vim.schedule(function() on_results({}) end)
        return
    end
    local all = {}
    local pending = #folders
    for _, dir in ipairs(folders) do
        vim.fn.jobstart(
            { "fd", "--type", "f", "--hidden", "--follow", "--exclude", ".git", "--", dir },
            {
                stdout_buffered = true,
                on_stdout = function(_, data)
                    for _, line in ipairs(data or {}) do
                        if line ~= "" then table.insert(all, line) end
                    end
                end,
                on_exit = function()
                    pending = pending - 1
                    if pending == 0 then
                        vim.schedule(function() on_results(all) end)
                    end
                end,
            }
        )
    end
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

local M = {}

-- ── Backend detection ────────────────────────────────────────────────────────

local function has(mod) return pcall(require, mod) end

local function get_backend()
    if has("telescope") then return "telescope" end
    if has("fzf-lua")   then return "fzf-lua" end
    if has("snacks")    then return "snacks" end
    return "native"
end

--- Convert paths to OS-native format for external tools.
--- On Windows, telescope/fd/rg work more reliably with backslash absolute paths.
local function to_native(paths)
    local is_win = vim.fn.has("win32") == 1
    if not is_win then return paths end
    return vim.tbl_map(function(p)
        return vim.fn.fnamemodify(p, ":p"):gsub("/", "\\"):gsub("\\$", "")
    end, paths)
end

-- ── File search ──────────────────────────────────────────────────────────────

--- Open a file picker across multiple root folders.
---@param folders string[]  Absolute paths to search in
---@param opts? table       { prompt?, initial_query? }
function M.find_files(folders, opts)
    opts = opts or {}
    if #folders == 0 then
        vim.notify("[CW] No folders to search", vim.log.levels.WARN)
        return
    end

    local backend = get_backend()
    local native_folders = to_native(folders)

    if backend == "telescope" then
        -- Build fd command explicitly so paths with spaces are handled correctly.
        -- Passing directories as separate positional args avoids shell quoting issues.
        local cmd = { "fd", "--type", "f", "--hidden", "--follow",
                      "--exclude", ".git", "--" }
        for _, dir in ipairs(native_folders) do
            table.insert(cmd, dir)
        end
        require("telescope.builtin").find_files(vim.tbl_extend("force", {
            prompt_title = opts.prompt or "CW Files",
            find_command = cmd,
        }, opts.telescope or {}))

    elseif backend == "fzf-lua" then
        require("fzf-lua").files(vim.tbl_extend("force", {
            prompt  = (opts.prompt or "CW Files") .. "> ",
            cmd     = "fd --type f --hidden --follow --exclude .git . " ..
                      table.concat(vim.tbl_map(function(f)
                          return vim.fn.shellescape(f)
                      end, native_folders), " "),
        }, opts.fzf_lua or {}))

    elseif backend == "snacks" then
        require("snacks").picker.files(vim.tbl_extend("force", {
            title = opts.prompt or "CW Files",
            dirs  = folders,
        }, opts.snacks or {}))

    else
        -- vim.ui.select fallback: list folders and let user pick one, then :e
        vim.ui.select(folders, {
            prompt = opts.prompt or "Pick folder",
        }, function(folder)
            if folder then
                vim.cmd("cd " .. vim.fn.fnameescape(folder))
                vim.ui.input({ prompt = "Filename: " }, function(input)
                    if input and input ~= "" then
                        vim.cmd("edit " .. vim.fn.fnameescape(folder .. "/" .. input))
                    end
                end)
            end
        end)
    end
end

-- ── Live grep ────────────────────────────────────────────────────────────────

--- Open a live grep across multiple root folders.
---@param folders string[]
---@param opts? table  { prompt?, initial_query? }
function M.live_grep(folders, opts)
    opts = opts or {}
    if #folders == 0 then
        vim.notify("[CW] No folders to search", vim.log.levels.WARN)
        return
    end

    local backend = get_backend()
    local native_folders = to_native(folders)

    if backend == "telescope" then
        require("telescope.builtin").live_grep(vim.tbl_extend("force", {
            search_dirs  = native_folders,
            prompt_title = opts.prompt or "CW Grep",
        }, opts.telescope or {}))

    elseif backend == "fzf-lua" then
        require("fzf-lua").live_grep(vim.tbl_extend("force", {
            prompt   = (opts.prompt or "CW Grep") .. "> ",
            rg_opts  = "--hidden --follow --column --line-number --no-heading --color=always -g '!.git'",
            cwd      = native_folders[1],
        }, opts.fzf_lua or {}))

    elseif backend == "snacks" then
        require("snacks").picker.grep(vim.tbl_extend("force", {
            title = opts.prompt or "CW Grep",
            dirs  = folders,
        }, opts.snacks or {}))

    else
        -- vim.ui.select fallback: ask for pattern, run grep, quickfix
        vim.ui.input({ prompt = "Grep pattern: " }, function(pattern)
            if not pattern or pattern == "" then return end
            local cmd = "grep -rn " .. vim.fn.shellescape(pattern)
                     .. " " .. table.concat(vim.tbl_map(vim.fn.shellescape, folders), " ")
            vim.fn.setqflist({}, "r", { title = "CW Grep", lines = vim.fn.systemlist(cmd) })
            vim.cmd("copen")
        end)
    end
end

return M
