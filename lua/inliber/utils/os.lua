--[[
  Utility functions for OS operations.
--]]

local M = {}

---Build a shell command from the given arguments
---@param args table|string
---@return string[]
function M.build_shell_command(args)
  return {
    (M.os == "windows" and "cmd.exe" or "sh"),
    M.os == "windows" and "/c" or "-c",
    type(args) == "table" and table.concat(args, " ") or args,
  }
end

return M
