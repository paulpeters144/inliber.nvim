local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = MiniTest.new_set()

local child = MiniTest.new_child_neovim()

T["Inline ACP"] = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        inline = h.setup_inline({})

        local acp_request = require("inliber.interactions.shared.acp_request")
        _G.submitted = nil
        _G.cancelled = false
        function acp_request.submit(opts)
          _G.submitted = opts
          return { cancel = function() _G.cancelled = true end }
        end
      ]])
    end,
    post_case = function()
      child.lua([[inline = nil]])
    end,
    post_once = child.stop,
  },
})

T["Inline ACP"]["is created with an ACP adapter"] = function()
  h.eq("acp", child.lua([[return inline.adapter.type]]))
  h.eq("test_acp", child.lua([[return inline.adapter.name]]))
end

T["Inline ACP"]["submit routes to the ACP request module"] = function()
  child.lua([[inline:submit({ { role = "user", content = "print hello" } })]])

  h.eq("inline", child.lua_get("_G.submitted.purpose"))
  h.eq("test_acp", child.lua_get("_G.submitted.adapter.name"))
  h.eq("user", child.lua_get("_G.submitted.messages[1].role"))
  h.eq("print hello", child.lua_get("_G.submitted.messages[1].content"))
end

T["Inline ACP"]["parse_output falls back to fenced code for ACP adapters"] = function()
  local result = child.lua([[
    local parsed = inline:parse_output("Here you go:\n```lua\nlocal x = 1\n```")
    if not parsed then
      return nil
    end
    return { code = parsed.code, language = parsed.language }
  ]])

  h.expect_truthy(result)
  h.eq("local x = 1", vim.trim(result.code))
  h.eq("lua", result.language)
end

T["Inline ACP"]["stop cancels an ACP request"] = function()
  child.lua([[
    inline:submit({ { role = "user", content = "print hello" } })
    _G.cancelled = false
    inline:stop()
  ]])

  h.is_true(child.lua_get("_G.cancelled"))
end

T["Inline ACP"]["cancel_last cancels the most recent request first"] = function()
  local order = child.lua([[
    local Inline = require("inliber.interactions.inline")
    local acp_request = require("inliber.interactions.shared.acp_request")
    _G.cancel_order = {}
    function acp_request.submit(opts)
      local label = opts.messages[1].content
      return { cancel = function() table.insert(_G.cancel_order, label) end }
    end

    local first = h.setup_inline({})
    first:submit({ { role = "user", content = "first" } })

    local second = h.setup_inline({})
    second:submit({ { role = "user", content = "second" } })

    Inline.cancel_last()
    Inline.cancel_last()

    return _G.cancel_order
  ]])

  h.eq({ "second", "first" }, order)
end

T["Inline ACP"]["uses a leaner system prompt"] = function()
  child.lua([[inline:prompt("print hello")]])

  h.eq("system", child.lua_get("_G.submitted.messages[1].role"))
  h.expect_starts_with("You are writing lua code", child.lua_get("_G.submitted.messages[1].content"))
end

T["Inline ACP"]["lands a new placement in the current buffer"] = function()
  child.lua([[
    _G.original_bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(_G.original_bufnr, 0, -1, false, { "local x = 1", "local y = 2" })

    -- The agent asks for a new buffer, but an inline edit belongs in the current one
    inline:done(vim.json.encode({ code = "local z = 3", placement = "new" }))
    vim.wait(200)
  ]])

  h.eq(child.lua_get("_G.original_bufnr"), child.lua([[return vim.api.nvim_get_current_buf()]]))
  h.eq(
    { "local x = 1", "local z = 3", "local y = 2" },
    child.lua([[return vim.api.nvim_buf_get_lines(_G.original_bufnr, 0, -1, true)]])
  )
end

return T
