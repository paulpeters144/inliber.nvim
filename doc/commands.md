---
description: "Every Inliber command in Neovim and the arguments each one takes."
---

# Commands

Inliber has four commands, all driving the inline interaction.

## Inline

| Command | Description |
|---|---|
| `:InliberAsk <prompt>` | Answer the prompt in a floating window, never editing the buffer |
| `:InliberAsk` | Prompt for the question first |
| `:InliberAsk adapter=<adapter> <prompt>` | Ask with a specific adapter |
| `:InliberAskResume` | Resume the last ask conversation, or prompt fresh if none exists |
| `:InliberEdit <prompt>` | Edit the current buffer (or visual selection) in place |
| `:InliberEdit` | Prompt for the edit first |
| `:InliberEdit adapter=<adapter> <prompt>` | Edit with a specific adapter |
| `:InliberCancelLast` | Cancel the most recently submitted request |

Both `Ask` and `Edit` accept a `range`, so a visual selection is sent to the agent as context. The adapter name also works as the first word of the prompt: `:InliberAsk opencode what does this do?`.

Completion for `adapter=` lists the adapters in `adapters.acp`, and `#{` completes the inline editor context.
