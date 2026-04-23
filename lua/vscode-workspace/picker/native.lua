-- lua/vscode-workspace/picker/native.lua
-- Native fallback: vim.ui.select / vim.ui.input + quickfix for grep.

local scanner = require("vscode-workspace.picker.scanner")

local M = {}

function M.files(spec)
    local results = scanner.collect(spec.dirs, spec.is_excluded)
    if #results == 0 then
        vim.notify("[CW] No files found in workspace folders", vim.log.levels.WARN)
        return
    end
    vim.ui.select(results, { prompt = spec.prompt }, function(choice)
        if not choice then return end
        if spec.on_submit then
            spec.on_submit(choice)
        else
            vim.cmd("edit " .. vim.fn.fnameescape(choice))
        end
    end)
end

function M.grep(spec)
    vim.ui.input({ prompt = "Grep pattern: " }, function(pattern)
        if not pattern or pattern == "" then return end
        local cmd = "grep -rn " .. vim.fn.shellescape(pattern)
                 .. " " .. table.concat(vim.tbl_map(vim.fn.shellescape, spec.dirs), " ")
        vim.fn.setqflist({}, "r", { title = spec.prompt, lines = vim.fn.systemlist(cmd) })
        vim.cmd("copen")
    end)
end

function M.static(spec)
    vim.ui.select(spec.items, { prompt = spec.prompt }, spec.on_submit)
end

return M
