local h = require("tests.helpers")

local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        _G.echoes = 0
        vim.api.nvim_echo = function()
          _G.echoes = _G.echoes + 1
        end
        _G.spinner = require("inliber.utils.spinner").new({ message = "get_editor_state" })
      ]])
    end,
    post_once = child.stop,
  },
})

T["Spinner"] = new_set()

T["Spinner"]["DOES NOT draw while AT a hit-enter prompt"] = function()
  local echoes = child.lua([[
    vim.api.nvim_get_mode = function()
      return { mode = "r", blocking = true }
    end
    _G.spinner:_render()
    return _G.echoes
  ]])

  h.eq(0, echoes)
end

T["Spinner"]["draws while NOT at a prompt"] = function()
  local echoes = child.lua([[
    _G.spinner:_render()
    return _G.echoes
  ]])

  h.eq(1, echoes)
end

T["Spinner"]["shows every running spinner on one line"] = function()
  local text = child.lua([[
    vim.api.nvim_echo = function(chunks)
      _G.text = chunks[1][1]
    end
    local other = require("inliber.utils.spinner").new({ message = "read_file" })
    _G.spinner:start()
    other:start()
    _G.spinner:_render()
    _G.spinner:stop()
    other:stop()
    return _G.text
  ]])

  h.expect_contains("get_editor_state | read_file", text)
end

T["Spinner"]["DOES NOT clear the message area WHILE another spinner runs"] = function()
  local cleared = child.lua([[
    _G.cleared = false
    vim.api.nvim_echo = function(chunks)
      _G.cleared = _G.cleared or chunks[1][1] == ""
    end
    local other = require("inliber.utils.spinner").new({ message = "read_file" })
    _G.spinner:start()
    other:start()
    _G.spinner:stop()
    vim.wait(50)
    local cleared_early = _G.cleared
    other:stop()
    vim.wait(50)
    return { early = cleared_early, last = _G.cleared }
  ]])

  h.eq({ early = false, last = true }, cleared)
end

return T
