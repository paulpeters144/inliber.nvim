--[[
===============================================================================
    File:       inliber/tools/approvals.lua
    Author:     paulpeters144
-------------------------------------------------------------------------------
    Description:
      This module implements the tool approvals cache for Inliber.
      It tracks which tools have been approved for use in which tool loop.

      Example:
      {
        -- Tool loop id
        [1] = {
          -- Tools that have been approved
          insert_edit_into_file = true,
          read_file = true,
        },
        [2] = {
          run_command = {
            -- Commands that has have approved
            ["ls -la"] = true,
            ["make test"] = true,
          },
          read_file = true,
        },
      }
-------------------------------------------------------------------------------
    Attribution:
      If you use or distribute this code, please credit:
      paulpeters144 (https://github.com/paulpeters144)
===============================================================================
--]]

local config = require("inliber.config")
local log = require("inliber.utils.log")

---@type table<string, string[]>
local approved = {}

---@alias Inliber.Tools.ApprovalMode "ask"|"auto"|"yolo"

---@type table<number, Inliber.Tools.ApprovalMode>
local modes = {}

---@class Inliber.Tools.Approvals
local Approvals = {}

---Always approve a given tool
---@param loop_id number The tool loop id
---@param args { cmd?: string, tool_name: string }
function Approvals:always(loop_id, args)
  if not args or not args.tool_name then
    return
  end

  local tool_cfg = config.tools and config.tools[args.tool_name]

  if not approved[loop_id] then
    approved[loop_id] = {}
  end

  if tool_cfg and tool_cfg.opts and tool_cfg.opts.require_cmd_approval and args.cmd then
    if not approved[loop_id][args.tool_name] then
      approved[loop_id][args.tool_name] = {}
    end
    approved[loop_id][args.tool_name][args.cmd] = true
    return
  end

  approved[loop_id][args.tool_name] = true
end

---Check if a tool has been approved for a given tool loop, by the mode or by the user
---@param loop_id number
---@param args { cmd?: string, tool_name?: string }
function Approvals:is_approved(loop_id, args)
  args = args or {}
  local mode = self:get_mode(loop_id)
  if mode == "yolo" then
    return true
  end

  local tool_cfg = args.tool_name and config.tools and config.tools[args.tool_name]
  local tool_opts = (tool_cfg and tool_cfg.opts) or {}

  -- Tools approved per command are vetted command by command in auto mode, via their safe list or the judge
  if mode == "auto" and not tool_opts.protect and not tool_opts.require_cmd_approval then
    return true
  end

  local approvals = approved[loop_id]
  if not approvals or not args.tool_name then
    return false
  end

  log:debug("Approvals for %s: %s", loop_id, approvals)

  if tool_opts.require_cmd_approval then
    if not approvals[args.tool_name] then
      return false
    end
    return approvals[args.tool_name][args.cmd] == true
  end

  return approvals[args.tool_name] == true
end

---@param loop_id number
---@return Inliber.Tools.ApprovalMode
function Approvals:get_mode(loop_id)
  return modes[loop_id] or config.tools.opts.approval_mode
end

---@param loop_id number
---@param opts { mode: Inliber.Tools.ApprovalMode }
function Approvals:set_mode(loop_id, opts)
  modes[loop_id] = opts.mode
end

---Can a shell command run without asking, in auto mode?
---@param cmd? string
---@return boolean
function Approvals.is_safe_command(cmd)
  if type(cmd) ~= "string" then
    return false
  end

  cmd = vim.trim(cmd)
  if cmd == "" or cmd:find("[;&|<>`\n\r]") or cmd:find("$(", 1, true) then
    return false
  end

  local run_command = config.tools and config.tools["run_command"]
  local safe_commands = (run_command and run_command.opts and run_command.opts.safe_commands) or {}
  for _, safe_command in ipairs(safe_commands) do
    if cmd == safe_command or vim.startswith(cmd, safe_command .. " ") then
      return true
    end
  end

  return false
end

---Reset the approvals for a given tool loop
---@param loop_id number
---@return nil
function Approvals:reset(loop_id)
  approved[loop_id] = nil
  modes[loop_id] = nil
end

return Approvals
