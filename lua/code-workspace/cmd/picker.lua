-- lua/CW/cmd/picker.lua
-- Collect files with a pure-Lua recursive scanner (vim.loop.fs_scandir).
-- No fd/rg dependency → no shell quoting / PATH issues on Windows.

local M = {}

-- ── Backend detection ────────────────────────────────────────────────────────

local function has(mod) return pcall(require, mod) end

local function get_backend()
    if has("telescope") then return "telescope" end
    if has("fzf-lua")   then return "fzf-lua" end
    if has("snacks")    then return "snacks" end
    return "native"
end

-- ── Recursive file scanner ────────────────────────────────────────────────────

local HARD_SKIP = { [".git"] = true, [".vs"] = true, ["node_modules"] = true }

--- Recursively collect files under `dir`.
---@param dir        string
---@param is_excluded fun(name:string, full:string):boolean|nil
---@param results    string[]   accumulator
---@param depth      integer
---@param max_depth  integer
local function scan_recursive(dir, is_excluded, results, depth, max_depth)
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
            scan_recursive(full, is_excluded, results, depth + 1, max_depth)
        elseif ftype == "file" then
            table.insert(results, full)
        end
        ::continue::
    end
end

--- Collect all files across multiple root directories (synchronous, pure Lua).
---@param folders    string[]
---@param is_excluded fun(name:string, full:string):boolean|nil
---@return string[]
local function collect_files(folders, is_excluded)
    local results = {}
    for _, dir in ipairs(folders) do
        scan_recursive(dir, is_excluded, results, 0, 20)
    end
    return results
end

-- ── File search ──────────────────────────────────────────────────────────────

---@param folders    string[]
---@param opts?      table  { prompt?, is_excluded? }
function M.find_files(folders, opts)
    opts = opts or {}
    if #folders == 0 then
        vim.notify("[CW] No folders to search", vim.log.levels.WARN)
        return
    end

    local title   = opts.prompt or "CW Files"
    local results = collect_files(folders, opts.is_excluded)

    if #results == 0 then
        vim.notify("[CW] No files found in workspace folders", vim.log.levels.WARN)
        return
    end

    local backend = get_backend()

    if backend == "telescope" then
        local pickers = require("telescope.pickers")
        local finders = require("telescope.finders")
        local conf_t  = require("telescope.config").values
        local devicons_ok, devicons = pcall(require, "nvim-web-devicons")
        local entry_display = require("telescope.pickers.entry_display")

        local displayer = entry_display.create({
            separator = " ",
            items = devicons_ok
                and { { width = 2 }, { remaining = true } }
                or  { { remaining = true } },
        })

        vim.schedule(function()
            pickers.new({ file_ignore_patterns = {} }, {
                prompt_title = title,
                finder = finders.new_table({
                    results     = results,
                    entry_maker = function(line)
                        local native = line:gsub("/", "\\")
                        local tail   = vim.fn.fnamemodify(line, ":t")
                        local icon, icon_hl = "", "Normal"
                        if devicons_ok then
                            local ext = tail:match("%.([^.]+)$") or ""
                            icon, icon_hl = devicons.get_icon(tail, ext, { default = true })
                            icon = icon or ""
                            icon_hl = icon_hl or "Normal"
                        end
                        return {
                            value    = line,
                            ordinal  = line,
                            filename = native,
                            path     = native,
                            icon     = icon,
                            icon_hl  = icon_hl,
                            display  = function(entry)
                                if devicons_ok then
                                    return displayer({
                                        { entry.icon, entry.icon_hl },
                                        tail,
                                    })
                                end
                                return displayer({ tail })
                            end,
                        }
                    end,
                }),
                sorter    = conf_t.generic_sorter({}),
                previewer = conf_t.file_previewer({}),
            }):find()
        end)

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
end

-- ── Live grep ────────────────────────────────────────────────────────────────

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

    if backend == "telescope" then
        require("telescope.builtin").live_grep({
            prompt_title         = title,
            search_dirs          = folders,
            file_ignore_patterns = {},
            additional_args      = { "--hidden", "--follow" },
        })

    elseif backend == "fzf-lua" then
        require("fzf-lua").live_grep(vim.tbl_extend("force", {
            prompt  = title .. "> ",
            rg_opts = "--hidden --follow --column --line-number --no-heading "
                   .. "--color=always -g '!.git' -- "
                   .. table.concat(vim.tbl_map(vim.fn.shellescape, folders), " "),
        }, opts.fzf_lua or {}))

    elseif backend == "snacks" then
        require("snacks").picker.grep(vim.tbl_extend("force", {
            title = title, dirs = folders,
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
