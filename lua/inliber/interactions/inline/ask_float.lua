--[[
The Ask Float - Floating-window UI for the ask intent's question-and-answer
conversation, with an input line for follow-ups.
--]]

local config = require("inliber.config")
local ui_utils = require("inliber.utils.ui")

local api = vim.api

local MIN_TEXT_ROWS = 8
local WINBAR = " <CR> ask · q close "

---@class Inliber.AskFloat.Config
---@field answer_max_width? number The float's max width in columns
---@field show_timestamps? boolean Show the time next to each speaker
---@field show_token_count? boolean Show the cumulative token count for each response
---@field token_count? fun(tokens: number): string Format the token count
---@field ask_separator? string Separator between the conversation and the input line

---@class Inliber.AskFloat
---@field answer_row? number The buffer row of the latest answer's speaker label
---@field bufnr? number The buffer holding the float's content
---@field winnr? number The current floating window
---@field input_row? number The buffer row where the input line starts
---@field max_width number The float's max width in columns
---@field on_submit? fun(question: string) Callback for a submitted question
---@field overflows boolean Whether the conversation is taller than the window
---@field pending_question? string The question awaiting an answer
---@field pending_asked_at? string The time the pending question was asked
---@field show_timestamps boolean Whether to show the time next to each speaker
---@field show_token_count boolean Whether to show the cumulative token count
---@field token_count fun(tokens: number): string Formats the token count
---@field ask_separator string Separator between the conversation and the input line
---@field thinking boolean Whether the float is waiting on a response
---@field tokens? number The cumulative token count to display
---@field turns table[] The conversation turns being rendered
local AskFloat = {}

---@param opts? Inliber.AskFloat.Config
---@return Inliber.AskFloat
function AskFloat.new(opts)
  opts = opts or config.interactions.inline.ask_float or {}
  return setmetatable({
    max_width = opts.answer_max_width or 110,
    show_timestamps = opts.show_timestamps ~= false,
    show_token_count = opts.show_token_count ~= false,
    token_count = opts.token_count or function(tokens)
      return " (" .. tokens .. " tokens)"
    end,
    ask_separator = opts.ask_separator or "──── ask ────",
    overflows = false,
    thinking = false,
    turns = {},
  }, { __index = AskFloat })
end

---Format a speaker label, with an optional timestamp
---@param speaker string
---@param timestamp? string
---@return string
local function speaker_label(speaker, timestamp)
  if timestamp then
    return ("**%s** · %s"):format(speaker, timestamp)
  end
  return ("**%s**"):format(speaker)
end

---Render the conversation turns as markdown lines
---@param turns table[] The conversation turns
---@param show_timestamps boolean Whether to append the time to each speaker label
---@return string[], number|nil
local function render_turns(turns, show_timestamps)
  local lines = {}
  local answer_row
  for _, turn in ipairs(turns) do
    table.insert(lines, speaker_label("You", show_timestamps and turn.asked_at))
    table.insert(lines, "")
    vim.list_extend(lines, vim.split(turn.question or "", "\n"))
    table.insert(lines, "")
    table.insert(lines, speaker_label("Agent", show_timestamps and turn.answered_at))
    answer_row = #lines
    table.insert(lines, "")
    vim.list_extend(lines, vim.split(turn.answer or "", "\n"))
    table.insert(lines, "")
  end
  return lines, answer_row
end

---Show the conversation in the chat float, creating the window on first use
---@param opts { turns?: table[], tokens?: number, on_submit?: fun(question: string) }
---@return nil
function AskFloat:show(opts)
  opts = opts or {}
  self.turns = opts.turns or self.turns
  self.tokens = opts.tokens
  if opts.on_submit then
    self.on_submit = opts.on_submit
  end
  self.thinking = false
  self.pending_question = nil

  if self:_valid() then
    self:_resize({ width = self:_content_width() })
  else
    self:close()
    local bufnr, winnr = ui_utils.create_float({ "" }, {
      title = "Agent",
      width = self:_content_width(),
      height = MIN_TEXT_ROWS + 1,
      ft = "markdown",
      ignore_keymaps = true,
      winbar = WINBAR,
      opts = { wrap = true, linebreak = true, number = false, relativenumber = false },
    })
    self.bufnr = bufnr
    self.winnr = winnr
  end

  self:_render()
  self:_set_keymaps()
  if self.overflows and self.answer_row then
    self:_focus_answer()
  else
    self:focus_input()
  end
end

---Show a pending question and lock the input while the answer arrives
---@param question string The question awaiting an answer
---@return nil
function AskFloat:set_thinking(question)
  self.thinking = true
  self.pending_question = question
  self.pending_asked_at = os.date("%H:%M")
  self:_render()
end

---Move the cursor to the input line and enter insert mode
---@return nil
function AskFloat:focus_input()
  if not self:_valid() then
    return
  end
  api.nvim_set_current_win(self.winnr)
  local last = api.nvim_buf_line_count(self.bufnr)
  api.nvim_win_set_cursor(self.winnr, { last, 0 })
  if not self.thinking then
    vim.cmd("startinsert!")
  end
end

---Scroll the latest answer to the top of the window, in normal mode
---@return nil
function AskFloat:_focus_answer()
  api.nvim_set_current_win(self.winnr)
  vim.cmd("stopinsert")
  api.nvim_win_call(self.winnr, function()
    vim.fn.winrestview({ lnum = self.answer_row, col = 0, topline = self.answer_row })
  end)
end

---Close the float and release its buffer
---@return nil
function AskFloat:close()
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

---Whether the float's window and buffer are usable
---@return boolean
function AskFloat:_valid()
  return self.bufnr ~= nil
    and api.nvim_buf_is_valid(self.bufnr)
    and self.winnr ~= nil
    and api.nvim_win_is_valid(self.winnr)
end

---Format the token count for the latest response
---@return string|nil
function AskFloat:_token_str()
  if not self.show_token_count or type(self.tokens) ~= "number" then
    return nil
  end
  return self.token_count(self.tokens)
end

---Render the conversation, plus the pending question while thinking
---@return string[], number|nil
function AskFloat:_conversation_lines()
  local lines, answer_row = render_turns(self.turns, self.show_timestamps)
  if self.thinking and self.pending_question then
    table.insert(lines, speaker_label("You", self.show_timestamps and self.pending_asked_at))
    table.insert(lines, "")
    vim.list_extend(lines, vim.split(self.pending_question, "\n"))
    table.insert(lines, "")
    table.insert(lines, speaker_label("Agent"))
    table.insert(lines, "")
  end
  return lines, answer_row
end

---Compute the float width from the conversation content
---@return number
function AskFloat:_content_width()
  local width = 60
  for _, line in ipairs(self:_conversation_lines()) do
    width = math.max(width, vim.fn.strdisplaywidth(line) + 1)
  end
  return math.min(width, self.max_width)
end

---Resize and recenter the window, keeping the dimensions not given
---@param opts { width?: number, height?: number }
---@return nil
function AskFloat:_resize(opts)
  local win_config = api.nvim_win_get_config(self.winnr)
  win_config.width = opts.width or win_config.width
  win_config.height = opts.height or win_config.height
  win_config.col = math.floor((vim.o.columns - win_config.width) / 2)
  win_config.row = math.floor((vim.o.lines - win_config.height) / 2 - 1)
  api.nvim_win_set_config(self.winnr, win_config)
end

---Build the buffer content: conversation, then the input line
---@return string[]
function AskFloat:_build_lines()
  local lines, answer_row = self:_conversation_lines()
  self.answer_row = answer_row

  if #self.turns > 0 then
    table.insert(lines, self.ask_separator)
  end
  table.insert(lines, "")

  return lines
end

---Fit the window to the wrapped conversation and pad it so the input line sits at the bottom
---@return nil
function AskFloat:_fit_height()
  -- Wrapped lines and virtual lines from markdown plugins take extra rows, so measure screen rows
  local text_rows = api.nvim_win_text_height(self.winnr, {}).all
  local max_text_rows = math.floor(vim.o.lines * 0.9) - 1
  local window_rows = math.max(MIN_TEXT_ROWS, math.min(text_rows, max_text_rows))
  self.overflows = text_rows > window_rows

  local last = api.nvim_buf_line_count(self.bufnr)
  local padding = vim.fn["repeat"]({ "" }, math.max(0, window_rows - text_rows))
  api.nvim_buf_set_lines(self.bufnr, last - 1, last - 1, false, padding)

  -- The window height includes the winbar row
  self:_resize({ height = window_rows + 1 })
end

---Write the content to the buffer
---@return nil
function AskFloat:_render()
  if not self:_valid() then
    return
  end

  api.nvim_set_option_value("modifiable", true, { buf = self.bufnr })
  api.nvim_buf_set_lines(self.bufnr, 0, -1, false, self:_build_lines())
  self:_fit_height()
  self.input_row = api.nvim_buf_line_count(self.bufnr)
  api.nvim_set_option_value("modifiable", not self.thinking, { buf = self.bufnr })

  -- Show token count in the winbar (unaffected by markdown plugins)
  local token_str = self:_token_str()
  local winbar = token_str and (WINBAR .. " " .. token_str) or WINBAR
  api.nvim_set_option_value("winbar", winbar, { win = self.winnr })
end

---Set keymaps for submitting questions and closing the float
---@return nil
function AskFloat:_set_keymaps()
  local bufnr = self.bufnr

  vim.keymap.set("i", "<CR>", function()
    self:_submit_input()
  end, { buffer = bufnr })
  vim.keymap.set("n", "<CR>", function()
    self:focus_input()
  end, { buffer = bufnr })
  vim.keymap.set("n", "i", function()
    self:focus_input()
  end, { buffer = bufnr })
  vim.keymap.set("n", "q", function()
    self:close()
  end, { buffer = bufnr })
  vim.keymap.set("n", "<Esc>", function()
    self:close()
  end, { buffer = bufnr })
end

---Submit the question from the input line and any pasted lines below it
---@return nil
function AskFloat:_submit_input()
  if self.thinking then
    return
  end
  local lines = api.nvim_buf_get_lines(self.bufnr, self.input_row - 1, -1, false)
  local question = vim.trim(table.concat(lines, "\n"))
  if question == "" then
    return
  end
  local on_submit = self.on_submit
  if on_submit then
    on_submit(question)
  end
end

return AskFloat
