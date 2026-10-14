# Research Topic
Replace HTTP-based agents with the Agent Client Protocol (ACP) for everything in inliber.nvim, mirroring the migration already completed in `C:/Users/paulp/Documents/repo/codecompanion.nvim/`.

## Context & chronology

- codecompanion.nvim completed this exact migration **today** (2026-10-14). Key commits:
  - `c71f51f0` (2025-08-27) — initial ACP support
  - `fc0958f8` (2026-10-14) — `feat(acp): support inline, cmd and background interactions`
  - `7ae5d202` (2026-10-14) — `refactor: remove HTTP support and make codecompanion ACP-only`
  - `9dd46b67` (2026-10-14) — slash commands in the inline interaction
- inliber.nvim is a renamed snapshot of codecompanion taken 2026-10-06 (root commit `691964a chore: rename codecompanion to inliber`), i.e. **before** the ACP-only work. inliber retains the full HTTP adapter layer plus a trimmed interaction set: only `inline/` remains (chat, cmd, background, MCP, memory, skills, sessions were already removed per `plans/dead-code-research.md`).
- The migration plan codecompanion actually used survives in its git history: `git show 7ae5d202:ACP_ONLY_PLAN.md` in the codecompanion repo. Much of it is irrelevant to inliber (chat/tools/skills/sessions phases already gone), but the adapter-layer and inline phases transfer directly.

## What ACP is

- **Agent Client Protocol** — open standard (Zed-initiated, Apache-2.0) for editors talking to coding agents: https://agentclientprotocol.com / https://github.com/agentclientprotocol/agent-client-protocol
- **Transport**: JSON-RPC 2.0 over stdio (local subprocess), newline-delimited messages, UTF-8, protocol version negotiated via `initialize` (stable version is `1`).
- **Client→Agent methods**: `initialize`, `authenticate` (conditional, driven by `authMethods`), `session/new`, `session/load` (optional), `session/prompt`, `session/set_mode`, `session/set_config_option`, `session/cancel` (notification).
- **Agent→Client**: `session/update` notifications (streaming: `agent_message_chunk`, `agent_thought_chunk`, `tool_call`, `tool_call_update`, `plan`, `available_commands_update`, `config_option_update`, `session_info_update`, `usage_update`), `session/request_permission` (request), `fs/read_text_file`, `fs/write_text_file`, `terminal/*`.
- **StopReason**: `end_turn`, `max_tokens`, `max_turn_requests`, `refusal`, `cancelled`.
- **Extensibility**: `_`-prefixed methods/values and `_meta` fields reserved for extensions.
- Agents are real CLI agents (Claude Code via `claude-agent-acp`, `copilot --acp --stdio`, Codex, Gemini CLI, Goose, OpenCode, Cursor CLI, etc.). Each brings its own tools, models, auth, and permission model. This is the point: the plugin stops being an API client and becomes an ACP host.

## Reference implementation (codecompanion, current tree)

Modules to port (sizes measured):

| codecompanion path | size | needed in inliber? |
| --- | --- | --- |
| `lua/codecompanion/acp/init.lua` (Connection) | 36 KB | yes — core |
| `lua/codecompanion/acp/methods.lua` | 0.5 KB | yes |
| `lua/codecompanion/acp/prompt_builder.lua` | 8.9 KB | yes |
| `lua/codecompanion/utils/jsonrpc.lua` | 4 KB | yes — new util (inliber lacks it) |
| `lua/codecompanion/utils/async.lua` | 2.3 KB | yes — new util (inliber lacks it) |
| `lua/codecompanion/adapters/acp/init.lua` (ACPAdapter) | ~5 KB | yes |
| `lua/codecompanion/adapters/acp/helpers.lua` | 1.5 KB | yes |
| `lua/codecompanion/adapters/acp/*.lua` (16 adapters) | ~2-5 KB each | subset or all |
| `lua/codecompanion/interactions/shared/acp_request.lua` | 4.9 KB | yes — the one-shot bridge inline uses |
| `lua/codecompanion/interactions/chat/acp/defaults.lua` | 3.1 KB | yes (slim) — session config options (`session/set_config_option` for model/mode) |
| `interactions/chat/acp/{handler,render,fs,formatters,commands,request_permission}.lua` | — | no (chat-specific) |

Key mechanics learned from codecompanion:

- **Connection lifecycle**: spawn process via `vim.system` with stdin/stdout; `connect_and_authenticate()` = start process → `initialize` → `authenticate`; `renew_session()` → `session/new`. `_run_once`/`_await_in_flight` dedupe concurrent callers.
- **PromptBuilder** is the streaming bridge: `session/prompt` request + `session/update` notifications dispatched to `on_message_chunk`/`on_complete`/`on_error` handlers; `session/cancel` notification for stop.
- **One-shot requests** (`acp_request.submit`): connections pooled per `purpose:adapter_name`; `fs` stripped from `clientCapabilities` so one-shot agents can't edit files directly; `shape_messages()` folds system/context content into the first user message (ACP agents get no server-side system role or JSON mode); output = concatenated `agent_message_chunk` text.
- **Config options**: models are changed through `session/set_config_option` with the `"model"` category option, not an adapter field. `acp_defaults.apply()` maps `adapter.defaults.session_config_options` onto the live session after `session/new`.
- **ACP adapter shape**: `{ name, formatted_name, type = "acp", roles = { llm = "assistant", user = "user" }, commands = { default = {...}, ... }, defaults = { mcpServers, timeout, session_config_options }, env = {...}, parameters = { protocolVersion = 1, clientCapabilities = { fs = ... }, clientInfo = {...} }, handlers = { setup, auth, form_messages, on_exit } }`.
- **Inline specifics** (codecompanion `interactions/inline/init.lua`): leaner system prompt ("Reply with ONLY a JSON object..."), `RESPONSE_WITH_PLACEMENT` schema string, whole-file-rewrite detection (ACP agents often reply with the entire edited file → forced `replace`), `"new"` placement redirect (ACP agents pick `new` on their own → redirect to current buffer), fenced-code parsing fallback when the agent ignores the JSON instruction (line 696-697).
- **Tool ecosystem**: codecompanion **deleted it entirely** (`lua/codecompanion/tools/` no longer exists). Agents bring their own tools. Only a slim approvals list survived, moved to `interactions/chat/approvals`, still used by the inline diff accept/reject flow.
- **Default adapter**: `copilot_acp` everywhere.

## inliber.nvim current state (inventory of what must change)

### HTTP coupling (delete/replace)

- `lua/inliber/adapters/http/` — 17 adapter files + `copilot/` (init, get_models, token) + `ollama/` (init, get_models) + `http/init.lua` (defines `Inliber.HTTPAdapter`).
- `lua/inliber/http.lua` — generic HTTP client (plenary curl based; reads `config.adapters.http.opts` at lines 344-345).
- `lua/inliber/adapters/init.lua` — thin delegator to `adapters.http` (resolve/resolved/extend/make_safe/set_model/get_handler/call_handler).
- `lua/inliber/adapters/shared.lua` — `map_roles`, `apply_extend` (keep), `input_limit` (HTTP model-meta; dies with tools).
- `lua/inliber/adapters/utils/` — `init.lua` (map_roles, env vars — keep what ACP needs), `structured_outputs.lua`, `tool_transformers.lua`, `models/{fetch,transform}.lua` (all HTTP-only).
- `lua/inliber/config.lua` — `adapters.http` defaults block (lines 10-36: 17 adapters + `opts`: allow_insecure, cache_models_for, hidden, proxy, show_presets); `interactions.inline.adapter = "copilot"` (line 142); `adapters.opts.cmd_timeout` (line 38, keep — ACP uses it).
- `lua/inliber/init.lua` — `adapter_config()` merges `config.adapters.http` (lines 35-45).
- `lua/inliber/interactions/inline/init.lua` — `require("inliber.http")` (line 41); `config.adapters.http` in `parse_special_syntax` (line 321); `Inline:submit()` builds `client.new({ adapter = self.adapter:map_schema_to_params() })` and parses via `adapters.call_handler(adapter, "parse_inline", ...)` (lines 701-740); `Inline:stop()` calls `adapters.call_handler(self.adapter, "on_exit")` (line 511); `submit_with_tools`/`_add_tools`/`_prepare_tool_messages`/`_structured_output` drive the tool loop (lines 532-696). Note: inliber's structured-output enforcement for inline JSON (`843955d`) is HTTP-only and has no ACP equivalent — must become prompt-based.
- `lua/inliber/commands/init.lua` — `get_adapters()` reads `config.adapters.http.opts.hidden` + iterates `config.adapters.http` (lines 13-30).
- `lua/inliber/tools/` — full HTTP tool loop: `init.lua` (ToolLoop, `require("inliber.http")` at line 11, `client.new(...):send(...)` at line 479), `engine.lua`, `runner.lua`, `orchestrator.lua`, `registry.lua`, `filter.lua`, `labels.lua`, `ui.lua`, `approvals.lua`, `builtin/` (10 tools), `helpers/{context,filter}.lua`.
- `lua/inliber/adapters/http/*` adapter files read `config.adapters.http.opts.{allow_insecure,proxy,cache_models_for}` — all vanish with the block.

### Already ACP-adjacent (keep/leverage)

- `lua/inliber/interactions/shared/agent_commands/` — slash-command discovery for **claude_code** and **opencode** providers already exists (project + global command dirs). Directly useful for ACP adapters (`available_commands_update`).
- `lua/inliber/utils/log.lua` has `new_response_file()` (used by the ACP RPC traffic log) and `utils.fire()` exists — both prerequisites of the ACP Connection code are present.
- `lua/inliber/interactions/shared/tags.lua`, `utils/markdown.lua` (`form_codeblock`) exist — needed by `adapters/acp/helpers.lua`.
- `lua/inliber/tools/approvals.lua` — the only tool-loop module with a non-tool consumer: the inline diff flow (`start_diff` → `is_approved`/`always`). Codecompanion precedent: keep a slim version, drop the loop-specific API.

### Missing prerequisites (must be created)

- No `utils/jsonrpc.lua`, no `utils/async.lua`, no `acp/` module, no `adapters/acp/`, no `interactions/shared/acp_request.lua`.
- No `integrations/` module — codecompanion's ACP Connection calls `integrations.agent_env()`; inliber must drop that call or substitute `{}`.

### Tests & docs to sweep

- Tests: `tests/adapters/http/` (12 test files + ~100 stub files incl. merge-conflict backups `ollama_reasoning_*_{BACKUP,BASE,LOCAL,REMOTE}_*.txt`), `tests/adapters/utils/`, `tests/adapters/test_adapters.lua` (http cases), `tests/test_http.lua`, `tests/interactions/inline/test_inline.lua` (stubs `inliber.http` at lines 417/441), `tests/scripts/ui.lua` (resolves `cc_config.adapters.http[...]`), `tests/helpers.lua` (http client stub).
- codecompanion test assets to port: `tests/acp/{test_acp,test_prompt_builder}.lua`, `tests/mocks/acp.lua`, `tests/stubs/acp/*.txt`, `tests/interactions/shared/test_acp_request.lua`, `tests/interactions/inline/test_inline_acp.lua`.
- Docs: delete `doc/configuration/adapters-http.md`, `doc/configuration/tools.md`, `doc/extending/tools.md`, `doc/guides/{tool-approvals,openai-compatible-providers}.md`; rewrite `doc/extending/adapters.md`, `doc/guides/{choosing-an-adapter,running-local-models,background-model}.md`, `doc/configuration/inline.md`, `doc/getting-started.md`, `doc/installation.md`, `doc/troubleshooting.md`, `doc/architecture.md`; add `doc/configuration/adapters-acp.md` (port from codecompanion). Then `make docs`.
- `AGENTS.md` — Architecture section says `adapters/acp/` (Claude Code, Codex, etc.) already; remove HTTP adapter mentions and the tools/slash-command sections that no longer match, and drop the Ollama/openai_compatible model rule (goes with HTTP).

## Proposed migration plan for inliber (phased, each step buildable)

### Phase 1 — Port ACP core (additive, no deletions)

1. New `lua/inliber/utils/jsonrpc.lua` (errors, request/result/error/notification builders, `LineBuffer`, `IdGenerator`) — port verbatim, rename `CodeCompanion.JsonRPC.*` → `Inliber.JsonRPC.*`.
2. New `lua/inliber/utils/async.lua` — port verbatim.
3. New `lua/inliber/acp/methods.lua` — method name constants.
4. New `lua/inliber/acp/init.lua` — Connection class: process spawn via `vim.system`, `initialize`/`authenticate`/`session/new`/`session/prompt`/`session/cancel`, `session/update` dispatch, `session/request_permission`, `fs/read_text_file` + `fs/write_text_file` request handlers, config-option model setting, RPC logging, `_run_once` dedupe. Drop `integrations.agent_env()`; point `VimLeavePre` disconnect at the inliber augroup name.
5. New `lua/inliber/acp/prompt_builder.lua` — streaming handlers incl. `extract_text` (`[resource: ...]`, `[image]`, `[audio]` placeholders).
6. New `lua/inliber/adapters/acp/init.lua` (ACPAdapter: extend/resolve/resolved/make_safe/set_model) + `lua/inliber/adapters/acp/helpers.lua` (`form_messages`).
7. ACP adapters. Minimum: `copilot_acp` (new default), `claude_code`, `opencode` (the two inliber already has agent_commands providers for). Porting all 16 from codecompanion is mostly copying; recommend the full set.
8. New `lua/inliber/interactions/shared/acp_request.lua` (connection pooling, fs stripping, `shape_messages`, cancel handle) + a slim `acp_defaults` (port `interactions/chat/acp/defaults.lua` minus chat deps).

### Phase 2 — Wire the inline interaction over ACP

- Port codecompanion's inline changes: `_submit_acp` via `acp_request.submit({ purpose = "inline", ... })`; `stop()` → `current_request.cancel()`; `parse_special_syntax` → `config.adapters.acp`; lean ACP system prompt + `RESPONSE_WITH_PLACEMENT`; whole-file-rewrite detection; `new`-placement redirect; fenced-code parse fallback.
- Replace `843955d`'s structured-output enforcement with the prompt-based JSON instruction + parsing fallback (ACP has no server-side JSON mode).
- Keep: diff UI flow, approvals for the diff, ask float conversation memory (messages are resent per turn — ACP sessions are renewed per request).

### Phase 3 — Delete the HTTP layer

- Delete `lua/inliber/adapters/http/`, `lua/inliber/http.lua`.
- Rewrite `lua/inliber/adapters/init.lua` to delegate only to `adapters.acp`; delete `get_handler`/`call_handler`.
- Prune `adapters/utils/` to what the ACP path uses (`map_roles`, `get_env_vars`, `set_env_vars`, `cache_expiry`-type helpers); delete `structured_outputs.lua`, `tool_transformers.lua`, `models/`.
- `adapters/shared.lua`: keep `map_roles`/`apply_extend`; drop `input_limit`.
- `config.lua`: replace the `adapters.http` block with `adapters.acp` (preset names + `opts.show_presets`); `interactions.inline.adapter = "copilot_acp"`; keep `adapters.opts.cmd_timeout`; drop `allow_insecure`/`proxy`/`cache_models_for`/`hidden` (or move hidden to `adapters.acp.opts`).
- `init.lua` `adapter_config()` → merge `config.adapters.acp`; `commands/init.lua` → `config.adapters.acp`.
- Replace all `Inliber.HTTPAdapter` annotations with `Inliber.ACPAdapter`.

### Phase 4 — Tool ecosystem: delete (recommended, codecompanion precedent)

- Delete `lua/inliber/tools/` except `approvals.lua`, which the inline diff flow still needs; trim its API to what inline uses (`is_approved`/`always` keyed by bufnr/tool_name, drop loop_id/mode machinery) or move it under `interactions/` as codecompanion did (`interactions/chat/approvals` → e.g. `lua/inliber/interactions/inline/approvals.lua`).
- Remove the tool-loop path from inline (`submit_with_tools`, `_add_tools`, `_prepare_tool_messages`, `_structured_output`, `tool_loop` fields, `stop()`/`reset()` tool-loop branches).
- Drop `config.tools` and `config.interactions.inline.tools`.
- Agents get file editing through their own tools + the ACP `fs/read_text_file`/`fs/write_text_file` client methods; permissions via `session/request_permission` (auto-respond or surface, at minimum respond `cancelled`/`selected` so turns don't hang).

### Phase 5 — Tests

- Delete `tests/adapters/http/` (incl. stale merge-conflict stub files), `tests/adapters/utils/`, `tests/test_http.lua`; strip HTTP cases from `tests/adapters/test_adapters.lua`.
- Port `tests/acp/`, `tests/mocks/acp.lua`, `tests/stubs/acp/`, `tests/interactions/shared/test_acp_request.lua`, `tests/interactions/inline/test_inline_acp.lua`.
- Rework `tests/interactions/inline/test_inline.lua` (replace `inliber.http` stubbing with ACP mock), `tests/scripts/ui.lua`, `tests/helpers.lua`.
- `make format` + `make test` green.

### Phase 6 — Docs & AGENTS.md

- Delete `doc/configuration/adapters-http.md`, `doc/configuration/tools.md`, `doc/extending/tools.md`, `doc/guides/tool-approvals.md`, `doc/guides/openai-compatible-providers.md`.
- Add `doc/configuration/adapters-acp.md` (port), rewrite `doc/extending/adapters.md` (ACP adapter contract: commands/env/handlers/parameters), `doc/guides/choosing-an-adapter.md`, `doc/guides/running-local-models.md`, `doc/guides/background-model.md`, `doc/configuration/inline.md`, `doc/getting-started.md`, `doc/installation.md`, `doc/troubleshooting.md`, `doc/architecture.md`.
- Update `AGENTS.md` (Architecture: `adapters/acp/`; drop HTTP-only rules such as the Ollama/openai_compatible `schema.model.default` note — `adapter_utils.model` stays as the safe accessor for the remaining utils).
- `make docs`, full test suite.

## Open decisions for the user

1. **Tool ecosystem**: delete entirely (codecompanion precedent; agents bring their own tools) vs keep a shim. Research recommends deletion. The only survivor is the diff-approvals list.
2. **Which ACP adapters to ship**: minimal set (`copilot_acp`, `claude_code`, `opencode`) vs all 16 from codecompanion. Recommended: port all — copy cost is low, and inliber already has agent_commands providers for two of them.
3. **Default adapter**: `copilot_acp` (codecompanion's choice).
4. **Inline JSON enforcement**: prompt-only (ACP reality) — drops the structured-output guarantee `843955d` added for HTTP.
5. **Permission requests**: auto-deny vs minimal prompt UI for `session/request_permission` during inline edits.

## Main risks

- `lua/inliber/acp/init.lua` is the largest single port (36 KB) and depends on Neovim 0.10+ `vim.system`; inliber targets NVIM v0.11 per Makefile — fine, but Windows stdio behavior (dev machine is Windows) needs a smoke test with a real agent.
- The `integrations.agent_env()` dependency must be excised cleanly or startup breaks on first ACP request.
- `interactions/inline/init.lua` is the hairiest edit: HTTP submit, tool-loop path, and structured-output enforcement are woven through `prompt`/`stop`/`reset`/`done`; all three must go together.
- Deleting `tools/` while keeping `approvals.lua` requires untangling `approvals` from `config.tools` (its `is_approved`/`always` read `config.tools[...]` today).
- Tests: `tests/scripts/ui.lua` and `tests/helpers.lua` resolve HTTP adapters to run UI fixtures; they need an ACP mock before anything passes.
- Legacy prompts using `adapter=openai`-style names will break; the `adapter=` syntax survives but resolves against `config.adapters.acp` only.
