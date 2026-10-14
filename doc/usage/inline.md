---
description: "Write and refactor code directly in Neovim buffers using Inliber's inline interaction — supports visual selection, ask conversations, and diff review."
---

# Using the Inline Interaction

As per the [Getting Started](/getting-started) guide, the inline interaction enables you to code directly into a Neovim buffer. Make a visual selection or place your cursor, then run `:InliberEdit <your prompt>`. The agent rewrites the code in place and shows you a diff.

To ask a question instead, run `:InliberAsk <your prompt>`. The answer appears in a floating window, where you can ask follow-up questions. Run `:InliberAskResume` to reopen the last conversation.

## Adapters

You can specify a different adapter to that in the configuration (`interactions.inline.adapter`) when sending an inline prompt. Simply include the adapter via `adapter=*`. For example `:'<,'>InliberEdit adapter=claude_code can you refactor this?`. This approach can also be combined with editor context.

## Placement

One of the challenges with inline editing is determining how the agent's response should be handled in the buffer. If you've prompted the agent to _"create a table of 5 common text editors"_ then you may wish for the response to be placed at the cursor's position in the current buffer. However, if you asked it to _"refactor this function"_ then you'd expect the response to _replace_ a visual selection. The agent decides whether the response should:

- _replace_ - replace a visual selection you've made
- _add_ - be added in the current buffer at the cursor position
- _before_ - to be added in the current buffer before the cursor position

ACP agents often reply with the whole updated file, or pick a `new` buffer placement. Inliber detects both: a full-file rewrite replaces the whole buffer, and a `new` placement is redirected into the buffer the prompt came from.

## Asking and Editing

Two commands make the intent explicit:

| Command | Action |
| ------- | ------ |
| `:InliberAsk` | Answer the prompt in a floating window, never editing the buffer |
| `:InliberEdit` | Edit the buffer, never answering in a floating window |
| `:InliberAskResume` | Resume the last ask conversation in the float, or prompt fresh if none exists |

Both `Ask` and `Edit` take a prompt (`:InliberEdit refactor this function`), work with a visual selection, and prompt for input when run without one.

After closing the ask float, `:InliberAskResume` reopens it with the full previous conversation so you can continue where you left off. If there is no prior conversation, it prompts for a fresh question.

## Diff Mode

By default, an inline interaction prompt will trigger the diff feature, showing differences between the original buffer and the changes made by the agent. This can be turned off in your config via the `display.diff.enabled` table. You can also choose to accept or reject the agent's suggestions with the following keymaps:

- `g1` - Always accept changes in this buffer
- `g2` - Accept an inline edit
- `g3` - Reject an inline edit

These keymaps can also be changed in your config via the `interactions.shared.keymaps` table.

## Editor Context

> [!TIP]
> To ensure the agent has enough context to complete a complex ask, it's recommended to use the `buffer` editor context

The inline interaction allows you to send context alongside your prompt via the notion of editor context. That is, context that relates to your current Neovim session:

- `buffer` - shares the contents of the current buffer
- `clipboard` - shares the data on your clipboard with the agent

Simply include them in your prompt. For example `:InliberEdit #{buffer} add a new method to this file`. Multiple context items can be sent as part of the same prompt. You can even add your own custom variables as per the [configuration](/configuration/inline#editor-context).

You can also have multiple editor context as part of a prompt, for example: `:InliberEdit #{buffer} #{clipboard} analyze this code`.
