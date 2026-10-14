---
description: "Configure Inliber's built-in diff engine in Neovim, covering the inline edit review and word level highlights."
---

# Configuring the Diff

Inliber has a built-in diff engine that's leveraged throughout the plugin. After an inline edit, the proposed change is shown as a diff in a floating window before it lands in your buffer.

There are a number of configuration options available to you:

```lua
require("inliber").setup({
  display = {
    diff = {
      enabled = true,

      -- Options for any diff windows (extends from floating_window)
      window = {
        opts = {},
      },
      word_highlights = {
        additions = true,
        deletions = true,
      },
    },
  },
})
```

Set `enabled = false` to apply inline edits immediately without review.

## Keymaps

The diff keymaps are shared and can be customised under `interactions.shared.keymaps`:

| Keymap | Default | Action |
|---|---|---|
| `view_diff` | `gv` | Open the proposed diff |
| `always_accept` | `g1` | Always accept changes in this buffer |
| `accept_change` | `g2` | Accept the change |
| `reject_change` | `g3` | Reject the change |

Buffers added via `always_accept` are remembered for the session, so their diffs are skipped from then on.
