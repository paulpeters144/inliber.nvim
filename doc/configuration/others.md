---
description: "Configure miscellaneous Inliber options: log level, per-project config files, and restricting code from being sent to agents."
---

# Other Configuration Options

## Log Level

> [!IMPORTANT]
> By default, logs are stored at `~/.local/state/nvim/inliber.log`

When it comes to debugging, you can change the level of logging which takes place in the plugin as follows:

```lua
require("inliber").setup({
  opts = {
    log_level = "ERROR", -- TRACE|DEBUG|ERROR|INFO
  },
}),
```

## Per-Project Configuration

Working across multiple projects, it can be useful to set different Inliber configurations.

The plugin allows you to specify a list of files which it will look for in the current working directory. If any of the files are found, they will be loaded and merged with the default configuration.

Alternatively, you can specify a directory as a key and the configuration as the value.

::: code-group

```lua [Files]
require("inliber").setup({
  opts = {
    per_project_config = {
      files = {
        ".inliber",
        ".inliber.lua",
      },
    },
  },
})
```

```lua [Dirs]
require("inliber").setup({
  opts = {
    per_project_config = {
      paths = {
        ["~/Code/Python/New-Startup"] = {
          interactions = {
            inline = {
              adapter = "opencode",
            },
          },
        },
      },
    },
  },
})
```

:::

File-based configuration must return a valid Lua table. For example:

```lua
return {
  interactions = {
    inline = {
      adapter = "claude_code",
    },
  },
}
```

## Sending Code

> [!IMPORTANT]
> Whilst the plugin makes every attempt to prevent code from being sent to the agent, use this option at your own risk

You can prevent any code from being sent to the agent with:

```lua
require("inliber").setup({
  opts = {
    send_code = false,
  },
}),
```

## Default Keymaps

Inliber registers a few keymaps when it's set up:

| Keymap | Action |
|---|---|
| `<leader>aa` | Ask, answering in a floating window |
| `<leader>ae` | Edit, in the current buffer |
| `<leader>ar` | Resume the last ask conversation |

You can override them with a list of keymaps. Each entry takes a left-hand side, a right-hand side, a `mode` and a `desc`:

```lua
require("inliber").setup({
  opts = {
    default_keymaps = {
      { "<leader>aa", "V:InliberAsk<cr>", mode = "n", desc = "Ask" },
      { "<leader>aa", ":InliberAsk<cr>", mode = "v", desc = "Ask" },
      { "<leader>ar", "<cmd>InliberAskResume<cr>", mode = "n", desc = "Resume Ask" },
    },
  },
})
```

Set the option to `false` to register none of them:

```lua
require("inliber").setup({
  opts = {
    default_keymaps = false,
  },
}),
```
