local M = {}

---Factory method to resolve adapters
---@param adapter string|table
---@param opts? table
---@return Inliber.ACPAdapter
function M.resolve(adapter, opts)
  return require("inliber.adapters.acp").resolve(adapter, opts)
end

---Factory method to check if the adapter has been resolved
---@param adapter any
---@return boolean
function M.resolved(adapter)
  if not adapter then
    return false
  end
  return require("inliber.adapters.acp").resolved(adapter)
end

---Factory method to extend the adapter
---@param adapter string|table
---@param opts? table
---@return Inliber.ACPAdapter
function M.extend(adapter, opts)
  return require("inliber.adapters.acp").extend(adapter, opts)
end

---Factory method to make adapters safe for serialization
---@param adapter any
---@return table
function M.make_safe(adapter)
  return require("inliber.adapters.acp").make_safe(adapter)
end

---Backwards compatibility: expose adapter methods directly at root level
---@param args { adapter: Inliber.ACPAdapter, model?: string }
---@return Inliber.ACPAdapter
function M.set_model(args)
  return require("inliber.adapters.acp").set_model(args)
end

return M
