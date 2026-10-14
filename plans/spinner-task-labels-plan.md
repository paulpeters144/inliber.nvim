# Description

The progress spinner floats top-right while inline requests run, but every row renders identically: one shared frame counter means concurrent spinners animate in lockstep, running rows are all `⠋ Thinking…`, and the Done row (`✓ Done`) carries no trace of which task finished. Give each spinner a task label built from the inline intent and buffer name, render `<glyph> <label>` for both running and done rows (done keeps the label, drops the word "Done"), stagger the frame animation per row so concurrent spinners move out of phase, and cap the float width by truncating labels to a display-cell budget. The only spinner caller is the inline interaction (`lua/inliber/interactions/inline/init.lua`), which has all the label context on hand.

# TODO

- [ ] `Spinner.new` accepts a label; rows render as `<glyph> <label>`
- [ ] Carry the label into the Done row (drop the word "Done")
- [ ] Stagger frame offsets per row
- [ ] Compute the float width per render and truncate labels to a cell budget
- [ ] Build the label in `Inline:_start_spinner` from intent and buffer name
- [ ] Update tests

# TODO Explanation

## `Spinner.new` accepts a label; rows render as `<glyph> <label>`

Change `Spinner.new()` to `Spinner.new(opts)` with `opts.label` defaulting to `"Thinking"`, and add `label` to the `Inliber.Spinner` annotation. `_render` builds each row as `glyph .. " " .. spinner.label`, where `glyph` is the spinner frame while running and `"✓"` when done. All braille frames are one cell wide, so the text after the glyph never shifts while animating.

## Carry the label into the Done row (drop the word "Done")

A done row renders `"✓ " .. spinner.label` instead of `"✓ Done"`, keeping the `InliberSpinnerDone` highlight. The running→done transition becomes a one-cell glyph swap with the label untouched, so the row does not widen when a task completes and the answer to "which task finished" is the label itself.

## Stagger frame offsets per row

The timer callback advances one module-level `frame` used by every row, so concurrent spinners move in lockstep. Compute each row's glyph from its 1-based index in `entries`: `frames[((frame - 1 + index) % #frames) + 1]`. Offset frames do not change row width (single-cell glyphs), and done rows do not animate.

## Compute the float width per render and truncate labels to a cell budget

Delete the module-level `width` constant (`lua/inliber/utils/spinner.lua:13`). `_render` builds the lines first, truncates each label so the full row fits a cell cap, computes `width` as the maximum `strdisplaywidth` across rows, then sizes the float from that width (`_open_float(width)`, `_resize(#lines, width)`). The cap is `math.min(40, math.floor(vim.o.columns * 0.4))`, clamped to at least a few cells and at most `vim.o.columns - 1` so the right-anchored `col = vim.o.columns - width` never goes negative.

Truncation is a module-local `truncate_label(text, max_cells)` that walks characters from the tail accumulating `strdisplaywidth`, stops at the budget, and prepends `…` (one cell reserved). Keeping the tail preserves the identifying part of a path (`…/lua/inliber.lua`). The label budget is `cap - 2` cells (glyph + space), and the intent prefix is short and constant per task so it survives any realistic cap.

## Build the label in `Inline:_start_spinner`

In `lua/inliber/interactions/inline/init.lua`, `_start_spinner()` (lines 542-545) builds the label from `self.intent` (`"Edit"`/`"Ask"`) and `self.buffer_context.filename` (basename, already computed at `lua/inliber/utils/context.lua:134`): `label = intent .. " · " .. filename`, falling back to the intent alone when the buffer has no name. Pass it as `Spinner.new({ label = label })`.

## Update tests

`tests/utils/test_spinner.lua` currently expects `"Thinking…"` and `"✓ Done"` — update the existing cases to pass labels and expect `<glyph> <label>` rows. New cases: label on the running row, label carried to the Done row, the truncation pair ("truncates a label that is OUTSIDE the cell budget" / "DOES NOT truncate a label that is INSIDE the cell budget"), float width stays within the cap, and staggered frames (two concurrent spinners render different glyphs). Run `make test_file FILE=tests/utils/test_spinner.lua`, then the full `make test` and `make format`.

# Objects

## Inliber.Spinner (modify)

```lua
---@class Inliber.Spinner
---@field state "running"|"done" What the spinner row currently shows
---@field label string What the row says after the status glyph
```

```lua
---@param opts? { label?: string }
---@return Inliber.Spinner
function Spinner.new(opts)
```

# Out of Scope

- Per-task colors or intent-specific highlight groups — labels and stagger are the differentiation mechanism for now.
- Elapsed time, turn numbers, or line-range suffixes on rows.
- Making the cap or label format user-configurable (`config.display`) — hardcoded constants until there is demand.
- Doc changes — nothing in `doc/` describes the spinner float, so `make docs` stays clean.
- Any change to `done_ms` or the shared-float anchoring behavior.
