--[[
The Inline Interaction - This is where code is applied directly to a Neovim buffer
--]]

---@class Inliber.Inline
---@field id number The ID of the inline prompt
---@field adapter Inliber.ACPAdapter The adapter to use for the inline prompt
---@field ask_float? Inliber.AskFloat The persistent float holding the ask conversation
---@field input_modal? Inliber.InputModal The input modal collecting the prompt
---@field aug number The ID for the autocmd group
---@field buffer_context Inliber.BufferContext
---@field bufnr number The buffer number to apply the inline edits to
---@field current_asked_at? string The time the current question was asked
---@field current_question? string The question of the current ask turn
---@field current_request? { cancel: fun() } The current request that's being processed
---@field diff_ui? Inliber.DiffUI The diff UI instance
---@field intent "ask"|"edit" Whether the prompt answers a question or edits the buffer
---@field lines table Lines in the buffer before the inline changes
---@field messages table Non-system messages sent across the conversation
---@field opts table
---@field original_region? string[] The lines the diff replaced, restored on reject
---@field pos? { line: number, col: number, bufnr: number } Where to place the generated code
---@field prompts table The prompts to send to the LLM
---@field spinner? Inliber.Spinner Progress feedback while the request runs
---@field turns table Rendered question/answer pairs for the ask float

---@class Inliber.InlineArgs
---@field adapter? Inliber.ACPAdapter
---@field buffer_context? Inliber.BufferContext
---@field intent "ask"|"edit" Whether the prompt answers a question or edits the buffer
---@field lines? table The lines in the buffer before the inline changes
---@field opts? table
---@field pre_hook? fun():number Function to run before the inline prompt is started
---@field prompts? table The prompts to send to the LLM

local acp_request = require("inliber.interactions.shared.acp_request")
local adapters = require("inliber.adapters")
local agent_commands = require("inliber.interactions.shared.agent_commands")
local agent_commands_providers = require("inliber.interactions.shared.agent_commands.providers")
local config = require("inliber.config")
local editor_context = require("inliber.interactions.inline.editor_context")
local editor_state = require("inliber.interactions.inline.editor_state")
local keymaps = require("inliber.utils.keymaps")
local log = require("inliber.utils.log")
local markdown = require("inliber.utils.markdown")
local tokens = require("inliber.utils.tokens")
local utils = require("inliber.utils")

local api = vim.api
local fmt = string.format

local marks_ns = api.nvim_create_namespace("inliber.inline.marks")

local user_role = config.constants.USER_ROLE

local CONSTANTS = {
  AUTOCMD_GROUP = "inliber.inline",

  -- ACP agents have no server-side JSON mode and are chatty by default, so a
  -- firm, compact instruction beats a long JSON schema
  SYSTEM_PROMPT = [[You are writing %s code directly into a Neovim buffer.

Reply with ONLY a JSON object. No markdown fences, no prose, no explanation:

%s

If you cannot answer, return {"error": "reason"}.
Preserve the exact indentation of the code you write.]],

  SYSTEM_PROMPT_ASK = [[You are answering the user's questions about the %s code in their Neovim buffer. Never write or modify code.

Reply with ONLY a JSON object. No markdown fences, no prose, no explanation:

%s

If you cannot answer, return {"error": "reason"}.
Put your full answer in the "message" field.]],

  RESPONSE_ASK = [["message": "<your full answer to the user's question>"]],

  RESPONSE_EDIT = [["code": "<the code>", "language": "<language>", "placement": "<replace|add|before>"

placement:
- replace: replace the visual selection with "code"
- add: insert "code" after the cursor
- before: insert "code" before the cursor]],
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

---Get the rows that differ between two versions of a buffer
---@param opts { from: string[], to: string[] }
---@return { first: number, from_end: number, to_end: number } 0-based first row and exclusive end rows
local function get_changed_rows(opts)
  local first = 0
  while first < #opts.from and first < #opts.to and opts.from[first + 1] == opts.to[first + 1] do
    first = first + 1
  end
  local from_end, to_end = #opts.from, #opts.to
  while from_end > first and to_end > first and opts.from[from_end] == opts.to[to_end] do
    from_end, to_end = from_end - 1, to_end - 1
  end
  return { first = first, from_end = from_end, to_end = to_end }
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

  api.nvim_buf_set_text(
    context.bufnr,
    context.start_line - 1,
    context.start_col,
    context.end_line - 1,
    context.end_col,
    { "" }
  )

  -- The window may show another buffer by now; only move the cursor if it still shows this one
  if context.winnr and api.nvim_win_is_valid(context.winnr) and api.nvim_win_get_buf(context.winnr) == context.bufnr then
    api.nvim_win_set_cursor(context.winnr, { context.start_line, context.start_col })
  end
end

---Join the next edit in the given buffer into its previous undo block
---@param bufnr number
---@return nil
local function undojoin(bufnr)
  api.nvim_buf_call(bufnr, function()
    pcall(vim.cmd.undojoin)
  end)
end

---@class Inliber.Inline
local Inline = {}

---@type Inliber.Inline|nil The last ask conversation retained for resume
local last_ask = nil

---@type table<number, Inliber.Inline[]> The requests waiting on the LLM in each buffer
local running_requests = {}

---@type Inliber.Inline[] The submitted requests, most recent last
local submitted_requests = {}

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

---Cancel the most recently submitted request
---@return nil
function Inline.cancel_last()
  local request = submitted_requests[#submitted_requests]
  if request then
    request:stop()
  end
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
---@param adapter Inliber.ACPAdapter|string|function
---@param opts? { model?: string }
---@return nil
function Inline:set_adapter(adapter, opts)
  if not self.adapter or not adapters.resolved(adapter) then
    self.adapter = adapters.resolve(adapter, opts)
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

  local config_adapters = config.adapters.acp
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

  local editor_state_config = config.interactions.inline.editor_state
  if editor_state_config.enabled then
    add_prompt(editor_state.format(self.buffer_context, editor_state_config), user_role, { visible = false })
  end

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
  return self:submit(vim.deepcopy(prompts))
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
  return self:submit(vim.deepcopy(prompts))
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

---Get the running request in a buffer whose selection is closest to the cursor
---@param bufnr number
---@return Inliber.Inline|nil
function Inline.get_request_at_cursor(bufnr)
  local requests = running_requests[bufnr] or {}
  if #requests < 2 or api.nvim_get_current_buf() ~= bufnr then
    return requests[#requests]
  end

  local cursor_line = api.nvim_win_get_cursor(0)[1]
  local closest, closest_distance
  for _, request in ipairs(requests) do
    local start_line, end_line = request:_get_selection_lines()
    local distance = math.max(start_line - cursor_line, cursor_line - end_line, 0)
    if not closest_distance or distance < closest_distance then
      closest, closest_distance = request, distance
    end
  end
  return closest
end

---Register the request as running and map the stop key in its buffer
---@return nil
function Inline:_start_request()
  local requests = running_requests[self.bufnr] or {}
  running_requests[self.bufnr] = requests
  if not vim.tbl_contains(requests, self) then
    table.insert(requests, self)
  end
  self:set_keymaps(self.buffer_context.bufnr, { keymaps = { "stop" } })
end

---Unregister the request, removing the stop key once no other request runs in the buffer
---@return nil
function Inline:_finish_request()
  local requests = vim.tbl_filter(function(request)
    return request ~= self
  end, running_requests[self.bufnr] or {})
  running_requests[self.bufnr] = requests
  submitted_requests = vim.tbl_filter(function(request)
    return request ~= self
  end, submitted_requests)
  if #requests == 0 then
    require("inliber.interactions.inline.keymaps").clear_map(config.interactions.inline.keymaps, self.bufnr)
  end
end

---Stop the current request
---@return nil
function Inline:stop()
  self:_finish_request()
  self:_stop_spinner()
  if self.current_request then
    self.current_request.cancel()
    self.current_request = nil
  end
  self:_restore_ask_float()
end

---Mark the selected lines so the edit still lands on them if other edits move them
---@return nil
function Inline:_track_selection()
  local context = self.buffer_context
  self.selection_mark = api.nvim_buf_set_extmark(context.bufnr, marks_ns, context.start_line - 1, 0, {
    end_row = context.end_line - 1,
    end_col = 0,
    end_right_gravity = true,
  })
end

---Get the lines the selection covers now, following any edits made since it was marked
---@return number, number
function Inline:_get_selection_lines()
  local context = self.buffer_context
  if self.selection_mark then
    local mark = api.nvim_buf_get_extmark_by_id(context.bufnr, marks_ns, self.selection_mark, { details = true })
    if mark[1] then
      return mark[1] + 1, mark[3].end_row + 1
    end
  end
  return context.start_line, context.end_line
end

---Move the selection to wherever its lines are now
---@return nil
function Inline:_update_selection()
  self.buffer_context.start_line, self.buffer_context.end_line = self:_get_selection_lines()
end

---Delete the extmarks this edit placed in the buffer
---@return nil
function Inline:_clear_marks()
  for _, mark in ipairs({ self.selection_mark, self.region_mark }) do
    pcall(api.nvim_buf_del_extmark, self.buffer_context.bufnr, marks_ns, mark)
  end
  self.selection_mark = nil
  self.region_mark = nil
end

---Start the progress spinner
---@return nil
function Inline:_start_spinner()
  local intent = self.intent:sub(1, 1):upper() .. self.intent:sub(2)
  local label = intent
  local filename = self.buffer_context.filename
  if filename and filename ~= "" then
    label = intent .. " · " .. filename
  end
  self.spinner = require("inliber.utils.spinner").new({ label = label })
  self.spinner:start()
end

---Finish the progress spinner with a Done row
---@return nil
function Inline:_finish_spinner()
  if self.spinner then
    self.spinner:finish()
    self.spinner = nil
  end
end

---Remove the progress spinner immediately
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
  local content = fmt(self:_system_prompt(), self.buffer_context.filetype, self:_response_schema())

  if self.intent == "edit" then
    -- The relative path keeps the user's home directory out of the request
    if self.buffer_context.relative_path and self.buffer_context.relative_path ~= "" then
      content = content .. "\n\nYou are editing the file: " .. self.buffer_context.relative_path
    end

    -- With no selection, the LLM must inspect the file itself to decide where
    -- the edit belongs. ACP agents have their own file tools
    if not self.buffer_context.is_visual then
      content = content
        .. "\n\nNo code was selected. "
        .. "Inspect the file"
        .. ", decide where the edit belongs, then return the complete updated file."
    end
  end

  return {
    role = config.constants.SYSTEM_ROLE,
    content = content,
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

---Submit the prompts to an ACP agent for processing
---@param prompt table The prompts to send to the LLM
---@return nil
function Inline:submit(prompt)
  if self.intent == "edit" then
    self:_track_selection()
  end
  self:_start_request()
  self:_start_spinner()
  table.insert(submitted_requests, self)
  return self:_submit_acp(prompt)
end

---Submit the prompts through the one-shot ACP request bridge
---@param prompt table The prompts to send to the agent
---@return nil
function Inline:_submit_acp(prompt)
  utils.fire("InlineStarted")
  self.current_request = acp_request.submit({
    purpose = "inline",
    adapter = self.adapter,
    messages = self.adapter:map_roles(prompt),
    bufnr = self.bufnr,
    on_done = function(output)
      self:_finish_request()
      self:done(output)
    end,
    on_error = function(err)
      self:_stop_spinner()
      self:_finish_request()
      log:error("[Inline] Request failed with error %s", err)
      self:_restore_ask_float()
    end,
  })
end

---Once the request has been completed, we can process the output
---@param output string The output from the LLM
---@return nil
function Inline:done(output)
  utils.fire("InlineFinished")
  self:_finish_spinner()

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
  if json.error then
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
    return self:_show_answer(tokens.get_tokens(self.messages))
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

  -- ACP agents reply with the whole edited file instead of just the changed lines.
  -- Treat that as a whole-buffer replacement so the file is not pasted inside the
  -- existing selection or cursor.
  if self:_is_full_file_rewrite(json.code) then
    local full = api.nvim_buf_get_lines(self.buffer_context.bufnr, 0, -1, true)
    self.buffer_context.start_line = 1
    self.buffer_context.start_col = 0
    self.buffer_context.end_line = #full
    self.buffer_context.end_col = #full[#full]
    placement = "replace"
  end

  -- ACP agents pick "new" on their own; redirect their code to the current buffer
  if placement == "new" and json.placement and json.placement:lower() == "new" then
    placement = self.buffer_context.is_visual and "replace" or "add"
  end

  vim.schedule(function()
    self:_update_selection()
    if not config.display.diff.enabled or placement == "new" then
      self:place(placement)
      undojoin(self.buffer_context.bufnr)
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
    self.input_modal = require("inliber.interactions.inline.input_modal").new({ intent = "ask" })
    self.input_modal:prompt(function(question)
      if question then
        self:ask(question)
      end
    end, self:agent_command_opts())
    return
  end

  return self:_show_answer(tokens.get_tokens(self.messages))
end

---Reset the inline prompt class
---@return nil
function Inline:reset()
  self:_finish_request()
  self.current_request = nil
  self:_stop_spinner()
  self:_clear_marks()
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
      -- end_col can be math.maxinteger for a line-wise selection; without the
      -- clamp, +1 overflows to a negative index and sub() returns the whole line
      end_suffix = result[ctx.end_line]:sub(math.min(ctx.end_col + 1, #result[ctx.end_line] + 1))
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

    -- ACP agents often answer with fenced raw code instead of the JSON schema
    if self.adapter.type == "acp" then
      return {
        code = markdown_code,
        language = self.buffer_context.filetype,
        placement = self.buffer_context.is_visual and "replace" or "add",
      }
    end
  end

  log:debug("[Inline] Unparsable response:\n%s", output)
  return log:error("[Inline] Failed to parse the response")
end

---Detect whether the model returned the whole buffer rather than just the changed lines
---@param code string The code returned by the model
---@return boolean
function Inline:_is_full_file_rewrite(code)
  local buffer_lines = api.nvim_buf_get_lines(self.buffer_context.bufnr, 0, -1, true)
  -- Normalise line endings so the comparison is indifferent to CRLF output
  local code_lines = vim.split(code:gsub("\r\n", "\n"):gsub("\r", "\n"), "\n")

  -- A trailing newline adds an empty line that the buffer does not report
  if #code_lines > 1 and code_lines[#code_lines] == "" then
    code_lines[#code_lines] = nil
  end

  if #buffer_lines < 2 or #code_lines < 2 then
    return false
  end

  -- A rewrite is comparable in size to the buffer, whereas a snippet is far
  -- shorter. It also shares a boundary line with the buffer, which a block
  -- selected from the middle of the file never does.
  if #code_lines < math.floor(#buffer_lines * 0.5) then
    return false
  end

  return code_lines[1] == buffer_lines[1] or code_lines[#code_lines] == buffer_lines[#buffer_lines]
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
    pos.line = self.buffer_context.start_line
    pos.col = self.buffer_context.start_col
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

  local approvals = require("inliber.interactions.inline.approvals")

  -- If the buffer has been added to the auto approval list, skip the diff
  if approvals:is_approved(self.bufnr, { tool_name = "inline" }) then
    self:place(args.placement)
    undojoin(self.buffer_context.bufnr)
    self:output(args.code)
    return self:reset()
  end

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
  if not self.diff_ui then
    return self:reset()
  end
  self:_track_region(args)
end

---Mark the lines the diff changed so a reject restores only those
---@param args { original_content: string[], new_content: string[] }
---@return nil
function Inline:_track_region(args)
  local rows = get_changed_rows({ from = args.original_content, to = args.new_content })
  self.original_region = vim.list_slice(args.original_content, rows.first + 1, rows.from_end)
  -- The inline diff adds a spacer line above a hunk that starts on the first line
  local offset = self.diff_ui.inline_spacer_mark and 1 or 0
  self.region_mark = api.nvim_buf_set_extmark(self.buffer_context.bufnr, marks_ns, rows.first + offset, 0, {
    end_row = rows.to_end + offset,
    end_col = 0,
    strict = false,
  })
end

---Handle diff accepted event
---@return nil
function Inline:on_diff_accepted()
  log:trace("[Inline] Diff accepted for id=%s", self.id)
  self.original_region = nil
  self.diff_ui = nil
  self:reset()
end

---Handle diff rejected event
---@return nil
function Inline:on_diff_rejected()
  log:trace("[Inline] Diff rejected for id=%s, restoring original content", self.id)

  local bufnr = self.buffer_context.bufnr
  if self.original_region and api.nvim_buf_is_valid(bufnr) then
    local mark = api.nvim_buf_get_extmark_by_id(bufnr, marks_ns, self.region_mark, { details = true })
    if mark[1] then
      api.nvim_buf_set_lines(bufnr, mark[1], mark[3].end_row, false, self.original_region)
    end
  end

  self.original_region = nil
  self.diff_ui = nil
  self:reset()
end

return Inline
