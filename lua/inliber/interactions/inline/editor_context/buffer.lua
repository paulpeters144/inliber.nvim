local buf_utils = require("inliber.utils.buffers")
local markdown = require("inliber.utils.markdown")

local fmt = string.format

---@class Inliber.Inline.EditorContext.Buffer: Inliber.Inline.EditorContextItems
local Buffer = {}

---@param args Inliber.Inline.EditorContextArgs
function Buffer.new(args)
  return setmetatable({
    context = args.context,
  }, { __index = Buffer })
end

---Fetch and output a buffer's contents
---@return string|nil
function Buffer:output()
  local message = "To help you assist with my user prompt, I'm attaching the contents of a buffer"
  local bufnr = self.context.bufnr
  local path = buf_utils.get_info(bufnr).path

  local ok, content = pcall(function()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
    local filetype = buf_utils.get_info(bufnr).filetype
    return markdown.form_codeblock(buf_utils.add_line_numbers(table.concat(lines, "\n")), { ft = filetype })
  end)

  if not ok then
    return
  end

  return fmt(
    [[<attachment filepath="%s" buffer_number="%s">%s:
%s
</attachment>]],
    path,
    bufnr,
    message,
    content
  )
end

return Buffer
