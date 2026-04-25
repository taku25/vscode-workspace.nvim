# vscode-workspace.nvim

<img width="1222" height="818" alt="image" src="https://github.com/user-attachments/assets/bef48a91-f9a9-4aa3-9e9a-3ad2094ebdb5" />

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
- **Flexible picker integration** — telescope / fzf-lua / snacks.nvim supported out of the box, fully customizable via `picker_function`

## Requirements

- Neovim 0.9+
- [nui.nvim](https://github.com/MunifTanjim/nui.nvim) (required)
- [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons) (optional, for file icons)
- One of: telescope.nvim / fzf-lua / snacks.nvim (optional, for picker support)

## Installation

```lua
-- lazy.nvim
{
    "taku25/vscode-workspace.nvim",
    dependencies = { "MunifTanjim/nui.nvim" },
    config = function()
        require("vscode-workspace").setup()
    end,
}
```

## Commands

| Command | Description |
|---|---|
| `:CW open` | Open the explorer panel |
| `:CW close` | Close the explorer panel |
| `:CW toggle` | Toggle the explorer panel |
| `:CW focus` | Focus the explorer panel |
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

### Favorites folder keymaps

| Key | Action |
|---|---|
| `<C-N>` | Add new favorites folder |
| `<C-r>` | Rename favorites folder under cursor |
| `<C-d>` | Remove favorites folder under cursor (files moved to Default) |
| `m` | Move file under cursor to another favorites folder |

### File system keymaps

| Key | Action |
|---|---|
| `a` | Create new file in directory under cursor |
| `A` | Create new directory in directory under cursor |
| `d` | Delete file / directory under cursor (with confirmation) |
| `r` | Rename file / directory under cursor |

## Configuration

```lua
require("vscode-workspace").setup({
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
        expander_open   = "",
        expander_closed = "",
        folder_closed   = "",
        folder_open     = "",
        default_file    = "",
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
        fav_add_folder    = "<C-N>",
        fav_rename_folder = "<C-r>",
        fav_remove_folder = "<C-d>",
        fav_move          = "m",
        find_files        = "f",
        live_grep         = "g",
        -- File system operations
        file_create       = "a",
        dir_create        = "A",
        file_delete       = "d",
        file_rename       = "r",
    },

    -- Picker backend: "telescope" | "fzf-lua" | "snacks" | "native"
    -- If omitted, auto-detected in the order above.
    -- picker = "telescope",

    -- Full override: receive a spec table and open your own picker.
    -- When set, `picker` is ignored.
    -- picker_function = function(spec)
    --     -- spec.type    = "files" | "grep" | "files_static" | "static"
    --     -- spec.prompt  = string
    --     -- spec.dirs    = string[]          (files / grep only)
    --     -- spec.items   = string[]          (static only)
    --     -- spec.on_submit = function(path)  called with the selected item
    --     if spec.type == "files" then
    --         require("telescope.builtin").find_files({
    --             prompt_title  = spec.prompt,
    --             search_dirs   = spec.dirs,
    --             attach_mappings = function(_, map)
    --                 map("i", "<CR>", function(pb)
    --                     local sel = require("telescope.actions.state").get_selected_entry()
    --                     require("telescope.actions").close(pb)
    --                     if sel then spec.on_submit(sel[1]) end
    --                 end)
    --                 return true
    --             end,
    --         })
    --     elseif spec.type == "grep" then
    --         require("telescope.builtin").live_grep({
    --             prompt_title = spec.prompt,
    --             search_dirs  = spec.dirs,
    --         })
    --     else  -- static (favorites folder picker, etc.)
    --         vim.ui.select(spec.items, { prompt = spec.prompt }, function(choice)
    --             if choice then spec.on_submit(choice) end
    --         end)
    --     end
    -- end,
})
```

## Picker Integration

Pickers are used for `:CW files`, `:CW grep`, favorites folder selection, and the add-favorites flow.

### Backend auto-detection (default)

When `picker` is not set, the plugin auto-detects in this order:

| Priority | Backend | Plugin |
|----------|---------|--------|
| 1 | `"telescope"` | [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) |
| 2 | `"fzf-lua"` | [fzf-lua](https://github.com/ibhagwan/fzf-lua) |
| 3 | `"snacks"` | [snacks.nvim](https://github.com/folke/snacks.nvim) |
| 4 | `"native"` | `vim.ui.select` (built-in fallback) |

### Selecting a backend explicitly

```lua
require("vscode-workspace").setup({
    picker = "fzf-lua",   -- skip auto-detect, always use fzf-lua
})
```

### Fully custom picker via `picker_function`

Set `picker_function` to take complete control. The function receives a **spec table** and must
open a picker, then call `spec.on_submit(selected)` when the user confirms:

```lua
require("vscode-workspace").setup({
    picker_function = function(spec)
        -- spec.type      "files" | "grep" | "files_static" | "static"
        -- spec.prompt    string — prompt / title for the picker
        -- spec.dirs      string[] — root dirs to search (files / grep)
        -- spec.items     string[] — pre-built list of items (files_static / static)
        -- spec.exclude_map  table<string,boolean> — raw files.exclude map
        -- spec.on_submit function(item) — call this with the chosen item

        if spec.type == "files" then
            require("telescope.builtin").find_files({
                prompt_title = spec.prompt,
                search_dirs  = spec.dirs,
                -- wire on_submit to telescope's <CR>:
                attach_mappings = function(pb, map)
                    map("i", "<CR>", function()
                        local sel = require("telescope.actions.state").get_selected_entry()
                        require("telescope.actions").close(pb)
                        if sel then spec.on_submit(sel[1]) end
                    end)
                    return true
                end,
            })

        elseif spec.type == "grep" then
            require("telescope.builtin").live_grep({
                prompt_title = spec.prompt,
                search_dirs  = spec.dirs,
            })

        else  -- "static" — favorites folder picker, etc.
            require("telescope.pickers").new({}, {
                prompt_title = spec.prompt,
                finder = require("telescope.finders").new_table({ results = spec.items }),
                sorter = require("telescope.config").values.generic_sorter({}),
                attach_mappings = function(pb)
                    require("telescope.actions").select_default:replace(function()
                        local sel = require("telescope.actions.state").get_selected_entry()
                        require("telescope.actions").close(pb)
                        if sel then spec.on_submit(sel[1]) end
                    end)
                    return true
                end,
            }):find()
        end
    end,
})
```

`picker_function` takes priority over the `picker` setting.

## Scanner (file enumeration)

`:CW files` and the add-favorites picker need to enumerate every file in your workspace.
The scanner tier is chosen automatically:

| Priority | Tool | `.gitignore` respected |
|----------|------|----------------------|
| 1 | `fd` / `fdfind` | ✅ |
| 2 | `rg --files` | ✅ |
| 3 | Pure-Lua BFS | ❌ (warns you) |

### Configuring the scanner

All options live under `scanner.files`:

```lua
require("vscode-workspace").setup({
    scanner = {
        files = {
            -- cmd: which tool to use for file enumeration
            --   nil   = auto-detect (fd > fdfind > rg > Lua)
            --   "fd"  | "fdfind" | "rg" | "/absolute/path/to/fd"
            --   false = skip external tools, always use pure-Lua BFS
            cmd = nil,

            -- args: argument list passed to cmd (workspace dirs are appended).
            --   nil = use the built-in safe defaults shown below.
            args = nil,
        },
    },
})
```

Built-in defaults when `args` is `nil`:

| cmd | default args |
|-----|-------------|
| `fd` / `fdfind` | `--type f --hidden --follow --color never` |
| `rg` | `--files --hidden --follow --color never --glob !.git` |

**Examples:**

```lua
-- Force fd, add --no-ignore to see files ignored by .gitignore too
scanner = { files = { cmd = "fd", args = { "--type", "f", "--no-ignore" } } }

-- Full path (e.g. installed via scoop on Windows)
scanner = { files = { cmd = "C:/Users/you/scoop/shims/fd.exe" } }

-- Disable external tools; use pure-Lua BFS
scanner = { files = { cmd = false } }
```

### Configuring the grep tool

`:CW grep` uses `rg` (ripgrep) by default. Customize via `scanner.grep`:

```lua
require("vscode-workspace").setup({
    scanner = {
        grep = {
            -- cmd: which tool to use for live grep
            --   nil   = auto-detect (rg > system grep)
            --   "rg"  | "grep" | "/absolute/path/to/rg"
            --   false = use backend default (no override)
            cmd = nil,

            -- args: argument list passed to cmd before the search pattern.
            --   nil = use built-in safe defaults.
            args = nil,
        },
    },
})
```

Built-in defaults when `args` is `nil`:

| cmd | default args |
|-----|-------------|
| `rg` | `--hidden --follow --smart-case` |
| other | `-rn` |

**Examples:**

```lua
-- Use ripgrep with extra flags (include hidden, follow symlinks, case-sensitive)
scanner = { grep = { cmd = "rg", args = { "--hidden", "--follow", "--case-sensitive" } } }

-- Use system grep
scanner = { grep = { cmd = "grep", args = { "-rn", "--include=*.lua" } } }
```



## Favorites

Favorites are displayed at the top of the explorer tree (★ Favorites node) mixed with the workspace folders — no separate tab.

- **`b`** in the explorer — toggle the file under cursor
- **`:CW favorite_current`** — toggle the current buffer
- **`:CW add_favorites`** — open a picker to add files
- **`:CW favorites_files`** — open Favorites in a picker (paths shown workspace-relative)

Favorites are persisted per workspace under `vim.fn.stdpath("cache")/vscode-workspace/`.

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

The patterns are applied to:
- **Tree view** — excluded files/directories are hidden during scanning
- **`:CW files` picker** — results filtered post-scan via `file_ignore_patterns`, regardless of which picker backend or scanner tool is used

## UEFN Projects

UEFN projects are auto-detected by the presence of `/Verse.org`, `/Fortnite.com`, or similar
`/domain.tld`-style folder names in the workspace. The `verse_project_root` is resolved from the
`/Verse.org` folder entry and exposed via `require("vscode-workspace.workspace").find()`.

## Documentation

Full reference available inside Neovim: `:help vscode-workspace`

## License

MIT License

Copyright (c) 2026 taku25

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
