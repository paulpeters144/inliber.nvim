local config = require("inliber.config")
local log = require("inliber.utils.log")

local api = vim.api

-- Lazy load context_utils
local context_utils
local function get_context(bufnr, args)
  if not context_utils then
    context_utils = require("inliber.utils.context")
  end
  return context_utils.get(bufnr, args)
end

---@class Inliber
local Inliber = {}

---Run the inline assistant from the current Neovim buffer
---@param args { intent: "ask"|"edit", args?: string }
---@return nil
Inliber.inline = function(args)
  local context = get_context(api.nvim_get_current_buf(), args)
  local inline = require("inliber.interactions.inline").new({
    buffer_context = context,
    intent = args.intent,
  })
  if inline then
    inline:prompt(args.args)
  end
end

---Handle adapter configuration merging
---@param opts table
---@return nil
local function adapter_config(opts)
  if opts and opts.adapters and opts.adapters.http then
    if config.adapters.http.opts.show_presets then
      local adapters_util = require("inliber.adapters.utils")
      adapters_util.extend(config.adapters.http, opts.adapters.http)
    else
      config.adapters.http =
        vim.tbl_deep_extend("keep", opts.adapters.http, { opts = config.adapters.http.opts })
    end
  end
end

---Register the plugin's default global keymaps
---@return nil
local function setup_default_keymaps()
  local keymaps = config.opts.default_keymaps
  if type(keymaps) ~= "table" then
    return
  end
  for _, keymap in ipairs(keymaps) do
    local lhs, rhs = keymap[1], keymap[2]
    if lhs and rhs then
      vim.keymap.set(keymap.mode or "n", lhs, rhs, {
        desc = keymap.desc,
        noremap = true,
        silent = true,
      })
    end
  end
end

---Setup the plugin
---@param opts? table
---@return nil
Inliber.setup = function(opts)
  opts = opts or {}

  -- Setup the plugin's config
  config.setup(opts)

  adapter_config(opts)

  local cmds = require("inliber.commands")
  for _, cmd in ipairs(cmds) do
    api.nvim_create_user_command(cmd.cmd, cmd.callback, cmd.opts)
  end

  setup_default_keymaps()

  -- Set the log root
  log.set_root(log.new({
    handlers = {
      {
        type = "notify",
        level = vim.log.levels.WARN,
      },
      {
        type = "file",
        filename = "inliber.log",
        level = vim.log.levels[config.opts.log_level],
      },
    },
  }))
end

return Inliber
