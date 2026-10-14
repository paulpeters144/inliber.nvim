--[[
===============================================================================
    File:       inliber/interactions/inline/approvals.lua
-------------------------------------------------------------------------------
    Description:
      Approvals for the inline diff accept/reject flow, keyed by buffer.
===============================================================================
--]]

local log = require("inliber.utils.log")

---@type table<number, table<string, boolean>> Approved actions per buffer
local approved = {}

---@alias Inliber.Inline.ApprovalMode "ask"|"auto"|"yolo"

---@type table<number, Inliber.Inline.ApprovalMode>
local modes = {}

---@class Inliber.Inline.Approvals
local Approvals = {}

---Always approve an action for a buffer
---@param bufnr number
---@param args { tool_name: string }
function Approvals:always(bufnr, args)
  if not args or not args.tool_name then
    return
  end

  if not approved[bufnr] then
    approved[bufnr] = {}
  end

  approved[bufnr][args.tool_name] = true
end

---Check if an action has been approved for a buffer, by the mode or by the user
---@param bufnr number
---@param args { tool_name?: string }
function Approvals:is_approved(bufnr, args)
  args = args or {}
  local mode = self:get_mode(bufnr)
  if mode == "yolo" or mode == "auto" then
    return true
  end

  local approvals = approved[bufnr]
  if not approvals or not args.tool_name then
    return false
  end

  log:debug("Approvals for %s: %s", bufnr, approvals)

  return approvals[args.tool_name] == true
end

---@param bufnr number
---@return Inliber.Inline.ApprovalMode
function Approvals:get_mode(bufnr)
  return modes[bufnr] or "ask"
end

---@param bufnr number
---@param opts { mode: Inliber.Inline.ApprovalMode }
function Approvals:set_mode(bufnr, opts)
  modes[bufnr] = opts.mode
end

---Reset the approvals for a buffer
---@param bufnr number
---@return nil
function Approvals:reset(bufnr)
  approved[bufnr] = nil
  modes[bufnr] = nil
end

return Approvals
