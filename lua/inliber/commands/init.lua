---@class Inliber.Command
---@field cmd string
---@field callback fun(args:table)
---@field opts Inliber.Command.Opts

---@class Inliber.Command.Opts:table
---@field desc string

local inliber = require("inliber")
local config = require("inliber.config")

local _cached_adapters = nil
local hidden = config.adapters.http.opts.hidden

---Get the available HTTP adapters from the config
---@return string[]
local function get_adapters()
  if not _cached_adapters then
    _cached_adapters = vim
      .iter(config.adapters.http)
      :filter(function(k, _)
        return k ~= "extend" and k ~= "opts" and not hidden[k]
      end)
      :map(function(k, _)
        return k
      end)
      :totable()
  end
  return _cached_adapters
end

---Complete adapter= params and inline editor context
---@param arg_lead string
---@return string[]
local function complete(arg_lead)
  local param_key = arg_lead:match("^(%w+)=$")
  if param_key == "adapter" then
    return vim
      .iter(get_adapters())
      :map(function(adapter)
        return "adapter=" .. adapter
      end)
      :totable()
  end

  local completions = {}
  for _, adapter in ipairs(get_adapters()) do
    table.insert(completions, "adapter=" .. adapter)
  end
  for key, _ in pairs(config.interactions.inline.editor_context) do
    if key ~= "opts" then
      table.insert(completions, string.format("#{%s}", key))
    end
  end

  return vim
    .iter(completions)
    :filter(function(completion)
      return completion:find(vim.pesc(arg_lead), 1, true) == 1
    end)
    :totable()
end

---Collect the first prompt in a small float, then drive the conversation from the chat float
---@param opts table
---@param intent "ask"|"edit"
---@return nil
local function ask_in_float(opts, intent)
  local Inline = require("inliber.interactions.inline")
  local inline = Inline.new({
    buffer_context = require("inliber.utils.context").get(vim.api.nvim_get_current_buf(), opts),
    intent = intent,
  })
  if not inline then
    return
  end
  if intent == "ask" then
    Inline.remember(inline)
  end

  local input_modal = require("inliber.interactions.inline.input_modal").new({
    title = intent == "edit" and "Edit" or "Ask",
  })
  inline.input_modal = input_modal
  input_modal:prompt(function(question)
    if not question then
      return
    end
    if intent == "edit" then
      return inline:prompt(question)
    end
    inline:ask(question)
  end, inline:agent_command_opts())
end

---Reopen the last ask conversation in the float, or prompt fresh if none exists
---@param opts table
---@return nil
local function resume_ask(opts)
  local Inline = require("inliber.interactions.inline")
  local last = Inline.last_ask()
  if last and #last.turns > 0 then
    return last:resume(opts)
  end
  return ask_in_float(opts, "ask")
end

---Run the inline interaction with a forced intent, prompting for input if no prompt was given
---@param opts table
---@param intent "ask"|"edit"
---@return nil
local function inline_with_intent(opts, intent)
  opts.intent = intent
  if #vim.trim(opts.args or "") > 0 then
    return inliber.inline(opts)
  end

  return ask_in_float(opts, intent)
end

---@type Inliber.Command[]
return {
  {
    cmd = "InliberAsk",
    callback = function(opts)
      inline_with_intent(opts, "ask")
    end,
    opts = {
      desc = "Ask Inliber a question, answered in a floating window",
      range = true,
      nargs = "*",
      complete = complete,
    },
  },
  {
    cmd = "InliberEdit",
    callback = function(opts)
      inline_with_intent(opts, "edit")
    end,
    opts = {
      desc = "Edit the current buffer with Inliber",
      range = true,
      nargs = "*",
      complete = complete,
    },
  },
  {
    cmd = "InliberAskResume",
    callback = function(opts)
      resume_ask(opts)
    end,
    opts = {
      desc = "Resume the last ask conversation in a floating window",
      range = true,
      nargs = "*",
      complete = complete,
    },
  },
}
