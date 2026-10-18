--[[
The Input Modal - Small floating-window input for the inline interaction.
Collects the first prompt for both the ask and edit intents before the request
runs.
--]]

local config = require("inliber.config")
local ui_utils = require("inliber.utils.ui")

local api = vim.api

local HISTORY_LIMIT = 15
local history = { ask = {}, edit = {} }

---@class Inliber.InputModal.Config
---@field title? string Title of the input modal
---@field input_width? number Width of the input modal in columns
---@field intent? "ask"|"edit" Intent the prompt history is keyed by

---@class Inliber.InputModal
---@field bufnr? number The buffer holding the input
---@field winnr? number The current floating window
---@field input_width number Width of the input modal in columns
---@field title string Title of the input modal
---@field intent "ask"|"edit" Intent the prompt history is keyed by
---@field history_index? number Position in the prompt history while navigating
---@field draft? string The unsubmitted text saved when history navigation starts
local InputModal = {}

---@param opts? Inliber.InputModal.Config
---@return Inliber.InputModal
function InputModal.new(opts)
  opts = opts or config.interactions.inline.input_modal or {}
  return setmetatable({
    input_width = opts.input_width or 60,
    title = opts.title or "Ask",
    intent = opts.intent or "ask",
  }, { __index = InputModal })
end

---Open the input modal; the callback receives the prompt, or nil if aborted. Attaches agent-command completion when a provider resolves
---@param on_submit fun(prompt: string|nil)
---@param opts? { provider?: Inliber.AgentCommands.Provider, root?: string }
---@return nil
function InputModal:prompt(on_submit, opts)
  opts = opts or {}
  local bufnr, winnr = ui_utils.create_float({ "" }, {
    title = self.title,
    width = self.input_width,
    height = 3,
    ft = "markdown",
    ignore_keymaps = true,
    opts = { number = false, relativenumber = false, wrap = true, linebreak = true },
  })
  self.bufnr = bufnr
  self.winnr = winnr
  self.history_index = nil
  self.draft = ""

  require("inliber.interactions.shared.agent_commands.completion").attach(bufnr, opts.provider, opts.root)
  require("inliber.interactions.shared.agent_commands.highlight").attach(bufnr, opts.provider, opts.root)

  local finished = false
  local function finish(prompt)
    if finished then
      return
    end
    finished = true
    self:close()
    on_submit(prompt)
  end

  local function submit()
    local prompt = vim.trim(self:_current_prompt())
    if prompt == "" then
      finish(nil)
      return
    end
    self:_record(prompt)
    finish(prompt)
  end

  vim.keymap.set({ "i", "n" }, "<CR>", submit, { buffer = bufnr })
  vim.keymap.set("i", "<Up>", function()
    self:_history_up()
  end, { buffer = bufnr })
  vim.keymap.set("i", "<Down>", function()
    self:_history_down()
  end, { buffer = bufnr })

  -- Esc leaves insert mode first; only in normal mode does it close the modal
  vim.keymap.set("n", "<Esc>", function()
    finish(nil)
  end, { buffer = bufnr })

  api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(winnr),
    once = true,
    callback = function()
      finish(nil)
    end,
  })

  vim.cmd("startinsert")
end

---Close the input modal and release its buffer
---@return nil
function InputModal:close()
  vim.cmd("stopinsert")
  if self.winnr and api.nvim_win_is_valid(self.winnr) then
    pcall(api.nvim_win_close, self.winnr, true)
  end
  if self.bufnr and api.nvim_buf_is_valid(self.bufnr) then
    pcall(api.nvim_buf_delete, self.bufnr, { force = true })
  end
  self.winnr = nil
  self.bufnr = nil
end

---Read the prompt currently in the buffer
---@return string
function InputModal:_current_prompt()
  return table.concat(api.nvim_buf_get_lines(self.bufnr, 0, -1, false), "\n")
end

---Replace the buffer with a history entry and move the cursor to its end
---@param text string
---@return nil
function InputModal:_show_history_entry(text)
  local lines = text == "" and { "" } or vim.split(text, "\n")
  api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)
  local last = api.nvim_buf_line_count(self.bufnr)
  api.nvim_win_set_cursor(self.winnr, { last, #lines[#lines] })
end

---Append a submitted prompt to the history, dropping the oldest past the limit
---@param prompt string
---@return nil
function InputModal:_record(prompt)
  local intent_history = history[self.intent]
  if intent_history[#intent_history] ~= prompt then
    table.insert(intent_history, prompt)
    if #intent_history > HISTORY_LIMIT then
      table.remove(intent_history, 1)
    end
  end
end

---Step to the previous prompt, saving the current draft on first press
---@return nil
function InputModal:_history_up()
  local intent_history = history[self.intent]
  if #intent_history == 0 then
    return
  end
  if self.history_index == nil then
    self.draft = self:_current_prompt()
    self.history_index = #intent_history
  else
    self.history_index = math.max(self.history_index - 1, 1)
  end
  self:_show_history_entry(intent_history[self.history_index])
end

---Step to the next prompt, restoring the draft once past the newest
---@return nil
function InputModal:_history_down()
  local intent_history = history[self.intent]
  if self.history_index == nil then
    return
  end
  self.history_index = self.history_index + 1
  if self.history_index > #intent_history then
    self.history_index = nil
    self:_show_history_entry(self.draft)
  else
    self:_show_history_entry(intent_history[self.history_index])
  end
end

return InputModal
