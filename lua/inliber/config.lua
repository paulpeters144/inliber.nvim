local fmt = string.format

local constants = {
  LLM_ROLE = "llm",
  USER_ROLE = "user",
  SYSTEM_ROLE = "system",
}

local defaults = {
  adapters = {
    http = {
      anthropic = "anthropic",
      azure_openai = "azure_openai",
      copilot = "copilot",
      deepseek = "deepseek",
      gemini = "gemini",
      gemini_interactions = "gemini_interactions",
      githubmodels = "githubmodels",
      huggingface = "huggingface",
      kimi = "kimi",
      novita = "novita",
      mistral = "mistral",
      ollama = "ollama",
      openai = "openai",
      openai_responses = "openai_responses",
      openrouter = "openrouter",
      xai = "xai",
      extend = nil, -- Per-adapter overrides keyed by config key e.g. { openai = { env = { api_key = "ABC-123" } } }
      opts = {
        allow_insecure = false, -- Allow insecure connections?
        cache_models_for = 1800, -- Cache adapter models for this long (seconds)
        hidden = {},
        proxy = nil, -- [protocol://]host[:port] e.g. socks5://127.0.0.1:9999
        show_presets = true, -- Show preset adapters
      },
    },
    opts = {
      cmd_timeout = 20e3, -- Timeout for commands that resolve env variables (milliseconds)
    },
  },

  constants = constants,

  tools = {
    -- Tools
    ["create_file"] = {
      path = "tools.builtin.create_file",
      description = "Create a file in the current working directory",
      opts = {
        require_approval_before = false,
        require_confirmation_after = true,
      },
    },
    ["delete_file"] = {
      path = "tools.builtin.delete_file",
      description = "Delete a file in the current working directory",
      opts = {
        judge = false,
        protect = true,
        require_approval_before = true,
        require_cmd_approval = true,
      },
    },
    ["file_search"] = {
      path = "tools.builtin.file_search",
      description = "Search for files in the current working directory by glob pattern",
      opts = {
        max_results = 500,
      },
    },
    ["get_changed_files"] = {
      path = "tools.builtin.get_changed_files",
      description = "Get git diffs of current file changes in a git repository",
      opts = {
        max_lines = 1000,
      },
    },
    ["get_diagnostics"] = {
      path = "tools.builtin.get_diagnostics",
      description = "Get LSP diagnostics for a given file",
    },
    ["grep_search"] = {
      path = "tools.builtin.grep_search",
      enabled = function()
        -- Currently this tool only supports ripgrep
        return vim.fn.executable("rg") == 1
      end,
      description = "Search for text in the current working directory",
      opts = {
        max_results = 100,
        respect_gitignore = true,
        require_approval_before = true,
      },
    },
    ["insert_edit_into_file"] = {
      path = "tools.builtin.insert_edit_into_file",
      description = "Robustly edit existing files with multiple automatic fallback interactions",
      opts = {
        require_approval_before = { -- Require approval before the tool is executed?
          buffer = false, -- For editing buffers in Neovim
          file = false, -- For editing files in the current working directory
        },
        require_confirmation_after = true, -- Require confirmation from the user before accepting the edit?
        file_size_limit_mb = 2, -- Maximum file size in MB
      },
    },
    ["read_file"] = {
      path = "tools.builtin.read_file",
      description = "Read a file in the current working directory",
      opts = {
        require_approval_before = true,
      },
    },
    ["run_command"] = {
      path = "tools.builtin.run_command",
      description = "Run shell commands initiated by the LLM",
      opts = {
        judge = false,
        require_approval_before = true,
        require_cmd_approval = true,
        safe_commands = { "git status", "ls", "pwd" }, -- Commands which run without asking in auto mode
        timeout = 300000, -- Timeout for commands (milliseconds) - 5 mins by default
      },
    },
    opts = {
      ---The approval mode every chat buffer starts in
      ---@type Inliber.Tools.ApprovalMode
      approval_mode = "ask",
      auto_submit_errors = true, -- Send any errors to the LLM automatically?
      auto_submit_success = true, -- Send any successful output to the LLM automatically?
      max_output_tokens = 30000, -- Truncate a tool's output above this many tokens, or the model's limit if lower
      notify_on_approval = true, -- Notify the user when a tool requires approval?,
    },
  },

  interactions = {
    opts = {
      date_format = "%A, %d %B %Y", -- The date format to use in system prompts
    },
    -- INLINE INTERACTION -----------------------------------------------------
    inline = {
      adapter = "copilot",
      tools = {
        enabled = false, -- Run the tool loop before responding?
        ---Read-only tools loaded for the "ask" intent
        ---@type string[]
        ask_tools = { "read_file", "grep_search", "file_search", "get_diagnostics", "get_changed_files" },
        ---Read and write tools loaded for the "edit" intent
        ---@type string[]
        edit_tools = {
          "read_file",
          "grep_search",
          "file_search",
          "get_diagnostics",
          "get_changed_files",
          "create_file",
          "delete_file",
          "insert_edit_into_file",
          "run_command",
        },
        opts = {
          approval_mode = "auto", -- ask|auto|yolo
        },
      },
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

---Move the yolo mode tool options over to their approval mode equivalents
---@param tools table
local function migrate_yolo_tool_opts(tools)
  local warned = {}
  ---@param opts { legacy: string, replacement: string }
  local function warn(opts)
    if not warned[opts.legacy] then
      warned[opts.legacy] = true
      vim.notify(
        ("[Inliber] The `%s` tool option is deprecated. Use `%s` instead."):format(opts.legacy, opts.replacement),
        vim.log.levels.WARN,
        { title = "Inliber" }
      )
    end
  end

  for _, tool in pairs(tools) do
    local opts = type(tool) == "table" and type(tool.opts) == "table" and tool.opts or {}
    if opts.allowed_in_yolo_mode ~= nil then
      warn({ legacy = "allowed_in_yolo_mode", replacement = "protect" })
      opts.protect = not opts.allowed_in_yolo_mode
      opts.allowed_in_yolo_mode = nil
    end
    if opts.judge_in_yolo_mode ~= nil then
      warn({ legacy = "judge_in_yolo_mode", replacement = "judge" })
      opts.judge = opts.judge_in_yolo_mode
      opts.judge_in_yolo_mode = nil
    end
  end
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

  migrate_yolo_tool_opts(M.config.tools)
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
