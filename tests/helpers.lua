local Helpers = {}

Helpers = vim.tbl_extend("error", Helpers, require("tests.expectations"))

---Stop adapter requests from reaching the network. A submitted request returns a
---job which never calls back, so tests that need a response must supply their own
---@return nil
local function mock_http_client()
  local client = require("inliber.http")
  if not client.static then
    return
  end
  local function unanswered_request()
    return { args = {}, shutdown = function() end }
  end
  client.static.methods.get.default = unanswered_request
  client.static.methods.post.default = unanswered_request
end

---Set up the Inliber plugin with test configuration
---@param config? table
---@return nil
Helpers.setup_plugin = function(config)
  local function mock_external_calls()
    local ok, copilot = pcall(require, "inliber.adapters.http.copilot")
    if ok then
      local get_models_ok, get_models = pcall(require, "inliber.adapters.http.copilot.get_models")
      if get_models_ok then
        get_models.choices = function(adapter, opts, provided_token)
          return { ["gpt-4.1"] = { opts = {} } }
        end
      end

      local token_ok, token = pcall(require, "inliber.adapters.http.copilot.token")
      if token_ok then
        token.init = function()
          return true
        end
        token.fetch = function()
          return {
            oauth_token = "mock_oauth_token",
            copilot_token = "mock_copilot_token",
            endpoints = { api = "https://api.githubcopilot.com" },
          }
        end
      end
    end
  end

  mock_external_calls()
  mock_http_client()

  local inliber = require("inliber")
  inliber.setup(config)
  return inliber
end

---Create a mock adapter for testing
---@param child table The child Neovim instance
---@param adapter? string|table Adapter name (e.g., "openai"), config table, or nil for default
---@param opts? { var_name?: string, handlers?: table } Options to customize adapter
---@return string var_name The variable name where adapter is stored
Helpers.create_mock_adapter = function(child, adapter, opts)
  opts = opts or {}
  local var_name = opts.var_name or "_G.mock_adapter"

  child.lua(
    string.format(
      [[
    local adapter_config
    local adapter_input = ...

    if adapter_input == nil then
      adapter_config = {
        name = "test_adapter",
        type = "http",
        url = "http://localhost/v1/chat/completions",
        roles = {
          llm = "assistant",
          user = "user",
        },
        opts = {
          stream = true,
        },
        headers = {
          content_type = "application/json",
        },
        schema = {
          model = {
            default = "gpt-3.5-turbo",
          },
        },
        handlers = {
          response = {
            parse_chat = function(self, data)
              local raw = type(data) == "table" and data.body or data
              local ok, body = pcall(vim.json.decode, raw)
              if not ok then
                return nil
              end

              if body.choices and body.choices[1] and body.choices[1].message then
                return {
                  status = "success",
                  output = body.choices[1].message,
                }
              end
              return nil
            end,
          },
        },
      }
    elseif type(adapter_input) == "string" then
      local adapters = require("inliber.adapters")
      adapter_config = adapters.resolve(adapter_input)
    else
      adapter_config = adapter_input
    end

    local Adapter = require("inliber.adapters.http")
    %s = Adapter.new(adapter_config)
  ]],
      var_name
    ),
    { adapter }
  )

  return var_name
end

---Setup mock HTTP client
---@param child table The child Neovim instance
---@param adapter? string Name of the adapter variable in child process (default: "_G.mock_adapter")
---@return nil
Helpers.mock_http = function(child, adapter)
  adapter = adapter or "_G.mock_adapter"

  child.lua(string.format(
    [[
    local mock_client = require("tests.mocks.http").new({ adapter = %s })
    _G.mock_client = mock_client

    package.loaded["inliber.http"] = {
      new = function()
        return _G.mock_client
      end,
    }
  ]],
    adapter
  ))
end

---Queue a response in the mock HTTP client
---@param child table The child Neovim instance
---@param response table The response to queue
---@return nil
Helpers.queue_mock_http_response = function(child, response)
  child.lua([[_G.mock_client:queue_response(...)]], { response })
end

---Get requests captured by mock HTTP client
---@param child table The child Neovim instance
---@return table
Helpers.get_mock_http_requests = function(child)
  return child.lua([[
    if not _G.mock_client then
      error("Mock client not initialized. Did you call setup_mock_http?")
    end
    return _G.mock_client:get_requests()
  ]])
end

---Get the lines of a buffer
---@param bufnr number
---@return table
Helpers.get_buf_lines = function(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
end

---Setup the inline buffer
---@param config table
---@return Inliber.Inline
Helpers.setup_inline = function(config)
  mock_http_client()
  require("inliber.config").setup(config or {})

  return require("inliber.interactions.inline").new({
    intent = "edit",
    buffer_context = {
      winnr = 0,
      bufnr = 0,
      filetype = "lua",
      start_line = 1,
      end_line = 1,
      start_col = 0,
      end_col = 0,
    },
  })
end

---Start a child Neovim instance with minimal configuration
---@param child table
---@return nil
Helpers.child_start = function(child)
  child.restart({ "-u", "scripts/minimal_init.lua" })
  child.o.statusline = ""
  child.o.laststatus = 0
  child.o.cmdheight = 0
end

return Helpers
