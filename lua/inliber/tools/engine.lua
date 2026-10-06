---@class Inliber.Tools
---@field adapter Inliber.HTTPAdapter The adapter in use for the tool loop
---@field aug number The augroup for the tool
---@field id number The id of the tool loop the engine runs in
---@field constants table<string, string> The constants for the tool
---@field host Inliber.Tools.Host The headless host that owns the loop
---@field status string The status of the tool
---@field stdout table The stdout of the tool
---@field stderr table The stderr of the tool
---@field tool Inliber.Tools.Tool The current tool that's being run
---@field tools_config table The available tools for the tool system

local Orchestrator = require("inliber.tools.orchestrator")
local approvals = require("inliber.tools.approvals")
local config = require("inliber.config")
local tool_filter = require("inliber.tools.filter")

local log = require("inliber.utils.log")
local utils = require("inliber.utils")

local api = vim.api

-- Registry of tool factories that can be extended from by users
local FACTORIES = {
  cmd_tool = "inliber.tools.builtin.cmd_tool",
}

local CONSTANTS = {
  AUTOCMD_GROUP = "inliber.tools",

  STATUS_ERROR = "error",
  STATUS_SUCCESS = "success",
}

---@class Inliber.Tools
local Tools = {}

-- Private helper methods

---Handle missing or invalid tool errors by reporting them to the LLM
---@param tool table The tool that failed
---@param error_message string The error message
---@return nil
function Tools:_handle_tool_error(tool, error_message)
  local name = tool["function"].name
  local tool_call = vim.deepcopy(tool)
  tool_call.name = name
  tool_call.function_call = tool_call

  log:error(error_message)

  local available_tools_msg = ""
  if self.host and self.host.registry and self.host.registry.in_use then
    local available_tools = vim.tbl_keys(self.host.registry.in_use)
    if next(available_tools) then
      available_tools_msg = "The available tools are: "
        .. table.concat(
          vim.tbl_map(function(t)
            return "`" .. t .. "`"
          end, available_tools),
          ", "
        )
    else
      available_tools_msg = "No tools available"
    end
  else
    available_tools_msg = "No tools available"
  end

  self.status = CONSTANTS.STATUS_ERROR
  self.host:add_tool_output(tool_call, string.format("Tool `%s` not found. %s", name, available_tools_msg), "")
end

---Resolve and prepare a tool for execution
---@param tool table The tool call from the LLM
---@return table|nil The resolved tool or nil if failed
---@return string|nil Error message if resolution failed
---@return boolean|nil Whether this is a JSON parsing error that needs special handling
function Tools:_resolve_and_prepare_tool(tool)
  local name = tool["function"].name
  local tool_config = self.tools_config[name]

  -- Allow for hybrid tools that use an adapter's tool alongside a Inliber tool
  if tool_config and tool_config._adapter_tool == true and tool_config._has_client_tool then
    tool_config = utils.resolve_nested_value(config, tool_config.opts.client_tool)
  end

  if not tool_config then
    return nil, string.format("Couldn't find the tool `%s`", name), false
  end

  local ok, resolved_tool = pcall(function()
    return Tools.resolve(tool_config)
  end)

  if not ok or not resolved_tool then
    log:debug("Tool resolution failed for `%s`: %s", name, resolved_tool)
    return nil, string.format("Couldn't resolve the tool `%s`", name), false
  end

  -- NOTE: We deepcopy here to avoid mutating the original tool definition which
  -- has disastrous side effects.
  local prepared_tool = vim.deepcopy(resolved_tool)
  prepared_tool.name = name
  prepared_tool.function_call = tool

  -- Parse and set arguments - handle JSON errors specially like the original code
  if tool["function"].arguments then
    local args = tool["function"].arguments
    -- For some adapter's that aren't streaming, the args are strings rather than tables
    if type(args) == "string" then
      if args == "" then
        args = "{}"
      end
      local ok, decoded = pcall(vim.json.decode, args)
      if not ok then
        log:error("Couldn't decode the tool arguments: %s", args)
        self.host:add_tool_output(
          prepared_tool,
          string.format('You made an error in calling the %s tool: "%s"', name, decoded),
          ""
        )
        self.status = CONSTANTS.STATUS_ERROR
        return nil, "JSON parsing failed", true -- Special flag to indicate this was handled
      end

      args = decoded
    end
    prepared_tool.args = args
  end

  -- Merge options
  prepared_tool.opts = vim.tbl_extend("force", prepared_tool.opts or {}, tool_config.opts or {})

  -- Handle environment variables
  if prepared_tool.env then
    local env = type(prepared_tool.env) == "function" and prepared_tool.env(vim.deepcopy(prepared_tool)) or {}
    utils.replace_placeholders(prepared_tool.cmds, env)
  end

  return prepared_tool, nil, false
end

-- Public interface methods

---@param args { adapter: Inliber.HTTPAdapter, id: number }
function Tools.new(args)
  return setmetatable({
    adapter = args.adapter,
    aug = api.nvim_create_augroup(CONSTANTS.AUTOCMD_GROUP .. ":" .. args.id, { clear = true }),
    id = args.id,
    constants = CONSTANTS,
    status = CONSTANTS.STATUS_SUCCESS,
    stdout = {},
    stderr = {},
    tool = {},
    tools_config = tool_filter.filter_enabled_tools(config.tools, { adapter = args.adapter }),
  }, { __index = Tools })
end

---Refresh the tools configuration to pick up any dynamically added tools
---@param opts? table Options for refreshing the tools
---@return Inliber.Tools
function Tools:refresh(opts)
  opts = opts or {}
  self.tools_config = tool_filter.filter_enabled_tools(config.tools, opts)
  return self
end

---Set the autocmds for the tool
---@return nil
function Tools:set_autocmds()
  api.nvim_create_autocmd("User", {
    desc = "Handle responses from the Tool system",
    group = self.aug,
    pattern = "InliberTools*",
    callback = function(request)
      if request.data.id ~= self.id then
        return
      end

      if request.match == "InliberToolsStarted" then
        log:info("[Tool System] Initiated")
      elseif request.match == "InliberToolsFinished" then
        return vim.schedule(function()
          local resubmit = function()
            self:reset({ auto_submit = true })
            self.host:resubmit()
          end

          if approvals:get_mode(self.id) ~= "ask" then
            return resubmit()
          end
          if self.status == CONSTANTS.STATUS_ERROR and self.tools_config.opts.auto_submit_errors then
            return resubmit()
          end
          if self.status == CONSTANTS.STATUS_SUCCESS and self.tools_config.opts.auto_submit_success then
            return resubmit()
          end

          self:reset({ auto_submit = false })
        end)
      end
    end,
  })
end

---Execute the tools the LLM has asked to run
---@param host Inliber.Tools.Host The headless host that owns the loop
---@param tools table The tools requested by the LLM
---@return nil
function Tools:execute(host, tools)
  local id = math.random(10000000)
  self.host = host

  -- Wrap the entire tool execution in error handling
  local function safe_execute()
    -- NOTE: Set autocmds early so that errors can be handled properly
    self:set_autocmds()

    local orchestrator = Orchestrator.new(self, id)

    for _, tool in ipairs(tools) do
      local resolved_tool, error_msg, is_json_error = self:_resolve_and_prepare_tool(tool)

      if not resolved_tool then
        -- NOTE: A JSON error has already been reported to the LLM
        if not is_json_error then
          self:_handle_tool_error(tool, error_msg or "Unknown Error occurred")
        end
      else
        self.tool = resolved_tool --[[@as Inliber.Tools.Tool]]
        orchestrator.queue:push(resolved_tool)
      end
    end

    -- If no tools were resolved, finalize with error status
    if orchestrator.queue:is_empty() then
      return utils.fire("ToolsFinished", { id = self.id, tool_call_id = id })
    end

    utils.fire("ToolsStarted", { id = self.id, tool_call_id = id })
    host.tool_orchestrator = orchestrator
    orchestrator:setup_next_tool()
  end

  local ok, err = pcall(safe_execute)
  if not ok then
    log:error("tools::engine::execute - Execution error %s", err)
    self.status = CONSTANTS.STATUS_ERROR
    vim.schedule(function()
      utils.fire("ToolsFinished", { id = self.id, tool_call_id = id })
    end)
  end
end

---Reset the Tools class
---@param opts? table
---@return nil
function Tools:reset(opts)
  opts = opts or {}

  api.nvim_clear_autocmds({ group = self.aug })

  self.status = CONSTANTS.STATUS_SUCCESS
  self.stderr = {}
  self.stdout = {}

  self.host:tools_done(opts)
  log:info("[Tools] Completed")
end

---Load a factory and pass the tool table through it
---@param extends string The factory name
---@param tool table The tool table (factory picks what it needs)
---@return Inliber.Tools.Tool|nil
local function resolve_factory(extends, tool)
  local factory_path = FACTORIES[extends]
  if not factory_path then
    return log:error("[Tools] Unknown factory: %s", extends)
  end

  local ok, factory = pcall(require, factory_path)
  if not ok then
    return log:error("[Tools] Failed to load factory %s: %s", extends, factory)
  end

  return factory(tool)
end

---Resolve a path string to a module or file
---@param path string The module path or file path
---@return Inliber.Tools.Unresolved|nil
local function resolve_path(path)
  return utils.resolve({ value = path, source = "Tools" })
end

---Resolve a tool from the config
---@param tool table The tool from the config
---@return Inliber.Tools.Tool|nil
function Tools.resolve(tool)
  -- 1. Factory extension (table in config)
  if tool.extends then
    return resolve_factory(tool.extends, tool)
  end

  -- 2. Path-based resolution (module path or file path)
  if type(tool.path) == "string" then
    local resolved = resolve_path(tool.path)
    if resolved and resolved.extends then
      return resolve_factory(resolved.extends, resolved)
    end
    return resolved
  end

  -- 3. Function callback
  if type(tool.callback) == "function" then
    ---@type Inliber.Tools.Unresolved
    local resolved = tool.callback()
    if resolved and resolved.extends then
      return resolve_factory(resolved.extends, resolved)
    end
    return resolved
  end

  -- 4. Inline tool table (no path or callback)
  ---@type Inliber.Tools.Tool
  return tool
end

return Tools
