# Description

HTTP-based agents are a failed experiment; move to ACP (Agent Client Protocol) for everything, mirroring the migration completed today in `codecompanion.nvim` (commits `fc0958f8`, `7ae5d202`, `9dd46b67`). Port the ACP core (Connection, PromptBuilder, JSON-RPC, async util), the ACP adapter layer, and the one-shot request bridge; rewire the inline interaction — the only one that survives in this codebase — to submit through ACP; then delete the HTTP client, HTTP adapters, and the tool ecosystem, and sweep tests, docs, and AGENTS.md. Background: `plans/http-to-acp-migration-research.md`.

# TODO

- [ ] Port the ACP core (jsonrpc util, async util, methods, Connection, PromptBuilder)
- [ ] Port the ACP adapter layer (ACPAdapter class, helpers, preset adapters)
- [ ] Port the one-shot request bridge (acp_request, acp defaults)
- [ ] Rewire the inline interaction over ACP
- [ ] Delete the HTTP layer
- [ ] Delete the tool ecosystem (keep a slim approvals list)
- [ ] Update config and commands
- [ ] Update tests
- [ ] Update docs and AGENTS.md

# TODO Explanation

## Port the ACP core (jsonrpc util, async util, methods, Connection, PromptBuilder)

Create `lua/inliber/utils/jsonrpc.lua` (port of codecompanion's `utils/jsonrpc.lua`, namespace renamed `CodeCompanion.JsonRPC.*` → `Inliber.JsonRPC.*`), `lua/inliber/utils/async.lua` (verbatim port), `lua/inliber/acp/methods.lua` (ACP method name constants), `lua/inliber/acp/init.lua` (Connection class), and `lua/inliber/acp/prompt_builder.lua` (streaming PromptBuilder). The Connection port must drop codecompanion's `integrations.agent_env()` call (inliber has no `integrations/` module) and point its `VimLeavePre` disconnect at an inliber augroup name. RPC traffic logging uses the existing `log.new_response_file()`.

## Port the ACP adapter layer (ACPAdapter class, helpers, preset adapters)

Create `lua/inliber/adapters/acp/init.lua` (ACPAdapter class), `lua/inliber/adapters/acp/helpers.lua` (`form_messages`), and the 13 preset adapters from codecompanion (`auggie_cli`, `cagent`, `claude_code`, `cline_cli`, `codex`, `cursor_cli`, `copilot_acp`, `gemini_cli`, `goose`, `kimi_cli`, `kiro`, `mistral_vibe`, `opencode`), renamed to the inliber namespace. codecompanion's `kilocode.lua` sits on disk but is unregistered in its config — do not port it. inliber's existing `interactions/shared/agent_commands/` providers (claude_code, opencode) are already ACP-adjacent and stay.

## Port the one-shot request bridge (acp_request, acp defaults)

Create `lua/inliber/interactions/shared/acp_request.lua` (connection pooling per `purpose:adapter_name`, fs stripped from `clientCapabilities` so one-shot agents cannot edit files directly, `shape_messages` folding, `submit` returning a cancel handle) and a slim `lua/inliber/interactions/inline/acp/defaults.lua` (port of codecompanion's `interactions/chat/acp/defaults.lua` minus the chat dependencies — applies `session_config_options` after `session/new`). One-shot requests register no `on_permission_request` handler, so `session/request_permission` auto-responds `cancelled` — the PromptBuilder default. This mirrors codecompanion's one-shot path exactly; turns never hang waiting on a permission prompt, and agents report the blocked action in their reply instead. No approval prompt UI is ported.

## Rewire the inline interaction over ACP

Replace the HTTP submit path in `lua/inliber/interactions/inline/init.lua` with the one-shot ACP path: `submit()` → `_submit_acp()` via `acp_request.submit({ purpose = "inline", ... })`, `stop()` → `current_request.cancel()`, and `parse_special_syntax` → `config.adapters.acp`. Add the ACP fenced-code parse fallback, whole-file-rewrite detection, and `"new"`-placement redirect. The structured-output enforcement (commit `843955d`, HTTP-only) becomes prompt-based: the lean ACP system prompt plus a JSON parsing fallback. Keep the diff UI flow, the approvals list for diffs, and the ask-float conversation memory (messages are resent per turn — ACP sessions renew per request).

## Delete the HTTP layer

Delete `lua/inliber/adapters/http/` (17 adapter files + `copilot/` + `ollama/` + `init.lua`) and `lua/inliber/http.lua`. Rewrite `lua/inliber/adapters/init.lua` to delegate only to `adapters.acp` and delete `get_handler`/`call_handler`. Prune `adapters/utils/` to what the ACP path needs (`map_roles`, env var helpers) and delete `structured_outputs.lua`, `tool_transformers.lua`, `models/`. `adapters/shared.lua` keeps `map_roles`/`apply_extend`, drops `input_limit`. Replace all `Inliber.HTTPAdapter` annotations with `Inliber.ACPAdapter`.

## Delete the tool ecosystem (keep a slim approvals list)

Delete `lua/inliber/tools/` except the approvals list, which the inline diff accept/reject flow still uses. Move it to `lua/inliber/interactions/inline/approvals.lua`, slimmed to bufnr-keyed `is_approved`/`always` (codecompanion precedent: `interactions/chat/approvals.lua`), and drop the loop-id machinery and the `config.tools` reads. Remove the tool-loop path from inline (`submit_with_tools`, `_add_tools`, `_prepare_tool_messages`, `_structured_output`, `_submit` routing, `tool_loop` field, tool-loop branches in `stop()`/`reset()`). Agents get file editing through their own tools and the ACP `fs/read_text_file`/`fs/write_text_file` client methods; permissions via `session/request_permission`.

## Update config and commands

`lua/inliber/config.lua`: replace the `adapters.http` block with `adapters.acp` (13 preset names + `extend` + `opts.show_presets`), set `interactions.inline.adapter = "copilot_acp"`, keep `adapters.opts.cmd_timeout`, drop `allow_insecure`/`proxy`/`cache_models_for`/`hidden`, and delete the `tools` block. `lua/inliber/init.lua` `adapter_config()` merges `config.adapters.acp`. `lua/inliber/commands/init.lua` `get_adapters()` iterates `config.adapters.acp`.

## Update tests

Delete `tests/adapters/http/` (including stale merge-conflict backup stubs), `tests/adapters/utils/`, `tests/test_http.lua`; strip HTTP cases from `tests/adapters/test_adapters.lua`. Port `tests/acp/`, `tests/mocks/acp.lua`, `tests/stubs/acp/`, `tests/interactions/shared/test_acp_request.lua`, `tests/interactions/inline/test_inline_acp.lua` from codecompanion. Rework `tests/interactions/inline/test_inline.lua` (replace `inliber.http` stubbing with an ACP mock), `tests/scripts/ui.lua`, `tests/helpers.lua`. `make format` + `make test` green.

## Update docs and AGENTS.md

Delete `doc/configuration/adapters-http.md`, `doc/configuration/tools.md`, `doc/extending/tools.md`, `doc/guides/tool-approvals.md`, `doc/guides/openai-compatible-providers.md`. Add `doc/configuration/adapters-acp.md` (port from codecompanion) and rewrite `doc/extending/adapters.md`, `doc/guides/choosing-an-adapter.md`, `doc/guides/running-local-models.md`, `doc/guides/background-model.md`, `doc/configuration/inline.md`, `doc/getting-started.md`, `doc/installation.md`, `doc/troubleshooting.md`, `doc/architecture.md`. Update `AGENTS.md` (Architecture: `adapters/acp/`; drop HTTP-only rules such as the Ollama/openai_compatible `schema.model.default` note). Run `make docs`.

# Objects

## Inliber.JsonRPC (new)

The JSON-RPC 2.0 message builders/parsers module. Lives in `lua/inliber/utils/jsonrpc.lua` (verbatim port of codecompanion's `utils/jsonrpc.lua`).

```lua
---@class Inliber.JsonRPC
local M = {}

---Standard JSON-RPC error codes
M.errors = {
  PARSE_ERROR = -32700,
  INVALID_REQUEST = -32600,
  METHOD_NOT_FOUND = -32601,
  INVALID_PARAMS = -32602,
  INTERNAL_ERROR = -32603,
}
```

## Inliber.JsonRPC.LineBuffer (new)

Reassembles newline-delimited stdout chunks into whole JSON-RPC messages. Lives in `lua/inliber/utils/jsonrpc.lua`.

```lua
---@class Inliber.JsonRPC.LineBuffer
---@field buffer string Partial line accumulated across stdout chunks
---@field decoder fun(line: string): any Decoder invoked on each complete line
---@field callback fun(message: any): nil Invoked with each decoded message
```

## Inliber.JsonRPC.IdGenerator (new)

Monotonic JSON-RPC request id source. Lives in `lua/inliber/utils/jsonrpc.lua`.

```lua
---@class Inliber.JsonRPC.IdGenerator
---@field id number Next id to hand out
```

## Inliber.ACP.Connection (new)

The ACP agent process connection: spawn, initialize, authenticate, sessions, streaming dispatch, and fs serving. Lives in `lua/inliber/acp/init.lua` (port of codecompanion's `acp/init.lua`).

```lua
---@class Inliber.ACP.Connection
---@field adapter Inliber.ACPAdapter
---@field adapter_modified Inliber.ACPAdapter Modified adapter with environment variables resolved
---@field pending_responses table<number, Inliber.ACP.Connection.PendingResponse>
---@field session_id string|nil
---@field _agent_info { agentCapabilities: table, authMethods: table, protocolVersion: number }|nil
---@field _initialized boolean
---@field _authenticated boolean
---@field _active_prompt Inliber.ACP.PromptBuilder|nil
---@field _state { handle: table, id_gen: Inliber.JsonRPC.IdGenerator, line_buffer: Inliber.JsonRPC.LineBuffer }
---@field _loading_session boolean|nil
---@field _on_session_update function|nil
---@field _config_options table[] Raw configOptions reported by the agent
---@field _in_flight table<string, Inliber.ACP.Connection.InFlight> Establishment steps currently underway
---@field _pending_callbacks table<number, function> Async callbacks keyed by request ID
---@field _rpc_log? { path: string, write: fun(data: string) } Per-connection log capturing raw JSON-RPC traffic

---@class Inliber.ACP.Connection.PendingResponse
---@field result any
---@field error any

---@class Inliber.ACP.Connection.InFlight
---@field done boolean
---@field success boolean
---@field callbacks function[]
```

## Inliber.ACP.PromptBuilder (new)

Fluent streaming handler for one `session/prompt`. Lives in `lua/inliber/acp/prompt_builder.lua` (port of codecompanion's `acp/prompt_builder.lua`).

```lua
---@class Inliber.ACP.PromptBuilder
---@field connection Inliber.ACP.Connection
---@field messages table[] Messages for the prompt, already role-mapped
---@field _on_message_chunk? fun(chunk: string)
---@field _on_thought_chunk? fun(chunk: string)
---@field _on_tool_call? fun(call: table)
---@field _on_tool_update? fun(update: table)
---@field _on_permission_request? fun(request: table)
---@field _on_write_text_file? fun(request: table)
---@field _on_plan? fun(plan: table)
---@field _on_complete? fun(stop_reason: string|nil)
---@field _on_error? fun(err: string)
---@field _on_cancel? fun()
---@field opts? { bufnr?: number, interaction?: string, silent?: boolean } Display opts for rendering side effects
```

## Inliber.ACPAdapter (new)

The adapter contract for ACP agents. Lives in `lua/inliber/adapters/acp/init.lua` (port of codecompanion's `adapters/acp/init.lua`).

```lua
---@class Inliber.ACPAdapter
---@field name string The name of the adapter
---@field formatted_name string The formatted name of the adapter
---@field type string|"acp" The type of the adapter
---@field roles table The mapping of roles in the config to the LLM's defined roles
---@field commands { default: table, [string]: table } The list of possible commands. Must include a 'default' key
---@field defaults? table Adapter defaults (session_config_options, timeout)
---@field env? table Environment variables referenced in the parameters
---@field env_replaced? table Environment variables with their values resolved
---@field parameters? table ACP protocol parameters (protocolVersion, clientCapabilities, clientInfo)
---@field handlers table Functions linking agent output back to Inliber
---@field handlers.setup? fun(self: Inliber.ACPAdapter): boolean
---@field handlers.auth? fun(self: Inliber.ACPAdapter): boolean Manually handle authentication
---@field handlers.on_exit? fun(self: Inliber.ACPAdapter, data: table): table|nil
---@field handlers.teardown? fun(self: Inliber.ACPAdapter): any
```

## Inliber.ACPRequest.Opts (new)

Options for a one-shot ACP request. Lives in `lua/inliber/interactions/shared/acp_request.lua` (port of codecompanion's `interactions/shared/acp_request.lua`, purpose narrowed to `"inline"`).

```lua
---@class Inliber.ACPRequest.Opts
---@field purpose "inline" One-shot request purpose; the connection-pool key
---@field adapter Inliber.ACPAdapter
---@field messages table[] Messages already run through adapter:map_roles()
---@field on_done fun(output: string)
---@field on_error? fun(err: string)
---@field bufnr? number
---@field silent? boolean
```

## Inliber.ACP.Defaults (new)

Applies adapter-level session config options to a live ACP session. Lives in `lua/inliber/interactions/inline/acp/defaults.lua` (slim port of codecompanion's `interactions/chat/acp/defaults.lua`).

```lua
---@class Inliber.ACP.Defaults
local M = {}
```

## Inliber.Config.Defaults (modify)

Config defaults: the `adapters.http` block becomes `adapters.acp`, the inline default adapter changes, and the `tools` block goes. Lives in `lua/inliber/config.lua`.

```lua
local defaults = {
  adapters = {
    acp = { -- changed: was `http = { ... }` with 17 HTTP presets and http opts
      auggie_cli = "auggie_cli",
      cagent = "cagent",
      claude_code = "claude_code",
      cline_cli = "cline_cli",
      codex = "codex",
      copilot_acp = "copilot_acp",
      cursor_cli = "cursor_cli",
      gemini_cli = "gemini_cli",
      goose = "goose",
      kimi_cli = "kimi_cli",
      kiro = "kiro",
      mistral_vibe = "mistral_vibe",
      opencode = "opencode",
      extend = nil, -- Per-adapter overrides keyed by config key
      opts = {
        show_presets = true, -- Show preset adapters
      },
    },
    opts = {
      cmd_timeout = 20e3, -- unchanged: ACP uses it to resolve command env vars
    },
  },

  -- ... existing defaults ...

  -- removed: the `tools` block (44+ lines of per-tool config and opts)

  -- ... existing defaults ...
}
```

## Inliber.Inline (modify)

The inline interaction: adapter and request fields change type, and the tool-loop field goes. Lives in `lua/inliber/interactions/inline/init.lua`.

```lua
---@class Inliber.Inline
---@field adapter Inliber.ACPAdapter -- changed: was Inliber.HTTPAdapter
---@field current_request? { cancel: fun() } -- changed: was Inliber.HTTPClient.RequestHandle
---@field tool_loop? Inliber.ToolLoop -- removed
---@field id number
---@field aug number Autocommand group id
---@field buffer_context Inliber.Inline.EditorContext
---@field bufnr number
---@field intent "ask"|"edit"
---@field lines table
---@field messages table
---@field opts table
---@field prompts table
---@field turns table
---@field classification Inliber.Inline.Classification
---@field spinner? table
```

## Inliber.Inline.Approvals (modify)

The approvals list, moved out of the deleted tool ecosystem and slimmed to what the inline diff flow uses (codecompanion precedent: `interactions/chat/approvals.lua`). Moves from `lua/inliber/tools/approvals.lua` to `lua/inliber/interactions/inline/approvals.lua`.

```lua
---@alias Inliber.Inline.ApprovalMode "ask"|"auto"|"yolo"

---@class Inliber.Inline.Approvals
---@field approved table<number, table<string, boolean>> Approved actions per buffer -- changed: was loop-id keyed
---@field modes table<number, Inliber.Inline.ApprovalMode> Modes per buffer -- changed: was loop-id keyed
```

## Inliber.HTTPAdapter (remove)

Removed from `lua/inliber/adapters/http/init.lua`, deleted along with the whole `adapters/http/` directory. Callers (inline submit/stop, adapters delegator, tools loop, commands) all move to `Inliber.ACPAdapter` or are deleted.

```lua
---@class Inliber.HTTPAdapter
---@field name string The name of the adapter
---@field vendor? string The vendor of the adapter, e.g. "openai" or "azure"
---@field formatted_name string The formatted name of the adapter
---@field model string The model to use with the adapter
---@field schema table The API schema the adapter implements
---@field roles table The mapping of roles in the config to the LLM's defined roles
---@field features? table Features the adapter supports
---@field env? table Environment variables which can be referenced in the parameters
---@field env_replaced? table Replacement of environment variables with their actual values
---@field parameters? table The parameters to pass to the request
---@field opts? table Additional options for the adapter
---@field handlers Inliber.HTTPAdapter.Handlers Functions which link the output from the HTTP request to Inliber
```

## Inliber.HTTPClient (remove)

Removed from `lua/inliber/http.lua`; the whole file is deleted. Its only caller is the inline interaction, which switches to `Inliber.ACPRequest.submit`.

```lua
---@class Inliber.HTTPClient
---@field adapter Inliber.HTTPAdapter
---@field adapter_modified Inliber.HTTPAdapter Modified adapter with environment variables set
---@field request? Inliber.HTTPClient.Request The request being processed
---@field stream? table The streaming connection
---@field user_args? table Arguments passed by the user to the client
```

## Inliber.ToolLoop (remove)

Removed from `lua/inliber/tools/init.lua`; the whole `tools/` directory is deleted. Its only caller is the inline interaction's `submit_with_tools` path, which is removed.

```lua
---@class Inliber.ToolLoop
---@field id number The loop id; the approvals key for the loop
---@field adapter Inliber.HTTPAdapter The adapter running the loop
---@field bufnr number The buffer the loop was started from, used for context
---@field callbacks { on_completed: fun(loop: Inliber.ToolLoop, result: table), on_cancelled: fun(), on_status?: fun(tool_name: string?, status: string, label?: string) }
---@field context Inliber.ToolLoop.Context A minimal store for tool context items
---@field current_request? table The in-flight request
---@field cycle number The number of submit cycles that have run
---@field engine Inliber.Tools The tool-execution engine
---@field messages table The message list for the LLM
---@field registry Inliber.Tools.Registry The tools available to the loop
---@field status string The status of the loop
---@field structured_output? Inliber.StructuredOutput.Schema The JSON schema the LLM's final text must match
---@field tokens? number|table The tokens reported by the adapter
---@field tool_orchestrator? Inliber.Tools.Orchestrator Coordinates running tools
```

# Services

## Inliber.JsonRPC (new)

Message builder functions. Lives in `lua/inliber/utils/jsonrpc.lua`.

```lua
---@class Inliber.JsonRPC
local M = {}

---Builds a JSON-RPC request message
function M.request(id: number, method: string, params: table|nil): string { ... }

---Builds a JSON-RPC result message
function M.result(id: number, result: any): string { ... }

---Builds a JSON-RPC error message
function M.error(id: number, message: string, code: number): string { ... }

---Builds a JSON-RPC notification message
function M.notification(method: string, params: table|nil): string { ... }

---Decodes one newline-delimited RPC message line
function M.decode(line: string, json_decode: fun(data: string): table): table|nil { ... }
```

## Inliber.JsonRPC.LineBuffer (new)

Stream reassembly. Lives in `lua/inliber/utils/jsonrpc.lua`.

```lua
---@class Inliber.JsonRPC.LineBuffer
local LineBuffer = {}

---Creates a line buffer that invokes the callback per complete message
function LineBuffer.new(decoder: fun(line: string): any, callback: fun(message: any): nil): Inliber.JsonRPC.LineBuffer { ... }

---Feeds a stdout chunk, invoking the callback for each whole message found
function LineBuffer:feed(data: string): nil { ... }
```

## Inliber.JsonRPC.IdGenerator (new)

Request id source. Lives in `lua/inliber/utils/jsonrpc.lua`.

```lua
---@class Inliber.JsonRPC.IdGenerator
local IdGenerator = {}

---Creates an id generator starting at 1
function IdGenerator.new(): Inliber.JsonRPC.IdGenerator { ... }

---Returns the next request id
function IdGenerator:next(): number { ... }
```

## Inliber.Async (new)

Coroutine sugar for keeping agent boot off the main loop. Lives in `lua/inliber/utils/async.lua` (verbatim port of codecompanion's `utils/async.lua`).

```lua
---@class Inliber.Async
local M = {}

---Runs a coroutine that may yield thunks
function M.sync(func: function, callback: function|nil): nil { ... }

---Yields until the deferred function completes
function M.wait(defer: function): any { ... }

---Yields until every deferred function completes
function M.wait_all(defers: table): any { ... }

---Wraps a function so it returns a thunk factory
function M.wrap(func: function): function { ... }
```

## Inliber.ACP.Connection (new)

Agent process lifecycle and RPC. Lives in `lua/inliber/acp/init.lua`.

```lua
---@class Inliber.ACP.Connection
local Connection = {}

---Creates a new connection for an adapter
function Connection.new(args: { adapter: Inliber.ACPAdapter, session_id?: string, opts?: table }): Inliber.ACP.Connection { ... }

---Whether the process is running and initialized
function Connection:is_connected(): boolean { ... }

---Whether the connection is fully established
function Connection:is_ready(): boolean { ... }

---Deduplicates concurrent establishment steps across callers
function Connection:_run_once(opts: { key: string, fn: function, callbacks: table }): nil { ... }

---Starts the agent process, initializes, and authenticates it
function Connection:connect_and_authenticate(): Inliber.ACP.Connection|nil { ... }

---Sends the initialize request and waits for agent capabilities
function Connection:_initialize(): boolean { ... }

---Sends the authenticate request when authMethods is non-empty
function Connection:_authenticate(): boolean { ... }

---Creates a fresh session for the connection
function Connection:renew_session(): boolean { ... }

---Whether the agent advertises session listing support
function Connection:can_list_sessions(): boolean { ... }

---Whether the agent advertises session loading support
function Connection:can_load_session(): boolean { ... }

---Lists the agent's sessions
function Connection:session_list(opts: table|nil): table { ... }

---Loads a saved session by id
function Connection:load_session(session_id: string, opts: table|nil): boolean { ... }

---Spawns the agent process via vim.system with stdio pipes
function Connection:start_agent_process(): boolean { ... }

---Sends a request and returns the pending-response container
function Connection:send_rpc_request(method: string, params: table|nil): table { ... }

---Sends a result for a client-role request
function Connection:send_result(id: number, result: any): nil { ... }

---Sends an error for a client-role request
function Connection:send_error(id: number, message: string, code: number): nil { ... }

---Blocks (via async) until the response for a request id arrives
function Connection:wait_for_rpc_response(id: number): Inliber.ACP.Connection.PendingResponse|nil { ... }

---Resolves adapter env vars and handler setup before spawn
function Connection:prepare_adapter(): boolean { ... }

---Stops the process and tears the connection down
function Connection:disconnect(): nil { ... }

---Buffers stdout chunks and dispatches whole messages
function Connection:buffer_stdout_and_dispatch(data: string): nil { ... }

---Routes one decoded RPC message by direction and kind
function Connection:handle_rpc_message(line: string): nil { ... }

---Stores a response against its request id and wakes waiters
function Connection:store_rpc_response(response: table): nil { ... }

---Sends a notification to the agent
function Connection:send_notification(method: string, params: table|nil): nil { ... }

---Handles agent→client requests/notifications (fs, permission, session/update)
function Connection:handle_incoming_request_or_notification(notification: table): nil { ... }

---Writes an encoded message to the agent's stdin
function Connection:write_message(data: string): nil { ... }

---Serves an fs/read_text_file request by reading the file
function Connection:handle_fs_read_text_file_request(id: number, params: table): nil { ... }

---Serves an fs/write_text_file request by writing the file
function Connection:handle_fs_write_file_request(id: number, params: table): nil { ... }

---Records the agent's available slash commands for a session
function Connection:handle_available_commands_update(session_id: string, commands: table): nil { ... }

---Records the agent's session config options
function Connection:handle_config_option_update(session_id: string, config_options: table): nil { ... }

---Runs when the agent process exits
function Connection:handle_process_exit(code: number|nil, signal: number|nil): nil { ... }

---Builds and sends a session/prompt for the given messages
function Connection:session_prompt(messages: table): Inliber.ACP.PromptBuilder|nil { ... }

---Returns the session config options the agent reported
function Connection:get_config_options(opts: table|nil): table[] { ... }

---Sets a session config option by id (e.g. the model)
function Connection:set_config_option(config_id: string, value: string): nil { ... }

---Flattens nested config option choices into a list
function Connection.flatten_config_options(opts: table): table { ... }
```

## Inliber.ACP.PromptBuilder (new)

Fluent streaming interface over one `session/prompt`. Lives in `lua/inliber/acp/prompt_builder.lua`.

```lua
---@class Inliber.ACP.PromptBuilder
local PromptBuilder = {}

---Creates a builder bound to a connection and messages
function PromptBuilder.new(connection: Inliber.ACP.Connection, messages: table): Inliber.ACP.PromptBuilder { ... }

---Registers the streaming message handler
function PromptBuilder:on_message_chunk(fn: fun(chunk: string)): Inliber.ACP.PromptBuilder { ... }

---Registers the streaming thought handler
function PromptBuilder:on_thought_chunk(fn: fun(chunk: string)): Inliber.ACP.PromptBuilder { ... }

---Registers the tool-call handler
function PromptBuilder:on_tool_call(fn: fun(call: table)): Inliber.ACP.PromptBuilder { ... }

---Registers the tool-update handler
function PromptBuilder:on_tool_update(fn: fun(update: table)): Inliber.ACP.PromptBuilder { ... }

---Registers the permission-request handler
function PromptBuilder:on_permission_request(fn: fun(request: table)): Inliber.ACP.PromptBuilder { ... }

---Registers the write-text-file request handler
function PromptBuilder:on_write_text_file(fn: fun(request: table)): Inliber.ACP.PromptBuilder { ... }

---Registers the plan handler
function PromptBuilder:on_plan(fn: fun(plan: table)): Inliber.ACP.PromptBuilder { ... }

---Registers the completion handler
function PromptBuilder:on_complete(fn: fun(stop_reason: string|nil)): Inliber.ACP.PromptBuilder { ... }

---Registers the error handler
function PromptBuilder:on_error(fn: fun(err: string)): Inliber.ACP.PromptBuilder { ... }

---Registers the cancellation handler
function PromptBuilder:on_cancel(fn: fun()) : Inliber.ACP.PromptBuilder { ... }

---Sets rendering options for the prompt
function PromptBuilder:with_options(opts: { bufnr?: number, interaction?: string, silent?: boolean }): Inliber.ACP.PromptBuilder { ... }

---Sends the session/prompt request and starts streaming
function PromptBuilder:send(): nil { ... }

---Dispatches one session/update notification to the right handler
function PromptBuilder:handle_session_update(params: table): nil { ... }

---Responds to a session/request_permission request
function PromptBuilder:handle_permission_request(id: number, params: table): nil { ... }

---Handles an error from the agent
function PromptBuilder:handle_error(error: table): nil { ... }

---Completes the prompt with a stop reason
function PromptBuilder:handle_done(stop_reason: string|nil): nil { ... }

---Sends a session/cancel notification for this prompt
function PromptBuilder:cancel(): nil { ... }
```

## Inliber.ACPAdapter (new)

Adapter factory and accessors. Lives in `lua/inliber/adapters/acp/init.lua`.

```lua
---@class Inliber.ACPAdapter
local Adapter = {}

---Creates an adapter instance from a plain table
function Adapter.new(args: table): Inliber.ACPAdapter { ... }

---Maps inliber roles to the adapter's roles (from adapters.shared)
function Adapter.map_roles(adapter: Inliber.ACPAdapter, messages: table): table { ... }

---Extends a preset adapter with overrides
function Adapter.extend(adapter: string|table|function, opts: table|nil): Inliber.ACPAdapter|nil { ... }

---Resolves an adapter from a string, table, or function, applying config extends and model/mode session options
function Adapter.resolve(adapter: Inliber.ACPAdapter|string|function|nil, opts: table|nil): Inliber.ACPAdapter|nil { ... }

---Whether the value is an already-resolved ACPAdapter
function Adapter.resolved(adapter: any): boolean { ... }

---Copies an adapter into a serializable-safe table
function Adapter.make_safe(adapter: Inliber.ACPAdapter): table { ... }

---Sets the model on a live connection via session/set_config_option
function Adapter.set_model(args: { acp_connection: Inliber.ACP.Connection, adapter: Inliber.ACPAdapter, model: string }): boolean { ... }
```

## Inliber.ACPRequest (new)

One-shot ACP request bridge with connection pooling. Lives in `lua/inliber/interactions/shared/acp_request.lua`.

```lua
---@class Inliber.ACPRequest
local M = {}

---Returns the connection for a one-shot request, reusing an idle pooled one
local function get_connection(purpose: string, adapter: Inliber.ACPAdapter): Inliber.ACP.Connection { ... }

---Folds non-user content into a leading user message and tags user messages with _meta
local function shape_messages(messages: table, roles: table): table[] { ... }

---Submits a one-shot prompt over ACP and streams the text to opts.on_done
function M.submit(opts: Inliber.ACPRequest.Opts): { cancel: function } { ... }
```

## Inliber.ACP.Defaults (new)

Session config option application. Lives in `lua/inliber/interactions/inline/acp/defaults.lua`.

```lua
---@class Inliber.ACP.Defaults
local M = {}

---Applies the adapter's session_config_options (model first) to a fresh session
function M.apply(adapter: Inliber.ACPAdapter, connection: Inliber.ACP.Connection): nil { ... }
```

## Inliber.adapters (modify)

The root adapter delegator now points at the ACP adapter layer only; the handler-lookup API goes. Lives in `lua/inliber/adapters/init.lua`.

```lua
local M = {}

---Factory method to resolve adapters
---@return Inliber.ACPAdapter -- changed: was Inliber.HTTPAdapter
function M.resolve(adapter: string|table, opts?: table): Inliber.ACPAdapter { ... }

---Factory method to check if the adapter has been resolved
function M.resolved(adapter: string|table): boolean { ... }

---Factory method to extend the adapter
---@return Inliber.ACPAdapter -- changed: was Inliber.HTTPAdapter
function M.extend(adapter: string|table, opts?: table): Inliber.ACPAdapter { ... }

---Factory method to make adapters safe for serialization
function M.make_safe(adapter: string|table): table { ... }

---Backwards compatibility: expose adapter methods directly at root level
---@param args { adapter: Inliber.ACPAdapter, model?: string } -- changed: was Inliber.HTTPAdapter
---@return Inliber.ACPAdapter
function M.set_model(args: table): Inliber.ACPAdapter { ... }

---removed: get_handler — callers move to ACP connection methods
---removed: call_handler — inline's parse_inline/on_exit calls go with the HTTP layer
```

## Inliber.Inline.Approvals (modify)

Slimmed to the inline diff accept/reject flow. Moves from `lua/inliber/tools/approvals.lua` to `lua/inliber/interactions/inline/approvals.lua`.

```lua
---@class Inliber.Inline.Approvals
local Approvals = {}

---Always approve an action for a buffer
function Approvals:always(bufnr: number, args: { tool_name: string }): nil { ... } -- changed: was loop_id

---Check if an action has been approved for a buffer, by mode or by the user
function Approvals:is_approved(bufnr: number, args: { tool_name?: string }): boolean { ... } -- changed: was loop_id; dropped cmd/config.tools branches

---Returns the approval mode for a buffer
function Approvals:get_mode(bufnr: number): Inliber.Inline.ApprovalMode { ... }

---Sets the approval mode for a buffer
function Approvals:set_mode(bufnr: number, opts: { mode: Inliber.Inline.ApprovalMode }): nil { ... }

---Resets approvals for a buffer
function Approvals:reset(bufnr: number): nil { ... }

---removed: is_safe_command — only the tool loop used it
```

## Inliber.Inline (modify)

Submission, stopping, and output handling change to the ACP one-shot path. Lives in `lua/inliber/interactions/inline/init.lua`.

```lua
---@class Inliber.Inline
local Inline = {}

---Set the adapter for the inline prompt
---@param adapter Inliber.ACPAdapter|string|function -- changed: was Inliber.HTTPAdapter|string|function
function Inline:set_adapter(adapter): nil { ... }

---Removed: routed prompts to the tool loop or direct request -- removed

---Run the prompt through the headless tool loop -- removed
---function Inline:submit_with_tools(prompts: table): nil { ... }

---Add the intent-specific tools to the tool loop's registry -- removed
---function Inline:_add_tools(tool_loop: Inliber.ToolLoop): nil { ... }

---Get the structured output schema for the current intent -- removed
---function Inline:_structured_output(): Inliber.StructuredOutput.Schema { ... }

---Prepare messages for the tool loop by appending the JSON format instruction -- removed
---function Inline:_prepare_tool_messages(prompts: table): table { ... }

---Stop the current request
function Inline:stop(): nil { ... } -- changed: cancels the ACP request; no on_exit handler, no tool-loop branch

---Submit the prompts to an ACP agent for processing
function Inline:submit(prompt: table): nil { ... } -- changed: spinner/keymaps then _submit_acp; no client.new, no streaming toggle

---Submit the prompts to an ACP agent for processing
function Inline:_submit_acp(prompt: table): nil { ... } -- added: acp_request.submit({ purpose = "inline", ... })

---Once the request has been completed, we can process the output
function Inline:done(output: string): nil { ... } -- changed: adds whole-file-rewrite detection and "new"-placement redirect

---Parse the LLM output into a JSON response
function Inline:parse_output(output: string): table|nil { ... } -- changed: adds ACP fenced-code fallback parsing

---Whether the returned code is the entire file rewritten
function Inline:_is_full_file_rewrite(code: string): boolean { ... } -- added
```

# Out of Scope

- Restoring chat, cmd, or background interactions — those were already removed; this work does not bring them back.
- Porting codecompanion's chat-specific ACP modules (`interactions/chat/acp/{handler,render,fs,formatters,commands,request_permission}.lua`).
- MCP server integration via `clientCapabilities.mcpServers` (codecompanion has `mcp_enabled` config; not part of this migration).
- Skills, sessions, slash-command UIs — already removed from inliber.
- ACP session persistence (`session/load` flows beyond what `acp_request` needs for one-shot turns).
- Keeping `integrations.agent_env()` — inliber has no `integrations/` module; the Connection port substitutes nothing (`{}` or dropped call).
