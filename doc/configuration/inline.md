---
description: "Configure Inliber's inline interaction for writing and refactoring code directly into Neovim buffers via LLM prompts, without opening a chat buffer."
---

# Configuring the Inline Interaction

> [!IMPORTANT]
> Only **http** adapters are supported for the inline interaction.

<p align="center">
  <img src="https://github.com/user-attachments/assets/21568a7f-aea8-4928-b3d4-f39c6566a23c" alt="Inline Interaction">
</p>

Inliber provides an _inline_ interaction for quick, direct editing of your code. Unlike the chat buffer, the inline interaction integrates responses directly into the current buffer—allowing the LLM to add or replace code as needed.

## Changing Adapter

By default, Inliber sets the _copilot_ adapter for the inline interaction. You can change this to any other HTTP adapter:

```lua
require("inliber").setup({
  interactions = {
    inline = {
      adapter = {
        name = "anthropic",
        model = "claude-haiku-4-5-20251001"
      },
    },
  },
})
```

See the section on [HTTP Adapters](/configuration/adapters-http) for more information.

## Keymaps

The inline interaction supports keymaps for accepting or rejecting changes:

```lua
require("inliber").setup({
  interactions = {
    inline = {
      keymaps = {
        accept_change = {
          modes = { n = "ga" },
          description = "Accept the suggested change",
        },
        reject_change = {
          modes = { n = "gr" },
          opts = { nowait = true },
          description = "Reject the suggested change",
        },
      },
    },
  },
})
```

In this example, `ga` accepts inline changes, while `gr` rejects them.

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

## Tools

The inline interaction can give the LLM access to the same [tools](/configuration/tools) as the chat buffer, letting it gather context (e.g. read a file or search the codebase) before producing its response. This is disabled by default:

```lua
require("inliber").setup({
  interactions = {
    inline = {
      tools = {
        enabled = true,
        -- Tools and/or groups loaded for the inline interaction
        default_tools = { "read_file", "grep_search", "file_search" },
        opts = {
          approval_mode = "auto", -- ask|auto|yolo
        },
      },
    },
  },
})
```

Tools run through a hidden chat buffer and reuse the tool definitions from the chat interaction, so any tool configured under `interactions.chat.tools` can be listed here. Because the buffer is hidden, `auto` is the recommended approval mode; the default read-only tools run without prompting in this mode.

**Note:** ACP adapters (like OpenCode, Claude Code) are also supported when tools are enabled. ACP agents use their own built-in tools rather than the Inliber tools listed above.

## Editor Context

The plugin comes with a number of [editor context](/usage/inline#editor-context) items that can be used alongside your prompt using the `#{}` syntax (e.g., `#{my_new_context_item}`). You can also add your own:

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
      }
    }
  }
})
```

## Layout

If the inline prompt creates a new buffer, you can also customize if this should be output in a vertical/horizontal split or a new buffer:

```lua
require("inliber").setup({
  display = {
    inline = {
      layout = "vertical", -- vertical|horizontal|tab|buffer
    },
  }
})
```

## Diff

Please see the [Diff section](chat-buffer#diff) on the Chat Buffer page for configuration options.
