---
description: "Every Inliber command in Neovim and the arguments each one takes."
---

# Commands

Inliber has six commands, one per interaction plus the action palette and code review. None of them are mapped to keys by default.

## Chat

| Command | Description |
|---|---|
| `:InliberChat` | Open a new chat buffer |
| `:InliberChat <prompt>` | Open a chat buffer and send the prompt |
| `:InliberChat adapter=<adapter> model=<model>` | Open a chat buffer with a specific HTTP adapter and model |
| `:InliberChat adapter=<adapter> command=<command>` | Open a chat buffer with a specific ACP adapter and command |
| `:InliberChat Toggle` | Show or hide the last chat buffer, creating one if none exist |
| `:InliberChat Add` | Add the visual selection to the current chat buffer |
| `:InliberChat Changes` | Open every file the LLM has changed in the quickfix list |
| `:InliberChat RefreshCache` | Refresh the editor context, slash commands and tools that are conditionally enabled |

## Inline

| Command | Description |
|---|---|
| `:Inliber <prompt>` | Send the prompt to the inline interaction |
| `:Inliber adapter=<adapter> <prompt>` | Send the prompt with a specific adapter |
| `:Inliber /<alias>` | Run a [prompt library](/usage/prompt-library) item by its alias |

## CLI

| Command | Description |
|---|---|
| `:InliberCLI` | Open a new CLI interaction |
| `:InliberCLI <prompt>` | Send the prompt to the last CLI interaction, creating one if none exist |
| `:InliberCLI! <prompt>` | Send and submit the prompt, keeping the cursor in the current buffer |
| `:InliberCLI agent=<agent> <prompt>` | Start a new CLI interaction with a specific agent |
| `:InliberCLI Ask` | Write the prompt in a buffer with editor context, then save to send it |
| `:InliberCLI Install` | Write Inliber's hooks into your CLI agents' settings |

## Code Review

| Command | Description |
|---|---|
| `:InliberCodeReview` | Open the changes made since the last review in the [review window](/usage/code-review) |
| `:InliberCodeReview Branch` | Review every change on the branch since it left the default branch |
| `:InliberCodeReview Comment` | Comment on the current line or visual selection |

## Others

| Command | Description |
|---|---|
| `:InliberActions` | Open the [action palette](/usage/action-palette) |
| `:InliberActions Refresh` | Reload the action palette and prompt library |
| `:InliberCmd <prompt>` | Generate a command in the command-line |
