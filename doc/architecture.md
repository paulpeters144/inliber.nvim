---
description: "How Inliber talks to ACP agents — the connection, prompt building, the one-shot request bridge, and the inline interaction — reference for contributors."
---

# Architecture

This section of the documentation covers architectural concepts and design principles that underpin Inliber's functionality.

This is not mandatory reading for users of Inliber. It may be of interest to those who are looking to understand some of the technical details of how Inliber works, or those who are looking to contribute to the project.

## The Agent Client Protocol

Inliber is an [Agent Client Protocol (ACP)](https://agentclientprotocol.com) host. It never calls a model API itself: it spawns a coding agent's CLI as a subprocess and talks JSON-RPC 2.0 over stdio. The agent brings its own tools, models, authentication and permission model.

## The Connection

`lua/inliber/acp/init.lua` defines `Inliber.ACP.Connection`, which owns the agent process:

1. `prepare_adapter` resolves the adapter's environment variables and selected command
2. `start_agent_process` spawns the process via `vim.system` with piped stdio
3. `_initialize` negotiates the protocol version and records the agent's capabilities
4. `_authenticate` runs the adapter's auth hook or drives the protocol `authenticate` method
5. `renew_session` creates a fresh `session/new` for each request

Stdout is reassembled into whole JSON-RPC messages by `Inliber.JsonRPC.LineBuffer`, and dispatched in `handle_rpc_message`. Responses to requests are stored against their request id (`store_rpc_response`), and agent-initiated requests — `session/request_permission`, `fs/read_text_file`, `fs/write_text_file` — are served by the client (`handle_incoming_request_or_notification`).

Establishment steps that block on the agent are deduplicated with `_run_once`, so concurrent callers share one process instead of spawning two. Raw traffic is captured per-connection by `log.new_response_file()`.

## The Prompt Builder

`lua/inliber/acp/prompt_builder.lua` defines `Inliber.ACP.PromptBuilder`, a fluent interface over one `session/prompt`. It registers streaming handlers (`on_message_chunk`, `on_complete`, `on_error`, ...), sends the request, and routes the stream of `session/update` notifications to them. `session/request_permission` requests are answered here — `cancelled` by default when no handler is registered, so turns never hang on a permission prompt.

## The One-Shot Request Bridge

`lua/inliber/interactions/shared/acp_request.lua` runs a single prompt against an agent and concatenates the streamed text. It:

- Pools connections per `purpose:adapter_name`, reusing idle processes
- Strips `fs` from `clientCapabilities` so a one-shot agent cannot edit files behind the diff flow
- Folds system and non-user messages into the first user message with `shape_messages`, since ACP agents get no server-side system role

## The Adapter Layer

`lua/inliber/adapters/acp/init.lua` defines `Inliber.ACPAdapter` and the preset adapters in the same directory. An adapter is a plain table: a `commands` list (process argv), `parameters` (protocol version and client capabilities), `defaults` (timeout, auth method, session config options) and `handlers` linking the agent back to Inliber. `Adapter.resolve` turns a config name, function or table into an adapter, applying the config's `extend` overrides.

## The Inline Interaction

`lua/inliber/interactions/inline/init.lua` is Inliber's only interaction. A prompt becomes a stack of messages (a lean JSON instruction as the system message, editor context, the user prompt) that is submitted through the one-shot bridge. The agent's reply is parsed as JSON; ACP agents that ignore the instruction and answer with fenced code fall back to treating the code block as the edit. The reply is applied to the buffer through the diff flow, with the approvals list (`interactions/inline/approvals.lua`) remembering always-accepted buffers.
