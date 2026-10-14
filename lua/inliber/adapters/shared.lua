local adapter_utils = require("inliber.adapters.utils")

local M = {}

---Replace roles in the messages with the adapter's defined roles
---@param adapter Inliber.ACPAdapter
---@param messages table
---@return table
function M.map_roles(adapter, messages)
  return adapter_utils.map_roles(adapter.roles, messages)
end

---Deep-merge a user's extend table onto a resolved adapter
---@param adapter Inliber.ACPAdapter
---@param opts { extend?: table, key?: string }
---@return Inliber.ACPAdapter
function M.apply_extend(adapter, opts)
  opts = opts or {}

  local patch = opts.key and opts.extend and opts.extend[opts.key]
  if type(patch) ~= "table" then
    return adapter
  end

  for key, value in pairs(patch) do
    if type(value) == "table" and type(adapter[key]) == "table" then
      adapter[key] = vim.tbl_deep_extend("force", adapter[key], value)
    else
      adapter[key] = value
    end
  end

  return adapter
end

return M
