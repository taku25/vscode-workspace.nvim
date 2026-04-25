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
        expander_open   = "",
        expander_closed = "",
        folder_closed   = "",
        folder_open     = "",
        default_file    = "",
        workspace       = "󰙅",
        uefn            = "",
        favorites       = "★",
        recent          = "",
        select_marker   = "〇",
    },
    highlights = {
        CWDirectoryIcon  = { link = "Directory" },
        CWFileIcon       = { link = "Comment" },
        CWFileName       = { link = "Normal" },
        CWCurrentFile    = { bold = true, underline = true },
        CWSelectedFile   = { link = "Visual" },
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
        refresh         = "R",
        toggle_favorite = "b",
        fav_add_folder    = "<C-N>",
        fav_rename_folder = "<C-r>",
        fav_remove_folder = "<C-d>",
        fav_move          = "m",
        find_files        = "f",
        live_grep         = "g",
        -- Multi-select
        select_toggle   = "<Space>",
        clear_selection = "<Esc>",
        -- Preview
        preview_toggle  = "p",
        -- File system operations
        file_create       = "a",
        dir_create        = "A",
        file_delete       = "d",
        file_rename       = "r",
        file_copy         = "y",
        file_cut          = "x",
        file_paste        = "P",
        -- Workspace switching
        switch_workspace  = "W",  -- shows saved workspaces picker (:CW workspaces)
        -- Favorite folder icon
        fav_set_icon      = "<C-i>",
    },
    -- ── Preview configuration ─────────────────────────────────────────────────
    preview = {
        auto             = true,    -- CursorMoved で自動表示
        debounce_ms      = 150,
        width_pct        = 0.80,
        height_pct       = 0.80,
        min_width        = 20,
        min_height       = 5,
        max_file_size_kb = 512,
    },
    -- ── Recent files configuration ────────────────────────────────────────────
    -- Max number of recently opened files to show in the Recent section of the tree.
    recent_files = {
        max = 20,
    },

    -- ── Picker configuration ─────────────────────────────────────────────────
    -- picker: explicitly name the backend to use.
    --   "telescope" | "fzf-lua" | "snacks" | "native"
    --   nil = auto-detect from installed plugins (telescope > fzf-lua > snacks > native)
    picker = nil,

    -- picker_function: fully custom picker. When set, ALL picker calls go here.
    -- Receives a spec table with:
    --   spec.type       "files" | "grep" | "static"
    --   spec.prompt     string  title / prompt text
    --   spec.dirs       string[]  (type="files" or "grep") directories to search
    --   spec.items      string[]  (type="static") pre-built list to pick from
    --   spec.on_submit  fun(choice: string|nil)  (type="static") selection callback
    -- Example:
    --   picker_function = function(spec)
    --     if spec.type == "files" then
    --       require("telescope.builtin").find_files({ search_dirs = spec.dirs })
    --     elseif spec.type == "grep" then
    --       require("telescope.builtin").live_grep({ search_dirs = spec.dirs })
    --     elseif spec.type == "static" then
    --       vim.ui.select(spec.items, { prompt = spec.prompt }, spec.on_submit)
    --     end
    --   end,
    picker_function = nil,

    -- ── Scanner configuration ─────────────────────────────────────────────────
    -- Controls which external tool is used when enumerating files or grepping.
    -- Organized by purpose: `files` (CW files / add_favorites) and `grep` (CW grep).
    --
    -- scanner.files.cmd / scanner.grep.cmd:
    --   nil   = auto-detect
    --   string = command name or absolute path (e.g. "fd", "rg", "C:/tools/fd.exe")
    --   false = skip external tools, use built-in fallback
    --
    -- scanner.files.args / scanner.grep.args:
    --   nil   = use built-in defaults for the detected command
    --   table = use exactly these args (search dirs appended at the end for files;
    --           pattern + dirs appended for grep)
    scanner = {
        files = {
            cmd  = nil,   -- nil = auto-detect (fd > fdfind > rg > Lua BFS)
            args = nil,   -- nil = built-in defaults
        },
        grep = {
            cmd  = nil,   -- nil = auto-detect (rg > grep)
            args = nil,   -- nil = built-in defaults
        },
    },
}

local current = vim.deepcopy(defaults)

function M.setup(opts)
    current = vim.tbl_deep_extend("force", defaults, opts or {})
    M._apply_highlights()
    -- Invalidate scanner cache so new scanner.* settings are picked up.
    require("vscode-workspace.picker.scanner").reset()
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
