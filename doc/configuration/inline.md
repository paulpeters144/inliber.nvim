---
description: "Configure Inliber's inline interaction for writing and refactoring code directly into Neovim buffers via ACP agents, without opening a chat buffer."
---

# Configuring the Inline Interaction

Inliber provides an _inline_ interaction for quick, direct editing of your code. The interaction integrates responses directly into the current buffer — allowing the agent to add or replace code as needed — and answers questions in a floating window.

## Changing Adapter

By default, Inliber sets the _copilot_acp_ adapter for the inline interaction. You can change this to any other ACP adapter:

```lua
require("inliber").setup({
  interactions = {
    inline = {
      adapter = "claude_code", -- Or "codex", "gemini_cli", "opencode"...
    },
  },
})
```

To use a specific model, pass the adapter as a table:

```lua
require("inliber").setup({
  interactions = {
    inline = {
      adapter = {
        name = "codex",
        model = "gpt-5.4",
      },
    },
  },
})
```

See the section on [ACP Adapters](/configuration/adapters-acp) for more information.

## Keymaps

The inline interaction supports keymaps for accepting or rejecting changes in the diff:

```lua
require("inliber").setup({
  interactions = {
    shared = {
      keymaps = {
        accept_change = {
          modes = { n = "g2" },
          description = "Accept the suggested change",
        },
        reject_change = {
          modes = { n = "g3" },
          description = "Reject the suggested change",
        },
      },
    },
  },
})
```

You can also cancel an inline request with:

```lua
require("inliber").setup({
  interactions = {
    inline = {
      keymaps = {
        stop = {
          modes = { n = "q" },
          index = 4,
          callback = "keymaps.stop",
          description = "Stop request",
        },
      },
    },
  },
})
```

## Editor Context

The plugin comes with a number of [editor context](/usage/inline#editor-context) items that can be used alongside your prompt using the `#{}` syntax (e.g., `#{buffer}`). You can also add your own:

```lua
require("inliber").setup({
  interactions = {
    inline = {
      editor_context = {
        ["my_new_context_item"] = {
          ---@return string
          callback = "/Users/Oli/Code/my_context_item.lua",
          description = "My shiny new context item",
          opts = {
            contains_code = true,
          },
        },
      },
    },
  },
})
```

## Diff

Please see the [Diff section](/configuration/diff) for configuration options.
