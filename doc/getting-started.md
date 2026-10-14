---
description: "Go from a fresh install of Inliber to an agent editing code in your project, and review what it changed."
---

# Getting Started

This page takes you from a fresh [installation](/installation) to an agent editing a file in your project, and you reviewing what it changed. Each step links to the page that covers it in full.

> [!TIP]
> Every example in these docs is wrapped in `require("inliber").setup({ ... })` so it can be pasted as-is. With [lazy.nvim](https://github.com/folke/lazy.nvim), put the contents of `setup()` in `opts` instead.

## Choosing an Adapter

An _adapter_ connects Inliber to an agent. The default is GitHub Copilot, so if you've installed the [Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/install-copilot-cli) and signed in, there's nothing to configure.

Otherwise, pick one:

```lua
require("inliber").setup({
  interactions = {
    inline = {
      adapter = "claude_code", -- Or "codex", "gemini_cli", "opencode", "copilot_acp"...
    },
  },
})
```

Inliber speaks the [Agent Client Protocol (ACP)](https://agentclientprotocol.com): it spawns the agent's CLI and streams the reply back into Neovim. Each agent needs a little setup first. For Claude Code, that's [installing it and adding a token](/configuration/adapters-acp#setup-claude-code).

Run `:checkhealth inliber` to confirm everything is in place. If you're not sure which adapter suits you, see [Choosing an Adapter](/guides/choosing-an-adapter).

## Asking a Question

Open a file in your project and run:

```
:InliberAsk
```

Type your question in the input modal. The answer appears in a floating window, where you can ask follow-up questions. Run `:InliberAskResume` to reopen the conversation later.

Add `#{buffer}` to share the file with the agent:

```
:InliberAsk What does the code in #{buffer} do?
```

`#{buffer}` is _editor context_. `#{clipboard}` shares your clipboard instead. See [Editor Context](/usage/inline#editor-context) for the full list.

## Letting the Agent Edit Code

Select some code and run:

```
:'<,'>InliberEdit Use early returns
```

The agent rewrites the selection in place and shows you a diff. Keep it with `g2` or undo it with `g3`.

| Keymap | Action |
|---|---|
| `g1` | Always accept changes in this buffer |
| `g2` | Accept the change |
| `g3` | Reject the change |

When nothing is selected, the agent inspects the file itself, decides where the edit belongs, and returns the complete updated file. See [Inline](/usage/inline) for more.

## Reviewing the Changes

The diff flow is the review: every edit is shown before it lands, and rejecting it restores the buffer. The agent's own edits outside the buffer (through its file tools) are its own concern — check `git diff` for those.

## Keymaps

Inliber registers a few keymaps by default:

| Keymap | Action |
|---|---|
| `<leader>aa` | Ask, answering in a floating window |
| `<leader>ae` | Edit, in the current buffer |
| `<leader>ar` | Resume the last ask conversation |

You can change or disable these with the `opts.default_keymaps` option. See [Other Configuration Options](/configuration/others#default-keymaps).

## Next Steps

- [Choosing an Adapter](/guides/choosing-an-adapter) - Pick the agent that suits you
- [Configuring Adapters](/configuration/adapters-acp) - Set models, credentials and commands
- [Running Local Models](/guides/running-local-models) - Keep your code on your machine
