-- lua/vscode-workspace/picker/telescope.lua
-- Telescope backend for find_files / live_grep / static select.

local path   = require("vscode-workspace.path")
local filter = require("vscode-workspace.filter")

local M = {}

-- ── entry maker ───────────────────────────────────────────────────────────────

--- Custom entry_maker for find_files that shows workspace-relative paths.
--- entry.value / entry.path stay absolute so the previewer and on_submit work.
---@param dirs string[]
---@return function
local function make_relative_entry_maker(dirs)
    local rel             = path.workspace_path_display(dirs)
    local devicons_ok, devicons = pcall(require, "nvim-web-devicons")

    return function(line)
        if not line or line == "" then return nil end
        local display_path = rel({}, line)
        local entry = {
            value    = line,
            ordinal  = display_path,
            path     = line,
            filename = line,
        }
        if devicons_ok then
            local ext      = vim.fn.fnamemodify(line, ":e")
            local icon, hl = devicons.get_icon(line, ext, { default = true })
            if icon then
                entry.display = function(_)
                    return icon .. " " .. display_path, { { { 0, #icon }, hl } }
                end
            else
                entry.display = display_path
            end
        else
            entry.display = display_path
        end
        return entry
    end
end

-- ── files ─────────────────────────────────────────────────────────────────────

function M.files(spec)
    local actions      = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    local attach = spec.on_submit and function(prompt_bufnr)
        actions.select_default:replace(function()
            actions.close(prompt_bufnr)
            local sel = action_state.get_selected_entry()
            if sel then
                local fpath = sel.path or sel.filename or sel.value
                spec.on_submit(fpath)
            end
        end)
        return true
    end or nil

    require("telescope.builtin").find_files({
        prompt_title         = spec.prompt,
        search_dirs          = spec.dirs,
        entry_maker          = make_relative_entry_maker(spec.dirs),
        attach_mappings      = attach,
        file_ignore_patterns = filter.to_ignore_patterns(spec.exclude_map),
    })
end

-- ── files_static (e.g. favorites: pre-resolved file paths) ───────────────────

function M.files_static(spec)
    local finders      = require("telescope.finders")
    local pickers      = require("telescope.pickers")
    local conf_t       = require("telescope.config").values
    local actions      = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    local attach = function(prompt_bufnr)
        actions.select_default:replace(function()
            actions.close(prompt_bufnr)
            local sel = action_state.get_selected_entry()
            if sel then
                local fpath = sel.path or sel.filename or sel.value
                if spec.on_submit then
                    spec.on_submit(fpath)
                else
                    vim.cmd("edit " .. vim.fn.fnameescape(fpath))
                end
            end
        end)
        return true
    end

    vim.schedule(function()
        pickers.new({
            prompt_title         = spec.prompt,
            finder               = finders.new_table({
                results     = spec.items,
                entry_maker = make_relative_entry_maker(spec.dirs or {}),
            }),
            sorter               = conf_t.generic_sorter({}),
            previewer            = conf_t.file_previewer({}),
            -- Override global file_ignore_patterns: we are showing a curated list
            -- of pre-resolved paths (e.g. favorites), so no filtering should apply.
            file_ignore_patterns = {},
            attach_mappings      = attach,
        }):find()
    end)
end

function M.grep(spec)
    require("telescope.builtin").live_grep({
        prompt_title = spec.prompt,
        search_dirs  = spec.dirs,
    })
end

-- ── static select ─────────────────────────────────────────────────────────────

function M.static(spec)
    local pickers      = require("telescope.pickers")
    local finders      = require("telescope.finders")
    local conf_t       = require("telescope.config").values
    local actions      = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    vim.schedule(function()
        pickers.new({}, {
            prompt_title = spec.prompt,
            finder       = finders.new_table({ results = spec.items }),
            sorter       = conf_t.generic_sorter({}),
            attach_mappings = function(prompt_bufnr)
                actions.select_default:replace(function()
                    actions.close(prompt_bufnr)
                    local sel = action_state.get_selected_entry()
                    spec.on_submit(sel and sel[1] or nil)
                end)
                return true
            end,
        }):find()
    end)
end

return M
