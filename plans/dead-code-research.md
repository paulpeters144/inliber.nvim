# Dead Code Research

Catalog of dead, test-only, and stale code left behind after the big refactor that removed the chat buffer, MCP, memory, extensions, web-search adapters/tools, and many utils (commit `facb06d4` and its docs rewrite). Findings verified by cross-referencing every public export in `lua/` against `require`/usage in both `lua/` and `tests/`.

## 1. Dead public functions (zero references in lua/ or tests/)

| Module | Symbol | Notes |
| --- | --- | --- |
| `utils/init.lua` (`codecompanion.utils`) | `is_array` | Never called |
| `utils/init.lua` (`codecompanion.utils`) | `contains` | Never called |
| `utils/log.lua` | `get_logfile` | Never called |
| `utils/log.lua` | `get_root` | Never called |
| `utils/log.lua` | delegated `:time` | Defined on Logger, never invoked |
| `utils/log.lua` | delegated `:get_handlers` | Defined on Logger, never invoked |
| `utils/tokens.lua` | `display` | Never called |
| `utils/native_bit.lua` | `bnot`, `bor`, `rshift` | Only `band`, `lshift`, `bxor` are used by `hash.lua` |
| `adapters/http/init.lua` | `Adapter.uses_new_handlers` | Exported (line 161) but only ever called locally (line 25); the public export is unused |
| `tools/init.lua` | `Context:remove_items` | Only reachable via dead `Registry:remove_group` |
| `tools/registry.lua` | `Registry:loaded` | Never called |
| `tools/registry.lua` | `Registry:remove_group` | Never called (chat buffer used to remove tool groups) |
| `tools/filter.lua` | `is_tool_enabled` | Never called |
| `tools/helpers/filter.lua` | `Filter.is_enabled` | Never called |
| `tools/helpers/filter.lua` | `Filter.refresh_cache` | Never called; its `CodeCompanionChatRefreshCache` autocmd is never fired since the chat buffer was removed |
| `tools/labels.lua` | `reject_always` | "Reject always" choice was removed |
| `tools/labels.lua` | `keymaps()` | Never called |
| `interactions/shared/agent_commands/discovery.lua` | `Discovery.refresh` | Never called |
| `diff/init.lua` | `M.LINE_OPTS` | Exported at `diff/init.lua:55` but never referenced — internal code uses `CONSTANTS.DIFF_LINE_OPTS` directly. Dead as an export, but it is a public field on the `codecompanion.diff` module, so removing it is an API change (see note below). |

> **Caveat — public API surface.** A handful of the entries above are exported on public-facing modules and could be used by user configs or external plugins even though nothing in this repo calls them: `codecompanion.version` and `codecompanion.has` (in `init.lua`), `Adapter.uses_new_handlers`, and `diff.LINE_OPTS`. Deleting any of these is a breaking API change. The rest (`utils.is_array`, `utils.contains`, the `log` helpers, `tokens.display`, `native_bit.bnot/bor/rshift`, `Registry:loaded`/`remove_group`, the `Filter`/`labels`/`Discovery`/`Context:remove_items` internals) are internal-only and safe to delete outright.

## 2. Test-only code (production caller removed; only tests/ reference it)

- `utils/context.lua` `get_visual_selection` — only called from `tests/utils/test_context.lua` (and internally by `get`).
- `diff/utils.lua` `unified` — only called from `tests/test_diff.lua`.
- `codecompanion` `has` (`init.lua:37`) — only called from `tests/test_has.lua`; it is public API for feature-detection by user configs, so keep unless deliberately dropping the feature gate.
- `codecompanion` `version` (`init.lua:60`) — no callers anywhere; public API formerly consumed by the removed `health.lua`. Keep if you want users/plugins to introspect the version, drop otherwise.
- `http.lua` `Client.merge_body`, `Client.build_curl_args`, `Client.resolve_method`, `Client.static.methods` — used internally plus asserted directly by `tests/test_http.lua`.

Note: `adapters.extend` and `adapters.set_model` (in `adapters/init.lua`) have no internal production callers, but are **public, documented extension points** (referenced in `doc/` and `AGENTS.md`) — NOT dead. Same for `openai_compatible.lua`: absent from the config presets but loaded on demand via `adapters.extend("openai_compatible")`; documented and not dead.

## 3. Dead config options

- `config.adapters.http.opts.show_model_choices` (`config.lua:35`) — defined, never read.
- `config.INFO_NS` / `config.ERROR_NS` (`config.lua:428-440`) — created and passed to `vim.diagnostic.config(...)` in `setup()`, but nothing in the codebase ever calls `vim.diagnostic.set()` (or `vim.diagnostic.reset()`) into either namespace, so they configure empty namespaces that are never populated. Dead weight left over from the removed chat buffer's inline diagnostics.

(Note: `cache_models_for`, `show_presets`, `hidden`, `proxy`, `allow_insecure`, `cmd_timeout` are all still consumed.)

## 4. Dead tree-sitter query files (no `vim.treesitter.query.get` caller)

Only `queries/markdown/tokens.scm` is still loaded (via `utils/tokens.lua:133`). Everything else in `queries/` is now orphaned:

- `queries/markdown/chat.scm`
- `queries/markdown/cc_context.scm`
- `queries/markdown/tools.scm`
- `queries/yaml/chat.scm`
- `queries/yaml/prompt_library.scm`
- `queries/python/tags.scm`
- `queries/ruby/tags.scm`
- `queries/{c,cpp,go,java,javascript,lua,php,python,ruby,rust,scala,typescript,vim}/cc_symbols.scm` (13 files)

These backed the removed chat buffer (`chat.scm`, `tools.scm`, `cc_context.scm`), the removed prompt library (`prompt_library.scm`), the removed `/symbols` slash command (`cc_symbols.scm`), and the removed tags feature (`tags.scm`).

## 5. Orphaned test stubs (only referenced by now-deleted tests)

- `tests/stubs/skills/*` — skills feature removed
- `tests/stubs/rules/*` — rules feature removed
- `tests/stubs/queue.txt` — queue test removed
- `tests/stubs/stub.go`, `stub.py`, `stub.txt`, `stub.lua`
- `tests/stubs/foo.lua`
- `tests/stubs/file.txt`
- `tests/stubs/fs_read_text_file.txt` — `test_files.lua` removed
- `tests/stubs/logo.png` — `test_images.lua` removed

`tests/stubs/weather.lua` is still used by many adapter tests — keep it.

## 6. Stale references (not shipped code, but incomplete cleanup)

- `minimal.lua:53` — `interactions.chat = { adapter = "copilot" }` references the removed chat interaction.
- `minimal.lua:41` — blink.cmp `sources = { default = { ..., "codecompanion" } }` references the removed completion source.
- `.codecompanion/` internal dev prompts that reference removed features:
  - `chat.md` (references `@./lua/codecompanion/interactions/chat/init.lua`, which no longer exists)
  - `code_review.md`, `rules.md`, `ui.md`, `workflows.md`, `tools.md`
  - `acp/acp.md`, `acp/claude_code_acp.md`, `acp/codex_acp.md`, `acp/acp_json_schema.json`
- `tools/helpers/filter.lua:120` — comment still mentions "MCP servers".

## 7. Latent bug (not dead code, but flagging)

- `utils/os.lua` `build_shell_command` branches on `M.os` (Windows vs. POSIX), but `M.os` is never assigned, so it is always `nil` and the Windows branch is unreachable.

## 8. Confirmed clean (checked, no dead code)

- All nine builtin tools (`read_file`, `create_file`, `delete_file`, `file_search`, `grep_search`, `get_changed_files`, `get_diagnostics`, `run_command`, `insert_edit_into_file`) are wired via `config.lua` tool paths.
- The entire tool execution stack (ToolLoop → engine → orchestrator → runner → registry) is reachable via `Inline:submit_with_tools`.
- `interactions/inline/keymaps.lua` is genuinely wired (via `config.lua` `callback = "keymaps.stop"`).
- All `adapters/http/*` handlers remain reachable (old flat names via the `get_handler` backward-compat map; new nested names directly).
- No dangling `require`s to removed modules (`mcp`, `memory`, `health`, `schema`, `types`, `_extensions`, `telescope`) remain in `lua/` or `plugin/`.
