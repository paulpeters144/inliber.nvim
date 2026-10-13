local buf_utils = require("inliber.utils.buffers")
local config = require("inliber.config")
local markdown = require("inliber.utils.markdown")

local api = vim.api
local fmt = string.format

local M = {}

---Get the lines to share: the whole buffer when small, otherwise the visible lines
---@param winnr number
---@param opts { line_count: number, max_lines: number, cursor_line: number }
---@return number, number
local function get_range(winnr, opts)
  if opts.line_count <= opts.max_lines then
    return 1, opts.line_count
  end
  local start_line, end_line = vim.fn.line("w0", winnr), vim.fn.line("w$", winnr)
  local height = api.nvim_win_get_height(winnr)
  -- Closed folds, as in diff mode, let w0..w$ span far more lines than the window shows
  if end_line - start_line + 1 > height then
    start_line = math.max(1, opts.cursor_line - math.floor(height / 2))
    end_line = math.min(opts.line_count, start_line + height - 1)
  end
  return start_line, end_line
end

---@param bufnr number
---@param opts { start_line: number, end_line: number, filetype: string }
---@return string
local function format_code(bufnr, opts)
  local numbered = {}
  for i, line in ipairs(api.nvim_buf_get_lines(bufnr, opts.start_line - 1, opts.end_line, false)) do
    table.insert(numbered, fmt("%d |%s", opts.start_line + i - 1, line))
  end
  return fmt(
    '<code start_line="%d" end_line="%d">\n%s\n</code>',
    opts.start_line,
    opts.end_line,
    markdown.form_codeblock(table.concat(numbered, "\n"), { ft = opts.filetype })
  )
end

---Describe the user's buffer, cursor and the code around it
---@param buffer_context Inliber.BufferContext
---@param opts { max_lines: number }
---@return string
function M.format(buffer_context, opts)
  local bufnr = buffer_context.bufnr
  local winnr = buffer_context.winnr
  local info = buf_utils.get_info(bufnr)
  local line_count = api.nvim_buf_line_count(bufnr)
  local cursor = api.nvim_win_get_cursor(winnr)

  local lines = {
    "This is the current state of my editor, to help you answer my prompt:",
    "<editor_state>",
    fmt("file: %s", info.relative_path ~= "" and info.relative_path or "[No Name]"),
    fmt("filetype: %s", info.filetype),
    fmt("lines: %d", line_count),
    fmt("modified: %s", tostring(vim.bo[bufnr].modified)),
    fmt("cursor: line %d, column %d", cursor[1], cursor[2] + 1),
  }

  if config.can_send_code() then
    local start_line, end_line =
      get_range(winnr, { line_count = line_count, max_lines = opts.max_lines, cursor_line = cursor[1] })
    table.insert(lines, format_code(bufnr, { start_line = start_line, end_line = end_line, filetype = info.filetype }))
  end

  table.insert(lines, "</editor_state>")
  return table.concat(lines, "\n")
end

return M
