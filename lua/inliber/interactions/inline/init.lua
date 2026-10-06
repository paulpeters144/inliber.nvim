--[[
The Inline Interaction - This is where code is applied directly to a Neovim buffer
--]]

---@class Inliber.Inline
---@field id number The ID of the inline prompt
---@field adapter Inliber.HTTPAdapter The adapter to use for the inline prompt
---@field ask_float? Inliber.AskFloat The persistent float holding the ask conversation
---@field input_modal? Inliber.InputModal The input modal collecting the prompt
---@field aug number The ID for the autocmd group
---@field buffer_context Inliber.BufferContext
---@field bufnr number The buffer number to apply the inline edits to
---@field current_asked_at? string The time the current question was asked
---@field current_question? string The question of the current ask turn
---@field current_request? table The current request that's being processed
---@field diff_ui? Inliber.DiffUI The diff UI instance
---@field intent "ask"|"edit" Whether the prompt answers a question or edits the buffer
---@field lines table Lines in the buffer before the inline changes
---@field messages table Non-system messages sent across the conversation
---@field opts table
---@field original_content? string[] The original buffer content before LLM changes
---@field pos? { line: number, col: number, bufnr: number } Where to place the generated code
---@field prompts table The prompts to send to the LLM
---@field spinner? Inliber.Spinner Progress feedback while the tool loop runs
---@field tool_loop? Inliber.ToolLoop The tool loop driving the request
---@field tokens? number The cumulative token count reported by the adapter
---@field turns table Rendered question/answer pairs for the ask float

---@class Inliber.InlineArgs
---@field adapter? Inliber.HTTPAdapter
---@field buffer_context? Inliber.BufferContext
---@field intent "ask"|"edit" Whether the prompt answers a question or edits the buffer
---@field lines? table The lines in the buffer before the inline changes
---@field opts? table
---@field pre_hook? fun():number Function to run before the inline prompt is started
---@field prompts? table The prompts to send to the LLM

local adapters = require("inliber.adapters")
local agent_commands = require("inliber.interactions.shared.agent_commands")
local agent_commands_providers = require("inliber.interactions.shared.agent_commands.providers")
local client = require("inliber.http")
local config = require("inliber.config")
local editor_context = require("inliber.interactions.inline.editor_context")
local keymaps = require("inliber.utils.keymaps")
local log = require("inliber.utils.log")
local markdown = require("inliber.utils.markdown")
local tokens = require("inliber.utils.tokens")
local utils = require("inliber.utils")

local api = vim.api
local fmt = string.format

local user_role = config.constants.USER_ROLE

local CONSTANTS = {
  AUTOCMD_GROUP = "inliber.inline",
  STATUS_ERROR = "error",
  STATUS_SUCCESS = "success",

  SYSTEM_PROMPT = [[You are a knowledgeable developer working in the Neovim text editor. You write %s code on behalf of a user, directly into their active Neovim buffer.

Your task:
- Carefully follow the user's prompt (enclosed in <prompt></prompt> tags).
- Use any provided code context to inform your response.
- Output only valid JSON as specified below.

Response schema:
%s

If you cannot answer, respond with a single-sentence reason in %s, enclosed in error tags:
{
  "error": "Reason for not being able to answer the prompt"
}

Rules:
- **CRITICAL**: ENSURE YOU PRESERVE THE EXACT INDENTATION (TABS/SPACES) as it appears in the provided code.
- Validate all code carefully.
- Adhere strictly to the JSON schema.
- Do not include markdown, code fences, or explanations.
- Include comments if appropriate for the language.
- Do not output anything except the JSON response]],

  SYSTEM_PROMPT_ASK = [[You are a knowledgeable developer working in the Neovim text editor. You answer the user's questions about the %s code in their active Neovim buffer.

Your task:
- Carefully follow the user's prompt (enclosed in <prompt></prompt> tags).
- Use any provided code context to inform your response.
- Output only valid JSON as specified below.

Response schema:
%s

If you cannot answer, respond with a single-sentence reason in %s, enclosed in error tags:
{
  "error": "Reason for not being able to answer the prompt"
}

Rules:
- NEVER write or modify code. Your job is only to answer the user's question.
- Adhere strictly to the JSON schema.
- Put your full answer to the user in the "message" field.
- Do not output anything except the JSON response]],

  RESPONSE_ASK = [[Return your answer in valid JSON matching this schema:

{
  "type": "object",
  "required": ["message"],
  "properties": {
    "message": { "type": "string" }
  },
  "additionalProperties": false
}

Example:

{
  "message": "Your full answer to the user's prompt."
}
]],

  -- Enforced via the adapter's structured outputs when using tools. `error` is
  -- optional so the LLM can still explain why it couldn't answer
  SCHEMA_ASK = {
    type = "object",
    required = { "message" },
    properties = {
      message = { type = "string" },
      error = { type = "string" },
    },
    additionalProperties = false,
  },

  SCHEMA_EDIT = {
    type = "object",
    required = { "code", "language", "placement" },
    properties = {
      code = { type = "string" },
      language = { type = "string" },
      placement = { type = "string", enum = { "replace", "add", "before", "new" } },
      error = { type = "string" },
    },
    additionalProperties = false,
  },

  RESPONSE_EDIT = [[Return your code and placement in valid JSON matching this schema:

{
  "type": "object",
  "required": ["code", "language", "placement"],
  "properties": {
    "code": { "type": "string" },
    "language": { "type": "string" },
    "placement": {
      "type": "string",
      "enum": ["replace", "add", "before", "new"],
      "description": "Where to place the code in Neovim."
    }
  },
  "additionalProperties": false
}

Placement options:
- "replace": Replace the user's current visual selection in the buffer with your code.
- "add": Insert your code after the user's current cursor position in the buffer.
- "before": Insert your code before the user's current cursor position in the buffer.
- "new": Create a new Neovim buffer and insert your code there.

Example:

{
  "code": "print('Hello World')",
  "language": "python",
  "placement": "replace"
}
]],
}

---Format code into a code block alongside a message
---@param message string
---@param filetype string
---@param code table
---@return string
local function code_block(message, filetype, code)
  return fmt(
    [[%s
<code>
%s
</code>]],
    message,
    markdown.form_codeblock(table.concat(code, "\n"), { ft = filetype })
  )
end

---Overwrite the given selection in the buffer with an empty string
---@param context table The buffer context in the inline class
local function overwrite_selection(context)
  log:trace("[Inline] Overwriting selection: %s", context)
  if context.start_col > 0 then
    context.start_col = context.start_col - 1
  end

  local line_length = #vim.api.nvim_buf_get_lines(context.bufnr, context.end_line - 1, context.end_line, true)[1]
  if context.end_col > line_length then
    context.end_col = line_length
  end

  -- NOTE: Ensure that focus is set to the correct buffer in case the user has navigated away
  api.nvim_set_current_buf(context.bufnr)
  api.nvim_buf_set_text(
    context.bufnr,
    context.start_line - 1,
    context.start_col,
    context.end_line - 1,
    context.end_col,
    { "" }
  )
  api.nvim_win_set_cursor(context.winnr, { context.start_line, context.start_col })
end

---@class Inliber.Inline
local Inline = {}

---@type Inliber.Inline|nil The last ask conversation retained for resume
local last_ask = nil

---Store an ask conversation for later resume
---@param inline Inliber.Inline
---@return nil
function Inline.remember(inline)
  last_ask = inline
end

---Retrieve the last remembered ask conversation
---@return Inliber.Inline|nil
function Inline.last_ask()
  return last_ask
end

---@param args Inliber.InlineArgs
function Inline.new(args)
  log:trace("[Inline] Initiating with args: %s", args)

  assert(args.intent == "ask" or args.intent == "edit", "[Inline] intent must be `ask` or `edit`")

  local id = math.random(10000000)

  local self = setmetatable({
    id = id,
    aug = api.nvim_create_augroup(CONSTANTS.AUTOCMD_GROUP .. ":" .. id, {
      clear = false,
    }),
    buffer_context = args.buffer_context,
    bufnr = args.buffer_context.bufnr,
    intent = args.intent,
    lines = {},
    messages = {},
    opts = args.opts or {},
    prompts = vim.deepcopy(args.prompts),
    turns = {},
  }, { __index = Inline })

  self:set_adapter(args.adapter or config.interactions.inline.adapter)
  if not self.adapter then
    return log:error("[Inline] No adapter found")
  end

  -- Check if the user has manually overridden the adapter
  if vim.g.inliber_adapter and self.adapter.name ~= vim.g.inliber_adapter then
    self:set_adapter(vim.g.inliber_adapter)
  end

  return self
end

---Set the adapter for the inline prompt
---@param adapter Inliber.HTTPAdapter|string|function
---@return nil
function Inline:set_adapter(adapter)
  if not self.adapter or not adapters.resolved(adapter) then
    self.adapter = adapters.resolve(adapter)
  end
end

---Resolve the agent-command provider named on the adapter, else the first provider with commands on disk
---@return Inliber.AgentCommands.Provider|nil
function Inline:_agent_commands_provider()
  if not config.interactions.inline.agent_commands.enabled then
    return nil
  end
  local provider = self.adapter and self.adapter.agent_commands and self.adapter.agent_commands.provider
  if provider then
    return agent_commands_providers.get(provider)
  end
  return agent_commands_providers.detect(self:_project_root())
end

---The directory to walk up from when discovering project agent commands
---@return string
function Inline:_project_root()
  local path = self.buffer_context and self.buffer_context.path
  if path and path ~= "" then
    return vim.fs.dirname(path)
  end
  return vim.uv.cwd()
end

---Options for the input modal's agent-command completion
---@return { provider?: Inliber.AgentCommands.Provider, root?: string }
function Inline:agent_command_opts()
  return { provider = self:_agent_commands_provider(), root = self:_project_root() }
end

---Parse an adapter override out of the user prompt
---@param prompt string
---@return string The cleaned prompt
function Inline:parse_special_syntax(prompt)
  local adapter_pattern = "adapter=([%w_]+)"
  local adapter_match = prompt:match(adapter_pattern)

  local config_adapters = config.adapters.http
  if adapter_match then
    if config_adapters[adapter_match] then
      self:set_adapter(adapter_match)
      prompt = prompt:gsub(adapter_pattern, "", 1) -- Remove only the first occurrence
    else
      utils.notify("Adapter not found: " .. adapter_match, vim.log.levels.ERROR)
    end
  else
    -- Handle legacy first-word adapter detection for backward compatibility
    local split = vim.split(prompt, " ")
    local first_word = split[1]
    if config_adapters[first_word] then
      self:set_adapter(first_word)
      table.remove(split, 1)
      prompt = table.concat(split, " ")
    end
  end

  return vim.trim(prompt)
end

---Set keymaps for the inline interaction
---@param bufnr? number
---@param opts? table
---@return nil
function Inline:set_keymaps(bufnr, opts)
  keymaps
    .new({
      bufnr = bufnr,
      callbacks = require("inliber.interactions.inline.keymaps"),
      data = self,
      keymaps = config.interactions.inline.keymaps,
    })
    :set(opts)
end

---Prompt the LLM
---@param user_prompt? string The prompt supplied by the user
---@return nil
function Inline:prompt(user_prompt)
  log:trace("[Inline] Starting")

  local prompts = {}

  local function add_prompt(content, role, opts)
    table.insert(prompts, {
      content = content,
      role = role or user_role,
      opts = opts or { visible = true },
    })
  end

  -- Add system prompt first
  table.insert(prompts, self:_system_message())

  -- Followed by prompts from external sources
  local ext_prompts = self:make_ext_prompts()
  if ext_prompts then
    for i = 1, #ext_prompts do
      prompts[#prompts + 1] = ext_prompts[i]
    end
  end

  if user_prompt then
    -- Parse adapters and editor context from the entire prompt
    user_prompt = self:parse_special_syntax(user_prompt)

    -- Check for any editor context
    local ec = editor_context.new({ inline = self, prompt = user_prompt })
    local found = ec:find():replace():output()
    if found then
      for _, item in ipairs(found) do
        add_prompt(item, user_role, { visible = false })
      end
      user_prompt = ec.prompt
    end

    -- Expand any agent slash commands tagged in the prompt
    local provider = self:_agent_commands_provider()
    if provider then
      local ac = agent_commands.new({ provider = provider, prompt = user_prompt, root = self:_project_root() })
      for _, item in ipairs(ac:find():replace():output()) do
        add_prompt(item, user_role, { visible = false })
      end
      user_prompt = ac.prompt
    end

    -- Add the user's prompt
    add_prompt("<prompt>" .. user_prompt .. "</prompt>")
    self.current_question = user_prompt
    self.current_asked_at = os.date("%H:%M")
  end

  self.prompts = prompts
  self.messages = vim.deepcopy(vim.list_slice(prompts, 2))
  return self:_submit(vim.deepcopy(prompts))
end

---Submit a question, starting or continuing the ask conversation
---@param question string The user's question
---@return nil
function Inline:ask(question)
  if #self.messages > 0 then
    return self:reply(question)
  end
  return self:prompt(question)
end

---Continue the ask conversation with a follow-up question, resending the full history
---@param question string The follow-up question from the user
---@return nil
function Inline:reply(question)
  self.current_question = question
  self.current_asked_at = os.date("%H:%M")
  table.insert(self.messages, {
    role = user_role,
    content = "<prompt>" .. question .. "</prompt>",
  })

  local prompts = { self:_system_message() }
  for _, message in ipairs(self.messages) do
    table.insert(prompts, message)
  end

  self.prompts = prompts
  return self:_submit(vim.deepcopy(prompts))
end

---Prompts can enter the inline class from external sources such as the command
---line. We begin to form the payload to send to the LLM in this method,
---checking conditions and expanding functions.
---@return table|nil
function Inline:make_ext_prompts()
  local prompts = {}

  if self.prompts then
    for _, prompt in ipairs(self.prompts) do
      if prompt.opts and prompt.opts.contains_code and not config.can_send_code() then
        goto continue
      end
      if prompt.condition and not prompt.condition(self.buffer_context) then
        goto continue
      end
      if type(prompt.content) == "function" then
        prompt.content = prompt.content(self.buffer_context)
      end
      table.insert(prompts, {
        role = prompt.role,
        content = prompt.content,
        opts = prompt.opts or {},
      })
      ::continue::
    end
  end

  -- Add any visual selections to the prompt
  if config.can_send_code() then
    if self.buffer_context.is_visual and not self.opts.stop_context_insertion then
      log:trace("[Inline] Sending visual selection")
      table.insert(prompts, {
        role = user_role,
        content = code_block(
          "For context, this is the code that I've visually selected in the buffer, which is relevant to my prompt:",
          self.buffer_context.filetype,
          self.buffer_context.lines
        ),
        _meta = { tag = "visual" },
        opts = {
          visible = false,
        },
      })
    end
  end

  return prompts
end

---Stop the current request
---@return nil
function Inline:stop()
  local tool_loop = self.tool_loop
  self.tool_loop = nil
  if tool_loop then
    tool_loop:stop()
  end
  self:_stop_spinner()
  if self.current_request then
    self.current_request.cancel()
    self.current_request = nil
    adapters.call_handler(self.adapter, "on_exit")
  end
  self:_restore_ask_float()
end

local _streaming = true

---Route the prompts to either the tool loop or the direct request
---@param prompts table The prompts to send to the LLM
---@return nil
function Inline:_submit(prompts)
  local tools = config.interactions.inline.tools
  if tools and tools.enabled then
    return self:submit_with_tools(prompts)
  end
  return self:submit(prompts)
end

---Run the prompt through the headless tool loop
---@param prompts table The prompts to send to the LLM
---@return nil
function Inline:submit_with_tools(prompts)
  local tools = config.interactions.inline.tools

  -- Remember the adapter's streaming setting so reset() restores it unchanged
  _streaming = self.adapter.opts and self.adapter.opts.stream

  self:set_keymaps(self.buffer_context.bufnr, { keymaps = { "stop" } })
  self:_start_spinner("Inliber")

  local messages = self:_prepare_tool_messages(prompts)

  local tool_loop = require("inliber.tools").new({
    adapter = self.adapter,
    bufnr = self.buffer_context.bufnr,
    messages = messages,
    structured_output = self:_structured_output(),
    approval_mode = tools.opts and tools.opts.approval_mode,
    callbacks = {
      on_completed = function(loop, result)
        vim.schedule(function()
          if self.tool_loop ~= loop then
            return
          end
          local content
          if result and result.status == CONSTANTS.STATUS_SUCCESS then
            content = loop:last_llm_message()
          end
          if not content then
            self.tool_loop = nil
            loop:close()
            self:reset()
            return self:_restore_ask_float()
          end
          self.tokens = loop.tokens
          self:done(content)
        end)
      end,
      on_cancelled = function()
        self:reset()
        self:_restore_ask_float()
      end,
      on_status = function(tool_name, status, label)
        if self.spinner then
          self.spinner:update(label or tool_name)
        end
      end,
    },
  })

  if not tool_loop then
    return log:error("[Inline] Failed to initiate the request")
  end

  self:_add_tools(tool_loop)

  self.tool_loop = tool_loop
  tool_loop:submit()
end

---Add the intent-specific tools to the tool loop's registry
---@param tool_loop Inliber.ToolLoop
---@return nil
function Inline:_add_tools(tool_loop)
  local tools = config.interactions.inline.tools
  local tool_names = self.intent == "ask" and tools.ask_tools or tools.edit_tools
  for _, tool in ipairs(tool_names or {}) do
    tool_loop:add_tool(tool)
  end
end

---Start the progress spinner
---@param message string
---@return nil
function Inline:_start_spinner(message)
  self.spinner = require("inliber.utils.spinner").new({ message = message })
  self.spinner:start()
end

---Stop the progress spinner
---@return nil
function Inline:_stop_spinner()
  if self.spinner then
    self.spinner:stop()
    self.spinner = nil
  end
end

---Get the system prompt for the current intent
---@return string
function Inline:_system_prompt()
  if self.intent == "ask" then
    return CONSTANTS.SYSTEM_PROMPT_ASK
  end
  return CONSTANTS.SYSTEM_PROMPT
end

---Build the system message for the current intent
---@return table
function Inline:_system_message()
  return {
    role = config.constants.SYSTEM_ROLE,
    content = fmt(
      self:_system_prompt(),
      self.buffer_context.filetype,
      self:_response_schema(),
      config.opts.language
    ),
    _meta = {
      tag = "system_tag",
    },
    opts = {
      visible = false,
    },
  }
end

---Get the response schema for the current intent
---@return string
function Inline:_response_schema()
  if self.intent == "ask" then
    return CONSTANTS.RESPONSE_ASK
  end
  return CONSTANTS.RESPONSE_EDIT
end

---Get the structured output schema for the current intent
---@return Inliber.StructuredOutput.Schema
function Inline:_structured_output()
  if self.intent == "ask" then
    return { name = "inline_ask", schema = CONSTANTS.SCHEMA_ASK }
  end
  return { name = "inline_edit", schema = CONSTANTS.SCHEMA_EDIT }
end

---Prepare messages for the tool loop by appending the JSON format instruction to the user message
---@param prompts table The original prompts
---@return table Messages suitable for the tool loop
function Inline:_prepare_tool_messages(prompts)
  local json_instruction = fmt(
    [[

IMPORTANT: After gathering any context you need, you MUST respond with ONLY valid JSON in this format:
%s

Do not include markdown, code fences, or explanations outside the JSON.
Write the JSON as your final text reply. Do not call a tool to produce it; only call the tools you were given.]],
    self:_response_schema()
  )

  local result = {}
  for _, msg in ipairs(prompts) do
    if msg.role == user_role and msg.content and msg.content:match("</prompt>") then
      table.insert(result, {
        role = msg.role,
        content = msg.content .. json_instruction,
        _meta = msg._meta,
        opts = msg.opts,
      })
    else
      table.insert(result, msg)
    end
  end

  return result
end

---Submit the prompts to the LLM to process
---@param prompt table The prompts to send to the LLM
---@return nil
function Inline:submit(prompt)
  -- Inline editing only works with streaming off - We should remember the current status
  _streaming = self.adapter.opts.stream
  self.adapter.opts.stream = false

  self:set_keymaps(self.buffer_context.bufnr, { keymaps = { "stop" } })

  self.current_request = client
    .new({ adapter = self.adapter:map_schema_to_params(), user_args = { event = "InlineStarted" } })
    :request({ messages = self.adapter:map_roles(prompt) }, {
      ---@param err string
      ---@param data table
      ---@param adapter Inliber.HTTPAdapter The modified adapter from the http client
      callback = function(err, data, adapter)
        require("inliber.interactions.inline.keymaps").clear_map(config.interactions.inline.keymaps, self.bufnr)

        local function error(msg)
          log:error("[Inline] Request failed with error %s", msg)
        end

        if err then
          local msg = type(err) == "table" and err.message or err
          return error(msg)
        end

        if data then
          data = adapters.call_handler(adapter, "parse_inline", data, self.buffer_context)
          if data and data.status == CONSTANTS.STATUS_SUCCESS then
            return self:done(data.output)
          elseif data then
            return error(data.output)
          end
        end
      end,
    }, {
      bufnr = self.bufnr,
      buffer_context = self.buffer_context or {},
      interaction = "inline",
    })
end

---Once the request has been completed, we can process the output
---@param output string The output from the LLM
---@return nil
function Inline:done(output)
  utils.fire("InlineFinished")
  self:_stop_spinner()

  local adapter_name = self.adapter.formatted_name

  if not output then
    log:error("[%s] No output received", adapter_name)
    self:reset()
    return self:_restore_ask_float()
  end

  local json = self:parse_output(output)
  if not json then
    -- Logging is done in parse_output
    self:reset()
    return self:_restore_ask_float()
  end
  if json and json.error then
    log:error("[%s] %s", adapter_name, json.error)
    self:reset()
    return self:_restore_ask_float()
  end

  -- An ask intent only ever answers the prompt; the LLM cannot edit the buffer
  if self.intent == "ask" then
    local answer = json and json.message
    self:reset()
    if not answer or answer == "" then
      log:error("[%s] Returned no answer", adapter_name)
      return self:_restore_ask_float()
    end
    table.insert(self.messages, { role = config.constants.LLM_ROLE, content = answer })
    table.insert(self.turns, {
      question = self.current_question,
      answer = answer,
      asked_at = self.current_asked_at,
      answered_at = os.date("%H:%M"),
    })
    return self:_show_answer(self.tokens or tokens.get_tokens(self.messages))
  end

  local placement = json and json.placement
  if not placement then
    log:error("[%s] No placement returned", adapter_name)
    return self:reset()
  end
  placement = string.lower(placement)

  if json and not json.code then
    log:error("[%s] Returned no code", adapter_name)
    return self:reset()
  end

  vim.schedule(function()
    if not config.display.diff.enabled or placement == "new" then
      self:place(placement)
      pcall(vim.cmd.undojoin)
      self:output(json.code)
      return self:reset()
    end

    local original_content = api.nvim_buf_get_lines(self.buffer_context.bufnr, 0, -1, true)
    local new_content = self:get_new_content(original_content, json.code, placement)

    self:start_diff({
      original_content = original_content,
      new_content = new_content,
      placement = placement,
      code = json.code,
    })
  end)
end

---Show the ask conversation in the chat float
---@param token_count? number The cumulative token count to display
---@return nil
function Inline:_show_answer(token_count)
  if not self.ask_float then
    self.ask_float = require("inliber.interactions.inline.ask_float").new()
  end

  local float = self.ask_float
  float:show({
    turns = self.turns,
    tokens = token_count,
    on_submit = function(question)
      float:set_thinking(question)
      self:ask(question)
    end,
  })
end

---Restore the ask float's input after a failed request so the user can retry
---@return nil
function Inline:_restore_ask_float()
  if self.intent == "ask" and self.ask_float then
    self.ask_float:show({ turns = self.turns })
  end
end

---Reopen the ask conversation in the float, rebinding to the current buffer
---@param opts? table
---@return nil
function Inline:resume(opts)
  last_ask = self
  self.buffer_context = require("inliber.utils.context").get(api.nvim_get_current_buf(), opts or {})
  self.bufnr = self.buffer_context.bufnr

  if #self.turns == 0 then
    self.input_modal = require("inliber.interactions.inline.input_modal").new()
    self.input_modal:prompt(function(question)
      if question then
        self:ask(question)
      end
    end, self:agent_command_opts())
    return
  end

  return self:_show_answer(self.tokens)
end

---Reset the inline prompt class
---@return nil
function Inline:reset()
  self.adapter.opts.stream = _streaming
  self.current_request = nil
  self:_stop_spinner()
  if self.tool_loop then
    local tool_loop = self.tool_loop
    self.tool_loop = nil
    vim.schedule(function()
      tool_loop:close()
    end)
  end
  api.nvim_clear_autocmds({ group = self.aug })
end

---Compute what the buffer content would look like after applying the LLM output
---@param original string[] The original buffer lines
---@param code string The code from the LLM
---@param placement string The placement type
---@return string[]
function Inline:get_new_content(original, code, placement)
  local new_lines = vim.split(code, "\n")
  local result = vim.deepcopy(original)
  local ctx = self.buffer_context

  if placement == "replace" then
    -- Replace the visual selection with the new code
    local before = vim.list_slice(result, 1, ctx.start_line - 1)
    local after = vim.list_slice(result, ctx.end_line + 1)

    -- Handle partial line replacement
    local start_prefix = ""
    local end_suffix = ""
    if ctx.start_col > 0 and result[ctx.start_line] then
      start_prefix = result[ctx.start_line]:sub(1, ctx.start_col - 1)
    end
    if result[ctx.end_line] then
      end_suffix = result[ctx.end_line]:sub(ctx.end_col + 1)
    end

    -- Combine prefix with first line and suffix with last line
    if #new_lines > 0 then
      new_lines[1] = start_prefix .. new_lines[1]
      new_lines[#new_lines] = new_lines[#new_lines] .. end_suffix
    else
      new_lines = { start_prefix .. end_suffix }
    end

    result = vim.list_extend(vim.list_extend(before, new_lines), after)
  elseif placement == "add" then
    -- Insert after the end line
    local before = vim.list_slice(result, 1, ctx.end_line)
    local after = vim.list_slice(result, ctx.end_line + 1)
    result = vim.list_extend(vim.list_extend(before, new_lines), after)
  elseif placement == "before" then
    -- Insert before the start line
    local before = vim.list_slice(result, 1, ctx.start_line - 1)
    local after = vim.list_slice(result, ctx.start_line)
    result = vim.list_extend(vim.list_extend(before, new_lines), after)
  end

  return result
end

---Extract a code block from markdown text
---@param content string
---@return string|nil
local function parse_with_treesitter(content)
  local parser = vim.treesitter.get_string_parser(content, "markdown")
  local syntax_tree = parser:parse()
  local root = syntax_tree[1]:root()

  local query = vim.treesitter.query.parse("markdown", [[(code_fence_content) @code]])

  local code = {}
  for id, node in query:iter_captures(root, content, 0, -1) do
    if query.captures[id] == "code" then
      local node_text = vim.treesitter.get_node_text(node, content)
      -- Deepseek protection!!
      node_text = node_text:gsub("```json", "")
      node_text = node_text:gsub("```", "")

      table.insert(code, node_text)
    end
  end

  return vim.tbl_count(code) > 0 and table.concat(code, "") or nil
end

---@param output string
---@return table|nil
function Inline:parse_output(output)
  -- Try parsing as plain JSON first
  output = output:gsub("^```json", ""):gsub("```$", "")
  local ok, json = pcall(vim.json.decode, output)
  if ok then
    return json
  end

  -- Fall back to Tree-sitter parsing
  local markdown_code = parse_with_treesitter(output)
  if markdown_code then
    ok, json = pcall(vim.json.decode, markdown_code)
    if ok then
      return json
    end
  end

  return log:error("[Inline] Failed to parse the response")
end

---Write the output from the LLM to the buffer
---@param output string
---@return nil
function Inline:output(output)
  local line = self.pos.line - 1
  local col = self.pos.col
  local bufnr = self.pos.bufnr

  local lines = vim.split(output, "\n")

  -- If there's only one line, use buf_set_text
  if #lines == 1 then
    api.nvim_buf_set_text(bufnr, line, col, line, col, { output })
    self.pos.line = line + 1
    self.pos.col = col + #output
    return
  end

  -- For multiple lines:
  -- 1. Handle first line
  api.nvim_buf_set_text(bufnr, line, col, line, col, { lines[1] })

  -- 2. Add remaining lines
  api.nvim_buf_set_lines(bufnr, line + 1, line + 1, false, vim.list_slice(lines, 2))
end

---With the placement determined, we can now place the output from the inline prompt
---@param placement string
---@return Inliber.Inline
function Inline:place(placement)
  local pos = { line = self.buffer_context.start_line, col = 0, bufnr = 0 }

  if placement == "replace" then
    self.lines = api.nvim_buf_get_lines(self.buffer_context.bufnr, 0, -1, true)
    overwrite_selection(self.buffer_context)
    local cursor_pos = api.nvim_win_get_cursor(self.buffer_context.winnr)
    pos.line = cursor_pos[1]
    pos.col = cursor_pos[2]
    pos.bufnr = self.buffer_context.bufnr
  elseif placement == "add" then
    self.lines = api.nvim_buf_get_lines(self.buffer_context.bufnr, 0, -1, true)
    api.nvim_buf_set_lines(
      self.buffer_context.bufnr,
      self.buffer_context.end_line,
      self.buffer_context.end_line,
      false,
      { "" }
    )
    pos.line = self.buffer_context.end_line + 1
    pos.col = 0
    pos.bufnr = self.buffer_context.bufnr
  elseif placement == "before" then
    self.lines = api.nvim_buf_get_lines(self.buffer_context.bufnr, 0, -1, true)
    api.nvim_buf_set_lines(
      self.buffer_context.bufnr,
      self.buffer_context.start_line - 1,
      self.buffer_context.start_line - 1,
      false,
      { "" }
    )
    self.buffer_context.start_line = self.buffer_context.start_line + 1
    pos.line = self.buffer_context.start_line - 1
    pos.col = math.max(0, self.buffer_context.start_col - 1)
    pos.bufnr = self.buffer_context.bufnr
  elseif placement == "new" then
    local bufnr
    if self.opts and type(self.opts.pre_hook) == "function" then
      bufnr = self.opts.pre_hook()
      assert(type(bufnr) == "number", "No buffer number returned from the pre_hook function")
    else
      bufnr = api.nvim_create_buf(true, false)
      local ft = utils.safe_filetype(self.buffer_context.filetype)
      utils.set_option(bufnr, "filetype", ft)
    end

    if config.display.inline.layout == "vertical" then
      vim.cmd("vsplit")
    elseif config.display.inline.layout == "horizontal" then
      vim.cmd("split")
    elseif config.display.inline.layout == "tab" then
      vim.cmd("tabnew")
    end

    api.nvim_win_set_buf(api.nvim_get_current_win(), bufnr)
    pos.line = 1
    pos.col = 0
    pos.bufnr = bufnr
  end

  self.pos = {
    line = pos.line,
    col = pos.col,
    bufnr = pos.bufnr,
  }

  return self
end

---Build the banner text for the inline diff
---@return string
function Inline:build_diff_banner()
  local keys = config.interactions.shared.keymaps
  return fmt(
    "%s Always Accept | %s Accept | %s Reject",
    keys.always_accept.modes.n,
    keys.accept_change.modes.n,
    keys.reject_change.modes.n
  )
end

---Start the diff process
---@param args { original_content: string[], new_content: string[], placement: string, code: string }
---@return nil
function Inline:start_diff(args)
  log:debug("[Inline] Starting diff")

  local approvals = require("inliber.tools.approvals")

  -- If the buffer has been added to the auto approval list, skip the diff
  if approvals:is_approved(self.bufnr, { tool_name = "inline" }) then
    self:place(args.placement)
    pcall(vim.cmd.undojoin)
    self:output(args.code)
    return self:reset()
  end

  -- Store original content for potential restoration on reject
  self.original_content = args.original_content

  -- Show the inline diff - this will transform the buffer from original to new
  local helpers = require("inliber.helpers")
  self.diff_ui = helpers.show_diff({
    bufnr = self.buffer_context.bufnr,
    from_lines = args.original_content,
    to_lines = args.new_content,
    diff_id = self.id,
    ft = self.buffer_context.filetype,
    inline = true,
    banner = self:build_diff_banner(),
    keymaps = {
      on_accept = function()
        self:on_diff_accepted()
      end,
      on_reject = function()
        self:on_diff_rejected()
      end,
      on_always_accept = function()
        approvals:always(self.buffer_context.bufnr, { tool_name = "inline" })
      end,
    },
  })
end

---Handle diff accepted event
---@return nil
function Inline:on_diff_accepted()
  log:trace("[Inline] Diff accepted for id=%s", self.id)
  self.original_content = nil
  self.diff_ui = nil
  self:reset()
end

---Handle diff rejected event
---@return nil
function Inline:on_diff_rejected()
  log:trace("[Inline] Diff rejected for id=%s, restoring original content", self.id)

  if self.original_content and api.nvim_buf_is_valid(self.buffer_context.bufnr) then
    api.nvim_buf_set_lines(self.buffer_context.bufnr, 0, -1, false, self.original_content)
  end

  self.original_content = nil
  self.diff_ui = nil
  self:reset()
end

return Inline
