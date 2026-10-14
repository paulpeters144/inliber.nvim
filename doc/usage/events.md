---
description: "Reference for all Inliber events and hooks — integrate with Neovim's autocmd system to react to inline and request lifecycle events."
---

# Events / Hooks

In order to enable a tighter integration between Inliber and your Neovim config, the plugin fires events at various points during its lifecycle.

## List of Events

The events that are fired from within the plugin are:

- `InliberInlineStarted` - Fired at the start of the Inline interaction
- `InliberInlineFinished` - Fired at the end of the Inline interaction
- `InliberRequestStarted` - Fired at the start of any request to an agent
- `InliberRequestStreaming` - Fired when the first chunk of a streaming response arrives
- `InliberRequestFinished` - Fired at the end of any request, with `status` (`success`, `error` or `cancelled`) in the data payload
- `InliberDiffHunkChanged` - Fired when the diff window's current hunk changes, with `id` and `bufnr` in the data payload

## Event Data

Each event also comes with a data payload. For example, with `InliberRequestStarted`:

```lua
{
  adapter = {
    formatted_name = "Claude Code",
    model = nil,
    name = "claude_code",
    type = "acp",
  },
  bufnr = 10,
  id = 6107753,
  interaction = "inline",
}
```

## Consuming an Event

Events can be hooked into as follows:

```lua
local group = vim.api.nvim_create_augroup("InliberHooks", {})

vim.api.nvim_create_autocmd({ "User" }, {
  pattern = "InliberInline*",
  group = group,
  callback = function(request)
    if request.match == "InliberInlineFinished" then
      -- Format the buffer after the inline request has completed
      require("conform").format({ bufnr = request.buf })
    end
  end,
})
```
