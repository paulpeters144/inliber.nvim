---
description: "Install inliber.nvim with lazy.nvim or packer. Covers dependencies, Neovim 0.11+ requirements, agent CLIs, and signing in."
---

# Installation

> [!IMPORTANT]
> To avoid breaking changes, it is recommended to pin the plugin to a specific release when installing.

## Requirements

- Neovim 0.11.0 or greater
- One or more [ACP agents](/configuration/adapters-acp), such as the Copilot CLI, Claude Code, Codex or OpenCode, installed and signed in
- _(Optional)_ [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) with the `markdown` parser, so Inliber can extract code from fenced responses

You can run `:checkhealth inliber` to verify that all requirements are met.

## Installation

The plugin can be installed with the plugin manager of your choice. It is recommended to pin the plugin to a specific release to avoid breaking changes.

::: code-group

```lua [Lazy.nvim]
{
  "paulpeters144/inliber.nvim",
  opts = {},
}
```

```lua [Packer.nvim]
use({
  "paulpeters144/inliber.nvim",
  config = function()
    require("inliber").setup()
  end,
})
```

:::

## Help

Consider using the [minimal.lua](https://github.com/paulpeters144/inliber.nvim/blob/main/minimal.lua) file to troubleshoot, running it with `nvim --clean -u minimal.lua`.
