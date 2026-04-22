-- lua/CW/config.lua

local M = {}

local defaults = {
    window = {
        position = "left",   -- "left" | "right"
        width = 35,
    },
    -- Directories ignored when scanning the tree
    ignore_dirs = {
        ".git", ".vs", ".vscode", ".idea",
        "node_modules", "__pycache__",
    },
    icon = {
        expander_open   = "",
        expander_closed = "",
        folder_closed   = "",
        folder_open     = "",
        default_file    = "",
        workspace       = "󰙅",
        uefn            = "⚡",
    },
    highlights = {
        CWDirectoryIcon  = { link = "Directory" },
        CWFileIcon       = { link = "Comment" },
        CWFileName       = { link = "Normal" },
        CWIndentMarker   = { link = "NonText" },
        CWRootName       = { link = "Title" },
        CWTabActive      = { link = "String" },
        CWTabInactive    = { link = "Normal" },
        CWTabSeparator   = { link = "NonText" },
        CWModifiedIcon   = { link = "Special" },
    },
    keymaps = {
        close           = { "q" },
        open            = { "<CR>", "o" },
        vsplit          = "s",
        split           = "i",
        tab_next        = "<Tab>",
        tab_prev        = "<S-Tab>",
        refresh         = "R",
        toggle_favorite = "b",
        fav_add_folder  = "N",
        fav_rename_folder = "<C-r>",
        fav_remove_folder = "<C-d>",
        fav_move        = "m",
        find_files      = "f",
        live_grep       = "g",
    },
    -- Optional: override picker behavior
    -- work_files = function(folders) ... end,
    -- work_grep  = function(folders) ... end,
    work_files = nil,
    work_grep  = nil,
}

local current = vim.deepcopy(defaults)

function M.setup(opts)
    current = vim.tbl_deep_extend("force", defaults, opts or {})
    M._apply_highlights()
end

function M.get()
    return current
end

function M._apply_highlights()
    for name, def in pairs(current.highlights or {}) do
        vim.api.nvim_set_hl(0, name, def)
    end
end

return M
