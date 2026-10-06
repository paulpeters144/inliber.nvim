--[[
Methods for handling interactions between the tool loop and tools
--]]

---@class Inliber.Tools.Registry
---@field host Inliber.Tools.Host The headless host that owns the loop
---@field ctx Inliber.SystemPrompt.Context The context for the system prompt
---@field flags table Flags that external functions can update and subscribers can interact with
---@field groups table<string, string[]> Groups and their member tool names
---@field in_use table<string, boolean> Tools that are in use on the loop
---@field schemas table<string, table> The config for the tools in use

---@class Inliber.Tools.Registry
local Registry = {}

local config = require("inliber.config")
local tags = require("inliber.interactions.shared.tags")
local utils = require("inliber.utils")

local fmt = string.format

---Make a tool ID from a tool name
---@param name string
---@return string
function Registry.tool_id(name)
  return fmt("<tool>%s</tool>", name)
end

---Make a group ID from a group name
---@param name string
---@return string
local function group_id(name)
  return fmt("<group>%s</group>", name)
end

---@class Inliber.Tools.RegistryArgs
---@field host Inliber.Tools.Host
---@field ctx Inliber.SystemPrompt.Context

---@param args Inliber.Tools.RegistryArgs
function Registry.new(args)
  local self = setmetatable({
    host = args.host,
    ctx = args.ctx,
    flags = {},
    groups = {},
    in_use = {},
    schemas = {},
  }, { __index = Registry })

  return self
end

---Add context about the tool to the loop
---@param host Inliber.Tools.Host The headless host
---@param id string The id of the tool
---@param opts? table Optional parameters for the context_item
---@return nil
local function add_context(host, id, opts)
  host.context:add({
    source = "tool",
    name = "tool",
    id = id,
    opts = opts,
  })
end

---Add the tool's system prompt to the loop's messages
---@param host Inliber.Tools.Host The headless host
---@param tool table the resolved tool
---@param id string The id of the tool
---@return nil
local function add_system_prompt(host, tool, id)
  if tool and tool.system_prompt then
    local system_prompt
    if type(tool.system_prompt) == "function" then
      system_prompt = tool.system_prompt(tool.schema)
    elseif type(tool.system_prompt) == "string" then
      system_prompt = tostring(tool.system_prompt)
    end
    host:add_message(
      { role = config.constants.SYSTEM_ROLE, content = system_prompt },
      { visible = false, _meta = { tag = tags.TOOL }, context = { id = id } }
    )
  end
end

---Add the tool's schema to the registry
---@param self Inliber.Tools.Registry The registry object
---@param tool table The resolved tool
---@param id string The id of the tool
---@return nil
local function add_schema(self, tool, id)
  self.schemas[id] = tool.schema
end

---Add a tool or group to the registry
---@param name string The name of the tool or group
---@param opts? { config: table, visible: boolean }
---@return Inliber.Tools.Registry|nil
function Registry:add(name, opts)
  opts = opts or {}

  local tools_config = opts.config or config.tools

  if tools_config.groups and tools_config.groups[name] then
    return self:add_group(name, { config = tools_config })
  end

  local tool_config = tools_config[name]
  if tool_config then
    return self:add_single_tool(name, { config = tool_config, visible = opts.visible })
  end

  return nil
end

---Add a single tool to the registry
---@param tool string The name of the tool
---@param opts? { config: table, visible: boolean }
---@return Inliber.Tools.Registry|nil
function Registry:add_single_tool(tool, opts)
  opts = opts or {}
  if opts.visible == nil then
    opts.visible = true
  end

  local tool_config = opts.config or config.tools[tool]
  if not tool_config then
    return nil
  end

  if self.in_use[tool] then
    return nil
  end

  local id = Registry.tool_id(tool)

  local is_adapter_tool = tool_config._adapter_tool == true
  if is_adapter_tool then
    add_context(self.host, id, opts)
    add_system_prompt(self.host, tool_config, id)
    add_schema(self, {
      schema = {
        name = tool,
        description = tool_config.description or "",
        _meta = {
          adapter_tool = true,
        },
      },
    }, id)
    self.in_use[tool] = true
  else
    local resolved_tool = require("inliber.tools.engine").resolve(tool_config)
    if not resolved_tool then
      return nil
    end

    add_context(self.host, id, opts)
    add_system_prompt(self.host, resolved_tool, id)
    add_schema(self, resolved_tool, id)
    self.in_use[tool] = true
    self:add_tool_system_prompt()
  end

  utils.fire("ToolAdded", { id = self.host.id, tool = tool })

  return self
end

---Add tools from a group to the registry
---@param group string The name of the group
---@param opts? { config: table }
---@return Inliber.Tools.Registry|nil
function Registry:add_group(group, opts)
  opts = opts or {}

  if self.groups[group] then
    return nil
  end

  local tools_config = opts.config or config.tools
  local group_config = tools_config.groups[group]
  if not group_config or not group_config.tools then
    return nil
  end

  local group_opts = vim.tbl_deep_extend("force", { collapse_tools = true }, group_config.opts or {})
  local collapse_tools = group_opts.collapse_tools

  local gid = group_id(group)

  if group_opts.ignore_system_prompt then
    self.host:remove_tagged_message("system_prompt_from_config")
    self.flags.ignore_system_prompt = true
  end

  if group_opts.ignore_tool_system_prompt then
    self.host:remove_tagged_message("tool_system_prompt")
    self.flags.ignore_tool_system_prompt = true
  end

  local system_prompt = group_config.system_prompt
  if type(system_prompt) == "function" then
    system_prompt = system_prompt(group_config, self.host:make_system_prompt_context())
  end
  if system_prompt then
    self.host:add_message({
      role = config.constants.SYSTEM_ROLE,
      content = system_prompt,
    }, { _meta = { tag = tags.TOOL }, context = { id = gid }, visible = false })
  end

  if collapse_tools then
    add_context(self.host, gid)
  end
  local added_tools = {}
  for _, tool in ipairs(group_config.tools) do
    local tool_cfg = tools_config[tool]
    if tool_cfg then
      if self:add_single_tool(tool, { config = tool_cfg, visible = not collapse_tools }) then
        table.insert(added_tools, tool)
      end
    end
  end
  self.groups[group] = added_tools

  return self
end

---Add a tool system prompt to the loop's messages, updated for every tool addition
---@return nil
function Registry:add_tool_system_prompt()
  if self.flags.ignore_tool_system_prompt then
    return
  end

  local opts = config.tools.opts.system_prompt or {}
  if not opts.enabled then
    return
  end

  local prompt = opts.prompt
  if type(prompt) == "function" then
    prompt = prompt({ ctx = self.ctx, tools = vim.tbl_keys(self.in_use) })
  end

  local index = 2 -- Add after the main system prompt if not replacing
  if opts.replace_main_system_prompt then
    index = 1
    self.host:remove_tagged_message(tags.SYSTEM_PROMPT_FROM_CONFIG)
  end

  self.host:set_system_prompt(prompt, { visible = false, _meta = { tag = tags.TOOL_SYSTEM_PROMPT, index = index } })
end

---Clear the tools
---@return nil
function Registry:clear()
  self.flags = {}
  self.groups = {}
  self.in_use = {}
  self.schemas = {}
end

return Registry
