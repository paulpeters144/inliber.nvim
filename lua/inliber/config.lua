local fmt = string.format

local constants = {
  LLM_ROLE = "llm",
  USER_ROLE = "user",
  SYSTEM_ROLE = "system",
}

local defaults = {
  adapters = {
    acp = {
      auggie_cli = "auggie_cli",
      cagent = "cagent",
      claude_code = "claude_code",
      cline_cli = "cline_cli",
      codex = "codex",
      copilot_acp = "copilot_acp",
      cursor_cli = "cursor_cli",
      gemini_cli = "gemini_cli",
      goose = "goose",
      kimi_cli = "kimi_cli",
      kiro = "kiro",
      mistral_vibe = "mistral_vibe",
      opencode = "opencode",
      extend = nil, -- Per-adapter overrides keyed by config key e.g. { codex = { env = { OPENAI_API_KEY = "ABC-123" } } }
      opts = {
        show_presets = true, -- Show preset adapters
      },
    },
    opts = {
      cmd_timeout = 20e3, -- Timeout for commands that resolve env variables (milliseconds)
    },
  },

  constants = constants,

  interactions = {
    opts = {
      date_format = "%A, %d %B %Y", -- The date format to use in system prompts
    },
    -- INLINE INTERACTION -----------------------------------------------------
    inline = {
      adapter = "copilot_acp",
      input_modal = {
        input_width = 60, -- Width of the input modal in columns
      },
      ask_float = {
        answer_max_width = 110, -- Max width of the chat float in columns
        show_timestamps = false, -- Show the time next to each speaker in the chat float
        show_token_count = true, -- Show the cumulative token count for each response
        token_count = function(tokens) -- Format the token count for the chat float
          return " (" .. tokens .. " tokens)"
        end,
        ask_separator = "──── ask ────", -- Separator between the conversation and the input line
      },
      keymaps = {
        stop = {
          callback = "keymaps.stop",
          description = "Stop request",
          index = 4,
          modes = { n = "q" },
        },
      },
      editor_state = {
        enabled = true, -- Send the current file, cursor and surrounding code with every prompt?
        max_lines = 300, -- Send the whole buffer up to this size, otherwise only the visible lines
      },
      editor_context = {
        ["buffer"] = {
          path = "interactions.inline.editor_context.buffer",
          description = "Share the current buffer with the LLM",
          opts = {
            contains_code = true,
          },
        },
        ["clipboard"] = {
          path = "interactions.inline.editor_context.clipboard",
          description = "Share the contents of the clipboard with the LLM",
          opts = {
            contains_code = true,
          },
        },
      },
      agent_commands = {
        enabled = true, -- Master switch for discovery, completion, and expansion
        trigger = "@", -- Prefix character for command tags in prompts
      },
    },
    -- SHARED -------------------------------------------------------------------
    shared = {
      keymaps = {
        view_diff = {
          description = "View the proposed diff",
          modes = { n = "gv" },
          opts = { nowait = true },
        },
        always_accept = {
          callback = "keymaps.always_accept",
          description = "Always accept changes in this buffer",
          index = 1,
          modes = { n = "g1" },
          opts = { nowait = true },
        },
        accept_change = {
          callback = "keymaps.accept_change",
          description = "Accept change",
          index = 2,
          modes = { n = "g2" },
          opts = { nowait = true, noremap = true },
        },
        reject_change = {
          callback = "keymaps.reject_change",
          description = "Reject change",
          index = 3,
          modes = { n = "g3" },
          opts = { nowait = true, noremap = true },
        },
        cancel = {
          description = "Cancel all pending tool calls",
          modes = { n = "g4" },
          opts = { nowait = true },
        },
        next_hunk = {
          callback = "keymaps.next_hunk",
          description = "Go to next hunk",
          modes = { n = "}" },
        },
        previous_hunk = {
          callback = "keymaps.previous_hunk",
          description = "Go to previous hunk",
          modes = { n = "{" },
        },
      },
    },
  },

  -- DISPLAY OPTIONS ----------------------------------------------------------
  display = {
    diff = {
      enabled = true,

      -- Options for any diff windows (extends from floating_window)
      window = {
        opts = {},
      },
      word_highlights = {
        additions = true,
        deletions = true,
      },
    },

    inline = {
      -- If the inline prompt creates a new buffer, how should we display this?
      layout = "vertical", -- vertical|horizontal|buffer
    },
  },
  -- GENERAL OPTIONS ----------------------------------------------------------
  opts = {
    log_level = "ERROR", -- TRACE|DEBUG|ERROR|INFO
    language = "English", -- The language used for LLM responses

    per_project_config = {
      enabled = true, -- Enable per-project configuration?
      files = {}, -- Files in the cwd that contain project configuration
      paths = {}, -- Per-path config: { ["~/Code/myproject"] = { ... } }
    },

    -- If this is false then any default prompt that is marked as containing code
    -- will not be sent to the LLM. Please note that whilst I have made every
    -- effort to ensure no code leakage, using this is at your own risk
    ---@type boolean|function
    ---@return boolean
    send_code = true,

    -- Global keymaps registered when the plugin is set up. Set to an empty
    -- table or false to disable the default bindings
    default_keymaps = {
      { "<leader>aa", "V:InliberAsk<cr>", mode = "n", desc = "Ask" },
      { "<leader>aa", ":InliberAsk<cr>", mode = "v", desc = "Ask" },
      { "<leader>ae", "V:InliberEdit<cr>", mode = "n", desc = "Edit" },
      { "<leader>ae", ":InliberEdit<cr>", mode = "v", desc = "Edit" },
      { "<leader>ar", "<cmd>InliberAskResume<cr>", mode = "n", desc = "Resume Ask" },
      { "<leader>ad", "<cmd>InliberCancelLast<cr>", mode = "n", desc = "Cancel Last Request" },
    },
  },
}

local M = {
  config = vim.deepcopy(defaults),
}

---Check the cwd for any per-project configuration files and load them if they exist
---@return table|nil
local function get_per_project_config()
  local file_utils = require("inliber.utils.files")

  local cfg = M.config.opts.per_project_config
  if not cfg or not cfg.enabled then
    return nil
  end

  local cwd = vim.fs.normalize(vim.fn.getcwd())
  local config = {}

  local function notify(msg)
    vim.notify(fmt("[Inliber] %s", msg), vim.log.levels.ERROR, { title = "Inliber" })
  end

  -- Collect path-based configs
  if cfg.paths then
    for path, path_cfg in pairs(cfg.paths) do
      if vim.fs.normalize(vim.fn.expand(path)) == cwd then
        if type(path_cfg) ~= "table" then
          notify(fmt("Per-project config for path `%s` must be a table", path))
        else
          config = vim.tbl_deep_extend("force", config, path_cfg)
        end
      end
    end
  end

  -- Collect file-based configs
  for _, filename in ipairs(cfg.files) do
    local path = vim.fs.joinpath(cwd, filename)
    if file_utils.exists(path) and not file_utils.is_dir(path) then
      local ok, file_cfg = pcall(dofile, path)
      if not ok then
        notify(fmt("Failed to load per-project config `%s`: %s", filename, file_cfg))
      elseif type(file_cfg) ~= "table" then
        notify(fmt("Per-project config `%s` must return a table", filename))
      else
        config = vim.tbl_deep_extend("force", config, file_cfg)
      end
    end
  end

  return next(config) ~= nil and config or nil
end

---@param keymaps table<string, table|boolean>
local function remove_disabled_keymaps(keymaps)
  local enabled = {}
  for name, keymap in pairs(keymaps) do
    if keymap ~= false then
      enabled[name] = keymap
    end
  end
  return enabled
end

---@param args? table
M.setup = function(args)
  args = vim.deepcopy(args or {})

  if args.constants then
    return vim.notify(
      "Your config table cannot have the field `constants`",
      vim.log.levels.ERROR,
      { title = "Inliber" }
    )
  end

  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), args)

  -- Replace the default keymaps outright instead of merging them element-wise
  if args.opts and args.opts.default_keymaps ~= nil then
    M.config.opts.default_keymaps = args.opts.default_keymaps
  end

  M.config.interactions.inline.keymaps = remove_disabled_keymaps(M.config.interactions.inline.keymaps)
  M.config.interactions.shared.keymaps = remove_disabled_keymaps(M.config.interactions.shared.keymaps)

  local project_config = get_per_project_config()
  if project_config then
    M.config = vim.tbl_deep_extend("force", M.config, project_config)
  end
end

---Determine if code can be sent to the LLM
---@return boolean
M.can_send_code = function()
  if type(M.config.opts.send_code) == "boolean" then
    return M.config.opts.send_code
  elseif type(M.config.opts.send_code) == "function" then
    return M.config.opts.send_code()
  end
  return false
end

return setmetatable(M, {
  __index = function(_, key)
    if key == "setup" then
      return M.setup
    end
    return rawget(M.config, key)
  end,
})
