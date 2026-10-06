local uv = vim.uv

local fmt = string.format

local M = {}

---Write content to a file, creating directories as needed
---@param path string The file path to write to
---@param content string The content to write to the file
---@return boolean
function M.write_to_path(path, content)
  local dir = vim.fn.fnamemodify(path, ":h")
  if dir ~= "" and vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
  local fd = assert(uv.fs_open(path, "w", 420)) -- 0644
  assert(uv.fs_write(fd, content or "", 0))
  assert(uv.fs_close(fd))

  return true
end

---Check if a file or directory exists at the given path
---@param path string The file or directory path to check
---@return boolean
function M.exists(path)
  local stat = uv.fs_stat(path)
  return stat ~= nil
end

---Delete a file or directory recursively
---@param path string The file or directory path to delete
---@return boolean success, string? error_message
function M.delete(path)
  local stat = uv.fs_stat(path)
  if not stat then
    return false, fmt("Path does not exist: %s", path)
  end

  if stat.type == "directory" then
    local handle = uv.fs_scandir(path)
    if handle then
      while true do
        local name, _ = uv.fs_scandir_next(handle)
        if not name then
          break
        end
        local child_path = path .. "/" .. name
        local success, err = M.delete(child_path)
        if not success then
          return false, err
        end
      end
    end

    local success, err, errname = uv.fs_rmdir(path)
    if not success then
      return false, fmt("Failed to remove directory %s: %s (%s)", path, err, errname)
    end
  else
    local success, err, errname = uv.fs_unlink(path)
    if not success then
      return false, fmt("Failed to remove file %s: %s (%s)", path, err, errname)
    end
  end

  return true, nil
end

---Check if path is a directory
---@param path string The path to check
---@return boolean
function M.is_dir(path)
  local stat = uv.fs_stat(path)
  return stat and stat.type == "directory" or false
end

---Read the content of a file at a given path
---@param path string The file to read
---@return string
function M.read(path)
  local fd = assert(uv.fs_open(path, "r", 420))
  local stat = assert(uv.fs_fstat(fd))
  local data = assert(uv.fs_read(fd, stat.size, 0)) or ""
  assert(uv.fs_close(fd))

  return data
end

---Read the content of a file without blocking the editor
---@param path string The file to read
---@param callback fun(content: string?, error_message: string?)
---@return nil
function M.read_async(path, callback)
  uv.fs_open(path, "r", 420, function(open_err, fd)
    if open_err or not fd then
      return callback(nil, open_err or fmt("Could not open %s", path))
    end

    uv.fs_fstat(fd, function(stat_err, stat)
      if stat_err or not stat then
        uv.fs_close(fd)
        return callback(nil, stat_err or fmt("Could not stat %s", path))
      end
      if stat.type ~= "file" then
        uv.fs_close(fd)
        return callback(nil, fmt("%s is not a file", path))
      end

      uv.fs_read(fd, stat.size, 0, function(read_err, data)
        uv.fs_close(fd)
        if read_err then
          return callback(nil, read_err)
        end
        callback(data or "")
      end)
    end)
  end)
end

---Normalizes extracted content to Unix format
---@param content string
---@return string
function M.normalize_content(content)
  return (content:gsub("\r\n", "\n"):gsub("\r", "\n"))
end

---Check if a path is within the current working directory
---@param path string The absolute path to check
---@return boolean
function M.is_path_within_cwd(path)
  local cwd = vim.uv.fs_realpath(vim.uv.cwd())
  if not cwd then
    return false
  end
  cwd = vim.fs.normalize(cwd) .. "/"

  local normalized = vim.fs.normalize(path)
  -- Resolve symlinks in the path's parent to handle macOS /var -> /private/var
  local parent = vim.fs.dirname(normalized)
  local real_parent = vim.uv.fs_realpath(parent)
  if real_parent then
    normalized = vim.fs.joinpath(real_parent, vim.fs.basename(normalized))
  end

  return normalized:sub(1, #cwd) == cwd
end

---Validate and normalize a path from tool args
---@param path string Raw path from tool args
---@return string|nil normalized_path Returns nil if path is invalid
function M.validate_and_normalize_path(path)
  local normalized = vim.fs.normalize(path)
  if M.exists(normalized) then
    return normalized
  end

  local abs_path = vim.fs.abspath(path)
  local normalized_path = vim.fs.normalize(abs_path)
  if M.exists(normalized_path) then
    return normalized_path
  end

  -- Check for duplicate CWD and fix it
  local cwd = vim.fs.normalize(vim.uv.cwd())
  if normalized_path:find(cwd, 1, true) and normalized_path:find(cwd, #cwd + 2, true) then
    local fixed_path = normalized_path:gsub("^" .. vim.pesc(cwd) .. "/", "")
    fixed_path = vim.fs.normalize(fixed_path)
    if M.exists(fixed_path) then
      return fixed_path
    end
  end

  -- For non-existent files, still return the normalized path
  -- This allows tracking files that may be created during tool execution
  return normalized_path
end

return M
