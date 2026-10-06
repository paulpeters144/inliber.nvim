local log = require("inliber.utils.log")

local api = vim.api

local M = {}

---Fire an event
---@param event string
---@param opts? table
function M.fire(event, opts)
  opts = opts or {}
  api.nvim_exec_autocmds("User", { pattern = "Inliber" .. event, data = opts })
end

---Notify the user
---@param msg string
---@param level? number|string
---@param opts? table
---@return nil
function M.notify(msg, level, opts)
  opts = opts or {}
  level = level or vim.log.levels.INFO

  return vim.notify(msg, level, {
    title = opts.title or "Inliber",
  })
end

---Escape percent signs in a string for use as a gsub replacement value.
---In Lua's gsub, the replacement string treats %0-%9 as capture references
---and %% as a literal percent. This function doubles all percent signs so
---that the replacement is inserted verbatim.
---@param str string
---@return string
local function escape_gsub_replacement(str)
  return (str:gsub("%%", "%%%%"))
end

---Replace any placeholders (e.g. ${placeholder}) in a string or table
---@param t table|string The content to process
---@param replacements table<string, string> Map of placeholder names to replacement values
---@return string|nil The replaced string if input was string, or nil if input was table (modified in place)
function M.replace_placeholders(t, replacements)
  if type(t) == "string" then
    for placeholder, replacement in pairs(replacements) do
      t = t:gsub("%${" .. vim.pesc(placeholder) .. "}", escape_gsub_replacement(replacement))
    end
    return t
  else
    for key, value in pairs(t) do
      if type(value) == "table" then
        M.replace_placeholders(value, replacements)
      elseif type(value) == "string" then
        for placeholder, replacement in pairs(replacements) do
          value = value:gsub("%${" .. vim.pesc(placeholder) .. "}", escape_gsub_replacement(replacement))
        end
        t[key] = value
      end
    end
  end
end

---Safely get the filetype
---@param filetype string
---@return string
function M.safe_filetype(filetype)
  if filetype == "C++" then
    return "cpp"
  end
  return filetype
end

---Set an option in Neovim
---@param bufnr number
---@param opt string
---@param value any
function M.set_option(bufnr, opt, value)
  if api.nvim_set_option_value then
    return api.nvim_set_option_value(opt, value, {
      buf = bufnr,
    })
  end

  if api.nvim_buf_set_option then
    return api.nvim_buf_set_option(bufnr, opt, value)
  end
end

---Resolve a config value into the module, table or function it points at
---@param args { value: string|function, source?: string }
---@return any|nil
function M.resolve(args)
  local value = args.value
  if type(value) == "function" then
    return value
  end
  if type(value) ~= "string" then
    return nil
  end

  local source = args.source or "Inliber"

  for _, name in ipairs({ "inliber." .. value, value }) do
    local ok, resolved = pcall(require, name)
    if ok then
      return resolved
    end
    -- A module that is on the runtimepath but fails to load must surface its own error
    if not tostring(resolved):match("module '" .. vim.pesc(name) .. "' not found") then
      return log:error("[%s] `%s` could not be loaded: %s", source, name, resolved)
    end
  end

  local chunk, err = loadfile(vim.fs.normalize(value))
  if err or not chunk then
    log:error("[%s] Could not resolve `%s`", source, value)
    return nil
  end

  return chunk()
end

---Resolve a nested table value using a dot-separated path string
---@param tbl table The table to traverse
---@param path string The dot-separated path (e.g. "tools.read_file")
---@return any|nil The resolved value, or nil if the path doesn't exist
function M.resolve_nested_value(tbl, path)
  local parts = vim.split(path, ".", { plain = true })
  local resolved = tbl
  for _, part in ipairs(parts) do
    resolved = resolved[part]
    if not resolved then
      return nil
    end
  end
  return resolved
end

return M
