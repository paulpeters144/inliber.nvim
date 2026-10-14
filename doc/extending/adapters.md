---
description: "Build a custom Inliber ACP adapter to connect Neovim to any Agent Client Protocol CLI. Covers the adapter interface, commands, environment variables, and handlers."
---

# Extending with Adapters

In Inliber, adapters are interfaces that act as a bridge between the plugin's functionality and a coding agent. All adapters must follow the interface, below.

This guide is intended to serve as a reference for anyone who wishes to contribute an adapter to the plugin or understand the inner workings of existing adapters.

The plugin's in-built adapters can be found in the [adapters source directory](https://github.com/paulpeters144/inliber.nvim/tree/main/lua/inliber/adapters/acp).

## The Interface

Let's take a look at the interface of an adapter as per the `adapters/acp/init.lua` file:

```lua
---@class Inliber.ACPAdapter
---@field name string The name of the adapter e.g. "claude_code"
---@field formatted_name string The formatted name of the adapter e.g. "Claude Code"
---@field type string|"acp" The type of the adapter
---@field roles table The mapping of roles in the config to the agent's defined roles
---@field commands { default: table, [string]: table } The list of possible commands. Must include a 'default' key
---@field defaults? table Adapter defaults (session_config_options, timeout, mcpServers, auth_method)
---@field env? table Environment variables which can be referenced in the parameters
---@field env_replaced? table Replacement of environment variables with their actual values
---@field parameters? table ACP protocol parameters (protocolVersion, clientCapabilities, clientInfo)
---@field handlers table Functions linking agent output back to Inliber
```

The `commands` table is the heart of the adapter. The `default` command is the process that Inliber spawns to talk to the agent over the [Agent Client Protocol](https://agentclientprotocol.com). You can define additional named commands (such as a `yolo` variant) and switch between them.

`parameters` is sent verbatim as the params of the `initialize` request. `protocolVersion` is the protocol version the client supports, `clientCapabilities` declares what the client can do (most importantly serving `fs/read_text_file` and `fs/write_text_file` requests), and `clientInfo` identifies the client to the agent.

## Handlers

```lua
handlers = {
  setup = function(self) end,                    -- Called before the process is spawned. Must return a boolean
  auth = function(self) end,                     -- Optionally handle authentication yourself. Return true on success
  form_messages = function(self, messages, capabilities) end, -- Transform Inliber messages into ACP content blocks
  on_exit = function(self, code) end,            -- Called when the agent process exits
  teardown = function(self) end,                 -- Called last, after on_exit
}
```

- `setup` runs before the agent process is spawned, after environment variables have been resolved. Returning `false` aborts the request.
- `auth` lets an adapter declare authentication a success itself, which skips the protocol `authenticate` exchange. Use it when an agent advertises an auth method that cannot be driven from the client (see the `opencode` preset).
- `form_messages` receives the messages already role-mapped by Inliber, plus the agent's reported capabilities, and must return the ACP `prompt` content blocks. Most adapters delegate to `helpers.form_messages`.
- `on_exit` receives the process exit code and is a good place to surface errors.

## Environment Variables

When building an adapter, you'll need to inject variables into different parts of the adapter class. The `env` table names the variables, which can then be interpolated into the adapter's `commands`, `defaults` and `parameters` via the `${}` notation:

```lua
env = {
  api_key = "GEMINI_API_KEY",
},
defaults = {
  auth_method = "gemini-api-key",
},
parameters = {
  clientInfo = {
    name = "Inliber.nvim",
    version = "${api_key}", -- Example only
  },
},
```

The value can represent one of:

- A command to execute on the user's system (`cmd:` prefix)
- An environment variable from the user's system
- A function to be executed at runtime
- A path to an item in the adapter's table (dot notation)
- A plain text value

**Commands**

An environment variable can be obtained from running a command on a user's system. This can be accomplished by prefixing the value with `cmd:` such as:

```lua
env = {
  api_key = "cmd:op read op://personal/Gemini_API/credential --no-newline",
},
```

In this example, we're running the `op read` command to get a credential from 1Password.

**Environment Variable**

An environment variable can also be obtained by using lua's `os.getenv` function. Simply enter the name of the variable as a string such as:

```lua
env = {
  api_key = "GEMINI_API_KEY",
},
```

**Functions**

An environment variable can also be resolved via the use of a function such as:

```lua
env = {
  api_key = function()
    return os.getenv("GEMINI_API_KEY")
  end,
},
```

**Table Values**

An environment variable can also be resolved by entering the path to a value in a table on the adapter class. For example:

```lua
env = {
  model = "defaults.model",
},
```

**Files**

A value prefixed with `file:` is read from disk, e.g. `"file:.api_key"` (relative to the cwd) or `"file:~/.dotfiles/.api_key"`. The file is read fresh on every request rather than being cached, so updating the file takes effect immediately.

## Session Config Options

Agents report their available [session config options](https://agentclientprotocol.com/protocol/session-config-options) — such as models and modes — when a session is created. The adapter can set defaults for them via `defaults.session_config_options`:

```lua
defaults = {
  session_config_options = {
    model = "opus",
    mode = "plan",
  },
},
```

Inliber applies these to each fresh session through `session/set_config_option`, resolving names against the options the agent actually reported. Values that the agent doesn't offer are skipped with a warning.

## Creating a Custom Adapter

Not every ACP-compatible tool will have a built-in adapter. You can define your own directly in your configuration:

```lua
require("inliber").setup({
  adapters = {
    acp = {
      my_agent = function()
        local helpers = require("inliber.adapters.acp.helpers")
        return {
          name = "my_agent",
          formatted_name = "MyAgent",
          type = "acp",
          roles = {
            llm = "assistant",
            user = "user",
          },
          commands = {
            default = {
              "myagent",
              "--acp",
            },
          },
          defaults = {
            mcpServers = {},
            timeout = 20000, -- 20 seconds
          },
          parameters = {
            protocolVersion = 1,
            clientCapabilities = {
              fs = { readTextFile = true, writeTextFile = true },
            },
            clientInfo = {
              name = "Inliber.nvim",
              version = "1.0.0",
            },
          },
          handlers = {
            setup = function(self)
              return true
            end,
            auth = function(self)
              return true
            end,
            form_messages = function(self, messages, capabilities)
              return helpers.form_messages(self, messages, capabilities)
            end,
            on_exit = function(self, code) end,
          },
        }
      end,
    },
  },
})
```

> [!TIP]
> All of the adapters in the plugin come with their own tests. These serve as a great reference to understand how they're working with the protocol.
