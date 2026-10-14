local helpers = require("inliber.adapters.acp.helpers")

---@class Inliber.ACPAdapter.ClineCLI: Inliber.ACPAdapter
return {
  name = "cline_cli",
  formatted_name = "Cline CLI",
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
      "cline",
      "--acp",
    },
  },
  defaults = {
    mcpServers = {},
    timeout = 20000, -- 20 seconds
    -- mode = "plan", -- Optional: Set default agent mode (e.g., "plan", "act")
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

    ---Manually handle authentication
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
