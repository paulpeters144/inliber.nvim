---
description: "The default keymaps in Inliber's inline ask, edit and diff review flows."
---

# Keymaps

Inliber registers a few keymaps by default:

| Keymap | Action |
|---|---|
| `<leader>aa` | Ask, answering in a floating window |
| `<leader>ae` | Edit, in the current buffer |
| `<leader>ar` | Resume the last ask conversation |
| `q` | Stop the current inline request |
| `g1` | Always accept changes in this buffer |
| `g2` | Accept the change |
| `g3` | Reject the change |
| `gv` | View the proposed diff |

The `<leader>` keymaps are set through `opts.default_keymaps` — see [Other Configuration Options](/configuration/others#default-keymaps). The stop keymap lives under `interactions.inline.keymaps`, and the diff keymaps under `interactions.shared.keymaps` — see [Configuring the Diff](/configuration/diff#keymaps).
