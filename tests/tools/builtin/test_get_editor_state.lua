local h = require("tests.helpers")

local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        _G.tool = require("inliber.tools.builtin.get_editor_state")
        _G.run = function(args, max_lines)
          return _G.tool.cmds[1]({ host = { bufnr = 0 }, tool = { opts = { max_lines = max_lines or 2000 } } }, args)
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["GetEditorState"] = new_set()

T["GetEditorState"]["reads unsaved buffer content"] = function()
  local result = child.lua([[
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "local unsaved = true" })
    return _G.run({ action = "read_buffer", bufnr = bufnr })
  ]])

  h.eq("success", result.status)
  h.expect_contains("1 |local unsaved = true", result.data)
end

T["GetEditorState"]["lists listed buffers"] = function()
  local result = child.lua([[
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, "listed.lua")
    return _G.run({ action = "list_buffers" })
  ]])

  h.expect_contains("listed.lua", result.data)
end

T["GetEditorState"]["DOES NOT list unlisted buffers"] = function()
  local result = child.lua([[
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, "unlisted.lua")
    return _G.run({ action = "list_buffers" })
  ]])

  h.expect_not_contains("unlisted.lua", result.data)
end

T["GetEditorState"]["DOES NOT list floating windows"] = function()
  local result = child.lua([[
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, "float.lua")
    vim.api.nvim_open_win(bufnr, false, { relative = "editor", row = 1, col = 1, width = 10, height = 2 })
    return _G.run({ action = "list_windows" })
  ]])

  h.expect_not_contains("float.lua", result.data)
end

T["GetEditorState"]["truncates a buffer OUTSIDE max_lines"] = function()
  local result = child.lua([[
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "one", "two", "three" })
    return _G.run({ action = "read_buffer", bufnr = bufnr }, 2)
  ]])

  h.expect_contains("2 |two", result.data)
  h.expect_not_contains("three", result.data)
  h.expect_contains("truncated", result.data)
end

T["GetEditorState"]["numbers lines from start_line"] = function()
  local result = child.lua([[
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "one", "two", "three" })
    return _G.run({ action = "read_buffer", bufnr = bufnr, start_line = 2, end_line = 3 })
  ]])

  h.expect_contains("2 |two", result.data)
  h.expect_contains("3 |three", result.data)
  h.expect_not_contains("one", result.data)
end

T["GetEditorState"]["reads the diff between diff windows"] = function()
  local result = child.lua([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two" })
    vim.cmd("diffthis | rightbelow vnew")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "three" })
    vim.cmd("diffthis")
    return _G.run({ action = "read_diff" })
  ]])

  h.eq("success", result.status)
  h.expect_contains("-two", result.data)
  h.expect_contains("+three", result.data)
end

T["GetEditorState"]["errors when NO diff is open"] = function()
  local result = child.lua([[
    vim.cmd("vnew")
    return _G.run({ action = "read_diff" })
  ]])

  h.eq("error", result.status)
end

T["GetEditorState"]["errors on an invalid bufnr"] = function()
  local result = child.lua([[return _G.run({ action = "read_buffer", bufnr = 9999 })]])

  h.eq("error", result.status)
end

return T
