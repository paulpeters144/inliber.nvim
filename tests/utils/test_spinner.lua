local h = require("tests.helpers")

local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        vim.o.columns = 80
        require("inliber.utils.spinner").done_ms = 20
      ]])
    end,
    post_once = child.stop,
  },
})

---Read the spinner float's rows and position from the child
---@return table|nil
local function float_state()
  local state = child.lua([[
    local bufnr = vim.fn.bufnr("inliber-spinner")
    local winnr = vim.fn.win_findbuf(bufnr)[1]
    if winnr == nil then
      return nil
    end
    local win_config = vim.api.nvim_win_get_config(winnr)
    local marks_ns = vim.api.nvim_get_namespaces()["inliber.spinner"]
    local hl_groups = {}
    if marks_ns then
      local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, marks_ns, 0, -1, { details = true })
      for _, extmark in ipairs(extmarks) do
        hl_groups[extmark[2] + 1] = extmark[4].line_hl_group
      end
    end
    return {
      lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false),
      hl_groups = hl_groups,
      width = win_config.width,
      height = win_config.height,
      row = win_config.row,
      col = win_config.col,
      columns = vim.o.columns,
    }
  ]])
  if state == vim.NIL then
    return nil
  end
  return state
end

T["Spinner"] = new_set()

T["Spinner"]["shows a Thinking row pinned to the top right"] = function()
  child.lua([[
    _G.spinner = require("inliber.utils.spinner").new()
    _G.spinner:start()
  ]])

  local state = float_state()

  h.expect_contains("Thinking", state.lines[1])
  h.eq("InliberSpinner", state.hl_groups[1])
  h.eq(0, state.row)
  h.eq(state.columns, state.col + state.width)
  child.lua([[_G.spinner:stop()]])
end

T["Spinner"]["renders the label after the running glyph"] = function()
  child.lua([[
    _G.spinner = require("inliber.utils.spinner").new({ label = "Edit · init.lua" })
    _G.spinner:start()
  ]])

  local state = float_state()

  h.eq(" ", vim.fn.strcharpart(state.lines[1], 1, 1))
  h.eq("Edit · init.lua", vim.fn.strcharpart(state.lines[1], 2))
  child.lua([[_G.spinner:stop()]])
end

T["Spinner"]["stacks one row per request in flight"] = function()
  child.lua([[
    _G.spinner = require("inliber.utils.spinner").new({ label = "Edit · main.lua" })
    _G.spinner:start()
    _G.other = require("inliber.utils.spinner").new({ label = "Ask · utils.lua" })
    _G.other:start()
  ]])

  local state = float_state()

  h.eq(2, #state.lines)
  h.eq(2, state.height)
  h.expect_contains("Edit · main.lua", state.lines[1])
  h.expect_contains("Ask · utils.lua", state.lines[2])
  child.lua([[
    _G.spinner:stop()
    _G.other:stop()
  ]])
end

T["Spinner"]["staggers frames across concurrent rows"] = function()
  child.lua([[
    _G.spinner = require("inliber.utils.spinner").new({ label = "Edit · main.lua" })
    _G.spinner:start()
    _G.other = require("inliber.utils.spinner").new({ label = "Edit · main.lua" })
    _G.other:start()
  ]])

  local state = float_state()

  local first_glyph = vim.fn.strcharpart(state.lines[1], 0, 1)
  local second_glyph = vim.fn.strcharpart(state.lines[2], 0, 1)
  h.not_eq(first_glyph, second_glyph)
  child.lua([[
    _G.spinner:stop()
    _G.other:stop()
  ]])
end

T["Spinner"]["keeps running rows when another request finishes"] = function()
  child.lua([[
    _G.spinner = require("inliber.utils.spinner").new({ label = "Edit · main.lua" })
    _G.spinner:start()
    _G.other = require("inliber.utils.spinner").new({ label = "Ask · utils.lua" })
    _G.other:start()
    _G.spinner:finish()
  ]])

  local state = float_state()

  h.eq(2, #state.lines)
  h.eq("✓ Edit · main.lua", state.lines[1])
  h.expect_contains("Ask · utils.lua", state.lines[2])
  h.eq("InliberSpinnerDone", state.hl_groups[1])
  h.eq("InliberSpinner", state.hl_groups[2])
  child.lua([[_G.other:stop()]])
end

T["Spinner"]["clears the Done row after done_ms"] = function()
  child.lua([[
    _G.spinner = require("inliber.utils.spinner").new({ label = "Edit · main.lua" })
    _G.spinner:start()
    _G.spinner:finish()
  ]])

  h.eq("✓ Edit · main.lua", float_state().lines[1])

  child.lua([[ vim.wait(200) ]])

  h.eq(nil, float_state())
end

T["Spinner"]["removes the row immediately on stop"] = function()
  child.lua([[
    _G.spinner = require("inliber.utils.spinner").new()
    _G.spinner:start()
    _G.spinner:stop()
  ]])

  h.eq(nil, float_state())
end

T["Spinner"]["DOES NOT truncate a label that is INSIDE the cell budget"] = function()
  child.lua([[
    _G.spinner = require("inliber.utils.spinner").new({ label = "Edit · main.lua" })
    _G.spinner:start()
  ]])

  local state = float_state()

  h.eq(" Edit · main.lua", vim.fn.strcharpart(state.lines[1], 1))
  h.eq(2 + vim.fn.strdisplaywidth("Edit · main.lua"), state.width)
  child.lua([[_G.spinner:stop()]])
end

T["Spinner"]["truncates a label that is OUTSIDE the cell budget"] = function()
  child.lua([[
    _G.spinner = require("inliber.utils.spinner").new({ label = "Edit · " .. string.rep("abcdefghij", 10) })
    _G.spinner:start()
  ]])

  local state = float_state()
  local line = state.lines[1]

  h.eq(" ", vim.fn.strcharpart(line, 1, 1))
  h.eq("…bcdefghijabcdefghijabcdefghij", vim.fn.strcharpart(line, 2))
  h.eq(32, state.width)
  h.eq(state.columns, state.col + state.width)
  child.lua([[_G.spinner:stop()]])
end

T["Spinner"]["keeps the float width within the cell cap"] = function()
  child.lua([[
    vim.o.columns = 200
    _G.spinner = require("inliber.utils.spinner").new({ label = "Edit · " .. string.rep("x", 200) })
    _G.spinner:start()
  ]])

  local state = float_state()

  h.eq(40, state.width)
  h.eq(state.columns, state.col + state.width)
  child.lua([[_G.spinner:stop()]])
end

return T
