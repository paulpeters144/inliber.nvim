local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = new_set()

local child = MiniTest.new_child_neovim()

T["ACP Request"] = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')

        _G.adapter = {
          name = "test_acp",
          type = "acp",
          roles = { user = "user", assistant = "assistant" },
        }

        -- Stub the acp module so M.submit runs against a controllable connection
        package.loaded["inliber.acp"] = {
          new = function(args)
            _G.connection_count = (_G.connection_count or 0) + 1
            local conn = { adapter = args.adapter }
            function conn:is_ready() return true end
            function conn:connect_and_authenticate() return self end
            function conn:renew_session() return true end
            function conn:session_prompt(messages)
              _G.shaped = messages
              local builder = {}
              conn._active_prompt = builder
              function builder:on_message_chunk(fn) self._chunk = fn; return self end
              function builder:on_complete(fn) self._complete = fn; return self end
              function builder:on_error(fn) self._error = fn; return self end
              function builder:with_options(opts) self._options = opts; return self end
              function builder:send() _G.sent_builder = self end
              function builder:cancel() _G.builder_cancelled = true end
              return builder
            end
            return conn
          end,
        }

        -- Stub defaults so model application is observable without config-option machinery
        package.loaded["inliber.interactions.inline.acp.defaults"] = {
          apply = function(adapter, connection)
            _G.applied = adapter.name
          end,
        }

        package.loaded["inliber.interactions.shared.acp_request"] = nil
        acp_request = require("inliber.interactions.shared.acp_request")
      ]])
    end,
    post_case = function()
      child.lua([[
        package.loaded["inliber.acp"] = nil
        package.loaded["inliber.interactions.inline.acp.defaults"] = nil
        package.loaded["inliber.interactions.shared.acp_request"] = nil
        _G.shaped = nil
        _G.sent_builder = nil
        _G.done = nil
        _G.errored = nil
        _G.connection_count = nil
        _G.builder_cancelled = nil
        _G.applied = nil
      ]])
    end,
    post_once = child.stop,
  },
})

T["ACP Request"]["folds system content into the first user message and tags _meta"] = function()
  child.lua([[
    acp_request.submit({
      purpose = "inline",
      adapter = _G.adapter,
      messages = {
        { role = "system", content = "You are helpful" },
        { role = "user", content = "Hello" },
      },
      on_done = function(output) _G.done = output end,
    })
  ]])

  local shaped = child.lua_get("_G.shaped")
  h.eq(1, #shaped)
  h.eq("user", shaped[1].role)
  h.eq("You are helpful\n\nHello", shaped[1].content)
  h.eq("table", type(shaped[1]._meta))
end

T["ACP Request"]["preserves an existing _meta tag"] = function()
  child.lua([[
    acp_request.submit({
      purpose = "inline",
      adapter = _G.adapter,
      messages = {
        { role = "user", content = "Hello", _meta = { tag = "visual" } },
      },
      on_done = function(output) _G.done = output end,
    })
  ]])

  local shaped = child.lua_get("_G.shaped")
  h.eq("visual", shaped[1]._meta.tag)
end

T["ACP Request"]["routes a canceled turn to on_error"] = function()
  child.lua([[
    acp_request.submit({
      purpose = "inline",
      adapter = _G.adapter,
      messages = { { role = "user", content = "Hi" } },
      on_done = function(output) _G.done = output end,
      on_error = function(err) _G.errored = err end,
    })
    _G.sent_builder._complete("canceled")
  ]])

  h.eq(vim.NIL, child.lua_get("_G.done"))
  h.expect_truthy(child.lua_get("_G.errored"))
end

T["ACP Request"]["routes an end_turn to on_done"] = function()
  child.lua([[
    acp_request.submit({
      purpose = "inline",
      adapter = _G.adapter,
      messages = { { role = "user", content = "Hi" } },
      on_done = function(output) _G.done = output end,
      on_error = function(err) _G.errored = err end,
    })
    _G.sent_builder._chunk("Hello ")
    _G.sent_builder._complete("end_turn")
  ]])

  h.eq("Hello ", child.lua_get("_G.done"))
  h.eq(vim.NIL, child.lua_get("_G.errored"))
end

T["ACP Request"]["applies adapter defaults to the session"] = function()
  child.lua([[
    acp_request.submit({
      purpose = "inline",
      adapter = _G.adapter,
      messages = { { role = "user", content = "Hi" } },
      on_done = function() end,
    })
  ]])

  h.eq("test_acp", child.lua_get("_G.applied"))
end

T["ACP Request"]["runs a concurrent request on its own connection"] = function()
  child.lua([[
    acp_request.submit({
      purpose = "inline",
      adapter = _G.adapter,
      messages = { { role = "user", content = "First" } },
      on_done = function() end,
    })
    acp_request.submit({
      purpose = "inline",
      adapter = _G.adapter,
      messages = { { role = "user", content = "Second" } },
      on_done = function() end,
    })
  ]])

  h.eq(2, child.lua_get("_G.connection_count"))
end

return T
