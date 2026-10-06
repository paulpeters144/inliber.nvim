local approvals = require("inliber.tools.approvals")
local config = require("inliber.config")
local ui_utils = require("inliber.utils.ui")

local fmt = string.format

local M = {}

---Create response for output_cb
---@param status "success"|"error"
---@param msg string
---@return table
local function make_response(status, msg)
  return { status = status, data = msg }
end

---Prompt the user for a rejection reason
---@param callback function
local function get_rejection_reason(callback)
  ui_utils.input({ prompt = "Rejection reason: " }, function(input)
    callback(input or "")
  end)
end

---Reject the changes, collecting a reason from the user
---@param opts table
---@return nil
local function reject_changes(opts)
  get_rejection_reason(function(reason)
    local msg = fmt('User rejected the changes for `%s`, with the reason "%s"', opts.title, reason)
    opts.output_cb(make_response("error", msg))
  end)
end

---Open the floating diff view with associated keymaps
---@param opts table
local function open_diff_view(opts)
  local diff_helpers = require("inliber.helpers")

  diff_helpers.show_diff({
    diff_id = math.random(10000000),
    ft = opts.ft,
    from_lines = opts.from_lines,
    to_lines = opts.to_lines,
    title = opts.title,
    tool_name = opts.tool_name,
    keymaps = {
      on_always_accept = function()
        approvals:always(opts.loop_id, { tool_name = opts.tool_name })
        opts.apply()
      end,
      on_accept = function()
        opts.apply()
      end,
      on_reject = function()
        reject_changes(opts)
      end,
    },
  })
end

---Show a diff and handle the approval flow for a tool's proposed changes
---@param opts { from_lines: string[], to_lines: string[], ft: string, title: string, tool_name: string, loop_id: number, approved: boolean, require_confirmation_after: boolean, apply: fun(), output_cb: fun(response: table) }
---@return any
function M.review(opts)
  local diff_enabled = config.display.diff.enabled == true

  if opts.approved or diff_enabled == false or opts.require_confirmation_after == false then
    return opts.apply()
  end

  opts.title = fmt("Proposed changes for `%s`:", opts.title)

  local labels = require("inliber.tools.labels")
  require("inliber.tools.ui").approve({
    name = opts.tool_name,
    prompt = opts.title,
    choices = {
      {
        label = labels.always_accept,
        callback = function()
          approvals:always(opts.loop_id, { tool_name = opts.tool_name })
          opts.apply()
        end,
      },
      {
        label = labels.accept,
        callback = function()
          opts.apply()
        end,
      },
      {
        label = labels.view,
        callback = function()
          open_diff_view(opts)
        end,
      },
      {
        label = labels.reject,
        callback = function()
          reject_changes(opts)
        end,
      },
      {
        label = labels.cancel,
        callback = function()
          opts.output_cb(make_response("error", fmt("User cancelled the changes for `%s`", opts.title)))
        end,
      },
    },
  })
end

return M
