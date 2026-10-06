---@class Inliber.AgentCommands.Provider
---@field name string Provider identifier matching the adapter's `agent_commands.provider`, e.g. "opencode"
---@field directories fun(root: string): string[] Absolute command directories to scan, nearest scope first
---@field commands fun(root: string): Inliber.AgentCommands.Command[] Discover commands using provider-specific directories, naming, frontmatter, and scope precedence

---@class Inliber.AgentCommands.Providers
local Providers = {}

local registered = {}
local order = {}

---Register a provider implementation, or override an existing one; the extension point for users and tests
---@param provider Inliber.AgentCommands.Provider
---@return nil
function Providers.register(provider)
  if not registered[provider.name] then
    table.insert(order, provider.name)
  end
  registered[provider.name] = provider
end

---Resolve a provider by name, or nil when unknown
---@param name string
---@return Inliber.AgentCommands.Provider|nil
function Providers.get(name)
  return registered[name]
end

---Resolve the first registered provider whose command directories exist on disk, or nil
---@param root string
---@return Inliber.AgentCommands.Provider|nil
function Providers.detect(root)
  for _, name in ipairs(order) do
    local provider = registered[name]
    if #provider.directories(root) > 0 then
      return provider
    end
  end
  return nil
end

Providers.register(require("inliber.interactions.shared.agent_commands.providers.opencode"))
Providers.register(require("inliber.interactions.shared.agent_commands.providers.claude_code"))

return Providers
