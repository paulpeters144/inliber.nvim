local config = require("inliber.config")

local M = {}

---Factory method to resolve adapters
---@param adapter string|table
---@param opts? table
---@return Inliber.HTTPAdapter
function M.resolve(adapter, opts)
  return require("inliber.adapters.http").resolve(adapter, opts)
end

---Factory method to check if the adapter has been resolved
---@param adapter string|table
---@return boolean
function M.resolved(adapter)
  if not adapter then
    return false
  end
  return require("inliber.adapters.http").resolved(adapter)
end

---Factory method to extend the adapter
---@param adapter string|table
---@param opts? table
---@return Inliber.HTTPAdapter
function M.extend(adapter, opts)
  return require("inliber.adapters.http").extend(adapter, opts)
end

---Factory method to make adapters safe for serialization
---@param adapter string|table
---@return table
function M.make_safe(adapter)
  return require("inliber.adapters.http").make_safe(adapter)
end

---Backwards compatibility: expose HTTP methods directly at root level
---@param args { adapter: Inliber.HTTPAdapter, model?: string }
---@return Inliber.HTTPAdapter
function M.set_model(args)
  return require("inliber.adapters.http").set_model(args)
end

---Get a handler function from an adapter with backwards compatibility
---@param adapter Inliber.HTTPAdapter
---@param handler_name string
---@return nil
function M.get_handler(adapter, handler_name)
  return require("inliber.adapters.http").get_handler(adapter, handler_name)
end

---Call a handler on an adapter with backwards compatibility
---@param adapter Inliber.HTTPAdapter
---@param handler_name string
---@param ... any Additional arguments to pass to the handler
---@return any|nil
function M.call_handler(adapter, handler_name, ...)
  local handler = M.get_handler(adapter, handler_name)
  if handler then
    return handler(adapter, ...)
  end
  return nil
end

return M
