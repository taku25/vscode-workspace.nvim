-- lua/vscode-workspace/picker/telescope.lua
-- Telescope backend for find_files / live_grep / static select.

local scanner = require("vscode-workspace.picker.scanner")

local M = {}

function M.files(spec)
    local results = scanner.collect(spec.dirs, spec.is_excluded)
    if #results == 0 then
        vim.notify("[CW] No files found in workspace folders", vim.log.levels.WARN)
        return
    end

    local pickers       = require("telescope.pickers")
    local finders       = require("telescope.finders")
    local conf_t        = require("telescope.config").values
    local actions       = require("telescope.actions")
    local action_state  = require("telescope.actions.state")
    local entry_display = require("telescope.pickers.entry_display")
    local devicons_ok, devicons = pcall(require, "nvim-web-devicons")

    local displayer = entry_display.create({
        separator = " ",
        items = devicons_ok and { { width = 2 }, { remaining = true } }
                             or { { remaining = true } },
    })

    vim.schedule(function()
        pickers.new({ file_ignore_patterns = {} }, {
            prompt_title = spec.prompt,
            finder = finders.new_table({
                results     = results,
                entry_maker = function(line)
                    local native = line:gsub("/", "\\")
                    local tail   = vim.fn.fnamemodify(line, ":t")
                    local icon, icon_hl = "", "Normal"
                    if devicons_ok then
                        local ext = tail:match("%.([^.]+)$") or ""
                        icon     = devicons.get_icon(tail, ext, { default = true }) or ""
                        icon_hl  = "Normal"
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
                                return displayer({ { entry.icon, entry.icon_hl }, tail })
                            end
                            return displayer({ tail })
                        end,
                    }
                end,
            }),
            sorter    = conf_t.generic_sorter({}),
            previewer = conf_t.file_previewer({}),
            attach_mappings = spec.on_submit and function(prompt_bufnr)
                actions.select_default:replace(function()
                    actions.close(prompt_bufnr)
                    local sel = action_state.get_selected_entry()
                    if sel then spec.on_submit(sel.path or sel.value) end
                end)
                return true
            end or nil,
        }):find()
    end)
end

function M.grep(spec)
    require("telescope.builtin").live_grep({
        prompt_title         = spec.prompt,
        search_dirs          = spec.dirs,
        file_ignore_patterns = {},
        additional_args      = { "--hidden", "--follow" },
    })
end

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
