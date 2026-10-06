---
description: "Write and refactor code directly in Neovim buffers using Inliber's inline interaction — supports visual selection, prompt library aliases, and diff review."
---

# Using the Inline Interaction

<p align="center">
  <video controls muted title="Inline interaction demo" src="https://github.com/user-attachments/assets/dcddcb85-cba0-4017-9723-6e6b7f080fee"></video>
</p>

As per the [Getting Started](/getting-started#editing-inline) guide, the inline interaction enables you to code directly into a Neovim buffer. Simply run `:Inliber <your prompt>`, or make a visual selection to send that as context to the LLM alongside your prompt.

For convenience, you can call prompts from the [prompt library](/configuration/prompt-library) via the interaction. For example, `:'<,'>Inliber /tests` would ask the LLM to create some unit tests from the selected text.

## Adapters

You can specify a different adapter to that in the configuration (`interactions.inline.adapter`) when sending an inline prompt. Simply include the adapter via `adapter=*`. For example `:<','>Inliber adapter=deepseek can you refactor this?`. This approach can also be combined with variables.

## Classification

One of the challenges with inline editing is determining how the LLM's response should be handled in the buffer. If you've prompted the LLM to _"create a table of 5 common text editors"_ then you may wish for the response to be placed at the cursor's position in the current buffer. However, if you asked the LLM to _"refactor this function"_ then you'd expect the response to _replace_ a visual selection. The plugin uses the inline LLM you've specified in your config to determine if the response should:

- _replace_ - replace a visual selection you've made
- _add_ - be added in the current buffer at the cursor position
- _before_ - to be added in the current buffer before the cursor position
- _new_ - be placed in a new buffer
- _chat_ - be placed in a chat buffer

## Asking and Editing

`:Inliber` leaves it to the LLM to decide whether your prompt is a question or an edit. To make that decision yourself, two commands force the outcome:

| Command | Action |
| ------- | ------ |
| `:InliberAsk` | Answer the prompt in a chat buffer, never editing the buffer |
| `:InliberEdit` | Edit the buffer, never answering in a chat buffer |
| `:InliberAskResume` | Resume the last ask conversation in the float, or prompt fresh if none exists |

Both `Ask` and `Edit` take a prompt (`:InliberEdit refactor this function`), work with a visual selection, and prompt for input when run without one.

After closing the ask float, `:InliberAskResume` reopens it with the full previous conversation so you can continue where you left off. If there is no prior conversation, it prompts for a fresh question.

## Diff Mode

By default, an inline interaction prompt will trigger the diff feature, showing differences between the original buffer and the changes made by the LLM. This can be turned off in your config via the `display.diff.provider` table. You can also choose to accept or reject the LLM's suggestions with the following keymaps:

- `gda` - Accept an inline edit
- `gdr` - Reject an inline edit

These keymaps can also be changed in your config via the `interactions.inline.keymaps` table.

## Editor Context

> [!TIP]
> To ensure the LLM has enough context to complete a complex ask, it's recommended to use the `buffer` editor context

The inline interaction allows you to send context alongside your prompt via the notion of editor context. That is, context that relates to your current Neovim session:

- `buffer` - shares the contents of the current buffer
- `chat` - shares the LLM's messages from the last chat buffer
- `clipboard` - shares the data on your clipboard with the LLM

Simply include them in your prompt. For example `:Inliber #{buffer} add a new method to this file`. Multiple context items can be sent as part of the same prompt. You can even add your own custom variables as per the [configuration](/configuration/inline#editor-context).

You can also have multiple editor context as part of a prompt, for example: `:Inliber #{buffer} #{clipboard} analyze this code`.

