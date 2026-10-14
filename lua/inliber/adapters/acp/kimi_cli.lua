local helpers = require("inliber.adapters.acp.helpers")

---@class Inliber.ACPAdapter.KimiCLI: Inliber.ACPAdapter
return {
  name = "kimi_cli",
  formatted_name = "Kimi CLI",
  type = "acp",
  roles = {
    llm = "assistant",
    user = "user",
  },
  opts = {
    vision = true,
  },
  commands = {
    default = {
      "kimi",
      "acp",
    },
  },
  defaults = {
    mcpServers = {},
    timeout = 20000, -- 20 seconds
  },
  parameters = {
    protocolVersion = 1,
    clientCapabilities = {
      fs = { readTextFile = true, writeTextFile = true },
    },
    clientInfo = {
      name = "Inliber.nvim",
      version = "1.0.0",
    },
  },
  handlers = {
    ---@param self Inliber.ACPAdapter
    ---@return boolean
    setup = function(self)
      return true
    end,

    ---Kimi CLI is already authenticated through CLI /login(setup)
    ---Returning true skips ACP authentication
    ---@param self Inliber.ACPAdapter
    ---@return boolean
    auth = function(self)
      return true
    end,

    ---@param self Inliber.ACPAdapter
    ---@param messages table
    ---@param capabilities table
    ---@return table
    form_messages = function(self, messages, capabilities)
      return helpers.form_messages(self, messages, capabilities)
    end,

    ---Function to run when the request has completed. Useful to catch errors
    ---@param self Inliber.ACPAdapter
    ---@param code number
    ---@return nil
    on_exit = function(self, code) end,
  },
}
