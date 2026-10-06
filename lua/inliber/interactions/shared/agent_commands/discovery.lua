local files = require("inliber.utils.files")
local log = require("inliber.utils.log")

local uv = vim.uv

---@class Inliber.AgentCommands.Command
---@field name string The command name as typed after the trigger, e.g. "git/commit"
---@field namespace? string The subdirectory the command lives in, nil at the top level
---@field description? string The frontmatter description
---@field argument_hint? string The frontmatter argument-hint
---@field path string Absolute path to the command file
---@field provider string Name of the provider that discovered the command
---@field scope "global"|"project"

---@class Inliber.AgentCommands.Discovery
local Discovery = {}

local cache = {}

---Ancestor directories from root up to the filesystem root, nearest first
---@param root string
---@return string[]
function Discovery.ancestor_dirs(root)
  local dirs = {}
  local dir = vim.fs.normalize(root)
  while dir and dir ~= "" do
    table.insert(dirs, dir)
    local parent = vim.fs.dirname(dir)
    if parent == dir then
      break
    end
    dir = parent
  end
  return dirs
end

local function walk(dir, prefix, acc)
  acc = acc or {}
  local handle = uv.fs_scandir(dir)
  if not handle then
    return acc
  end

  while true do
    local name, kind = uv.fs_scandir_next(handle)
    if not name then
      break
    end
    local relative = prefix and (prefix .. "/" .. name) or name
    if kind == "directory" then
      walk(vim.fs.joinpath(dir, name), relative, acc)
    elseif name:sub(-3) == ".md" then
      table.insert(acc, relative)
    end
  end

  return acc
end

---Markdown command files under a directory, as paths relative to it
---@param dir string
---@return string[]
function Discovery.command_files(dir)
  return walk(dir, nil, {})
end

---@param path string
---@return string body, table frontmatter
local function split_frontmatter(path)
  local ok, content = pcall(files.read, path)
  if not ok then
    log:error("[AgentCommands] Could not read command file: %s", path)
    return "", {}
  end
  local lines = vim.split(files.normalize_content(content), "\n")
  if lines[1] ~= "---" then
    return table.concat(lines, "\n"), {}
  end

  local frontmatter = {}
  for i = 2, #lines do
    local line = lines[i]
    if line == "---" then
      return table.concat(vim.list_slice(lines, i + 1), "\n"), frontmatter
    end
    local key, value = line:match("^%s*([%w%-_]+)%s*:%s*(.-)%s*$")
    if key then
      frontmatter[key] = value
    end
  end

  return table.concat(lines, "\n"), frontmatter
end

---Parse a command file's YAML frontmatter into a key-value table
---@param path string Absolute file path
---@return table<string, any>
function Discovery.parse_frontmatter(path)
  local _, frontmatter = split_frontmatter(path)
  return frontmatter
end

---Read a command file's body, with any frontmatter block and trailing newline removed; empty when unreadable
---@param path string Absolute file path
---@return string
function Discovery.read_body(path)
  return split_frontmatter(path):gsub("\n+$", "")
end

---@param path string
---@return { sec: integer, nsec: integer }|nil
local function mtime(path)
  local stat = uv.fs_stat(path)
  return stat and stat.mtime or nil
end

---@param recorded { sec: integer, nsec: integer }|nil
---@param current { sec: integer, nsec: integer }|nil
---@return boolean
local function mtime_changed(recorded, current)
  if recorded == nil or current == nil then
    return recorded ~= current
  end
  return recorded.sec ~= current.sec or recorded.nsec ~= current.nsec
end

---Commands for a provider, cached per (provider.name, root) and invalidated by file and directory mtime
---@param provider Inliber.AgentCommands.Provider
---@param root string
---@return Inliber.AgentCommands.Command[]
function Discovery.commands(provider, root)
  local key = provider.name .. "|" .. (root or "")
  local dirs = provider.directories(root)

  local entry = cache[key]
  if entry then
    local fresh = #entry.dirs == #dirs
    if fresh then
      for i, dir in ipairs(dirs) do
        if entry.dirs[i].path ~= dir or mtime_changed(entry.dirs[i].mtime, mtime(dir)) then
          fresh = false
          break
        end
      end
    end
    if fresh then
      for _, file in ipairs(entry.files) do
        if mtime_changed(file.mtime, mtime(file.path)) then
          fresh = false
          break
        end
      end
    end
    if fresh then
      return entry.commands
    end
  end

  local commands = provider.commands(root)
  cache[key] = {
    dirs = vim.tbl_map(function(dir)
      return { path = dir, mtime = mtime(dir) }
    end, dirs),
    files = vim.tbl_map(function(command)
      return { path = command.path, mtime = mtime(command.path) }
    end, commands),
    commands = commands,
  }

  return commands
end

return Discovery
