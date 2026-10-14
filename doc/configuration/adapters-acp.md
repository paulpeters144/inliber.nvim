---
description: "Configure Agent Client Protocol (ACP) adapters in Inliber to connect with CLI agents like Claude Code, Codex, Gemini CLI, and OpenCode from Neovim."
---

# Configuring Adapters

Inliber connects to CLI agents through the [Agent Client Protocol (ACP)](https://agentclientprotocol.com). This page covers configuration specific to ACP adapters such as Claude Code, Codex, Gemini CLI, and OpenCode.

## Customising an Adapter

There are two ways to customise a preset adapter, and you'll see both throughout this page:

- **Function** - Use this for full or computed setups. Custom `commands`, `defaults`, or values resolved at call time
- **`extend` table** - Use this for static overrides like credentials or setting a default value

::: code-group

```lua [Function]
require("inliber").setup({
  adapters = {
    acp = {
      gemini_cli = function()
        return require("inliber.adapters").extend("gemini_cli", {
          commands = {
            default = { "some-other-gemini", "--experimental-acp" },
          },
          defaults = {
            auth_method = "gemini-api-key",
            timeout = 20000, -- 20 seconds
          },
          env = { GEMINI_API_KEY = "cmd:op read op://personal/Gemini/credential --no-newline" },
        })
      end,
    },
  },
})
```

```lua [Extend Table]
require("inliber").setup({
  adapters = {
    acp = {
      extend = {
        gemini_cli = {
          defaults = { auth_method = "gemini-api-key" },
          env = { GEMINI_API_KEY = "cmd:op read op://personal/Gemini/credential --no-newline" },
        },
      },
    },
  },
})
```

:::

> [!IMPORTANT]
> The `extend` key is the adapter's name in the [config](https://github.com/paulpeters144/inliber.nvim/blob/main/lua/inliber/config.lua), not the resolved adapter name.

## Setting a Default Adapter

You can select an ACP adapter to be the default for the inline interaction:

```lua
require("inliber").setup({
  interactions = {
    inline = {
      adapter = "gemini_cli",
    },
  },
}),
```

## Setting Default Session Config Options

The ACP specification has support for [session config options](https://agentclientprotocol.com/protocol/session-config-options). These are lists of configuration options that agents can share with Inliber at the start of a session such as models, reasoning levels, and more.

### Models

There are numerous ways you can set a model in your config:

::: code-group

```lua [Interactions] {4-7}
require("inliber").setup({
  interactions = {
    inline = {
      adapter = {
        name = "codex",
        model = "gpt-5.4",
      },
    },
  },
}),
```

```lua [Adapter String] {6-10}
require("inliber").setup({
  adapters = {
    acp = {
      codex = function()
        return require("inliber.adapters").extend("codex", {
          defaults = {
            session_config_options = {
              model = "gpt-5.4",
            },
          },
        })
      end,
    },
  },
}),
```

```lua [Adapter Function] {6-14}
require("inliber").setup({
  adapters = {
    acp = {
      codex = function()
        return require("inliber.adapters").extend("codex", {
          defaults = {
            session_config_options = {
              ---@param self Inliber.ACPAdapter
              ---@return string
              model = function(self)
                return "gpt-5.4"
              end,
            },
          },
        })
      end,
    },
  },
}),
```

:::

### Others

To set any other session config option, you can pass them in the `defaults.session_config_options` table:

```lua {6-11}
require("inliber").setup({
  adapters = {
    acp = {
      codex = function()
        return require("inliber.adapters").extend("codex", {
          defaults = {
            session_config_options = {
              mode = "Full Access",
              thought_level = "Xhigh",
            },
          },
        })
      end,
    },
  },
}),
```

## Configuring MCP Servers

Some ACP adapters [support](https://agentclientprotocol.com/protocol/session-setup#mcp-servers) connecting to Model Client Protocol (MCP) servers. You can configure them manually. In the below example, we're configuring Claude Code to connect to the [sequential-thinking](https://github.com/modelcontextprotocol/servers/tree/main/src/sequentialthinking) server via stdio:

```lua
require("inliber").setup({
  adapters = {
    acp = {
      claude_code = function()
        return require("inliber.adapters").extend("claude_code", {
          defaults = {
            mcpServers = {
              {
                name = "sequential-thinking",
                command = "npx",
                args = { "-y", "@modelcontextprotocol/server-sequential-thinking" },
                env = {},
              },
            },
          },
        })
      end,
    },
  },
})
```

## Hiding Preset Adapters

By default, the plugin shows all available adapters, including the presets. If you prefer to only display the adapters defined in your user configuration, you can set the `show_presets` option to `false`:

```lua
require("inliber").setup({
  adapters = {
    acp = {
      opts = {
        show_presets = false,
      },
    },
  },
})
```

## Environment Variables

Setting environment variables within adapters is a key part of configuration. The adapter `env` table lets you define values that will be interpolated into the adapter's fields at runtime.

::: code-group

```lua{7} [Plain Text]
require("inliber").setup({
  adapters = {
    acp = {
      claude_code = function()
        return require("inliber.adapters").extend("claude_code", {
          env = {
            ANTHROPIC_API_KEY = "MY_OTHER_ANTHROPIC_KEY",
          },
        })
      end,
    },
  },
})
```

```lua{7} [Commands]
require("inliber").setup({
  adapters = {
    acp = {
      gemini_cli = function()
        return require("inliber.adapters").extend("gemini_cli", {
          env = {
            GEMINI_API_KEY = "cmd:op read op://personal/Gemini/credential --no-newline",
          },
        })
      end,
    },
  },
})
```

```lua{7-9} [Function]
require("inliber").setup({
  adapters = {
    acp = {
      claude_code = function()
        return require("inliber.adapters").extend("claude_code", {
          env = {
            ANTHROPIC_API_KEY = function()
              return my_custom_api_key_fetcher()
            end,
          },
        })
      end,
    },
  },
})
```

```lua{7} [Schema Reference]
require("inliber").setup({
  adapters = {
    acp = {
      claude_code = function()
        return require("inliber.adapters").extend("claude_code", {
          env = {
            model_for_url = "defaults.model",
          },
        })
      end,
    },
  },
})
```

```lua{7} [File]
require("inliber").setup({
  adapters = {
    acp = {
      claude_code = function()
        return require("inliber.adapters").extend("claude_code", {
          env = {
            ANTHROPIC_API_KEY = "file:~/.dotfiles/.anthropic_api_key",
          },
        })
      end,
    },
  },
})
```

:::

> [!NOTE]
> In this _command_ example, we're using the 1Password CLI to extract the API Key.

Supported `env` value types:

- **Plain environment variable name (string)**: if the value is the name of an environment variable that has already been set (e.g. `"HOME"` or `"GEMINI_API_KEY"`), the plugin will read the value.
- **Command (string prefixed with `cmd:`)**: any value that starts with `cmd:` will be executed via the shell. Example: `"cmd:op read op://personal/Gemini/credential --no-newline"`.
- **Function**: you can provide a Lua function which returns a string and will be called with the adapter as its sole argument.
- **Schema reference (dot notation)**: you can reference values from the adapter table (for example `"defaults.model"`).
- **File (string prefixed with `file:`)**: any value that starts with `file:` will be read from disk, e.g. `"file:.api_key"` (relative to the cwd) or `"file:~/.dotfiles/.api_key"`. The file is read fresh on every request rather than being cached, so updating the file takes effect immediately.

## Setup: Auggie CLI from Augment Code

To use [Auggie CLI](https://docs.augmentcode.com/cli/overview) within Inliber, you simply need to follow their [Getting Started](https://docs.augmentcode.com/cli/overview#getting-started) guide.

## Setup: Cagent

To use Docker's [Cagent](https://github.com/docker/cagent) within Inliber, you need to follow these steps:

1. [Install](https://github.com/docker/cagent?tab=readme-ov-file#installation) Cagent as per their instructions
2. [Create an agent](https://github.com/docker/cagent?tab=readme-ov-file#run-agents) in the repository you're working from
3. Test the agent by running `cagent run your_agent.yaml` in the CLI
4. In your Inliber config, extend the `cagent` adapter to include the agent:

```lua
require("inliber").setup({
  adapters = {
    acp = {
      cagent = function()
        return require("inliber.adapters").extend("cagent", {
          commands = {
            default = {
              "cagent",
              "acp",
              "your_agent.yaml",
            },
          },
        })
      end,
    },
  },
})
```

If you have multiple agent files that you like to run separately, you can create multiple commands for each agent.

## Setup: Claude Code

To use [Claude Code](https://www.anthropic.com/claude-code) within Inliber, you'll need to take the following steps:

1. [Install](https://docs.anthropic.com/en/docs/claude-code/quickstart#step-1%3A-install-claude-code) Claude Code
2. [Install](https://github.com/zed-industries/claude-agent-acp) the Zed ACP adapter for Claude Code

### Using Claude Pro Subscription

3. In your CLI, run `claude setup-token`. You'll be redirected to the Claude.ai website for authorization.
4. Back in your CLI, copy the OAuth token.
5. In your Inliber config, extend the `claude_code` adapter and include the OAuth token (see the section on [environment variables](#environment-variables) for other ways to do this):

```lua
require("inliber").setup({
  adapters = {
    acp = {
      claude_code = function()
        return require("inliber.adapters").extend("claude_code", {
          env = {
            CLAUDE_CODE_OAUTH_TOKEN = "my-oauth-token",
          },
        })
      end,
    },
  },
})
```

### Using an API Key

3. [Create](https://console.anthropic.com/settings/keys) an API key in your Anthropic console.
4. In your Inliber config, extend the `claude_code` adapter and set the `ANTHROPIC_API_KEY`:

```lua
require("inliber").setup({
  adapters = {
    acp = {
      claude_code = function()
        return require("inliber.adapters").extend("claude_code", {
          env = {
            ANTHROPIC_API_KEY = "my-api-key",
          },
        })
      end,
    },
  },
})
```

## Setup: Cline CLI

To use [Cline CLI](https://cline.bot/cli) within Inliber, you'll need to take the following steps:

1. [Install](https://docs.cline.bot/getting-started/installing-cline#cli) Cline CLI.
2. Authenticate by running `cline auth`.
3. Set the `cline_cli` adapter as the default in your config.

## Setup: Codex

To use OpenAI's [Codex](https://openai.com/codex/), install [codex-acp](https://github.com/agentclientprotocol/codex-acp).

By default, the adapter will look for an `OPENAI_API_KEY` in your shell, however you can also authenticate via ChatGPT. This can be customized in the plugin configuration:

```lua
require("inliber").setup({
  adapters = {
    acp = {
      codex = function()
        return require("inliber.adapters").extend("codex", {
          defaults = {
            auth_method = "api-key", -- "api-key"|"chat-gpt"
          },
          env = {
            OPENAI_API_KEY = "my-api-key",
          },
        })
      end,
    },
  },
})
```

## Setup: Copilot CLI

Install [Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/install-copilot-cli) as per the instructions and then in the terminal run `copilot` and ensure that you're authenticated. This is the default adapter for the inline interaction.

## Setup: Cursor CLI

To use [Cursor](https://www.cursor.com/) within Inliber, you'll need to take the following steps:

1. Install `agent` as per the [Cursor CLI documentation](https://cursor.com/docs/cli/overview)
2. Authenticate by running `agent login` in your terminal
3. Set the `cursor_cli` adapter as the default in your config

## Setup: Gemini CLI

1. Install [Gemini CLI](https://github.com/google-gemini/gemini-cli)
2. Update your Inliber config and select which authentication methods you'd like to use. Currently there are:
   - `oauth-personal` which uses your Google login
   - `gemini-api-key`
   - `vertex-ai`)

The example below uses the `gemini-api-key` method, pulling the API key from [1Password CLI](https://developer.1password.com/docs/cli/get-started/):

```lua
require("inliber").setup({
  adapters = {
    acp = {
      gemini_cli = function()
        return require("inliber.adapters").extend("gemini_cli", {
          defaults = {
            auth_method = "gemini-api-key", -- "oauth-personal"|"gemini-api-key"|"vertex-ai"
          },
          env = {
            GEMINI_API_KEY = "cmd:op read op://personal/Gemini_API/credential --no-newline",
          },
        })
      end,
    },
  },
})
```

## Setup: Goose CLI

To use [Goose](https://goose-docs.ai/) in Inliber, ensure you've followed their [documentation](https://goose-docs.ai/docs/getting-started/installation/) to setup and install Goose CLI. Then set the `goose` adapter as the default in your config.

## Setup: Kimi CLI

Install [Kimi CLI](https://github.com/MoonshotAI/kimi-cli?tab=readme-ov-file#installation) as per their instructions. Then in the CLI, run `kimi` followed by `/login` to configure your API key. Then set the `kimi_cli` adapter as the default in your config.

## Setup: Kiro CLI

Install [Kiro cli](https://kiro.dev/docs/cli/) as per their instructions. Then open it and login (if installation doesn't already prompt you to login). The Inliber adapter will execute `kiro-cli acp`, make sure to have it available on your PATH.

## Setup: Mistral Vibe

To use [Mistral Vibe](https://github.com/mistralai/mistral-vibe) in Inliber, ensure you've followed their documentation to [install](https://github.com/mistralai/mistral-vibe). Then run `vibe --setup` in your CLI in order to setup your API key. Then set the `mistral_vibe` adapter as the default in your config.

## Setup: OpenCode

To use [OpenCode](https://opencode.ai) in Inliber, ensure you've followed their documentation to [install](https://opencode.ai/docs/#install) and [configure](https://opencode.ai/docs/#configure) it. Then set the `opencode` adapter as the default in your config.

You can specify a custom model in your `~/.config/opencode/opencode.jsonc` (or `~/.config/opencode/opencode.json`) file:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "github-copilot/claude-sonnet-4.5"
}
```

## Creating Custom ACP Adapters

Not every ACP-compatible tool will have a built-in adapter. You can define your own directly in your configuration — the example below uses a hypothetical `myagent` CLI tool. Use the [built-in ACP adapters](https://github.com/paulpeters144/inliber.nvim/blob/main/lua/inliber/adapters/acp) as a reference.

````lua
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
````

See [Extending with Adapters](/extending/adapters) for the full adapter interface.
