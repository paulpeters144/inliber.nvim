# inliber.nvim

A Neovim AI coding assistant for coding with LLMs and AI agents.

## Features

- Inline ask and edit transformations, code creation and refactoring
- Tools and agentic workflows
- Diff review of AI-edited code
- Support for many LLM providers (Anthropic, OpenAI, Gemini, Copilot, Ollama, OpenRouter and more)

## Requirements

- Neovim 0.11+
- The `curl` library

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "paulpeters144/inliber.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  opts = {},
}
```

## Usage

```lua
require("inliber").setup()
```

See `:help inliber` for full documentation.

## License

[Apache 2.0](LICENSE)

This project is a fork of [codecompanion.nvim](https://github.com/olimorris/codecompanion.nvim) by Oli Morris. See [NOTICE](NOTICE) for attribution.
