local api = vim.api

local M = {}

---Get the information of a given buffer
---@param bufnr number
---@return table
function M.get_info(bufnr)
  local bufname = api.nvim_buf_get_name(bufnr)

  return {
    bufnr = bufnr,
    filetype = api.nvim_get_option_value("filetype", { buf = bufnr }),
    name = vim.fn.fnamemodify(bufname, ":t"),
    number = bufnr,
    path = bufname,
    relative_path = vim.fn.fnamemodify(bufname, ":."),
    short_path = vim.fs.joinpath(vim.fn.fnamemodify(bufname, ":h:t"), vim.fn.fnamemodify(bufname, ":t")),
  }
end

---Check if a path is open as a buffer and return the buffer number
---@param path string The path to check
---@return number|nil Buffer number if found, nil otherwise
function M.get_bufnr_from_path(path)
  local normalized_path = vim.fn.fnamemodify(path, ":p")

  for _, bufnr in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted then
      local buf_path = vim.fn.fnamemodify(api.nvim_buf_get_name(bufnr), ":p")
      if buf_path == normalized_path then
        return bufnr
      end
    end
  end

  return nil
end

---Write content to a given buffer
---@param bufnr number
---@param content string|table
---@return boolean, string|nil
function M.write(bufnr, content)
  local old = {
    modifiable = vim.bo[bufnr].modifiable,
    readonly = vim.bo[bufnr].readonly,
  }
  if not old.modifiable then
    vim.bo[bufnr].modifiable = true
  end
  if old.readonly then
    vim.bo[bufnr].readonly = false
  end

  local lines = content
  if type(lines) == "string" then
    lines = vim.split(content or "", "\n", { plain = true })
  end

  api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)

  api.nvim_buf_call(bufnr, function()
    vim.cmd("silent update!")
  end)

  if not old.modifiable then
    vim.bo[bufnr].modifiable = false
  end
  if old.readonly then
    vim.bo[bufnr].readonly = true
  end

  return true
end

---Add line numbers to the table of content
---@param content string
---@return string
function M.add_line_numbers(content)
  local formatted = {}

  content = vim.split(content, "\n")
  for i, line in ipairs(content) do
    table.insert(formatted, string.format("%d |%s", i, line))
  end

  return table.concat(formatted, "\n")
end

return M
