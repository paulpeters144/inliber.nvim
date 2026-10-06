local AgentCommands = require("inliber.interactions.shared.agent_commands")

---@class Inliber.AgentCommands.Highlight
local Highlight = {}

local namespace = vim.api.nvim_create_namespace("inliber_agent_commands")

---Attach live highlight tracking to a buffer; recognized command names are marked and refreshed on each change
---@param bufnr integer The modal buffer to mark
---@param provider Inliber.AgentCommands.Provider|nil
---@param root string
---@return nil
function Highlight.attach(bufnr, provider, root)
  if not provider then
    return
  end

  local function redraw()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    Highlight.clear(bufnr)
    local prompt = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or ""
    local found = AgentCommands.new({ provider = provider, prompt = prompt, root = root }):find().found
    for _, match in ipairs(found) do
      vim.api.nvim_buf_set_extmark(bufnr, namespace, 0, match.start - 1, {
        end_col = match.name_finish - 1,
        hl_group = "InliberAgentCommand",
      })
    end
  end

  vim.api.nvim_create_autocmd("TextChangedI", {
    buffer = bufnr,
    callback = redraw,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    once = true,
    callback = function()
      Highlight.clear(bufnr)
    end,
  })
end

---Remove every extmark this module placed in a buffer
---@param bufnr integer
---@return nil
function Highlight.clear(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, 1)
  end
end

return Highlight
