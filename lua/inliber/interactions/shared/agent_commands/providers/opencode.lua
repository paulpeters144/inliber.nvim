local Discovery = require("inliber.interactions.shared.agent_commands.discovery")
local files = require("inliber.utils.files")

---@class Inliber.AgentCommands.Providers.OpenCode: Inliber.AgentCommands.Provider
local OpenCode = {}

OpenCode.name = "opencode"

local SUBDIRECTORIES = { "commands", "command" }

local function home()
  local base = vim.env.XDG_CONFIG_HOME
  if not base or base == "" then
    base = vim.fs.joinpath(vim.fn.expand("~"), ".config")
  end
  return vim.fs.joinpath(base, "opencode")
end

local function scoped_directories(root)
  local result = {}
  for _, ancestor in ipairs(Discovery.ancestor_dirs(root)) do
    local project = vim.fs.joinpath(ancestor, ".opencode")
    for _, sub in ipairs(SUBDIRECTORIES) do
      local dir = vim.fs.joinpath(project, sub)
      if files.is_dir(dir) then
        table.insert(result, { path = dir, scope = "project" })
      end
    end
  end
  for _, sub in ipairs(SUBDIRECTORIES) do
    local dir = vim.fs.joinpath(home(), sub)
    if files.is_dir(dir) then
      table.insert(result, { path = dir, scope = "global" })
    end
  end
  return result
end

local function namespace_of(name)
  local parts = vim.split(name, "/", { plain = true })
  if #parts > 1 then
    return table.concat(vim.list_slice(parts, 1, #parts - 1), "/")
  end
  return nil
end

---@param root string
---@return string[]
function OpenCode.directories(root)
  local dirs = {}
  for _, entry in ipairs(scoped_directories(root)) do
    table.insert(dirs, entry.path)
  end
  return dirs
end

---Discover commands from ~/.config/opencode/{command,commands}/**/*.md and project .opencode/{command,commands}/**/*.md
---@param root string
---@return Inliber.AgentCommands.Command[]
function OpenCode.commands(root)
  local commands = {}
  local seen = {}

  for _, entry in ipairs(scoped_directories(root)) do
    for _, relative in ipairs(Discovery.command_files(entry.path)) do
      local name = relative:gsub("%.md$", "")
      if not seen[name] then
        seen[name] = true
        local path = vim.fs.joinpath(entry.path, relative)
        local frontmatter = Discovery.parse_frontmatter(path)
        table.insert(commands, {
          name = name,
          namespace = namespace_of(name),
          description = frontmatter.description,
          argument_hint = frontmatter["argument-hint"],
          path = path,
          provider = OpenCode.name,
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

return OpenCode
