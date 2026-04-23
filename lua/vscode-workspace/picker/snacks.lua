-- lua/vscode-workspace/picker/snacks.lua
-- snacks.nvim backend for find_files / live_grep / static select.

local scanner = require("vscode-workspace.picker.scanner")

local M = {}

function M.files(spec)
    local results = scanner.collect(spec.dirs, spec.is_excluded)
    if #results == 0 then
        vim.notify("[CW] No files found in workspace folders", vim.log.levels.WARN)
        return
    end
    local picker_opts = {
        title  = spec.prompt,
        items  = vim.tbl_map(function(p) return { text = p, file = p } end, results),
        format = "file",
    }
    if spec.on_submit then
        picker_opts.confirm = function(picker, item)
            picker:close()
            if item then spec.on_submit(item.file or item.text) end
        end
    end
    require("snacks").picker.pick(picker_opts)
end

function M.grep(spec)
    require("snacks").picker.grep({ title = spec.prompt, dirs = spec.dirs })
end

function M.static(spec)
    require("snacks").picker.pick({
        title   = spec.prompt,
        items   = vim.tbl_map(function(s) return { text = s } end, spec.items),
        format  = function(item) return { { item.text } } end,
        confirm = function(picker, item)
            picker:close()
            spec.on_submit(item and item.text or nil)
        end,
    })
end

return M
