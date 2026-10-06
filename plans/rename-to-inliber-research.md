# Research Topic
Rename the repo/project `codecompanion.nvim` to `inliber` and identify the full surface area that must change.

## Name availability & meaning
- `inliber` is Latin: "in liber" = "in the book" (liber also means both "book" and "free", the root of library/liberty). Fits an AI coding plugin loosely ("inside the editor/book").
- No existing `inliber.nvim` plugin was found (web search). The name appears effectively unclaimed in the Neovim plugin ecosystem.
- Closest existing collisions (all unrelated): `InLibre` org (`github.com/inlibre`, inlibre.io — "redefining inclusion", India), `INLib` (iOS CocoaPods lib), `infilib` (library manager). None are Neovim plugins; none block use of `inliber.nvim`.
- Implication: repo could become `inliber.nvim` (or `inliber`), module namespace `require("inliber")`, filetype `inliber`, docs domain possibly `inliber.…`.

## Current naming surface (inventory)

The name is embedded far beyond the repo slug. `codecompanion` / `CodeCompanion` appears (case-insensitive) in **161 files**. Categorised:

### 1. Module namespace & files (must rename for a real rename)
- `lua/codecompanion/` — 97 Lua files across `adapters/`, `commands/`, `diff/`, `interactions/`, `tools/`, `utils/`.
- `plugin/codecompanion.lua` — entry point; sets `vim.g.loaded_codecompanion` (`plugin/codecompanion.lua:1,4`) and 13 highlight groups (`CodeCompanionChatInfo`, `CodeCompanionChatSubtext`, `CodeCompanionChatTokens`, `CodeCompanionChatWarn`, `CodeCompanionDiffAdd`, `CodeCompanionDiffDelete`, `CodeCompanionDiffText`, `CodeCompanionDiffTextDelete`, `CodeCompanionDiffBanner`, `CodeCompanionDiffBannerInline`, `CodeCompanionVirtualText`, `CodeCompanionAgentCommand`, plus `CodeCompanionChatInfo` used in spinner).
- Every `require("codecompanion…")` call site (e.g. `lua/codecompanion/init.lua:1`, spread across all 97 files + tests + `minimal.lua`).

### 2. Public Lua API / classes (LuaCATS `---@class CodeCompanion.*`)
- Hundreds of type annotations reference `CodeCompanion.*` (e.g. `CodeCompanion.Tools.Registry`, `CodeCompanion.HTTPAdapter`, `CodeCompanion.Adapter.ModelChoice`, `CodeCompanion.Spinner`, etc.). These are doc-only, but they form the plugin's public typing surface and any docs rendering.

### 3. User-facing identifiers (breaking for existing users)
- **User commands**: `CodeCompanionAsk`, `CodeCompanionEdit`, `CodeCompanionAskResume` (`lua/codecompanion/commands/init.lua:124,136,148`; default keymaps in `lua/codecompanion/config.lua:295-299`).
- **User autocmd events**: `CodeCompanion<Event>` — ~50 named events (`CodeCompanionChatCreated`, `CodeCompanionToolStarted`, `CodeCompanionRequestStarted`, `CodeCompanionInline*`, …). Pattern built in `lua/codecompanion/utils/init.lua:12` (`"CodeCompanion" .. event`) and matched in `lua/codecompanion/tools/engine.lua:176` (`"CodeCompanionTools*"`), `lua/codecompanion/diff/ui.lua:499` (`CodeCompanionDiffHunkChanged`). Documented in `doc/usage/events.md`.
- **Highlight groups**: 13 groups listed above (public theming surface).
- **Global variables**: `vim.g.loaded_codecompanion` (guard), `vim.g.codecompanion_adapter` (`lua/codecompanion/interactions/inline/init.lua:245-246`), and documented `_G.codecompanion_chat_metadata`, `_G.codecompanion_current_context`, `_G.codecompanion_current_tool` (in `doc/codecompanion.txt`, tied to chat buffer code that is currently mid-refactor out of the tree).
- **Filetype**: default buffer filetype `"codecompanion"` (`lua/codecompanion/utils/ui.lua:61`). Treesitter injected as `vim.treesitter.language.register("markdown", "codecompanion")` in `scripts/minimal_init.lua:33`.
- **Config directory**: `.codecompanion/` and `.codecompanion.lua` (documented `doc/configuration/others.md:51-52`; also `.codecompanion/skills`, `.codecompanion/acp/acp_json_schema.json` in docs).
- **Log file**: `codecompanion.log` (`lua/codecompanion/init.lua:93`), stored at `~/.local/state/nvim/codecompanion.log` (`doc/configuration/others.md:24`, `doc/codecompanion.txt:8681`).

### 4. Internal identifiers (rename for consistency, low external impact)
- Namespaces: `CodeCompanion-info`, `CodeCompanion-error` (`lua/codecompanion/config.lua:428-429`), `codecompanion_diff_ui_*`, `codecompanion_diff_extmarks_*` (`lua/codecompanion/diff/ui.lua:75,598`), `codecompanion_agent_commands` (`lua/codecompanion/interactions/shared/agent_commands/highlight.lua:6`).
- Augroup: `codecompanion.diff_window_<bufnr>` (`lua/codecompanion/diff/ui.lua:461`).
- Buffer names: `codecompanion://diff` (`lua/codecompanion/diff/utils.lua:20`), `codecompanion_input` (docs).
- Omnifunc global: `_G._codecompanion_agent_commands_omnifunc` (`lua/codecompanion/interactions/shared/agent_commands/completion.lua:32,35`).
- Notification titles: `"CodeCompanion"` (multiple in `utils/init.lua:25,101`, `utils/log.lua`, `config.lua`).

### 5. HTTP headers / external service identifiers
- `User-Agent: CodeCompanion.nvim` (`lua/codecompanion/adapters/http/copilot/token.lua:150`, `huggingface.lua:23`).
- OpenRouter: `HTTP-Referer = "https://codecompanion.olimorris.dev"`, `X-OpenRouter-Title = "CodeCompanion"` (`lua/codecompanion/adapters/http/openrouter.lua:77,79`).

### 6. Documentation (source + generated)
- `doc/codecompanion.txt` — generated vimdoc (~11.9k lines), 1274 matches. **Regenerated**, not hand-edited.
- `doc/*.md` — source pages; frontmatter + body reference "CodeCompanion.nvim", `codecompanion.olimorris.dev` links, `require("codecompanion")`, `.codecompanion/` paths. Pages with `olimorris` refs: `index.md`, `installation.md`, `extending/adapters.md`, `extending/tools.md`, `configuration/adapters-http.md`, `configuration/tools.md`, `configuration/upgrading.md`.
- `doc/architecture.md`, `doc/commands.md`, `doc/keymaps.md`, `doc/integrations.md`, `doc/troubleshooting.md`, `doc/getting-started.md`, `doc/guides/*`, `doc/configuration/*`, `doc/usage/*` — all reference the name to varying degrees.
- `doc/public/robots.txt` — references the domain.

### 7. Repo/branding/CI (non-code)
- `README.md` — title, logo alt, badge URLs, `olimorris/codecompanion.nvim` links, `codecompanion.olimorris.dev` links (26 matches).
- `CHANGELOG.md` — 1412 matches, almost all historical links to `olimorris/codecompanion.nvim` (decide whether to rewrite history or leave).
- `.github/` — issue templates (`bug_report.yml` references `CodeCompanionChat`, `codecompanion.log`, docs URL), `pull_request_template.md`, `ISSUE_TEMPLATE/config.yml` discussion URLs, `workflows/sponsors.yml:21` (`repository == 'olimorris/codecompanion.nvim'`), `workflows/rockspec.yml:23` (`codecompanion.nvim-dev-1.rockspec`).
- `Makefile` / `Make.ps1` — `--metadata="project:codecompanion"`, output `-o doc/codecompanion.txt`.
- `scripts/panvimdoc-cleanup.lua` — header-cleanup regexes matching `"CodeCompanion"` (`scripts/panvimdoc-cleanup.lua:25,32,34,35,36,38`).
- `minimal.lua` — `"olimorris/codecompanion.nvim"`, `name = "codecompanion"`, comments, `codecompanion` completion source.
- `scripts/minimal_init.lua`, `tests/helpers.lua`, `tests/*` — `require("codecompanion")`, `.codecompanion_test_api_key`, `codecompanion_test_file_that_does_not_exist`, `codecompanion_test.log`, `codecompanion_agent_commands` namespace.
- `queries/` — treesitter query files prefixed `cc_` (`cc_symbols.scm`, `cc_context.scm`, `chat.scm`, `tokens.scm`, `tools.scm`, `tags.scm`, `prompt_library.scm`). Filename prefix `cc` is a shorthand, not literal "codecompanion", but is part of the brand.
- Root files referencing the name: `AGENTS.md`, `STYLE.md`, `VOICE.md`, `CONTRIBUTING.md`, `CLAUDE.md`.
- `.codecompanion/` — internal dev prompt/notes directory (chat.md, rules.md, ui.md, workflows.md, acp/, adapters/, tests/) — should be renamed `.inliber/`.
- `LICENSE` — copyright is "Oli Morris", no plugin name (no change needed beyond repo/domain).
- `version.txt` — just `19.27.0`, no name.

## Scope decisions (what "rename" means)

The rename has two very different depths; they must be decided explicitly:

1. **Repo-level only** (cheap): rename the GitHub repo slug + README title/links + badges + docs domain, but keep `require("codecompanion")`, filetype, commands, events, and directory names unchanged.
2. **Full namespace rename** (the thorough version): also rename `lua/codecompanion/` → `lua/inliber/`, `plugin/codecompanion.lua` → `plugin/inliber.lua`, all `require("codecompanion")` → `require("inliber")`, `CodeCompanion` → `InLiber`/`Inliber`, and every user-facing identifier.

Full rename is a **breaking change** for every existing user config: `require("codecompanion").setup`, `CodeCompanion*` autocmd events, `CodeCompanion*` highlight groups, `CodeCompanionAsk`/`Edit` commands, `vim.g.codecompanion_adapter`, the `.codecompanion/` config dir, and `codecompanion.log`.

## Backwards-compatibility considerations

- Neovim plugin managers (lazy.nvim, etc.) key off the repo slug + `require` name; changing `require` breaks existing `opts`/`config` blocks.
- Autocmd events and highlight groups are referenced directly by users' configs (`autocmd User CodeCompanionChatDone …`, custom highlights). A rename needs either:
  - an explicit migration/breaking-change release note + major version bump, or
  - shim layer: keep firing old event names, keep old highlight group aliases (`default = true` link), accept both `.codecompanion` and `.inliber` config dirs for a deprecation window.
- Command names (`:CodeCompanion*`) are muscle memory and appear in the default keymap config; a deprecation alias could register both for a transition release.
- `vim.g.loaded_codecompanion` guard must remain consistent with the new name or double-loading/`load` detection breaks.
- Filetype rename: `codecompanion` → `inliber` requires the treesitter `markdown` language registration and any user `ftplugin`/treesitter queries to be updated; chat buffer code (currently mid-refactor out of `interactions/`) sets this filetype.
- Case convention: decide `inliber` (lowercase, matching `codecompanion`) vs `InLiber`/`Inliber` for the class/event/hl-group prefix. `CodeCompanion` → `InLiber` keeps the CamelCase shape (`InLiberChatDone`, `InLiberChatInfo`), whereas `Inliber` would produce `InliberChatDone`. This is a branding decision, not mechanical.

## Mechanical steps checklist (for a full namespace rename)

1. Git: `git mv lua/codecompanion lua/inliber`, `git mv plugin/codecompanion.lua plugin/inliber.lua`, `git mv doc/codecompanion.txt doc/inliber.txt`, `git mv .codecompanion .inliber`.
2. Replace `require("codecompanion` → `require("inliber` and `require("codecompanion")` across lua/tests/scripts/docs.
3. Replace `CodeCompanion` → `<ChosenCamel>` and `codecompanion` → `inliber` in code, with the category-by-category review above (events, hl groups, commands, globals, filetype, namespaces, augroups, buffer names, headers, notify titles).
4. Rename queries `cc_*` prefix if keeping brand consistency (`il_*` or `inliber_*`); note filetype change also affects which `queries/<ft>/` dirs load.
5. Update `Makefile`/`Make.ps1` docs metadata (`project:inliber`, `-o doc/inliber.txt`) and `scripts/panvimdoc-cleanup.lua` header patterns.
6. Update `.github/` (issue/PR templates, workflows `rockspec`/`sponsors` repo conditions), `minimal.lua`, `scripts/minimal_init.lua`, `tests/helpers.lua` and all test fixtures/strings.
7. Update `README.md`, `doc/*.md` frontmatter/links (domain), `doc/public/robots.txt`, `AGENTS.md`, `STYLE.md`, `VOICE.md`, `CONTRIBUTING.md`, `CLAUDE.md`.
8. Decide `CHANGELOG.md` treatment (historical `olimorris/codecompanion.nvim` links — typically left as-is or note the rename).
9. Regenerate vimdoc (`make docs`).
10. Run `make test` (full suite) and `make format`.

## Open questions to resolve before implementing

- Repo slug: `inliber.nvim` (Neovim convention) vs `inliber`? Owner/org? GitHub transfer/redirect keeps old links working.
- Docs domain: `inliber.…` replacement for `codecompanion.olimorris.dev`?
- Depth: repo-only vs full namespace rename; whether to ship a deprecation/alias shim.
- Case convention for the CamelCase identifiers (`InLiber` vs `Inliber`).
- Whether the `.codecompanion` internal dev folder and `cc_` query prefix are in scope.
