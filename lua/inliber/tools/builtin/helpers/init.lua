local fmt = string.format

local M = {}

---Rejection message back to the LLM
---@param self Inliber.Tools.Tool
---@param opts table
---@return nil
M.rejected = function(self, opts)
  opts = opts or {}

  local rejection = opts.message or "The user declined to execute the tool"
  if opts.opts and opts.opts.reason then
    rejection = fmt('%s, with the reason: "%s"', rejection, opts.opts.reason)
  end

  return opts.tools.host:add_tool_output(self, rejection)
end

return M
