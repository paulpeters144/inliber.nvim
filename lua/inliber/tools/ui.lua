local labels = require("inliber.tools.labels")
local utils = require("inliber.utils")

local fmt = string.format

---Headless UI helpers for the tool loop: approvals and questions via vim.ui
local M = {}

---@class Inliber.Tools.UI.Choice
---@field label string Display label (e.g. "Always accept")
---@field callback function Called when the user selects this choice

---Ask the user to approve a pending tool call
---@param opts { name: string, prompt?: string, choices: Inliber.Tools.UI.Choice[] }
---@return nil
function M.approve(opts)
  utils.fire("ToolApprovalRequested", { name = opts.name })

  local items = {}
  for _, choice in ipairs(opts.choices) do
    table.insert(items, choice.label)
  end

  local prompt = opts.prompt
  if prompt == nil or prompt == "" then
    prompt = fmt("Run the %q tool?", opts.name)
  end

  vim.ui.select(items, { prompt = prompt }, function(_, idx)
    -- Dismissing the prompt cancels the pending tool
    if not idx then
      for _, choice in ipairs(opts.choices) do
        if choice.label == labels.cancel then
          utils.fire("ToolApprovalFinished", { choice = choice.label })
          return choice.callback()
        end
      end
      return
    end

    local choice = opts.choices[idx]
    utils.fire("ToolApprovalFinished", { choice = choice.label })
    choice.callback()
  end)
end

return M
