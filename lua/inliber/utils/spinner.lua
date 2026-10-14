--[[
A floating progress spinner anchored to the top-right of the editor while requests run.
--]]

local api = vim.api

local frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local interval_ms = 100
local hl_group = "InliberSpinner"
local hl_group_done = "InliberSpinnerDone"
local marks_ns = api.nvim_create_namespace("inliber.spinner")

---@type number Narrowest float width allowed, in display cells
local min_width = 10

---@class Inliber.Spinner
---@field state "running"|"done" What the spinner row currently shows
---@field label string What the row says after the status glyph
local Spinner = {}

---@type number How long the Done row stays after a request finishes
Spinner.done_ms = 2000

---@type Inliber.Spinner[] The spinners with a visible row, in start order
local entries = {}
---@type number|nil The float window drawing the rows
local winnr = nil
---@type number|nil The float buffer
local bufnr = nil
---@type uv.uv_timer_t|nil The timer advancing the frames
local timer = nil
local frame = 1

---Compute the display-cell cap for the float from the current columns
---@return number
local function float_cap()
  local cap = math.min(40, math.floor(vim.o.columns * 0.4))
  cap = math.max(min_width, cap)
  return math.min(cap, vim.o.columns - 1)
end

---Shorten text to a display-cell budget, keeping the tail
---@param text string
---@param max_cells number
---@return string
local function truncate_label(text, max_cells)
  if vim.fn.strdisplaywidth(text) <= max_cells then
    return text
  end

  local char_count = vim.fn.strchars(text)
  local budget = max_cells - 1
  local cells = 0
  local kept_from = char_count + 1
  for index = char_count, 1, -1 do
    cells = cells + vim.fn.strdisplaywidth(vim.fn.strcharpart(text, index - 1, 1))
    if cells > budget then
      break
    end
    kept_from = index
  end
  return "…" .. vim.fn.strcharpart(text, kept_from - 1)
end

---@param opts? { label?: string }
---@return Inliber.Spinner
function Spinner.new(opts)
  opts = opts or {}
  return setmetatable({ state = "running", label = opts.label or "Thinking" }, { __index = Spinner })
end

---Start the spinner, adding its row to the float
---@return nil
function Spinner:start()
  if vim.tbl_contains(entries, self) then
    return
  end
  table.insert(entries, self)
  self:_render()
  self:_start_timer()
end

---Finish the spinner, showing the Done row until it clears after done_ms
---@return nil
function Spinner:finish()
  if self.state ~= "running" then
    return
  end
  self.state = "done"
  self:_render()
  vim.defer_fn(function()
    entries = vim.tbl_filter(function(spinner)
      return spinner ~= self
    end, entries)
    self:_render()
  end, Spinner.done_ms)
end

---Remove the spinner row immediately, without a Done state
---@return nil
function Spinner:stop()
  entries = vim.tbl_filter(function(spinner)
    return spinner ~= self
  end, entries)
  self:_render()
end

---Draw every spinner row into the shared float
---@return nil
function Spinner:_render()
  if #entries == 0 then
    return self:_close_float()
  end

  local label_budget = float_cap() - 2
  local lines = {}
  local highlights = {}
  local any_running = false
  local width = 0
  for index, spinner in ipairs(entries) do
    local glyph = "✓"
    local highlight = hl_group_done
    if spinner.state == "running" then
      glyph = frames[((frame - 1 + index) % #frames) + 1]
      highlight = hl_group
      any_running = true
    end
    local line = glyph .. " " .. truncate_label(spinner.label, label_budget)
    table.insert(lines, line)
    table.insert(highlights, highlight)
    width = math.max(width, vim.fn.strdisplaywidth(line))
  end

  self:_open_float(width)

  api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  api.nvim_buf_clear_namespace(bufnr, marks_ns, 0, -1)
  for row = 1, #lines do
    api.nvim_buf_set_extmark(bufnr, marks_ns, row - 1, 0, { line_hl_group = highlights[row] })
  end
  self:_resize(#lines, width)

  if not any_running then
    self:_stop_timer()
  end
end

---Open the shared float at the top-right of the editor
---@param width number Float width in display cells
---@return nil
function Spinner:_open_float(width)
  if winnr and api.nvim_win_is_valid(winnr) then
    return
  end

  bufnr = api.nvim_create_buf(false, true)
  api.nvim_buf_set_name(bufnr, "inliber-spinner")
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false

  winnr = api.nvim_open_win(bufnr, false, {
    relative = "editor",
    row = 0,
    col = math.max(0, vim.o.columns - width),
    width = width,
    height = 1,
    style = "minimal",
    focusable = false,
    zindex = 100,
    noautocmd = true,
  })
  vim.wo[winnr].winhighlight = "NormalFloat:Normal"
  vim.wo[winnr].wrap = false
end

---Close the shared float once no row remains
---@return nil
function Spinner:_close_float()
  if not winnr then
    return
  end
  pcall(api.nvim_win_close, winnr, true)
  winnr = nil
  bufnr = nil
end

---Resize and reposition the float as rows come and go
---@param height number The number of visible rows
---@param width number Float width in display cells
---@return nil
function Spinner:_resize(height, width)
  local col = math.max(0, vim.o.columns - width)
  local win_config = api.nvim_win_get_config(winnr)
  if win_config.height ~= height or win_config.col ~= col or win_config.width ~= width then
    api.nvim_win_set_config(winnr, { relative = "editor", row = 0, height = height, col = col, width = width })
  end
end

---Start the timer advancing the frames
---@return nil
function Spinner:_start_timer()
  if timer then
    return
  end
  timer = vim.uv.new_timer()
  timer:start(
    0,
    interval_ms,
    vim.schedule_wrap(function()
      frame = (frame % #frames) + 1
      self:_render()
    end)
  )
end

---Stop and release the frame timer
---@return nil
function Spinner:_stop_timer()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
end

return Spinner
