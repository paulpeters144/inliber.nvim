---
description: "inliber.nvim is an AI coding plugin for Neovim. Code with agents like Claude Code, Codex, Gemini CLI and Copilot, and edit code inline."
prev: false
next:
  text: 'Installation'
  link: '/installation'
---

# Welcome to inliber.nvim

> AI Coding, Vim Style

Inliber is a plugin which enables you to code with AI, using coding agents, in Neovim.

## Features

- :robot: Support for the [Agent Client Protocol](https://agentclientprotocol.com/overview/introduction), enabling coding with agents like [Augment Code](https://docs.augmentcode.com/cli/overview), [Cagent](https://github.com/docker/cagent) from Docker, [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview), [Cline CLI](https://docs.cline.bot/home), [Codex](https://openai.com/codex), [Copilot CLI](https://github.com/features/copilot/cli), [Cursor CLI](https://cursor.com/docs/cli/overview), [Gemini CLI](https://github.com/google-gemini/gemini-cli), [Goose](https://block.github.io/goose/), [Kimi CLI](https://github.com/MoonshotAI/kimi-cli), [Kiro](https://kiro.dev/cli/), [Mistral Vibe](https://github.com/mistralai/mistral-vibe) and [OpenCode](https://opencode.ai)
- :rocket: [Inline transformations](/usage/inline), code creation and refactoring
- :speech_balloon: Ask questions in a floating window, with follow-ups
- :art: Built-in diff review for every inline edit
- :electric_plug: [Editor Context](/usage/inline#editor-context) to share buffers and clipboard with an agent
- :muscle: Async execution for fast performance

## Overview

Inliber utilises objects called _interactions_. These are the different ways that a user can interact with an agent. The _inline_ interaction allows output from the agent to be written directly, inline, to a pre-existing Neovim buffer, and answers questions in a floating window.

Inliber uses [adapters](/configuration/adapters-acp) to connect Neovim to an agent, even going as far as specifying [models](/configuration/adapters-acp#setting-default-session-config-options) through the agent's session config options. You can specify an adapter for the inline interaction. Be sure to check out the [adapters folder](https://github.com/paulpeters144/inliber.nvim/tree/main/lua/inliber/adapters/acp) in the main repository. You can also roll your own adapters. Refer to the [extending adapters](/extending/adapters) documentation for more information.

## Using the Docs

You can use the search bar at the top left of the page.
