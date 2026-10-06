local config = require("inliber.config")

local tokens = require("inliber.utils.tokens")

local M = {}

local fmt = string.format

---The most tokens a single tool result may contribute to the message history
---@param adapter Inliber.HTTPAdapter
---@return number
local function tool_output_limit(adapter)
  local limit = config.tools.opts.max_output_tokens
  local input_limit = require("inliber.adapters.shared").input_limit(adapter)

  return input_limit and math.min(limit, input_limit) or limit
end

---@param opts { adapter: Inliber.HTTPAdapter, content: string }
---@return string
function M.truncate_tool_output(opts)
  if type(opts.content) ~= "string" or opts.content == "" then
    return opts.content
  end

  local token_count = tokens.calculate(opts.content)
  local limit = tool_output_limit(opts.adapter)
  if token_count <= limit then
    return opts.content
  end

  local notice = fmt(
    "\n\n[Tool output truncated: it was around %d tokens, which is over the %d token limit for a single tool result. Re-run the tool with a narrower scope to see the rest.]",
    token_count,
    limit
  )

  -- The notice has to fit inside the limit too, otherwise trimming puts us back over it
  local budget = math.max(limit - tokens.calculate(notice), 0)
  local keep = math.floor(#opts.content * (budget / token_count))

  return opts.content:sub(1, keep) .. notice
end

return M
