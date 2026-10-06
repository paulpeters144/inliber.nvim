--[[
The Input Modal - Small floating-window input for the inline interaction.
Collects the first prompt for both the ask and edit intents before the request
runs.
--]]

local config = require("inliber.config")
local ui_utils = require("inliber.utils.ui")

local api = vim.api

---@class Inliber.InputModal.Config
---@field title? string Title of the input modal
---@field input_width? number Width of the input modal in columns

---@class Inliber.InputModal
---@field bufnr? number The buffer holding the input
---@field winnr? number The current floating window
---@field input_width number Width of the input modal in columns
---@field title string Title of the input modal
local InputModal = {}

---@param opts? Inliber.InputModal.Config
---@return Inliber.InputModal
function InputModal.new(opts)
  opts = opts or config.interactions.inline.input_modal or {}
  return setmetatable({
    input_width = opts.input_width or 60,
    title = opts.title or "Ask",
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
    opts = { number = false, relativenumber = false },
  })
  self.bufnr = bufnr
  self.winnr = winnr

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

  vim.keymap.set({ "i", "n" }, "<CR>", function()
    local line = vim.trim(api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or "")
    finish(line ~= "" and line or nil)
  end, { buffer = bufnr })

  vim.keymap.set({ "i", "n" }, "<Esc>", function()
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

return InputModal
