local h = require("tests.helpers")

local new_set = MiniTest.new_set

local child = MiniTest.new_child_neovim()
T = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')
        utils = require("inliber.adapters.utils")

        _G.test_adapter = {
          name = "test_adapter",
          type = "acp",
          roles = { llm = "assistant", user = "user" },
          commands = { default = { "test-agent", "--acp" } },
          env = {
            home = "HOME",
            model = "defaults.model",
          },
          defaults = {
            model = "test-model-v2",
            mcpServers = {},
            timeout = 20000,
          },
          parameters = {
            protocolVersion = 1,
          },
        }
      ]])
    end,
    post_case = child.stop,
  },
})

T["ACP Adapter"] = new_set()

T["ACP Adapter"]["resolves a preset adapter with its command"] = function()
  local result = child.lua([[
    local adapter = require("inliber.adapters").resolve("claude_code")
    return {
      name = adapter.name,
      type = adapter.type,
      formatted = adapter.formatted_name,
      command = adapter.commands.selected,
    }
  ]])

  h.eq("claude_code", result.name)
  h.eq("acp", result.type)
  h.eq("Claude Code", result.formatted)
  h.eq({ "claude-agent-acp" }, result.command)
end

T["ACP Adapter"]["resolve falls back to the inline default adapter"] = function()
  local result = child.lua([[return require("inliber.adapters").resolve().name]])
  h.eq("copilot_acp", result)
end

T["ACP Adapter"]["resolves a table adapter"] = function()
  local result = child.lua([[
    local adapter = require("inliber.adapters").resolve(_G.test_adapter)
    return { name = adapter.name, type = adapter.type, command = adapter.commands.selected }
  ]])

  h.eq("test_adapter", result.name)
  h.eq("acp", result.type)
  h.eq({ "test-agent", "--acp" }, result.command)
end

T["ACP Adapter"]["resolved() is true only for resolved adapters"] = function()
  local result = child.lua([[
    local adapters = require("inliber.adapters")
    return {
      resolved = adapters.resolved(adapters.resolve("claude_code")),
      not_resolved = adapters.resolved("claude_code"),
      nil_value = adapters.resolved(nil),
    }
  ]])

  h.eq(true, result.resolved)
  h.eq(false, result.not_resolved)
  h.eq(false, result.nil_value)
end

T["ACP Adapter"]["resolve applies session_config_options to a string adapter"] = function()
  local result = child.lua([[
    local adapter = require("inliber.adapters").resolve("claude_code", { model = "opus" })
    return adapter.defaults.session_config_options
  ]])

  h.eq("opus", result.model)
end

T["ACP Adapter"]["extend patches by config key, not resolved name"] = function()
  local result = child.lua([[
    require("inliber").setup({
      adapters = { acp = {
        -- A second config key resolving to the same preset
        claude_variant = function()
          return require("inliber.adapters").extend("claude_code")
        end,
        extend = {
          claude_code = { defaults = { timeout = 1000 } },
          claude_variant = { defaults = { timeout = 2000 } },
        },
      } },
    })
    local adapters = require("inliber.adapters")
    return {
      claude_code = adapters.resolve("claude_code").defaults.timeout,
      variant = adapters.resolve("claude_variant").defaults.timeout,
    }
  ]])

  h.eq(1000, result.claude_code)
  h.eq(2000, result.variant)
end

T["ACP Adapter"]["set_model delegates to the connection"] = function()
  local result = child.lua([[
    _G.set_model_called = nil
    local connection = {
      set_model = function(_, model)
        _G.set_model_called = model
        return true
      end,
    }
    local ok = require("inliber.adapters").set_model({ acp_connection = connection, model = "opus" })
    return { ok = ok, called = _G.set_model_called }
  ]])

  h.eq(true, result.ok)
  h.eq("opus", result.called)
end

T["ACP Adapter"]["make_safe serializes the adapter"] = function()
  local result = child.lua([[
    local adapter = require("inliber.adapters").resolve("claude_code")
    local safe = require("inliber.adapters").make_safe(adapter)
    return { name = safe.name, type = safe.type, has_metatable = getmetatable(safe) ~= nil }
  ]])

  h.eq("claude_code", result.name)
  h.eq("acp", result.type)
  h.eq(false, result.has_metatable)
end

T["ACP Adapter"]["can form environment variables"] = function()
  local result = child.lua([[
    local adapter = require("inliber.adapters").extend(_G.test_adapter)
    return utils.get_env_vars(adapter)
  ]])

  h.eq(child.lua_get([[_G.test_adapter.defaults.model]]), result.env_replaced.model)
  h.eq(os.getenv("HOME"), result.env_replaced.home)
end

T["ACP Adapter"]["can set environment variables in the adapter"] = function()
  local result = child.lua([[
    adapter = require("inliber.adapters").extend(_G.test_adapter)
    utils.get_env_vars(adapter)

    return utils.set_env_vars(adapter, adapter.commands.default)
  ]])

  h.eq({ "test-agent", "--acp" }, result)
end

T["ACP Adapter"]["will not set environment variables if it doesn't need to"] = function()
  local params = child.lua([[
    local adapter = require("inliber.adapters").extend(_G.test_adapter)
    utils.get_env_vars(adapter)
    return utils.set_env_vars(adapter, adapter.parameters)
  ]])

  h.eq(child.lua_get([[_G.test_adapter.parameters]]), params)
end

T["ACP Adapter"]["environment variables can be functions"] = function()
  local result = child.lua([[
    local adapter = require("inliber.adapters").extend("claude_code", {
      env = {
        api_key = function()
          return "test_api_key"
        end,
      }
    })
    return utils.get_env_vars(adapter).env_replaced.api_key
  ]])

  h.eq("test_api_key", result)
end

T["ACP Adapter"]["environment variables can be read from a file (absolute path)"] = function()
  local result = child.lua([[
    local path = vim.fn.tempname()
    vim.fn.writefile({ "sk-test-123" }, path)

    local adapter = require("inliber.adapters").extend("claude_code", {
      env = {
        api_key = "file:" .. path,
      }
    })
    local api_key = utils.get_env_vars(adapter).env_replaced.api_key

    vim.fn.delete(path)
    return api_key
  ]])

  h.eq("sk-test-123", result)
end

T["ACP Adapter"]["environment variables can be read from a file (relative path)"] = function()
  local result = child.lua([[
    local filename = ".inliber_test_api_key"
    vim.fn.writefile({ "relative-key" }, filename)

    local adapter = require("inliber.adapters").extend("claude_code", {
      env = {
        api_key = "file:" .. filename,
      }
    })
    local api_key = utils.get_env_vars(adapter).env_replaced.api_key

    vim.fn.delete(filename)
    return api_key
  ]])

  h.eq("relative-key", result)
end

T["ACP Adapter"]["returns nil when the file for an environment variable doesn't exist"] = function()
  local result = child.lua([[
    local adapter = require("inliber.adapters").extend("claude_code", {
      env = {
        api_key = "file:/tmp/inliber_test_file_that_does_not_exist",
      }
    })
    return utils.get_env_vars(adapter).env_replaced.api_key
  ]])

  h.eq(vim.NIL, result)
end

T["ACP Adapter"]["map_roles maps the adapter's roles"] = function()
  local result = child.lua([[
    local adapter = require("inliber.adapters").resolve("claude_code")
    return adapter:map_roles({
      { role = "system", content = "sys" },
      { role = "llm", content = "hi" },
      { role = "user", content = "hello" },
    })
  ]])

  h.eq("system", result[1].role)
  h.eq("assistant", result[2].role)
  h.eq("user", result[3].role)
end

return T
