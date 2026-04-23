-- lua/vscode-workspace/picker/fzf_lua.lua
-- fzf-lua backend for find_files / live_grep / static select.

local scanner = require("vscode-workspace.picker.scanner")

local M = {}

function M.files(spec)
    local results = scanner.collect(spec.dirs, spec.is_excluded)
    if #results == 0 then
        vim.notify("[CW] No files found in workspace folders", vim.log.levels.WARN)
        return
    end
    local fzf = require("fzf-lua")
    require("fzf-lua").fzf_exec(results, {
        prompt    = spec.prompt .. "> ",
        previewer = "builtin",
        actions   = spec.on_submit and {
            ["default"] = function(selected)
                if selected and selected[1] then
                    spec.on_submit(selected[1])
                end
            end,
        } or fzf.defaults.actions.files,
    })
end

function M.grep(spec)
    require("fzf-lua").live_grep({
        prompt  = spec.prompt .. "> ",
        rg_opts = "--hidden --follow --column --line-number --no-heading "
               .. "--color=always -g '!.git' -- "
               .. table.concat(vim.tbl_map(vim.fn.shellescape, spec.dirs), " "),
    })
end

function M.static(spec)
    require("fzf-lua").fzf_exec(spec.items, {
        prompt  = spec.prompt .. "> ",
        actions = {
            ["default"] = function(selected)
                spec.on_submit(selected and selected[1] or nil)
            end,
        },
    })
end

return M
