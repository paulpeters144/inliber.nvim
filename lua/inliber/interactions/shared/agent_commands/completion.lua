local Discovery = require("inliber.interactions.shared.agent_commands.discovery")
local config = require("inliber.config")

---@class Inliber.AgentCommands.Completion
local Completion = {}

local attached = {}

---Byte index (1-based) of the trigger when the cursor sits in a token containing it, else nil
---@return integer|nil
local function trigger_start()
  local trigger = config.interactions.inline.agent_commands.trigger
  local line = vim.api.nvim_get_current_line()
  local column = vim.api.nvim_win_get_cursor(0)[2]
  local before = line:sub(1, column)
  local token_start = before:match("()[^%s]*$")
  return before:find(trigger, token_start, true)
end

---Attach agent-command completion to a buffer as its omnifunc; does nothing when the provider is nil
---@param bufnr number
---@param provider Inliber.AgentCommands.Provider|nil
---@param root string
---@return nil
function Completion.attach(bufnr, provider, root)
  if not provider then
    return
  end

  attached[bufnr] = { provider = provider, root = root }
  -- omnifunc only accepts a name, so route through one global callback
  _G._inliber_agent_commands_omnifunc = function(findstart, base)
    return Completion._omnifunc(findstart, base)
  end
  vim.api.nvim_set_option_value("omnifunc", "v:lua._inliber_agent_commands_omnifunc", { buf = bufnr })
  -- Without noinsert/menuone the popup clobbers the prompt with the first match and hides single matches
  vim.api.nvim_set_option_value("completeopt", "menu,menuone,noinsert,noselect", { buf = bufnr })

  vim.api.nvim_create_autocmd("TextChangedI", {
    buffer = bufnr,
    callback = function()
      Completion._auto_trigger()
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    once = true,
    callback = function()
      attached[bufnr] = nil
    end,
  })
end

---Completion items for the provider's discovered commands; word inserts @name
---@param provider Inliber.AgentCommands.Provider
---@param root string
---@return { word: string, abbr: string }[]
function Completion.items(provider, root)
  local trigger = config.interactions.inline.agent_commands.trigger
  local items = {}
  for _, command in ipairs(Discovery.commands(provider, root)) do
    table.insert(items, {
      word = trigger .. command.name,
      abbr = command.name,
    })
  end
  return items
end

---Vim omnifunc contract: findstart locates the trigger, then returns matching items
---@param findstart integer 1 to locate the trigger start, 0 to return matches
---@param base string Partial text typed after the trigger
---@return integer|table[]
function Completion._omnifunc(findstart, base)
  local state = attached[vim.api.nvim_get_current_buf()]
  if not state then
    return findstart == 1 and -1 or {}
  end

  if findstart == 1 then
    local at = trigger_start()
    if at then
      return at - 1
    end
    return -1
  end

  base = base or ""
  local matches = {}
  for _, item in ipairs(Completion.items(state.provider, state.root)) do
    if item.word:sub(1, #base) == base then
      table.insert(matches, item)
    end
  end
  return matches
end

---Open the completion popup when the cursor follows a trigger, re-filtering as the token grows
---@return nil
function Completion._auto_trigger()
  local state = attached[vim.api.nvim_get_current_buf()]
  if not state then
    return
  end
  local at = trigger_start()
  if not at then
    return
  end
  vim.fn.complete(at, Completion.items(state.provider, state.root))
end

return Completion
