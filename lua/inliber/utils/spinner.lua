--[[
A lightweight progress spinner shown in the message area. Driven by the
ToolLoop's report_status callback so the user can see the loop is working.
--]]

local api = vim.api

local frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local interval_ms = 100

---@class Inliber.Spinner
---@field timer? uv.uv_timer_t
---@field frame number The current frame index
---@field message string The text shown alongside the spinner
local Spinner = {}

---@param opts? { message?: string }
---@return Inliber.Spinner
function Spinner.new(opts)
  opts = opts or {}
  return setmetatable({
    frame = 1,
    message = opts.message or "Inliber",
  }, { __index = Spinner })
end

---Draw the current frame
---@return nil
function Spinner:_render()
  local text = ("%s %s"):format(frames[self.frame], self.message)
  api.nvim_echo({ { text, "InliberChatInfo" } }, false, {})
end

---Start the spinner
---@return nil
function Spinner:start()
  if self.timer then
    return
  end
  self.timer = vim.uv.new_timer()
  self.timer:start(
    0,
    interval_ms,
    vim.schedule_wrap(function()
      self:_render()
      self.frame = (self.frame % #frames) + 1
    end)
  )
end

---Update the message shown alongside the spinner
---@param message? string
---@return nil
function Spinner:update(message)
  if message and message ~= "" then
    self.message = message
  end
end

---Stop the spinner and clear the message area
---@return nil
function Spinner:stop()
  if self.timer then
    self.timer:stop()
    self.timer:close()
    self.timer = nil
  end
  vim.schedule(function()
    api.nvim_echo({ { "", "Normal" } }, false, {})
  end)
end

return Spinner
