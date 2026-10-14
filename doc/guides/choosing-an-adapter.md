---
description: "Pick an ACP agent - GitHub Copilot, Claude Code, Codex, Gemini CLI, OpenCode or another - for Inliber in Neovim, and set it up."
---

# Choosing an Adapter

Inliber defaults to GitHub Copilot, which is no help if you don't have it. Every other option works too. If you haven't set up the plugin yet, start with [Getting Started](/getting-started).

## The Options

An _adapter_ connects Inliber to an agent. Inliber speaks the [Agent Client Protocol (ACP)](https://agentclientprotocol.com): it spawns the agent's CLI as a subprocess, sends it your prompt and streams the reply back. The agent brings its own tools, models, authentication and permission model.

| Option | Adapter | What you need |
|---|---|---|
| GitHub Copilot | `copilot_acp` | A Copilot plan, including Free and Student, signed in with the Copilot CLI |
| Claude Code | `claude_code` | Claude Code and the `claude-agent-acp` adapter, signed in |
| Codex | `codex` | OpenAI's `codex-acp` wrapper and an API key or ChatGPT login |
| Gemini CLI | `gemini_cli` | The Gemini CLI, signed in or with an API key |
| OpenCode | `opencode` | OpenCode installed and configured |
| Others | `cursor_cli`, `goose`, `kiro`, `kimi_cli`, `auggie_cli`, `cline_cli`, `mistral_vibe`, `cagent` | The agent installed and signed in |

Each agent needs installing and authenticating first. See the setup steps in [ACP Adapters](/configuration/adapters-acp).

### GitHub Copilot

If you pay for Copilot, or have Copilot Free or Student, there's nothing to configure beyond installing the [Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/install-copilot-cli) and signing in. This is Inliber's default adapter.

### Claude Code

Choose this when you already use Claude Code. It can bill against a Claude Pro subscription, and its tools, subagents and permissions all work through Inliber. See [Setup: Claude Code](/configuration/adapters-acp#setup-claude-code).

### An Agent You Already Use

Any ACP agent works the same way: install it, sign in, then set it as the inline adapter. Inliber spawns the agent's CLI, so whatever you've configured in the agent itself (models, permissions, MCP servers) applies.

## Setting the Adapter

The adapter is set per interaction. Inliber's only interaction is the _inline_ one, which answers questions in a float and edits buffers in place:

```lua
require("inliber").setup({
  interactions = {
    inline = {
      adapter = "claude_code", -- Or "codex", "gemini_cli", "opencode", "copilot_acp"...
    },
  },
})
```

To use a specific model, pass a table with the adapter's `name` and a `model`:

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

The model is set through the ACP [session config options](https://agentclientprotocol.com/protocol/session-config-options), so it must be one the agent actually offers. See [Setting Default Session Config Options](/configuration/adapters-acp#setting-default-session-config-options).

## Switching Adapters Per Prompt

You can override the adapter for a single prompt with the `adapter=` syntax:

```
:InliberEdit adapter=claude_code refactor this function
```

The adapter name also works as the first word of the prompt: `:InliberAsk opencode what does this do?`. See [Commands](/commands) for the rest.

## Hiding Adapters

Command completion lists every preset. To show only the adapters you've defined yourself, set `show_presets = false`:

```lua
require("inliber").setup({
  adapters = {
    acp = {
      opts = {
        show_presets = false,
      },
    },
  },
})
```

See [Hiding Preset Adapters](/configuration/adapters-acp#hiding-preset-adapters).
