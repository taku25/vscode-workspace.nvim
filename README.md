# vscode-workspace.nvim

<img width="1222" height="817" alt="image" src="https://github.com/user-attachments/assets/a6e0641d-0119-4f8e-b732-609998c875dd" />

A Neovim plugin for working with [VS Code `.code-workspace`](https://code.visualstudio.com/docs/editor/workspaces) files.  
Multi-root folder tree, favorites, and cross-workspace file/grep search — no VS Code required.

Works with any `.code-workspace` project, including **UEFN (Unreal Editor for Fortnite)** projects.

## Features

- **Multi-root tree view** — all `folders` in `.code-workspace` shown as roots
- **Favorites** — bookmark files directly in the tree (same panel, no separate tab)
- **`:CW files`** — find files across all workspace folders
- **`:CW grep`** — live grep across all workspace folders
- **`files.exclude` support** — workspace settings patterns applied to tree and file search
- **UEFN detection** — auto-detects Verse projects (highlights UEFN roots with ⚡)
- **No external tools required** — file scanning uses `vim.loop` (pure Lua)
- Picker auto-detection: **telescope → fzf-lua → snacks → vim.ui.select**

## Requirements

- Neovim 0.9+
- [nui.nvim](https://github.com/MunifTanjim/nui.nvim) (required)
- [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons) (optional, for file icons)
- One of: telescope.nvim / fzf-lua / snacks.nvim (optional, for picker support)

## Installation

```lua
-- lazy.nvim
{
    "taku25/code-workspace.nvim",
    dependencies = { "MunifTanjim/nui.nvim" },
    config = function()
        require("CW").setup()
    end,
}
```

## Commands

| Command | Description |
|---|---|
| `:CW open` | Open the explorer panel |
| `:CW close` | Close the explorer panel |
| `:CW toggle` | Toggle the explorer panel |
| `:CW focus` | Focus the current file in the tree |
| `:CW refresh` | Refresh the tree |
| `:CW files` | Find files across all workspace folders |
| `:CW grep` | Live grep across all workspace folders |
| `:CW favorite_current` | Toggle current buffer in Favorites |
| `:CW add_favorites` | Add files to Favorites via picker |
| `:CW favorites_files` | Open Favorites in picker |

## Explorer Keymaps

Default keymaps inside the explorer buffer:

| Key | Action |
|---|---|
| `<CR>` / `o` | Open file / expand directory |
| `s` | Open in vertical split |
| `i` | Open in horizontal split |
| `b` | Toggle current file in Favorites |
| `f` | Find files (`:CW files`) |
| `g` | Live grep (`:CW grep`) |
| `R` | Refresh tree |
| `q` | Close explorer |

## Configuration

```lua
require("CW").setup({
    window = {
        position = "left",   -- "left" | "right"
        width    = 35,
    },

    -- Directories always hidden in the tree
    ignore_dirs = {
        ".git", ".vs", ".vscode", ".idea",
        "node_modules", "__pycache__",
    },

    -- Icons (requires a Nerd Font)
    icon = {
        expander_open   = "",
        expander_closed = "",
        folder_closed   = "",
        folder_open     = "",
        default_file    = "",
        workspace       = "󰙅",
        uefn            = "⚡",
    },

    -- Keymaps (inside the explorer buffer)
    keymaps = {
        close           = { "q" },
        open            = { "<CR>", "o" },
        vsplit          = "s",
        split           = "i",
        refresh         = "R",
        toggle_favorite = "b",
        find_files      = "f",
        live_grep       = "g",
    },

    -- Optional: fully override picker behavior
    -- work_files = function(folders)
    --     require("telescope.builtin").find_files({ search_dirs = folders })
    -- end,
    -- work_grep = function(folders)
    --     require("telescope.builtin").live_grep({ search_dirs = folders })
    -- end,
})
```

## Favorites

Favorites are displayed at the top of the explorer tree (★ Favorites node) mixed with the workspace folders — no separate tab.

- **`b`** in the explorer — toggle the file under cursor
- **`:CW favorite_current`** — toggle the current buffer
- **`:CW add_favorites`** — open a picker to add files
- **`:CW favorites_files`** — open Favorites in a picker

Favorites are persisted per workspace under `vim.fn.stdpath("data")/code-workspace/`.

## `files.exclude` Support

If your `.code-workspace` contains a `settings` block with `files.exclude`, those patterns are
automatically applied to the tree view and file search:

```json
"settings": {
    "files.exclude": {
        "**/*.uasset": true,
        "**/*.umap":   true,
        "Intermediate": true
    }
}
```

Only entries set to `true` are applied. Entries set to `false` are ignored.

## UEFN Projects

UEFN projects are auto-detected by the presence of `/Verse.org`, `/Fortnite.com`, or similar
`/domain.tld`-style folder names in the workspace. The `verse_project_root` is resolved from the
`/Verse.org` folder entry and exposed via `require("CW.workspace").find()`.

## License

MIT © [taku25](https://github.com/taku25)
