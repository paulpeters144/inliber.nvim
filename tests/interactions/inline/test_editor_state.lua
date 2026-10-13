local h = require("tests.helpers")

local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        require("inliber.config").setup({})
        _G.format = function(lines, max_lines)
          vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
          vim.bo.filetype = "lua"
          return require("inliber.interactions.inline.editor_state").format(
            { bufnr = vim.api.nvim_get_current_buf(), winnr = vim.api.nvim_get_current_win() },
            { max_lines = max_lines or 300 }
          )
        end
      ]])
    end,
    post_once = child.stop,
  },
})

T["EditorState"] = new_set()

T["EditorState"]["shares the buffer details"] = function()
  local output = child.lua([[return _G.format({ "local a = 1", "local b = 2" })]])

  h.expect_contains("filetype: lua", output)
  h.expect_contains("lines: 2", output)
  h.expect_contains("modified: true", output)
  h.expect_contains("cursor: line 1, column 1", output)
end

T["EditorState"]["shares the whole buffer INSIDE max_lines"] = function()
  local output = child.lua([[
    local lines = {}
    for i = 1, 100 do
      lines[i] = "line " .. i
    end
    return _G.format(lines)
  ]])

  h.expect_contains("1 |line 1", output)
  h.expect_contains("100 |line 100", output)
end

T["EditorState"]["shares only the visible lines OUTSIDE max_lines"] = function()
  local output = child.lua([[
    local lines = {}
    for i = 1, 100 do
      lines[i] = "line " .. i
    end
    return _G.format(lines, 50)
  ]])

  h.expect_contains("1 |line 1", output)
  h.expect_not_contains("100 |line 100", output)
end

T["EditorState"]["shares only the lines around the cursor WHEN folds hide most of the buffer"] = function()
  local output = child.lua([[
    local lines = {}
    for i = 1, 100 do
      lines[i] = "line " .. i
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.cmd("2,99fold")
    return require("inliber.interactions.inline.editor_state").format(
      { bufnr = vim.api.nvim_get_current_buf(), winnr = vim.api.nvim_get_current_win() },
      { max_lines = 50 }
    )
  ]])

  h.expect_contains("1 |line 1", output)
  h.expect_not_contains("100 |line 100", output)
end

T["EditorState"]["DOES NOT share code when sending code is disabled"] = function()
  local output = child.lua([[
    require("inliber.config").setup({ opts = { send_code = false } })
    return _G.format({ "local secret = 1" })
  ]])

  h.expect_contains("filetype: lua", output)
  h.expect_not_contains("local secret", output)
end

return T
