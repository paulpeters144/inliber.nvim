local log = require("inliber.utils.log")

local M = {}

---Extend a default adapter
---@param base_tbl table
---@param new_tbl table
---@return nil
function M.extend(base_tbl, new_tbl)
  for name, adapter in pairs(new_tbl) do
    if name ~= "extend" and name ~= "opts" and base_tbl[name] then
      if type(adapter) == "table" then
        base_tbl[name] = adapter
      end
    end
  end
end

-------------------------------------------------------------------------------
-- Utility functions extracted from adapters/init.lua
-------------------------------------------------------------------------------

---Check if a variable starts with "cmd:"
---@param var string
---@return boolean
local function is_cmd(var)
  return var:match("^cmd:")
end

---Check if a variable starts with "file:"
---@param var string
---@return boolean
local function is_file(var)
  return var:match("^file:")
end

---Read the contents of the file in the environment variable, relative to the cwd if not absolute
---@param var string
---@return string|nil
local function read_file(var)
  log:trace("[Adapters] Detected file in environment variable")

  local path = vim.fs.normalize(var:sub(6))
  local files = require("inliber.utils.files")

  if not files.exists(path) then
    return log:error("[Adapters] Could not find file: %s", path)
  end

  local ok, content = pcall(files.read, path)
  if not ok then
    return log:error("[Adapters] Could not read file: %s", path)
  end

  return (content:gsub("%s+$", ""))
end

---Check if the variable is an environment variable
---@param var string
---@return boolean
local function is_env_var(var)
  local found_var = os.getenv(var)
  if not found_var then
    return false
  end
  return true
end

---Run the command in the environment variable
---@param var string
---@param timeout number
---@return string|nil
local function run_cmd(var, timeout)
  log:trace("[Adapters] Detected cmd in environment variable")

  local cmd = var:sub(5)

  local shell_cmd = require("inliber.utils.os").build_shell_command(cmd)

  local obj = vim.system(shell_cmd, { text = true, timeout = timeout })
  if not obj then
    return log:error("[Adapters] Could not execute cmd: %s", cmd)
  end

  local result = obj:wait()

  if result.code ~= 0 then
    return log:error("[Adapters] Command execution failed: %s", cmd)
  end

  log:trace("[Adapters] Executed cmd: %s", cmd)

  local output = result.stdout or ""
  output = output:gsub("%s+$", "")

  return output
end

---Get the environment variable
---@param var string
---@return string|nil
local function get_env_var(var)
  log:trace("Fetching environment variable: %s", var)
  return os.getenv(var) or nil
end

---Get the schema value
---@param adapter table
---@param var string
---@return string|nil
local function get_schema(adapter, var)
  log:trace("Fetching variable from schema: %s", var)

  local keys = {}
  for key in var:gmatch("[^%.]+") do
    table.insert(keys, key)
  end

  local node = adapter
  for _, key in ipairs(keys) do
    if type(node) ~= "table" then
      return nil
    end
    node = node[key]
    if node == nil then
      return nil
    end
  end

  if not node then
    return
  end

  return node
end

---Replace a variable with its value e.g. "${var}" -> "value"
---@param adapter table
---@param str string
---@return string
local function replace_var(adapter, str)
  if type(str) ~= "string" then
    return str
  end

  local pattern = "${(.-)}"

  local result = str:gsub(pattern, function(var)
    return adapter.env_replaced[var]
  end)

  return result
end

---Get the variables from the env key of the adapter
---@param adapter table
---@param args? { timeout: number }
---@return table
function M.get_env_vars(adapter, args)
  local env_vars = adapter.env or {}

  if not env_vars then
    return adapter
  end

  adapter.env_replaced = {}

  for k, v in pairs(env_vars) do
    if type(v) == "string" and is_cmd(v) then
      local timeout = (args and args.timeout) or 5000
      adapter.env_replaced[k] = run_cmd(v, timeout)
    elseif type(v) == "string" and is_file(v) then
      adapter.env_replaced[k] = read_file(v)
    elseif type(v) == "string" and is_env_var(v) then
      adapter.env_replaced[k] = get_env_var(v)
    elseif type(v) == "function" then
      adapter.env_replaced[k] = v(adapter)
    else
      local schema = get_schema(adapter, v)
      if schema then
        adapter.env_replaced[k] = schema
      else
        adapter.env_replaced[k] = v
      end
    end
  end

  return adapter
end

---Set env vars in a given object in the adapter
---@param adapter table
---@param object string|table
---@return string|table|nil
function M.set_env_vars(adapter, object)
  local obj_copy = vim.deepcopy(object)

  if type(obj_copy) == "string" then
    return replace_var(adapter, obj_copy)
  elseif type(obj_copy) == "table" then
    local replaced = {}
    for k, v in pairs(obj_copy) do
      if type(v) == "string" then
        replaced[k] = replace_var(adapter, v)
      elseif type(v) == "function" then
        replaced[k] = replace_var(adapter, v(adapter))
      else
        replaced[k] = v
      end
    end
    return replaced
  end
end

---Replace roles in the messages with the adapter's defined roles
---@param roles table The roles mapping, e.g. { user = "human", assistant = "ai" }
---@param messages table
---@return table
function M.map_roles(roles, messages)
  for _, message in ipairs(messages) do
    if message.role then
      message.role = roles[message.role:lower()] or message.role
    end
  end

  return messages
end

return M
