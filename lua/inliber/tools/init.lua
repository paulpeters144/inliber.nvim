--[[
The Tool Loop - A headless host that runs the agentic submit → tool-call →
execute → re-submit cycle until the LLM produces its final answer. It owns the
message list and implements the Inliber.Tools.Host interface that the
tool engine, orchestrator and registry depend on.
--]]

local adapter_utils = require("inliber.adapters.utils")
local adapters = require("inliber.adapters")
local approvals = require("inliber.tools.approvals")
local client = require("inliber.http")
local config = require("inliber.config")
local context_helpers = require("inliber.tools.helpers.context")
local hash = require("inliber.utils.hash")
local log = require("inliber.utils.log")
local tags = require("inliber.interactions.shared.tags")
local tokens = require("inliber.utils.tokens")

---@class Inliber.ToolLoop
---@field id number The loop id; the approvals key for the loop
---@field adapter Inliber.HTTPAdapter The adapter running the loop
---@field bufnr number The buffer the loop was started from, used for context
---@field callbacks { on_completed: fun(loop: Inliber.ToolLoop, result: table), on_cancelled: fun(), on_status?: fun(tool_name: string?, status: string, label?: string) }
---@field context Inliber.ToolLoop.Context A minimal store for tool context items
---@field current_request? table The in-flight request
---@field cycle number The number of submit cycles that have run
---@field engine Inliber.Tools The tool-execution engine
---@field messages table The message list for the LLM
---@field registry Inliber.Tools.Registry The tools available to the loop
---@field status string The status of the loop
---@field structured_output? Inliber.StructuredOutput.Schema The JSON schema the LLM's final text must match
---@field tokens? number|table The tokens reported by the adapter
---@field tool_orchestrator? Inliber.Tools.Orchestrator Coordinates running tools

---@class Inliber.ToolLoopArgs
---@field adapter Inliber.HTTPAdapter
---@field approval_mode? Inliber.Tools.ApprovalMode
---@field bufnr? number The buffer the loop is started from
---@field callbacks { on_completed: fun(loop: Inliber.ToolLoop, result: table), on_cancelled: fun(), on_status?: fun(tool_name: string?, status: string, label?: string) }
---@field messages table The messages to seed the loop
---@field structured_output? Inliber.StructuredOutput.Schema Constrain the LLM's final text to this JSON schema

---@class Inliber.Tools.Host
---@field id number The loop id
---@field adapter Inliber.HTTPAdapter The adapter in use
---@field messages table The message list the engine mutates
---@field registry Inliber.Tools.Registry The tool registry for this loop
---@field add_tool_output fun(self: Inliber.Tools.Host, tool: table, for_llm: string, for_user?: string) Append a tool result to the messages
---@field add_message fun(self: Inliber.Tools.Host, data: table, opts?: table) Append a message
---@field set_system_prompt fun(self: Inliber.Tools.Host, content: string, opts?: table) Set or replace the system prompt
---@field remove_tagged_message fun(self: Inliber.Tools.Host, tag: string) Remove messages by tag
---@field make_system_prompt_context fun(self: Inliber.Tools.Host): Inliber.SystemPrompt.Context Build the system-prompt context
---@field resubmit fun(self: Inliber.Tools.Host) Re-submit after tools finish
---@field report_status fun(self: Inliber.Tools.Host, tool_name: string, status: string, label?: string) Report tool progress

local CONSTANTS = {
  STATUS_CANCELLING = "cancelling",
  STATUS_ERROR = "error",
  STATUS_SUCCESS = "success",

  INCOMPLETE_TOOL_CALL = "This tool call did not complete and produced no result",
}

---@class Inliber.ToolLoop
local ToolLoop = {}

---A minimal context store. The chat buffer tracked context items for its UI
---and watchers; the headless loop only needs to add context items.
---@class Inliber.ToolLoop.Context
---@field items table
local Context = {}

---@return Inliber.ToolLoop.Context
local function new_context()
  return setmetatable({ items = {} }, { __index = Context })
end

---@param item table
---@return nil
function Context:add(item)
  table.insert(self.items, item)
end

---Check if any message carries a given tag
---@param tag string
---@param messages table
---@return boolean
local function has_tag(tag, messages)
  for _, msg in ipairs(messages) do
    if msg._meta and msg._meta.tag == tag then
      return true
    end
  end
  return false
end

---Find a message that holds the result for a specific tool call ID
---@param id string
---@param messages table
---@return table|nil
local function find_tool_call(id, messages)
  for _, msg in ipairs(messages) do
    if msg.tools and msg.tools.call_id and msg.tools.call_id == id then
      return msg
    end
  end
  return nil
end

---Turn a failed request's reason into text passed to on_completed
---@param reason string|table
---@return string
local function describe_error(reason)
  if type(reason) == "table" then
    return reason.body or vim.inspect(reason)
  end
  return reason
end

---@param opts Inliber.ToolLoopArgs
---@return Inliber.ToolLoop|nil
function ToolLoop.new(opts)
  log:trace("[ToolLoop] Initiating with messages: %s", opts.messages)

  local id = math.random(10000000)

  local self = setmetatable({
    id = id,
    adapter = opts.adapter,
    bufnr = opts.bufnr or 0,
    callbacks = opts.callbacks,
    context = new_context(),
    cycle = 1,
    messages = opts.messages or {},
    status = CONSTANTS.STATUS_SUCCESS,
    structured_output = opts.structured_output,
  }, { __index = ToolLoop })

  if opts.approval_mode then
    approvals:set_mode(id, { mode = opts.approval_mode })
  end

  self.registry = require("inliber.tools.registry").new({
    host = self,
    ctx = self:make_system_prompt_context(),
  })
  self.engine = require("inliber.tools.engine").new({ adapter = self.adapter, id = id })

  return self
end

---Register a tool (or group) with the loop's registry
---@param name string The tool or group name
---@param opts? { config: table, visible: boolean }
---@return nil
function ToolLoop:add_tool(name, opts)
  self.registry:add(name, opts)
end

---Add a message to the message list
---@param data { role: string, content: string, reasoning?: table, tool_calls?: table }
---@param opts? table
---@return Inliber.ToolLoop
function ToolLoop:add_message(data, opts)
  opts = opts or { visible = true }
  if opts.visible == nil then
    opts.visible = true
  end

  local message = {
    role = data.role,
    content = data.content,
    reasoning = data.reasoning,
    _meta = {
      id = 1,
      cycle = self.cycle,
      estimated_tokens = type(data.content) == "string" and tokens.calculate(data.content) or nil,
    },
  }

  if data.tool_calls then
    message.tools = message.tools or {}
    message.tools.calls = data.tool_calls
  end

  if opts._meta then
    message._meta = vim.tbl_deep_extend("force", message._meta, opts._meta)
    opts._meta = nil
  end
  if opts.context then
    message.context = opts.context
    opts.context = nil
  end

  message.opts = opts
  message._meta.id = hash.hash(message)

  if message._meta.index then
    table.insert(self.messages, message._meta.index, message)
  else
    message._meta.index = #self.messages + 1
    table.insert(self.messages, message)
  end

  return self
end

---Set the system prompt in the message list
---@param prompt? string|fun(ctx: Inliber.SystemPrompt.Context): string
---@param opts? { opts: table, _meta: table }
---@return Inliber.ToolLoop
function ToolLoop:set_system_prompt(prompt, opts)
  prompt = prompt or ""
  opts = opts or { visible = false }

  local _meta = { tag = tags.SYSTEM_PROMPT_FROM_CONFIG }
  if opts._meta then
    _meta = opts._meta
    opts._meta = nil
  end

  if has_tag(_meta.tag, self.messages) then
    self:remove_tagged_message(_meta.tag)
  end

  if not _meta.index then
    for i = #self.messages, 1, -1 do
      if self.messages[i].role == config.constants.SYSTEM_ROLE then
        _meta.index = i + 1
        break
      end
    end
  end

  if prompt ~= "" then
    if type(prompt) == "function" then
      prompt = prompt(self:make_system_prompt_context())
    end

    local system_prompt = {
      role = config.constants.SYSTEM_ROLE,
      content = prompt,
    }
    system_prompt.opts = opts

    _meta.cycle = self.cycle
    _meta.id = hash.hash(system_prompt)
    _meta.index = _meta.index or 1
    _meta.estimated_tokens = tokens.calculate(prompt)
    system_prompt._meta = _meta

    table.insert(self.messages, _meta.index, system_prompt)
  end

  return self
end

---Remove messages with a given tag
---@param tag string
---@return nil
function ToolLoop:remove_tagged_message(tag)
  local kept = {}
  for _, msg in ipairs(self.messages) do
    if not (msg._meta and msg._meta.tag == tag) then
      kept[#kept + 1] = msg
    end
  end
  self.messages = kept
end

---Build the context that system prompts are evaluated against
---@return Inliber.SystemPrompt.Context
function ToolLoop:make_system_prompt_context()
  local dynamic_ctx = {
    adapter = function()
      return adapters.make_safe(self.adapter)
    end,
    os = function()
      local machine = vim.uv.os_uname().sysname
      if machine == "Darwin" then
        machine = "Mac"
      end
      if machine:find("Windows") then
        machine = "Windows"
      end
      return machine
    end,
  }

  local bufnr = self.bufnr > 0 and self.bufnr or vim.api.nvim_get_current_buf()
  local static_ctx = { ---@type Inliber.SystemPrompt.Context|{}
    cwd = vim.fn.getcwd(),
    date = tostring(os.date(config.interactions.opts.date_format)),
    language = config.opts.language or "English",
    nvim_version = vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch,
    project_root = vim.fs.root(bufnr, { ".git", ".svn", "hg" }),
  }

  ---@type Inliber.SystemPrompt.Context
  return setmetatable(static_ctx, {
    __index = function(_, key)
      local val = dynamic_ctx[key]
      if type(val) == "function" then
        return val()
      end
      return val
    end,
  })
end

---Add the output from a tool to the message history
---@param tool table The Tool that was executed
---@param for_llm string The output to share with the LLM
---@param for_user? string Unused in the headless loop; kept for interface parity
---@return nil
function ToolLoop:add_tool_output(tool, for_llm, for_user)
  local tool_call = tool.function_call
  log:debug("[ToolLoop] Tool output: %s", tool_call)

  local output = adapters.call_handler(self.adapter, "format_response", tool_call, for_llm)
  if not output then
    return log:error("[ToolLoop] Adapter does not support tool response formatting")
  end

  output._meta = { cycle = self.cycle }
  output._meta.id = hash.hash({ role = output.role, content = output.content })
  output.opts = vim.tbl_extend("force", output.opts or {}, {
    visible = true,
  })

  -- Ensure that tool output is merged if it has the same tool call ID
  local existing = find_tool_call(tool_call.id, self.messages)
  if existing then
    if existing.content ~= "" then
      existing.content = existing.content .. "\n\n" .. output.content
    else
      existing.content = output.content
    end
    output = existing
  else
    table.insert(self.messages, output)
  end

  -- Truncate after merging so that a tool emitting many small chunks is caught too
  output.content = context_helpers.truncate_tool_output({ adapter = self.adapter, content = output.content })
  output._meta = vim.tbl_extend("force", output._meta or {}, {
    estimated_tokens = tokens.calculate(output.content),
  })
end

---Report tool progress. Forwards to the on_status callback, if one was given
---@param tool_name string
---@param status string
---@param label? string
---@return nil
function ToolLoop:report_status(tool_name, status, label)
  if self.callbacks.on_status then
    self.callbacks.on_status(tool_name, status, label)
  end
end

---Find tool calls in messages that are missing matching results
---@return table<string, table> Map of pairing_id to the call object
function ToolLoop:_orphaned_tool_calls()
  local pending = {}

  for _, msg in ipairs(self.messages) do
    if msg.tools and msg.tools.calls then
      for _, call in ipairs(msg.tools.calls) do
        local pairing_id = adapter_utils.pairing_id(call)
        if pairing_id then
          pending[pairing_id] = call
        end
      end
    end
    if msg.tools and msg.tools.call_id then
      pending[msg.tools.call_id] = nil
    end
  end

  return pending
end

---Prevent any orphaned tool calls by "completing" them with a stand-in result
---@param opts? { reason?: string }
---@return nil
function ToolLoop:_complete_orphaned_tool_calls(opts)
  local pending = self:_orphaned_tool_calls()
  if next(pending) == nil then
    return
  end

  local reason = opts and opts.reason or "Cancelled by user"
  for id, call in pairs(pending) do
    local output = adapters.call_handler(self.adapter, "format_response", call, reason)
    if output then
      output.opts = vim.tbl_extend("force", output.opts or {}, { visible = false })
      output._meta = {
        cycle = self.cycle,
        id = hash.hash({ call_id = id, content = output.content, role = output.role }),
      }
      table.insert(self.messages, output)
      log:debug("[ToolLoop] Completed orphaned tool call result for tool call %s", id)
    end
  end
end

---Run the agentic loop until the LLM produces its final answer
---@param opts? { auto_submit?: boolean }
---@return nil
function ToolLoop:submit(opts)
  if self.current_request then
    return log:debug("[ToolLoop] Request already in progress")
  end

  opts = opts or {}

  if opts.auto_submit then
    self:_complete_orphaned_tool_calls({ reason = CONSTANTS.INCOMPLETE_TOOL_CALL })
  end

  self.engine:refresh({ adapter = self.adapter })

  -- Shallow-copy each message so map_roles can mutate role without affecting self.messages
  local shallow_messages = {}
  for i, msg in ipairs(self.messages) do
    local copy = {}
    for k, v in pairs(msg) do
      copy[k] = v
    end
    shallow_messages[i] = copy
  end

  local payload = {
    messages = self.adapter:map_roles(shallow_messages),
    tools = (not vim.tbl_isempty(self.registry.schemas) and { self.registry.schemas } or {}),
    structured_output = self.structured_output,
  }

  log:trace("[ToolLoop] Messages:\n%s", payload.messages)
  log:trace("[ToolLoop] Tools:\n%s", payload.tools)

  local adapter = self.adapter
  local output, reasoning, tools, meta = {}, {}, {}, {}

  local function process_chunk(data)
    if adapter.features.tokens then
      local token_count = adapters.call_handler(adapter, "parse_tokens", data)
      if token_count then
        self.tokens = token_count
      end
    end

    local result = adapters.call_handler(adapter, "parse_chat", data, tools)
    local parse_meta = adapters.get_handler(adapter, "parse_meta")
    if result and result.extra and type(parse_meta) == "function" then
      result = parse_meta(adapter, result)
    end

    if result and result.status then
      self.status = result.status
      if self.status == CONSTANTS.STATUS_SUCCESS then
        if result.output.reasoning then
          table.insert(reasoning, result.output.reasoning)
        end
        if result.output.meta then
          meta = vim.tbl_deep_extend("force", meta, result.output.meta)
        end
        if result.output.content then
          table.insert(output, result.output.content)
        end
      elseif self.status == CONSTANTS.STATUS_ERROR then
        log:error("[ToolLoop] Error: %s", result.output)
        self:_on_done(output, nil, nil, nil, { error = describe_error(result.output) })
      end
    end
  end

  local handle = client.new({ adapter = adapter:map_schema_to_params() }):send(payload, {
    on_chunk = function(data)
      process_chunk(data)
    end,
    on_done = function(data)
      if data and not adapter.opts.stream then
        process_chunk(data)
      end
      self:_on_done(output, reasoning, tools, meta)
    end,
    on_error = function(err)
      if self.status == CONSTANTS.STATUS_CANCELLING then
        return
      end
      self.status = CONSTANTS.STATUS_ERROR
      local reason = (err and (err.stderr or err.message)) or "unknown"
      log:error("[ToolLoop] Error: %s", reason)
      self:_on_done(output, nil, nil, nil, { error = describe_error(reason) })
    end,
    interaction = "inline",
  })

  self.current_request = handle
end

---Re-submit the loop after tools have finished
---@return nil
function ToolLoop:resubmit()
  self.cycle = self.cycle + 1
  return self:submit({ auto_submit = true })
end

---Called by the engine when tools finish without an automatic re-submit
---@param opts? { auto_submit?: boolean }
---@return nil
function ToolLoop:tools_done(opts)
  opts = opts or {}
  if opts.auto_submit then
    return
  end
  -- The headless loop cannot wait for user input, so finish with what we have
  self:_finish({ error = "The tool loop ended before the LLM gave a final answer" })
end

---Method to call after the response from the LLM is received
---@param output? table The message output from the LLM
---@param reasoning? table The reasoning output from the LLM
---@param tools? table The tools output from the LLM
---@param meta? table Any metadata from the LLM
---@param opts? { error?: string }
---@return nil
function ToolLoop:_on_done(output, reasoning, tools, meta, opts)
  opts = opts or {}
  self.current_request = nil

  local has_output = output and not vim.tbl_isempty(output)
  local has_tools = tools and not vim.tbl_isempty(tools)

  local content
  if has_output then
    content = vim.trim(table.concat(output, ""))
  end

  local reasoning_content = nil
  if reasoning and not vim.tbl_isempty(reasoning) then
    if vim.iter(reasoning):any(function(item)
      return item and type(item) ~= "string"
    end) then
      reasoning_content = adapters.call_handler(self.adapter, "build_reasoning", reasoning)
    else
      reasoning_content = table.concat(reasoning, "")
    end
  end

  if content and content ~= "" then
    self:add_message({
      role = config.constants.LLM_ROLE,
      content = content,
      reasoning = reasoning_content,
    })
    reasoning_content = nil
  end

  -- Process tools last
  if has_tools then
    tools = adapters.call_handler(self.adapter, "format_calls", tools)
    if tools then
      self:add_message({
        role = config.constants.LLM_ROLE,
        reasoning = reasoning_content,
        tool_calls = tools,
      }, { visible = false })
      return self.engine:execute(self, tools)
    end
  end

  self:_finish({ error = opts.error })
end

---End the loop, handing the result to the on_completed callback
---@param opts? { error?: string }
---@return nil
function ToolLoop:_finish(opts)
  opts = opts or {}
  if self.callbacks.on_status then
    self.callbacks.on_status(nil, "done")
  end
  self.callbacks.on_completed(self, {
    status = opts.error and CONSTANTS.STATUS_ERROR or CONSTANTS.STATUS_SUCCESS,
    error = opts.error,
  })
end

---Returns the LLM's final message content from the loop
---@return string|nil
function ToolLoop:last_llm_message()
  for i = #self.messages, 1, -1 do
    local message = self.messages[i]
    if message.role == config.constants.LLM_ROLE and message.content and message.content ~= "" then
      return vim.trim(message.content)
    end
  end
  return nil
end

---Stop the loop: cancel the request and any running tools
---@return nil
function ToolLoop:stop()
  self.status = CONSTANTS.STATUS_CANCELLING

  if self.current_request then
    self.current_request.cancel()
    self.current_request = nil
  end

  if self.tool_orchestrator then
    self.tool_orchestrator:cancel()
    self.tool_orchestrator = nil
  end

  approvals:reset(self.id)
  self.callbacks.on_cancelled()
end

---Close the loop and release its resources
---@return nil
function ToolLoop:close()
  approvals:reset(self.id)
  self.messages = {}
  self.registry:clear()
end

return ToolLoop
