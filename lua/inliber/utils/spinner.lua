--[[
A lightweight progress spinner shown in the message area. Driven by the
ToolLoop's report_status callback so the user can see the loop is working.
--]]

local api = vim.api

local frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local interval_ms = 100

---@class Inliber.Spinner
---@field message string The text shown alongside the spinner
local Spinner = {}

---@type Inliber.Spinner[] The spinners currently drawn, sharing one line in the message area
local running = {}
---@type uv.uv_timer_t|nil
local timer = nil
local frame = 1

---@param opts? { message?: string }
---@return Inliber.Spinner
function Spinner.new(opts)
  opts = opts or {}
  return setmetatable({
    message = opts.message or "Inliber",
  }, { __index = Spinner })
end

---Draw the current frame with the message of every running spinner
---@return nil
function Spinner:_render()
  -- Echoing at a hit-enter or more prompt adds a new line on every frame instead of redrawing
  if api.nvim_get_mode().mode:sub(1, 1) == "r" then
    return
  end
  local messages = vim.tbl_map(function(spinner)
    return spinner.message
  end, #running > 0 and running or { self })
  local text = ("%s %s"):format(frames[frame], table.concat(messages, " | "))
  api.nvim_echo({ { text, "InliberChatInfo" } }, false, {})
end

---Start the spinner
---@return nil
function Spinner:start()
  if vim.tbl_contains(running, self) then
    return
  end
  table.insert(running, self)
  if timer then
    return
  end
  timer = vim.uv.new_timer()
  timer:start(
    0,
    interval_ms,
    vim.schedule_wrap(function()
      if running[1] then
        running[1]:_render()
      end
      frame = (frame % #frames) + 1
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

---Stop the spinner, clearing the message area once no other spinner is running
---@return nil
function Spinner:stop()
  running = vim.tbl_filter(function(spinner)
    return spinner ~= self
  end, running)
  if #running > 0 or not timer then
    return
  end
  timer:stop()
  timer:close()
  timer = nil
  vim.schedule(function()
    api.nvim_echo({ { "", "Normal" } }, false, {})
  end)
end

return Spinner
