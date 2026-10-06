---
description: "Go from a fresh install of Inliber to an LLM editing code in your project, and review what it changed."
---

# Getting Started

This page takes you from a fresh [installation](/installation) to an LLM editing a file in your project, and you reviewing what it changed. Each step links to the page that covers it in full.

> [!TIP]
> Every example in these docs is wrapped in `require("inliber").setup({ ... })` so it can be pasted as-is. With [lazy.nvim](https://github.com/folke/lazy.nvim), put the contents of `setup()` in `opts` instead

## Choosing an Adapter

An _adapter_ connects Inliber to an LLM or an agent. The default is GitHub Copilot, so if you've signed in with [copilot.vim](https://github.com/github/copilot.vim) or [copilot.lua](https://github.com/zbirenbaum/copilot.lua) there's nothing to configure.

Otherwise, pick one. Adapters are set per _interaction_, which is one of the ways you work with an LLM: `chat` is the chat buffer and `inline` is `:Inliber`, which edits a buffer in place:

::: code-group

```lua [API Key]
-- Reads the ANTHROPIC_API_KEY environment variable
require("inliber").setup({
  interactions = {
    chat = {
      adapter = "anthropic", -- Or "openai", "gemini", "deepseek", "mistral", "openrouter"...
    },
    inline = {
      adapter = "anthropic",
    },
  },
})
```

```lua [Local Model]
-- Requires Ollama to be running
require("inliber").setup({
  interactions = {
    chat = {
      adapter = {
        name = "ollama",
        model = "qwen3:8b",
      },
    },
    inline = {
      adapter = {
        name = "ollama",
        model = "qwen3:8b",
      },
    },
  },
})
```

```lua [Agent]
-- Requires Claude Code and claude-agent-acp to be installed
require("inliber").setup({
  interactions = {
    chat = {
      adapter = "claude_code", -- Or "codex", "gemini_cli", "opencode"...
    },
  },
})
```

:::

HTTP adapters look for an API key in an environment variable named after the provider, such as `OPENAI_API_KEY` or `GEMINI_API_KEY`. To read it from somewhere else, like a password manager, see [environment variables](/configuration/adapters-http#environment-variables).

An agent, such as Claude Code, runs its own tools and connects over the [Agent Client Protocol](/agent-client-protocol). Each one needs a little setup first. For Claude Code, that's [installing it and adding a token](/configuration/adapters-acp#setup-claude-code). Agents only work in the chat buffer.

Run `:checkhealth inliber` to confirm everything is in place. If you're not sure which adapter suits you, see [Choosing an Adapter](/guides/choosing-an-adapter).

## Starting a Chat

Open a file in your project and run:

```
:InliberChat
```

This opens a _chat buffer_. Type a message and send it with `<C-s>` in insert mode or `<CR>` in normal mode. To share the file you opened the chat from, add `#{buffer}` to your message:

```md
What does the code in #{buffer} do?
```

`#{buffer}` is _editor context_. Other editor context includes `#{diagnostics}` for LSP errors, `#{selection}` for a visual selection and `#{terminal}` for your latest terminal output. Typing `#` shows everything that's available. See [Editor Context](/usage/chat-buffer/editor-context) for the full list.

Run `:InliberChat Toggle` to hide the chat and bring it back. The chat keeps its history while it's hidden.

## Letting the LLM Edit Code

An LLM can't touch your files until you give it _tools_. Add `@{files}` to your message to let it read, create and edit files:

```md
@{files} Add a docstring to each function in #{buffer}
```

<p>
  <video controls muted title="Tool editing demo" src="https://github.com/user-attachments/assets/4d63d4ea-b625-4549-a946-eb3db24eb078"></video>
</p>

Some tools, like reading a file, ask for your approval before they run. The chat buffer lists your options:

| Keymap | Action |
|---|---|
| `g1` | Always accept this tool in this chat |
| `g2` | Accept this time |
| `g3` | Reject, and tell the LLM why |
| `g4` | Cancel this and every other pending tool call |

Before an edit is written to the file, you're shown it as a diff. Small diffs appear in the chat buffer and larger ones open in a floating window. Press `gv` to open it yourself. Accept the change with `g2` or reject it with `g3`.

Once you're happy with the tools, press `gty` to stop being asked each time. See [approval modes](/usage/chat-buffer/agents-tools#approval-modes) for what each mode allows.

> [!NOTE]
> Agents like Claude Code bring their own tools, so you don't need `@{files}`. They ask for permission in the chat buffer too

`@{agent}` gives the LLM every tool it needs to work through a task by itself, including running commands. See [Tools](/usage/chat-buffer/agents-tools) for the full list.

## Reviewing the Changes

Once the LLM has finished, run:

```
:InliberCodeReview
```

<img src="https://github.com/user-attachments/assets/d50bd196-0612-4297-9a39-375d599018e5" width="100%" alt="Code review window">

This opens every change made since your first message, file by file and hunk by hunk. Press `ga` to accept a change, `gr` to revert it or `gc` to leave a comment on it. To send your comments back, add `#{code_review}` to your next message:

```md
#{code_review} Please address my comments
```

The next review only shows what the LLM changed in response. See [Code Review](/usage/code-review) for the full workflow.

## Editing Inline

You don't need a chat buffer for smaller changes. Select some code and run:

```
:'<,'>Inliber Use early returns
```

<p>
  <video controls muted title="Inline interaction demo" src="https://github.com/user-attachments/assets/ed3014be-11ff-4583-93da-efcb5d7ca0d6"></video>
</p>

The LLM rewrites the selection in place and shows you a diff. Keep it with `g2` or undo it with `g3`. See [Inline](/usage/inline) for more.

The [prompt library](/usage/prompt-library) has prompts for common tasks, called by their alias:

| Command | Action |
|---|---|
| `:'<,'>Inliber /explain` | Explain how the selected code works, in a chat buffer |
| `:'<,'>Inliber /fix` | Fix the selected code, in a chat buffer |
| `:'<,'>Inliber /lsp` | Explain the LSP diagnostics for the selected code, in a chat buffer |
| `:'<,'>Inliber /tests` | Write unit tests for the selected code, in a new buffer |
| `:Inliber /commit` | Write a commit message for your staged changes, in a chat buffer |

Run `:InliberActions` to browse them, alongside any prompts you write yourself.

## Keymaps

Inliber registers a few keymaps by default:

| Keymap | Action |
|---|---|
| `<leader>aa` | Ask, answering in a floating window |
| `<leader>ae` | Edit, never answering in a chat buffer |
| `<leader>ar` | Resume the last ask conversation |

You can change or disable these with the `opts.default_keymaps` option. See [Other Configuration Options](/configuration/others#default-keymaps).

These are the other ones the author uses:

```lua
vim.keymap.set({ "n", "v" }, "<C-a>", "<cmd>InliberActions<cr>", { noremap = true, silent = true })
vim.keymap.set({ "n", "v" }, "<LocalLeader>a", "<cmd>InliberChat Toggle<cr>", { noremap = true, silent = true })
vim.keymap.set("v", "ga", "<cmd>InliberChat Add<cr>", { noremap = true, silent = true })

-- Expand 'cc' into 'Inliber' in the command line
vim.cmd([[cab cc Inliber]])
```

`:InliberChat Add` adds the visual selection to the current chat. See [Commands](/commands) for every command and its arguments.

## Next Steps

- [Coding with an Agent](/guides/coding-with-an-agent) - Use Claude Code, Codex and others from the chat buffer
- [Controlling Tool Approvals](/guides/tool-approvals) - Decide what an LLM can do without asking
- [Sharing Rules and Skills Across Projects](/guides/sharing-rules-and-skills) - Give the LLM your project's conventions, like `AGENTS.md`
- [Setting Up Web Search](/guides/web-search) - Let the LLM look things up
- [Using a Cheaper Model for Background Tasks](/guides/background-model) - Keep costs down on chat titles and compaction
