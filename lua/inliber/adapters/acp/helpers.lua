local log = require("inliber.utils.log")
local tags = require("inliber.interactions.shared.tags")

local M = {}

---@param self Inliber.ACPAdapter
---@param messages table
---@param capabilities ACP.agentCapabilities
---@return table
M.form_messages = function(self, messages, capabilities)
  local has = capabilities and capabilities.promptCapabilities

  return vim
    .iter(messages)
    :filter(function(msg)
      -- Ensure we're only sending messages that the agent hasn't seen before
      return msg.role == self.roles.user and msg._meta and not msg._meta.sent
    end)
    :map(function(msg)
      if msg._meta and msg._meta.tag == tags.IMAGE and msg.context and msg.context.mimetype then
        if not has.image then
          log:warn("The %s agent does not support receiving images", self.formatted_name)
        else
          return {
            type = "image",
            data = msg.content,
            mimeType = msg.context.mimetype,
          }
        end
      end
      if msg.content and msg.content ~= "" then
        return {
          type = "text",
          text = msg.content,
        }
      end
    end)
    :totable()
end

return M
