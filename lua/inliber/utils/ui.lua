local async = require("plenary.async")

local api = vim.api

local M = {}

---@class Inliber.WindowOpts
---@field bufnr? number Buffer number to use
---@field row? number Row position of the floating window
---@field col? number Column position of the floating window
---@field ft? string Filetype to set for the buffer
---@field ignore_keymaps? boolean Whether to ignore default keymaps
---@field lock? boolean Whether to lock the buffer (non-modifiable)
---@field opts? table Window options to set
---@field overwrite_buffer? boolean Whether to overwrite the buffer content
---@field relative? string Relative position of the floating window
---@field style? string Style of the floating window
---@field title? string Title of the floating window
---@field width? number Default width if not specified in window
---@field height? number Default height if not specified in window
---@field winbar? string Winbar text to display at the top of the window

---Open a floating window with the provided lines
---@param lines table
---@param opts Inliber.WindowOpts
---@return number,number The buffer and window numbers
M.create_float = function(lines, opts)
  local cols = function()
    return vim.o.columns
  end
  local rows = function()
    return vim.o.lines
  end

  if type(opts.height) == "function" then
    opts.height = opts.height()
  end
  if type(opts.width) == "function" then
    opts.width = opts.width()
  end
  if type(opts.height) == "string" then
    opts.height = rows()
  end
  if type(opts.width) == "string" then
    opts.width = cols()
  end

  local width = opts.width
  if width and width > 0 and width < 1 then
    width = math.floor(cols() * width)
  end
  width = (width and width >= 1 and width or opts.width or 85) ---@cast width number

  local height = opts.height
  if height and height > 0 and height < 1 then
    height = math.floor(rows() * height)
  end
  height = (height and height >= 1 and height or opts.height or 17) ---@cast height number

  local bufnr = opts.bufnr or api.nvim_create_buf(false, true)
  api.nvim_set_option_value("filetype", opts.ft or "inliber", { buf = bufnr })

  -- Calculate center position if not specified
  local row = opts.row or opts.row ---@cast row number
  local col = opts.col or opts.col ---@cast col number
  if not row or not col then
    row = math.floor((rows() - height) / 2 - 1) -- Account for status line for better UX
    col = math.floor((cols() - width) / 2)
  end

  local winnr = api.nvim_open_win(bufnr, true, {
    relative = opts.relative or "editor",
    -- thanks to @mini.nvim for this, it's for >= 0.11, to respect users winborder style
    border = (vim.fn.exists("+winborder") == 0 or vim.o.winborder == "") and "single" or nil,
    width = width,
    height = height,
    style = opts.style,
    row = row,
    col = col,
    title = opts.title and (" " .. opts.title .. " ") or " Options ",
    title_pos = "center",
  })

  if not opts.bufnr or opts.overwrite_buffer ~= false then
    api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  end

  if opts.lock then
    vim.bo[bufnr].modified = false
    vim.bo[bufnr].modifiable = false
  end

  if opts.winbar then
    vim.wo[winnr].winbar = opts.winbar
  end

  if opts.opts then
    M.set_win_options(winnr, opts.opts)
  end

  if opts.ignore_keymaps then
    return bufnr, winnr
  end

  -- Set some sensible keymaps for closing the window

  local function close()
    pcall(function()
      api.nvim_win_close(winnr, true)
      api.nvim_buf_delete(bufnr, { force = true })
    end)
  end

  vim.keymap.set("n", "q", close, { buffer = bufnr })

  return bufnr, winnr
end

---@param bufnr number
---@return boolean
M.buf_is_empty = function(bufnr)
  return api.nvim_buf_line_count(bufnr) == 1 and api.nvim_buf_get_lines(bufnr, 0, -1, false)[1] == ""
end

---Scroll the window to show a specific line without moving cursor
---@param bufnr number The buffer number
---@param line_num number The line number to scroll to (1-based)
function M.scroll_to_line(bufnr, line_num)
  local winnr = M.buf_get_win(bufnr)
  if not winnr then
    return
  end

  api.nvim_win_call(winnr, function()
    vim.cmd(":" .. tostring(line_num))
    vim.cmd("normal! zz")
  end)
end

---@param bufnr nil|number
---@return nil|number
M.buf_get_win = function(bufnr)
  for _, winnr in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_buf(winnr) == bufnr then
      return winnr
    end
  end
end

---@param winnr number
---@param opts table
---@return nil
function M.set_win_options(winnr, opts)
  for k, v in pairs(opts) do
    api.nvim_set_option_value(k, v, { scope = "local", win = winnr })
  end
end

---Set a winbar for a specific window
---@param winnr number
---@param text string Text to set in the winbar
---@param hl string Highlight group to use for the winbar
---@return nil
function M.set_winbar(winnr, text, hl)
  if not vim.api.nvim_win_is_valid(winnr) then
    return
  end

  local centered = "%=" .. (text or ""):gsub("%%", "%%%%") .. "%="
  local existing_hl = vim.wo[winnr].winhighlight or ""
  existing_hl = #existing_hl > 0 and existing_hl .. "," or existing_hl
  vim.wo[winnr].winhighlight = existing_hl .. "WinBar:" .. hl .. ",WinBarNC:" .. hl
  vim.wo[winnr].winbar = centered
end

---Wait for user input via vim.ui.input, wrapped in plenary.async
---@param opts table Options for vim.ui.input
---@param callback fun(input: string|nil)
---@return nil
M.input = async.wrap(function(opts, callback)
  --Ref: https://github.com/CopilotC-Nvim/CopilotChat.nvim/blob/7a8e238e36ea9e1df9d6309434a37bcdc15a9fae/lua/CopilotChat/utils.lua#L148
  local fn = function()
    vim.ui.input(opts, function(input)
      if input == nil or input == "" then
        callback(nil)
        return
      end
      callback(input)
    end)
  end

  if vim.in_fast_event() then
    vim.schedule(fn)
  else
    fn()
  end
end, 2)

return M
