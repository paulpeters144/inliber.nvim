# inliber.nvim

This is a Neovim plugin written in Lua, which allows developers to code with LLMs and agents from within Neovim. Tests use Mini.Test with child processes. Always run the full test suite after changes and ensure all tests pass before considering work complete.

## Commands

- `make format` - StyLua (120 cols, 2 spaces). Run before committing.
- `make test` - full test suite (Mini.Test)
- `make test_file FILE=path` - targeted tests
- `make docs` - regenerate vimdoc. Run this after changing any docs pages.

## Code conventions

The full style guide, with worked examples:

@STYLE.md

- **Naming:** snake_case for files/functions, PascalCase for classes, underscore prefix for private functions
- **Explicit names:** `pattern` not `pat`, `should_include` not `include_ok`
- **Readable code:** names, variables, and control flow should read like clean English. Avoid generic names like `ctx` - use domain-specific names (`permission`, `request`, `source`)
- **Plain language:** avoid jargon shortcuts in code, comments, commit messages, and chat. Don't say "no-op" - say what the code actually does ("returns unchanged", "does nothing", "skipped because already edited")
- **Comments earn their place:** don't restate what a readable line of code already says. If a guard like `if type(x) ~= "number" then return end` is self-evident, a comment explaining it is noise. Comment the *why* that isn't in the code (e.g. `-- NOTE: Not handling token tables yet`), not the *what*
- **Don't narrate every change:** the maintainer is an expert who knows this codebase. Do NOT add a comment to explain routine code (`-- Clear the modified flag`, `-- Loop over the messages`, `-- Return early`). Default to no comment. Reserve comments for genuinely non-obvious *why* - a subtle API quirk, a workaround, an ordering constraint - the kind of thing that would trip up even a reader who knows the codebase
- **Function params:** take an `opts` table, not a list of positional args - a new parameter then costs one edit instead of every call site. Default to `opts` alone. A leading positional is earned, not assumed: it must be the single subject the function acts on and stable enough that it will never be replaced or joined by a sibling (`Chat:add_message(data, opts)`, `markdown.form_codeblock(content, opts)`). If you're weighing whether an argument qualifies, it doesn't. Normalise it on the first line with `opts = opts or {}` and annotate the shape inline: `---@param opts? { auto_submit?: boolean }`
- **Error handling:** `pcall` + `log:error()`, return nil on failure
- **Type annotations:** LuaCATS for public APIs. Keep doc blocks concise - one description line, params should be self-explanatory without inline comments
- **Function descriptions:** exactly one line. No multi-paragraph rationale, no usage examples, no "why we cache this" essays - that belongs in commit messages or a single inline `--` comment at the relevant line. If you can't summarise the function in one line, the function is doing too much
- **Functions:** keep under 50 lines
- **Globals:** avoid; use module-local state
- **Code blocks:** use four backticks with language spec unless in a markdown file

## Architecture

Core: `lua/inliber/`

- **Interactions** (`interactions/`): `inline/` — the only interaction (ask float, input modal, diff flow, ACP submit)
- **ACP** (`acp/`): `init.lua` (Connection), `prompt_builder.lua`, `fs.lua`, `methods.lua` — JSON-RPC 2.0 over stdio to agent CLIs
- **Adapters** (`adapters/acp/`): `init.lua` (ACPAdapter), `helpers.lua`, 13 preset adapters (copilot_acp, claude_code, opencode, codex, ...)
- **One-shot requests** (`interactions/shared/acp_request.lua`): connection pooling and message shaping for the inline interaction
- **Agent commands** (`interactions/shared/agent_commands/`): discovery, completion and expansion of `@command` tags (claude_code, opencode providers)
- **Editor Context** (`interactions/inline/editor_context/`): `buffer`, `clipboard`
- **Config:** `config.lua` - adapter presets, inline settings, display options
- **Entry point:** `plugin/inliber.lua` → `lua/inliber/init.lua`

## General rules

- Don't over-explore the codebase with excessive grep/read calls. If you haven't converged on an approach after 3-4 searches, pause and share what you've found so far rather than continuing to search.
- When the user asks to fix tests, fix the tests - not the source code - unless explicitly asked otherwise.
- If you're working with directories or files, utilise the functions in `inliber/utils/files.lua` ensuring you join paths with `vim.fs.joinpath`
- To change an adapter's model, `adapters.resolve(name, { model = "gpt-4o" })` — it lands in `defaults.session_config_options.model` and is applied to the session via `session/set_config_option`. On a live connection, `adapters.set_model({ acp_connection = conn, model = "gpt-4o" })`. Don't assign the adapter table yourself

### Testing

- `make test_file FILE=` takes a single file (e.g. `tests/acp/test_acp.lua`), never a directory. Run one file per invocation
- When running `make test_file` tests, do not append `| tail -12` or similar to filter the output. This prevents the user's rules governing what can be auto-accepted, from applying
- Float cursor position, scrolling and folds are verified by hand in real use. Don't add test cases for them, even alongside a fix. Ask first
- Test the behaviour, not the obvious. A case that only proves a guard clause returns `false`, or that a value passes through a shared utility unchanged, earns nothing - cut it and keep the cases where the outcome could genuinely go either way
- Name a case for the behaviour it pins down, and lean on contrast so a pair reads as a pair: `DOES NOT truncate a tool that is INSIDE the limit` / `truncates a tool that is OUTSIDE the limit`

## Important instructions

- Do what has been asked; nothing more, nothing less.
- NEVER create files unless absolutely necessary
- ALWAYS prefer editing existing files
- NEVER proactively create documentation files
- ALWAYS keep memory in the current working directory and `memories/` folder

### Self-improvement loop

The user may have shared a `PERSONAL.md` file with specific instructions for how they like to work. If so, follow these instructions carefully:

- Review the `PERSONAL.md` at the start of every session
- After ANY correction from the user: update the `PERSONAL.md` with the pattern
- Write rules that prevent the same mistake from happening again

