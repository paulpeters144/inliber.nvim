---
description: "Run Inliber against a local model by pointing an ACP agent such as OpenCode or Goose at Ollama."
---

# Running Local Models

A local model keeps your code on your own machine and needs no API key. Inliber itself doesn't call models — the agents do — so a local model is a matter of pointing an agent at one.

This guide assumes [Ollama](https://ollama.com) is installed and running, and that you've pulled a model:

```
ollama pull qwen3:8b
```

## Pointing an Agent at Ollama

Any agent that supports local providers works. [OpenCode](https://opencode.ai) ships with an Ollama provider — set the model in `~/.config/opencode/opencode.jsonc`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "ollama/qwen3:8b"
}
```

[Goose](https://goose-docs.ai/) and [Kimi CLI](https://github.com/MoonshotAI/kimi-cli) offer similar local providers in their own config files.

Then point Inliber at the agent:

```lua
require("inliber").setup({
  interactions = {
    inline = {
      adapter = "opencode", -- Or "goose", "kimi_cli"...
    },
  },
})
```

The agent manages the model, its context window and its tools, so the provider-specific options live in the agent's config rather than Inliber's. See [Choosing an Adapter](/guides/choosing-an-adapter) for setting the adapter, and the agent's own setup section in [ACP Adapters](/configuration/adapters-acp).

## Limitations

- The model must be one the agent's provider supports. Inliber sets models through ACP session config options, which only cover what the agent reports
- Small local models are slower and weaker at tool use than hosted ones. The agent's own tasks, such as reading files and planning edits, run on the model too
