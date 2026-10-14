---
description: "Diagnose problems with Inliber in Neovim with the health check, the log file and the per-request ACP RPC logs."
---

# Troubleshooting

## Health Check

Run:

```
:checkhealth inliber
```

It reports whether Neovim meets the plugin's requirements and warns about common misconfigurations.

## The Log File

By default, logs are stored at `~/.local/state/nvim/inliber.log`. Raise the log level when chasing a problem:

```lua
require("inliber").setup({
  opts = {
    log_level = "DEBUG", -- TRACE|DEBUG|ERROR|INFO
  },
})
```

## ACP RPC Logs

Every request to an agent captures the raw JSON-RPC traffic in a temporary file. The connection logs its path at the INFO level:

```
[acp] RPC log: /tmp/nvim.example/xxxxxx.log
```

Set `log_level = "INFO"` (or lower) and watch for the line after starting an inline request. The file contains every message sent to and received from the agent.

## Common Problems

### The agent is not found

The adapter spawns the agent's CLI from your PATH. If the process fails to start, check:

- The agent is installed and on your PATH _inside Neovim_. GUIs and terminal multiplexers often have a different PATH than your shell
- The command the adapter runs. Extend the adapter with an absolute path if needed:

```lua
require("inliber").setup({
  adapters = {
    acp = {
      extend = {
        claude_code = {
          commands = {
            default = { "/path/to/claude-agent-acp" },
          },
        },
      },
    },
  },
})
```

### The agent is not authenticated

Run the agent once in your terminal and complete its login flow. Some agents (Claude Code, Cline, Cursor) authenticate through their own CLI, and Inliber reuses that. Check the [setup section](/configuration/adapters-acp) for your agent.

### The request hangs

One-shot requests auto-deny the agent's permission requests, so a hang is usually the agent waiting on something else, such as a missing API key prompt on its stderr. Check the RPC log to see where the conversation stopped.

### The edit landed in the wrong place

ACP agents often reply with the whole updated file, or pick a `new` buffer placement. Inliber detects both: a full-file rewrite replaces the whole buffer, and a `new` placement is redirected into the buffer the prompt came from.
