if vim.g.loaded_cw == 1 then return end
vim.g.loaded_cw = 1

local subcommands = {
    open    = { desc = "Open the explorer",         handler = function() require("vscode-workspace.api").explorer_open() end },
    close   = { desc = "Close the explorer",        handler = function() require("vscode-workspace.api").explorer_close() end },
    toggle  = { desc = "Toggle the explorer",       handler = function() require("vscode-workspace.api").explorer_toggle() end },
    focus   = { desc = "Focus current file",        handler = function() require("vscode-workspace.api").explorer_focus() end },
    refresh = { desc = "Refresh the explorer",      handler = function() require("vscode-workspace.api").explorer_refresh() end },
    files = {
        desc    = "Find files across all workspace folders",
        handler = function() require("vscode-workspace.api").files() end,
    },
    grep = {
        desc    = "Live grep across all workspace folders",
        handler = function() require("vscode-workspace.api").grep() end,
    },
    workspaces = {
        desc    = "Show saved workspaces picker (cd + reload)",
        handler = function() require("vscode-workspace.api").explorer_workspaces() end,
    },
    favorite_current = {
        desc    = "Toggle current buffer in Favorites",
        handler = function() require("vscode-workspace.api").favorite_current() end,
    },
    add_favorites = {
        desc    = "Add files to Favorites via picker",
        handler = function() require("vscode-workspace.api").add_favorites() end,
    },
    favorites_files = {
        desc    = "Open Favorites in picker",
        handler = function() require("vscode-workspace.api").favorites_files() end,
    },
}

vim.api.nvim_create_user_command("CW", function(args)
    local sub = args.fargs[1]
    if sub and subcommands[sub] then
        subcommands[sub].handler(args)
    else
        local valid = vim.tbl_keys(subcommands)
        table.sort(valid)
        vim.notify("[CW] Unknown subcommand: " .. tostring(sub)
            .. "\nValid: " .. table.concat(valid, ", "), vim.log.levels.ERROR)
    end
end, {
    nargs    = "+",
    complete = function(_, line)
        local parts = vim.split(line, "%s+")
        if #parts <= 2 then
            return vim.tbl_keys(subcommands)
        end
    end,
    desc = "code-workspace.nvim",
})
