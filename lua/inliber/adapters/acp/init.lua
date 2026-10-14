local config = require("inliber.config")
local log = require("inliber.utils.log")
local shared = require("inliber.adapters.shared")

---@class Inliber.ACPAdapter
---@field name string The name of the adapter
---@field model string The model to use with the adapter
---@field type string|"acp" The type of the adapter, e.g. "acp"
---@field formatted_name string The formatted name of the adapter
---@field roles table The mapping of roles in the config to the LLM's defined roles
---@field command table The command to execute
---@field commands { default: table, [string]: table } The list of possible commands for the adapter. Must include a 'default' key
---@field opts? table Additional options for the adapter
---@field defaults? table Additional options for the adapter
---@field env? table Environment variables which can be referenced in the parameters
---@field env_replaced? table Replacement of environment variables with their actual values
---@field parameters? table The parameters to pass to the request
---@field handlers table Functions which link the output from the request to Inliber
---@field handlers.setup? fun(self: Inliber.ACPAdapter): boolean
---@field handlers.auth? fun(self: Inliber.ACPAdapter): boolean Manually handle authentication
---@field handlers.on_exit? fun(self: Inliber.ACPAdapter, data: table): table|nil
---@field handlers.teardown? fun(self: Inliber.ACPAdapter): any

---@class Inliber.ACPAdapter
local Adapter = {}

---@return Inliber.ACPAdapter
function Adapter.new(args)
  return setmetatable(args, { __index = Adapter })
end

Adapter.map_roles = shared.map_roles

---Extend an existing adapter
---@param adapter table|string|function
---@param opts? table
---@return Inliber.ACPAdapter
function Adapter.extend(adapter, opts)
  local ok
  local adapter_config
  opts = opts or {}

  if type(adapter) == "string" then
    ok, adapter_config = pcall(require, "inliber.adapters.acp." .. adapter)
    if not ok then
      -- Check acp adapters first, then fall back to root adapters
      adapter_config = (config.adapters.acp and config.adapters.acp[adapter]) or config.adapters[adapter]
      if type(adapter_config) == "function" then
        adapter_config = adapter_config()
      end
    end
  elseif type(adapter) == "function" then
    adapter_config = adapter()
  else
    adapter_config = adapter
  end

  if not adapter_config then
    return log:error("[adapters::acp::extend] Adapter not found: %s", adapter)
  end

  adapter_config = vim.tbl_deep_extend("force", {}, vim.deepcopy(adapter_config), opts or {})

  return Adapter.new(adapter_config)
end

---Resolve an adapter from deep within the plugin...somewhere
---@param adapter? Inliber.ACPAdapter|string|function
---@param opts? table
---@return Inliber.ACPAdapter
function Adapter.resolve(adapter, opts)
  adapter = adapter or config.interactions.inline.adapter
  opts = opts or {}

  local key = type(adapter) == "string" and adapter or nil

  if type(adapter) == "table" then
    -- Handle { name = "claude_code", model = "opus" } style config first
    if adapter.name and adapter.model and not adapter.type then
      log:trace("[adapters::acp::resolve] Table adapter with model: %s", adapter.name)
      return Adapter.resolve(adapter.name, { model = adapter.model })
    elseif adapter.name and not adapter.type then
      log:trace("[adapters::acp::resolve] Table adapter: %s", adapter.name)
      return Adapter.resolve(adapter.name)
    end

    if opts.session_config_options then
      adapter = vim.tbl_deep_extend("force", vim.deepcopy(adapter), {
        defaults = { session_config_options = opts.session_config_options },
      })
    end

    -- A configured session model or mode takes precedence over `defaults.model` and `defaults.mode`
    if opts.model or opts.mode then
      adapter = vim.tbl_deep_extend("force", vim.deepcopy(adapter), {
        defaults = { session_config_options = { model = opts.model, mode = opts.mode } },
      })
    end

    adapter = Adapter.new(adapter)
  elseif type(adapter) == "string" then
    if not config.adapters.acp or not config.adapters.acp[adapter] then
      return log:error("[adapters::acp::resolve] Adapter not found: %s", adapter)
    end
    adapter = Adapter.extend(config.adapters.acp[adapter] or adapter)

    if opts.session_config_options then
      adapter.defaults = adapter.defaults or {}
      adapter.defaults.session_config_options =
        vim.tbl_deep_extend("force", adapter.defaults.session_config_options or {}, opts.session_config_options)
    end
    if opts.model or opts.mode then
      adapter.defaults = adapter.defaults or {}
      adapter.defaults.session_config_options =
        vim.tbl_extend("force", adapter.defaults.session_config_options or {}, { model = opts.model, mode = opts.mode })
    end
  elseif type(adapter) == "function" then
    adapter = adapter()
  end

  shared.apply_extend(adapter, { extend = config.adapters.acp.extend, key = key })

  if adapter.commands and adapter.commands.default then
    adapter.commands.selected = adapter.commands.default
  end

  return adapter
end

---Check if an adapter has already been resolved
---@param adapter Inliber.ACPAdapter|string|function|nil
---@return boolean
function Adapter.resolved(adapter)
  if adapter and getmetatable(adapter) and getmetatable(adapter).__index == Adapter then
    return true
  end
  return false
end

---Make an adapter safe for serialization
---@param adapter Inliber.ACPAdapter
---@return table
function Adapter.make_safe(adapter)
  return {
    name = adapter.name,
    formatted_name = adapter.formatted_name,
    type = adapter.type,
    command = adapter.command,
    defaults = adapter.defaults,
    params = adapter.parameters,
    opts = adapter.opts,
    handlers = adapter.handlers,
  }
end

---Set the ACP model
---@param args { acp_connection: Inliber.ACP.Connection, adapter: Inliber.ACPAdapter, model: string }
---@return boolean
function Adapter.set_model(args)
  return args.acp_connection:set_model(args.model)
end

return Adapter
