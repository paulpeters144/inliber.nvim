local Discovery = require("inliber.interactions.shared.agent_commands.discovery")
local files = require("inliber.utils.files")

---@class Inliber.AgentCommands.Providers.ClaudeCode: Inliber.AgentCommands.Provider
local ClaudeCode = {}

ClaudeCode.name = "claude_code"

local function home()
  return vim.fs.joinpath(vim.fn.expand("~"), ".claude")
end

local function scoped_directories(root)
  local result = {}
  for _, ancestor in ipairs(Discovery.ancestor_dirs(root)) do
    local dir = vim.fs.joinpath(ancestor, ".claude", "commands")
    if files.is_dir(dir) then
      table.insert(result, { path = dir, scope = "project" })
    end
  end
  local global = vim.fs.joinpath(home(), "commands")
  if files.is_dir(global) then
    table.insert(result, { path = global, scope = "global" })
  end
  return result
end

---@param root string
---@return string[]
function ClaudeCode.directories(root)
  local dirs = {}
  for _, entry in ipairs(scoped_directories(root)) do
    table.insert(dirs, entry.path)
  end
  return dirs
end

---Discover commands from ~/.claude/commands/**/*.md and project .claude/commands/**/*.md, joining nested paths with ":"
---@param root string
---@return Inliber.AgentCommands.Command[]
function ClaudeCode.commands(root)
  local commands = {}
  local seen = {}

  for _, entry in ipairs(scoped_directories(root)) do
    for _, relative in ipairs(Discovery.command_files(entry.path)) do
      local parts = vim.split(relative:gsub("%.md$", ""), "/", { plain = true })
      local name = table.concat(parts, ":")
      if not seen[name] then
        seen[name] = true
        local path = vim.fs.joinpath(entry.path, relative)
        local frontmatter = Discovery.parse_frontmatter(path)
        table.insert(commands, {
          name = name,
          namespace = #parts > 1 and table.concat(vim.list_slice(parts, 1, #parts - 1), "/") or nil,
          description = frontmatter.description,
          argument_hint = frontmatter["argument-hint"],
          path = path,
          provider = ClaudeCode.name,
          scope = entry.scope,
        })
      end
    end
  end

  table.sort(commands, function(a, b)
    return a.name < b.name
  end)

  return commands
end

return ClaudeCode
