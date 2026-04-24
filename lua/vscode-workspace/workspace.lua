-- lua/CW/workspace.lua
-- .code-workspace file finder and parser

local path = require("vscode-workspace.path")

local M = {}

--- Search upward from start_path and collect ALL *.code-workspace files found
--- in the first directory that contains at least one.
---@param start_path string
---@param max_depth? integer  Default: 10
---@return string[]  Full paths to all .code-workspace files found
local function find_workspace_files(start_path, max_depth)
    max_depth = max_depth or 10
    local dir = vim.fn.fnamemodify(start_path, ":p")
    if vim.fn.isdirectory(dir) == 0 then
        dir = vim.fn.fnamemodify(dir, ":h")
    end

    for _ = 1, max_depth do
        local found = {}
        local handle = vim.loop.fs_scandir(dir)
        if handle then
            while true do
                local name, ftype = vim.loop.fs_scandir_next(handle)
                if not name then break end
                if (ftype == "file" or ftype == nil) and name:match("%.code%-workspace$") then
                    table.insert(found, path.join(dir, name))
                end
            end
        end
        if #found > 0 then
            table.sort(found)
            return found
        end
        local parent = vim.fn.fnamemodify(dir, ":h")
        if parent == dir then break end
        dir = parent
    end
    return {}
end

--- Resolve a folder path from .code-workspace.
--- Paths in .code-workspace can be absolute or relative to the workspace file.
---@param raw_path string
---@param ws_dir string  Directory containing the .code-workspace file
---@return string  Normalized absolute path
local function resolve_folder_path(raw_path, ws_dir)
    local joined
    if raw_path:match("^[A-Za-z]:") or raw_path:match("^/") or raw_path:match("^\\\\") then
        joined = raw_path
    else
        joined = path.join(ws_dir, raw_path)
    end
    -- simplify() resolves "." and ".." components so node IDs are canonical
    return path.normalize(vim.fn.simplify(joined))
end

--- Detect if a workspace is a UEFN project by inspecting folder names.
--- UEFN workspaces have folders named "/Verse.org", "/Fortnite.com", etc.
---@param folders table  List of {name, path} entries
---@return boolean
local function is_uefn(folders)
    for _, f in ipairs(folders) do
        if f.name and f.name:match("^/[A-Za-z]") then
            return true
        end
    end
    return false
end

--- Parse a .code-workspace file.
---@param ws_path string  Full path to the .code-workspace file
---@return table|nil  { ws_path, ws_dir, name, safe_name, folders, is_uefn, verse_project_root? }
function M.parse(ws_path)
    if vim.fn.filereadable(ws_path) == 0 then return nil end

    local ok, lines = pcall(vim.fn.readfile, ws_path)
    if not ok then return nil end

    local text = table.concat(lines, "\n")
    local dok, data = pcall(vim.json.decode, text)
    if not dok or type(data) ~= "table" then return nil end

    local ws_dir = vim.fn.fnamemodify(ws_path, ":h")
    local ws_name = vim.fn.fnamemodify(ws_path, ":t:r")  -- stem without extension

    local folders = {}
    for _, entry in ipairs(data.folders or {}) do
        if type(entry) == "table" and entry.path then
            local resolved = resolve_folder_path(entry.path, ws_dir)
            -- Derive display name: resolve "." / ".." to the real directory name
            local display_name = entry.name
            if not display_name then
                local tail = vim.fn.fnamemodify(resolved, ":t")
                if tail == "." or tail == ".." or tail == "" then
                    -- fnamemodify with :p resolves relative parts, then grab tail
                    display_name = vim.fn.fnamemodify(vim.fn.resolve(resolved), ":t")
                else
                    display_name = tail
                end
                if not display_name or display_name == "" then
                    display_name = path.basename(ws_dir)  -- last-resort fallback
                end
            end
            table.insert(folders, {
                name     = display_name,
                path     = resolved,
                raw_path = entry.path,
            })
        end
    end

    local uefn = is_uefn(folders)

    -- Resolve verse_project_root from /Verse.org entry
    local verse_project_root = nil
    if uefn then
        for _, f in ipairs(folders) do
            if f.name == "/Verse.org" and path.exists(f.path) then
                verse_project_root = path.parent(f.path)
                break
            end
        end
    end

    -- Extract files.exclude patterns (value==true only)
    -- Stored as raw map so callers can pass to filter.compile() / filter.make_matcher()
    local exclude_map = {}
    local settings = data.settings or {}
    for k, v in pairs(settings["files.exclude"] or {}) do
        exclude_map[k] = v
    end

    -- Compute a collision-resistant safe name: "{wsname}_{sha256[:16]}"
    -- This matches UNL.nvim's convention and avoids full-path collisions.
    local ws_hash     = vim.fn.sha256(path.normalize(ws_path)):sub(1, 16)
    local ws_safe_name = ws_name .. "_" .. ws_hash

    return {
        ws_path            = path.normalize(ws_path),
        ws_dir             = path.normalize(ws_dir),
        name               = ws_name,
        safe_name          = ws_safe_name,
        folders            = folders,
        is_uefn            = uefn,
        verse_project_root = verse_project_root,
        exclude_map        = exclude_map,   -- raw VS Code files.exclude map
        settings           = settings,
    }
end

--- Find and parse the nearest .code-workspace from the given path.
--- If multiple files are found in the same directory, shows a picker.
---@param start_path? string  Defaults to current buffer path, then cwd
---@param on_result fun(ws: table|nil)  Callback (async when picker is shown)
function M.find(start_path, on_result)
    if not start_path or start_path == "" then
        start_path = vim.api.nvim_buf_get_name(0)
        if start_path == "" then
            start_path = vim.loop.cwd()
        end
    end

    local files = find_workspace_files(start_path)

    if #files == 0 then
        if on_result then on_result(nil) end
        return nil
    end

    if #files == 1 then
        local ws = M.parse(files[1])
        if on_result then on_result(ws) end
        return ws
    end

    -- Multiple workspaces → show picker
    local labels = vim.tbl_map(function(f)
        return vim.fn.fnamemodify(f, ":t")  -- just the filename
    end, files)

    if on_result then
        require("vscode-workspace.picker").select(labels, {
            prompt    = "Select workspace",
            on_submit = function(choice)
                if not choice then on_result(nil); return end
                -- find the index that matches the chosen label
                for i, label in ipairs(labels) do
                    if label == choice then
                        on_result(M.parse(files[i]))
                        return
                    end
                end
                on_result(nil)
            end,
        })
        return nil  -- async path
    else
        -- Synchronous fallback: return first (for internal use)
        return M.parse(files[1])
    end
end

--- Get all folder paths from a workspace as a flat list.
---@param ws table  Workspace object from M.parse() or M.find()
---@return string[]
function M.get_folder_paths(ws)
    local result = {}
    for _, f in ipairs(ws.folders or {}) do
        if path.exists(f.path) then
            table.insert(result, f.path)
        end
    end
    return result
end

return M
