--[[
===============================================================================
    File:       inliber/acp/init.lua
    Author:     Oli Morris
-------------------------------------------------------------------------------
    Description:
      This module implements ACP communication in Inliber.
      It provides a fluent API for interacting with ACP agents,
      handling session management, and processing responses.

      Inspired by Zed's ACP implementation patterns.

      This code is licensed under the Apache-2.0 License.
-------------------------------------------------------------------------------
    Attribution:
      If you use or distribute this code, please credit:
      Oli Morris (https://github.com/olimorris)
===============================================================================
--]]

local METHODS = require("inliber.acp.methods")
local PromptBuilder = require("inliber.acp.prompt_builder")
local adapter_utils = require("inliber.adapters.utils")
local async = require("inliber.utils.async")
local config = require("inliber.config")
local jsonrpc = require("inliber.utils.jsonrpc")
local log = require("inliber.utils.log")
local utils = require("inliber.utils")

local TIMEOUTS = {
  DEFAULT = 2e4, -- 20 seconds
  RESPONSE_POLL = 10, -- 10ms
}

local api = vim.api
local uv = vim.uv

--=============================================================================
-- ACP Connection Class - Handles the connection to ACP agents
--=============================================================================

---@class Inliber.ACP.Connection
---@field adapter Inliber.ACPAdapter
---@field adapter_modified Inliber.ACPAdapter Modified adapter with environment variables set
---@field pending_responses table<number, Inliber.ACP.Connection.PendingResponse>
---@field session_id string|nil
---@field _agent_info {agentCapabilities: ACP.agentCapabilities, authMethods: ACP.authMethods, protocolVersion: number}|nil
---@field _initialized boolean
---@field _authenticated boolean
---@field _active_prompt Inliber.ACP.PromptBuilder|nil
---@field _state {handle: table, id_gen: Inliber.JsonRPC.IdGenerator, line_buffer: Inliber.JsonRPC.LineBuffer}
---@field _available_commands table[]|nil Raw availableCommands reported by the agent
---@field _config_options table[] Raw configOptions from the agent
---@field _in_flight table<string, Inliber.ACP.Connection.InFlight> Establishment steps currently underway
---@field _pending_callbacks table<number, function> Async callbacks keyed by request ID
---@field _rpc_log? { path: string, write: fun(data: string) } Per-connection log capturing raw JSON-RPC traffic
---@field methods table
local Connection = {}

Connection.METHODS = METHODS

---@class Inliber.ACP.Connection.PendingResponse
---@field result any
---@field error any

---@class Inliber.ACP.Connection.InFlight
---@field done boolean
---@field success boolean
---@field callbacks function[]

local METHOD_DEFAULTS = {
  decode = vim.json.decode,
  encode = vim.json.encode,
  job = vim.system,
  schedule = vim.schedule,
  schedule_wrap = vim.schedule_wrap,
}

---@class Inliber.ACPConnectionArgs
---@field adapter Inliber.ACPAdapter
---@field session_id? string
---@field opts? table

---Create new ACP connection
---@param args Inliber.ACPConnectionArgs
---@return Inliber.ACP.Connection
function Connection.new(args)
  args = args or {}

  local methods = vim.tbl_extend("force", METHOD_DEFAULTS, args.opts or {})

  local self = setmetatable({
    adapter = args.adapter,
    adapter_modified = {},
    methods = methods,
    pending_responses = {},
    session_id = args.session_id,
    _authenticated = false,
    _config_options = {},
    _in_flight = {},
    _initialized = false,
    _pending_callbacks = {},
    _state = { handle = nil, id_gen = jsonrpc.IdGenerator.new(), line_buffer = jsonrpc.LineBuffer.new() },
  }, { __index = Connection }) ---@cast self Inliber.ACP.Connection

  return self
end

---Check if the connection has a session ready for prompting
---@return boolean
function Connection:is_connected()
  return self._state.handle and self._initialized and self._authenticated and self.session_id ~= nil
end

---Check if the connection is authenticated
---@return boolean
function Connection:is_ready()
  return self._state.handle ~= nil and self._initialized and self._authenticated
end

---Wait on an establishment step another caller already started
---@param in_flight Inliber.ACP.Connection.InFlight
---@return boolean success
function Connection:_await_in_flight(in_flight)
  if coroutine.running() then
    return async.wait(function(callback)
      table.insert(in_flight.callbacks, callback)
    end)
  end

  -- vim.wait pumps the event loop, so the caller that owns the step can finish
  local defaults = (self.adapter_modified and self.adapter_modified.defaults) or {}
  vim.wait(defaults.timeout or TIMEOUTS.DEFAULT, function()
    return in_flight.done
  end, TIMEOUTS.RESPONSE_POLL)

  return in_flight.success
end

---Run an establishment step once, sharing its result with concurrent callers
---@param opts { key: string, work: fun(): boolean }
---@return boolean success
function Connection:_run_once(opts)
  local in_flight = self._in_flight[opts.key]
  if in_flight then
    return self:_await_in_flight(in_flight)
  end

  in_flight = { done = false, success = false, callbacks = {} }
  self._in_flight[opts.key] = in_flight

  -- An error here must still release the step, or every later caller waits on it forever
  local ok, result = pcall(opts.work)
  if not ok then
    log:error("[acp::_run_once] Step `%s` failed: %s", opts.key, result)
  end
  local success = ok and result and true or false

  in_flight.done = true
  in_flight.success = success
  self._in_flight[opts.key] = nil

  for _, callback in ipairs(in_flight.callbacks) do
    self.methods.schedule(function()
      callback(success)
    end)
  end

  return success
end

---Connect, initialize and authenticate the ACP process
---@return Inliber.ACP.Connection|nil
function Connection:connect_and_authenticate()
  if self:is_ready() then
    return self
  end

  -- Every step here blocks on the agent, so a second caller arriving mid-flight
  -- would spawn its own process and leave the first one orphaned
  local connected = self:_run_once({
    key = "connect",
    work = function()
      return self:start_agent_process() and self:_initialize() and self:_authenticate()
    end,
  })

  return connected and self or nil
end

---Negotiate the protocol version and record what the agent supports
---@return boolean success
function Connection:_initialize()
  if self._initialized then
    return true
  end

  local initialized = self:send_rpc_request(METHODS.INITIALIZE, self.adapter_modified.parameters)
  if not initialized then
    log:error("[acp::_initialize] Failed to initialize")
    return false
  end
  self._agent_info = initialized

  if
    initialized.protocolVersion and initialized.protocolVersion ~= self.adapter_modified.parameters.protocolVersion
  then
    log:warn(
      "[acp::_initialize] Agent selected protocolVersion=%s (client sent=%s)",
      initialized.protocolVersion,
      self.adapter_modified.parameters.protocolVersion
    )
  end

  self._initialized = true
  log:debug("[acp] Initialized (protocol_version=%s)", initialized.protocolVersion or "unknown")

  api.nvim_create_autocmd("VimLeavePre", {
    group = api.nvim_create_augroup("inliber.acp.disconnect", { clear = false }),
    callback = function()
      pcall(function()
        return self:disconnect()
      end)
    end,
  })

  return true
end

---Authenticate the connection via adapter hook or agent auth methods
---@return boolean success
function Connection:_authenticate()
  -- Allow adapters to handle authentication themselves
  if
    not self._authenticated
    and self.adapter_modified
    and self.adapter_modified.handlers
    and self.adapter_modified.handlers.auth
  then
    local ok, result = pcall(self.adapter_modified.handlers.auth, self.adapter_modified)
    if not ok then
      log:error("[acp::_authenticate] Adapter auth hook failed: %s", result)
      return false
    end
    if result == true then
      self._authenticated = true
    end
  end

  -- Authenticate only if agent supports it (authMethods not empty)
  if not self._authenticated then
    local auth_methods = (self._agent_info and self._agent_info.authMethods) or {}
    if #auth_methods > 0 then
      local wanted = self.adapter_modified.defaults.auth_method
      local method_id
      local available_method_ids = {}
      for _, m in ipairs(auth_methods) do
        table.insert(available_method_ids, m.id)
        if m.id == wanted then
          method_id = m.id
          break
        end
      end

      if wanted and not method_id then
        log:error(
          "[acp::_authenticate] Auth method %s is not advertised by the agent; available methods: %s",
          wanted,
          table.concat(available_method_ids, ", ")
        )
        return false
      end
      method_id = method_id or (auth_methods[1] and auth_methods[1].id)

      if method_id then
        local ok = self:send_rpc_request(METHODS.AUTHENTICATE, { methodId = method_id })
        if not ok then
          log:error("[acp::_authenticate] Failed to authenticate with method %s", method_id)
          return false
        end
      end
    end
    self._authenticated = true
  end

  log:debug("[acp] Authenticated")
  return true
end

---Discard any current session and create a fresh one
---@return boolean success
function Connection:renew_session()
  self.session_id = nil
  -- session/new can take seconds, and a second caller arriving before the reply
  -- would create a second session whose id then replaces the one being prompted
  return self:_run_once({
    key = "session",
    work = function()
      return self:_establish_session()
    end,
  })
end

---Create a fresh session
---@return boolean success
function Connection:_establish_session()
  local defaults = self.adapter_modified and self.adapter_modified.defaults or {}
  local session_args = {
    cwd = vim.fn.getcwd(),
    mcpServers = defaults.mcpServers or {},
  }

  local new_session = self:send_rpc_request(METHODS.SESSION_NEW, session_args)
  if not new_session or not new_session.sessionId then
    log:error("[acp::_establish_session] Failed to create session")
    return false
  end
  self.session_id = new_session.sessionId
  if new_session.configOptions then
    self:_apply_config_options(new_session.configOptions)
    log:debug("[acp::_establish_session] New session config options applied")
  end

  log:debug("[acp] Session established: %s", self.session_id)
  return true
end

---Create the ACP process
---@return boolean success
function Connection:start_agent_process()
  local adapter = self:prepare_adapter()
  self.adapter_modified = adapter

  if adapter.handlers and adapter.handlers.setup then
    if not adapter.handlers.setup(adapter) then
      log:error("[acp::start_agent_process] Adapter setup failed")
      return false
    end
  end

  self._state.line_buffer:reset()

  self._rpc_log = log.new_response_file()
  log:info("[acp] RPC log: %s", self._rpc_log.path)

  local ok, sysobj = pcall(
    self.methods.job,
    self.adapter_modified.command,
    {
      stdin = true,
      cwd = vim.fn.getcwd(),
      env = adapter.env_replaced or {},
      stdout = self.methods.schedule_wrap(function(err, data)
        if err then
          log:error("[acp::start_agent_process::stdout] Error: %s", err)
        elseif data then
          self:buffer_stdout_and_dispatch(data)
        end
      end),
      stderr = self.methods.schedule_wrap(function(err, data)
        if err then
          log:error("[acp::start_agent_process::stderr] Error: %s", err)
        end
      end),
    },
    self.methods.schedule_wrap(function(obj)
      self:handle_process_exit(obj.code, obj.signal)
    end)
  )

  if not ok then
    log:error("[acp::start_agent_process] Failed: %s", sysobj)
    return false
  end

  self._state.handle = sysobj
  log:debug("[acp] Process started: %s", table.concat(self.adapter_modified.command, " "))
  return true
end

---If called inside an async coroutine, yields until the response arrives, or fallback to sync
---@param method string
---@param params table
---@return table|nil
function Connection:send_rpc_request(method, params)
  if not self._state.handle then
    return nil
  end

  local id = self._state.id_gen:next()
  local request = jsonrpc.request(id, method, params)

  if not self:write_message(self.methods.encode(request) .. "\n") then
    return nil
  end

  -- Async path: yield and let store_rpc_response resume us
  if coroutine.running() then
    return async.wait(function(callback)
      self._pending_callbacks[id] = callback
    end)
  end

  -- Sync fallback
  return self:wait_for_rpc_response(id)
end

---Send a result response to the ACP process
---@param id number
---@param result table
---@return nil
function Connection:send_result(id, result)
  self:write_message(self.methods.encode(jsonrpc.result(id, result)) .. "\n")
end

---Send an error response to the ACP process
---@param id number
---@param message string
---@param code? number
---@return nil
function Connection:send_error(id, message, code)
  self:write_message(self.methods.encode(jsonrpc.error(id, message, code or jsonrpc.errors.INTERNAL)) .. "\n")
end

---Wait for a specific response ID
---@param id number
---@return nil
function Connection:wait_for_rpc_response(id)
  local start_time = uv.hrtime()
  local defaults = (self.adapter_modified and self.adapter_modified.defaults) or {}
  local timeout = (defaults.timeout or TIMEOUTS.DEFAULT) * 1e6 -- Nanoseconds to milliseconds

  while uv.hrtime() - start_time < timeout do
    vim.wait(TIMEOUTS.RESPONSE_POLL)

    if self.pending_responses[id] then
      local result, err = unpack(self.pending_responses[id])
      self.pending_responses[id] = nil
      return err and nil or result
    end
  end

  log:error("[acp::wait_for_rpc_response] Request timeout ID %s", id)
  return nil
end

---Setup the adapter, making a copy and setting environment variables
---@return Inliber.ACPAdapter
function Connection:prepare_adapter()
  local adapter = vim.deepcopy(self.adapter)
  adapter = adapter_utils.get_env_vars(adapter, { timeout = config.adapters.opts.cmd_timeout })
  adapter.parameters = adapter_utils.set_env_vars(adapter, adapter.parameters)
  adapter.defaults.auth_method = adapter_utils.set_env_vars(adapter, adapter.defaults.auth_method)
  adapter.defaults.mcpServers = adapter_utils.set_env_vars(adapter, adapter.defaults.mcpServers)
  adapter.command = adapter_utils.set_env_vars(adapter, adapter.commands.selected or adapter.commands.default)

  return adapter
end

---Disconnect and clean up the ACP process
---@return nil
function Connection:disconnect()
  assert(self._state.handle):kill("sigterm")
end

---Process the output
---@param data string
function Connection:buffer_stdout_and_dispatch(data)
  -- JSON-RPC doesn't guarantee message boundaries align with I/O boundaries
  -- so we need to buffer and handle this carefully.
  self._state.line_buffer:push(data, function(line)
    self:handle_rpc_message(line)
  end)
end

---Handle incoming JSON message
---@param line string
function Connection:handle_rpc_message(line)
  if not line or line == "" then
    return
  end

  -- If it doesn't look like JSON-RPC, skip it
  if not line:match("^%s*{") then
    return
  end

  if self._rpc_log then
    self._rpc_log.write("Received:\n" .. line)
  end

  local ok, message = jsonrpc.decode(line, self.methods.decode)
  if not ok then
    return log:error("[acp::handle_rpc_message] Invalid JSON:\n%s", line)
  end

  if message.id and not message.method then
    self:store_rpc_response(message)
    if message.result and message.result ~= vim.NIL and message.result.stopReason then
      if self._active_prompt and self._active_prompt._request_id == message.id and self._active_prompt.handle_done then
        self._active_prompt:handle_done(message.result.stopReason)
      end
    end
  elseif message.method then
    self:handle_incoming_request_or_notification(message)
  else
    log:error("[acp::handle_rpc_message] Invalid message format: %s", message)
  end

  if message.error and message.error.code ~= jsonrpc.errors.INTERNAL then
    log:error("[acp::handle_rpc_message] Error: %s", message.error)
  end
end

---Handles the response to the request
---@param response table
function Connection:store_rpc_response(response)
  local function forward_error_to_prompt()
    if not response.error or not self._active_prompt or not self._active_prompt.handle_error then
      return
    end
    self.methods.schedule(function()
      local error_msg = response.error.message or "Unknown error"
      if response.error.data and response.error.data.error then
        error_msg = response.error.data.error
      end
      self._active_prompt:handle_error(error_msg)
    end)
  end

  -- Async path: resume the waiting coroutine via its callback
  local cb = self._pending_callbacks[response.id]
  if cb then
    self._pending_callbacks[response.id] = nil
    self.methods.schedule(function()
      cb((not response.error) and response.result or nil)
    end)
    return forward_error_to_prompt()
  end

  -- Sync path: store for polling
  if response.error then
    self.pending_responses[response.id] = { nil, response.error }
    return forward_error_to_prompt()
  end
  self.pending_responses[response.id] = { response.result, nil }
end

---Send a notification to the ACP process
---@param method string
---@param params table
---@return nil
function Connection:send_notification(method, params)
  self:write_message(self.methods.encode(jsonrpc.notification(method, params)) .. "\n")
end

---@private
local DISPATCH = {
  [METHODS.SESSION_UPDATE] = function(self, m)
    if m.params.update and m.params.update.sessionUpdate == "available_commands_update" then
      self:handle_available_commands_update(m.params.sessionId, m.params.update.availableCommands)
    elseif m.params.update and m.params.update.sessionUpdate == "config_option_update" then
      self:handle_config_option_update(m.params.sessionId, m.params.update.configOptions)
    elseif self._active_prompt then
      self._active_prompt:handle_session_update(m.params.update)
    end
  end,
  [METHODS.SESSION_REQUEST_PERMISSION] = function(self, m)
    if self._active_prompt then
      self._active_prompt:handle_permission_request(m.id, m.params)
    end
  end,
  [METHODS.FS_READ_TEXT_FILE] = function(self, m)
    self:handle_fs_read_text_file_request(m.id, m.params)
  end,
  [METHODS.FS_WRITE_TEXT_FILE] = function(self, m)
    self:handle_fs_write_file_request(m.id, m.params)
  end,
}

---Handle incoming requests and notifications from the ACP agent process
---@param notification? table
function Connection:handle_incoming_request_or_notification(notification)
  if type(notification) ~= "table" or type(notification.method) ~= "string" then
    return
  end

  local sid = notification.params and notification.params.sessionId
  local is_request = notification.id ~= nil
  if sid and self.session_id and sid ~= self.session_id then
    if is_request then
      return self:send_error(notification.id, "invalid sessionId", jsonrpc.errors.INVALID_PARAMS)
    end
    return
  end

  local handler = DISPATCH[notification.method]
  if handler then
    return handler(self, notification)
  end
end

---Send data to the ACP process
---@param data string
---@return boolean
function Connection:write_message(data)
  if not self._state.handle then
    log:error("[acp::write_message] Process not running")
    return false
  end

  if self._rpc_log then
    self._rpc_log.write("Sent:\n" .. vim.trim(data))
  end

  local ok, err = pcall(function()
    self._state.handle:write(data)
  end)

  if not ok then
    log:error("[acp::write_message] Failed to send data: %s", err)
    return false
  end

  return true
end

---Check if params target the active session
---@param params table
---@return boolean valid true if an active session exists and sessionId matches it
function Connection:_has_valid_session_id(params)
  return self.session_id ~= nil and params.sessionId == self.session_id
end

---Handle fs/read_text_file requests
---@param id number
---@param params { path: string, sessionId?: string, limit?: number|nil, line?: number|nil }
---@return nil
function Connection:handle_fs_read_text_file_request(id, params)
  if not id or type(params) ~= "table" then
    return
  end

  if not self:_has_valid_session_id(params) then
    return self:send_error(id, "invalid sessionId for fs/read_text_file", jsonrpc.errors.INVALID_PARAMS)
  end

  local path = params.path
  if type(path) ~= "string" then
    return self:send_error(id, "invalid params", jsonrpc.errors.INVALID_PARAMS)
  end

  -- One-shot sessions strip the fs capability, but the agent may ignore that hint
  local caps = self.adapter.parameters and self.adapter.parameters.clientCapabilities
  if not (caps and caps.fs and caps.fs.readTextFile) then
    return self:send_error(id, "fs/read_text_file not supported", jsonrpc.errors.METHOD_NOT_FOUND)
  end

  local fs = require("inliber.acp.fs")
  local ok, content = fs.read_text_file(path, { line = params.line, limit = params.limit })
  if ok then
    return self:send_result(id, { content = content })
  end

  -- If the file does not exist we treat it as empty so the agent can create it
  local errstr = tostring(content)
  if errstr:find("ENOENT", 1, true) then
    self:send_result(id, { content = "" })
    return
  end

  self:send_error(id, ("fs/read_text_file failed: %s"):format(errstr))
end

---Handle fs/write_text_file requests
---We carry this out here as they could arrive outside of the standard prompt flow
---@param id number
---@param params { path: string, content: string, sessionId?: string }
function Connection:handle_fs_write_file_request(id, params)
  if not id or type(params) ~= "table" then
    return
  end

  if not self:_has_valid_session_id(params) then
    return self:send_error(id, "invalid sessionId for fs/write_text_file", jsonrpc.errors.INVALID_PARAMS)
  end

  local path = params.path
  local content = params.content or ""
  if type(path) ~= "string" or type(content) ~= "string" then
    return self:send_error(id, "invalid params", jsonrpc.errors.INVALID_PARAMS)
  end

  -- One-shot sessions strip the fs capability, but the agent may ignore that hint
  local caps = self.adapter.parameters and self.adapter.parameters.clientCapabilities
  if not (caps and caps.fs and caps.fs.writeTextFile) then
    return self:send_error(id, "fs/write_text_file not supported", jsonrpc.errors.METHOD_NOT_FOUND)
  end

  local fs = require("inliber.acp.fs")
  local ok, err = fs.write_text_file(path, content)
  if ok then
    self:send_result(id, vim.NIL)
    local info = { path = path, bytes = #content, sessionId = params.sessionId }
    if self._active_prompt and self._active_prompt.handlers and self._active_prompt.handlers.write_text_file then
      pcall(self._active_prompt.handlers.write_text_file, info)
    end
  else
    self:send_error(id, ("fs/write_text_file failed: %s"):format(err or "unknown"))
  end
end

---Handle available_commands_update (Slash Commands)
---Ref: https://agentclientprotocol.com/protocol/slash-commands
---@param session_id string
---@param commands ACP.availableCommands
---@return nil
function Connection:handle_available_commands_update(session_id, commands)
  if not session_id then
    return
  end

  if type(commands) ~= "table" then
    return log:error("[acp::handle_available_commands_update] Invalid commands format")
  end

  self._available_commands = commands
  log:debug("[acp::handle_available_commands_update] Agent advertised %d commands", vim.tbl_count(commands))
end

---Store raw configOptions from the agent
---@param config_options table[] Array of SessionConfigOption
function Connection:_apply_config_options(config_options)
  self._config_options = config_options
end

---Find a config option by category
---@param category string
---@return table|nil
function Connection:_find_config_option(category)
  for _, opt in ipairs(self._config_options) do
    if opt.category == category and opt.type == "select" then
      return opt
    end
  end
end

---Handle config_option_update notification
---@param session_id string
---@param config_options table[]|nil
---@return nil
function Connection:handle_config_option_update(session_id, config_options)
  if not session_id or session_id ~= self.session_id then
    return
  end
  if type(config_options) == "table" then
    self:_apply_config_options(config_options)
  end
end

---Handle process exit
---@param code number
---@param signal number
function Connection:handle_process_exit(code, signal)
  log:debug("[acp] Process exited (code=%s, signal=%s)", code, signal)

  if self.adapter_modified and self.adapter_modified.handlers and self.adapter_modified.handlers.on_exit then
    self.adapter_modified.handlers.on_exit(self.adapter_modified, code)
  end

  -- Fire any pending async callbacks so coroutines don't hang
  for id, cb in pairs(self._pending_callbacks) do
    self._pending_callbacks[id] = nil
    pcall(cb, nil)
  end

  -- Always clean up state
  self.adapter_modified = nil
  self._authenticated = false
  self._initialized = false
  self._pending_callbacks = {}
  self.pending_responses = {}
  self.session_id = nil

  if self._active_prompt and self._active_prompt.handle_done then
    pcall(function()
      self._active_prompt:handle_done("canceled")
    end)
  end
  self._active_prompt = nil
end

---Initiate a prompt
---@param messages table
---@return Inliber.ACP.PromptBuilder
function Connection:session_prompt(messages)
  if not self.session_id then
    return log:error("[acp::session_prompt] Connection not established. Create a session first.")
  end
  return PromptBuilder.new(self, messages)
end

---Get the available models
---@return table|nil models {currentModelId: string, availableModels: table[]} or nil
function Connection:get_models()
  local opt = self:_find_config_option("model")
  if not opt then
    return nil
  end

  local available = vim.tbl_map(function(val)
    return { modelId = val.value, name = val.name }
  end, Connection.flatten_config_options(opt.options or {}))

  return {
    availableModels = available,
    currentModelId = opt.currentValue,
  }
end

---Set a model via session/set_config_option
---@param model_id string
---@return boolean success
function Connection:set_model(model_id)
  local opt = self:_find_config_option("model")
  if not opt then
    log:error("[acp::set_model] Agent does not support changing models")
    return false
  end

  return self:set_config_option(opt.id, model_id)
end

---Get all config options, optionally excluding certain categories
---@param opts? { exclude_categories?: string[] }
---@return table[] Array of SessionConfigOption
function Connection:get_config_options(opts)
  opts = opts or {}
  if not opts.exclude_categories then
    return self._config_options or {}
  end

  local exclude = {}
  for _, category in ipairs(opts.exclude_categories) do
    exclude[category] = true
  end

  return vim.tbl_filter(function(opt)
    return not exclude[opt.category]
  end, self._config_options or {})
end

---Set a config option via session/set_config_option
---@param config_id string The config option ID
---@param value string The value ID to set
---@return boolean success
function Connection:set_config_option(config_id, value)
  if not self.session_id then
    log:error("[acp::set_config_option] Connection not established")
    return false
  end

  -- Ref: https://agentclientprotocol.com/protocol/session-config-options#from-the-client
  local result = self:send_rpc_request(METHODS.SESSION_SET_CONFIG_OPTION, {
    sessionId = self.session_id,
    configId = config_id,
    value = value,
  })

  if not result then
    log:error("[acp::set_config_option] Failed to set %s to %s", config_id, value)
    return false
  end

  if result.configOptions then
    self:_apply_config_options(result.configOptions)
  end

  log:debug("[acp::set_config_option] Changed %s to %s", config_id, value)
  return true
end

---Flatten session config options
---@param opts table[]
---@return table[]
function Connection.flatten_config_options(opts)
  return vim
    .iter(opts)
    :map(function(item)
      -- The ACP specification allows options to be grouped
      -- Ref: https://agentclientprotocol.com/protocol/schema#sessionconfigselectgroup
      if item.group then
        return vim.tbl_map(function(val)
          return vim.tbl_extend("force", val, { group = item.name })
        end, item.options or {})
      end
      return { item }
    end)
    :flatten()
    :totable()
end

return Connection
