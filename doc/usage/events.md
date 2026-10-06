---
description: "Reference for all Inliber events and hooks — integrate with Neovim's autocmd system to react to chat, inline, CLI, and tool lifecycle events."
---

# Events / Hooks

In order to enable a tighter integration between Inliber and your Neovim config, the plugin fires events at various points during its lifecycle.

## List of Events

The events that are fired from within the plugin are:

- `InliberACPConnected` - Fired after the ACP connection is authenticated and ready to use
- `InliberACPSessionPre` - Fired after ACP authentication completes but before a new session is established; allows subscribers to modify the connection (e.g. inject MCP servers) synchronously
- `InliberACPSessionPost` - Fired after a new ACP session has been established
- `InliberChatACPModeChanged` - Fired after the ACP mode has been changed in the chat
- `InliberACPChatRestored` - Fired after an ACP session has been restored
- `InliberChatCreated` - Fired after a chat has been created for the first time
- `InliberChatOpened` - Fired after a chat has been opened
- `InliberChatClosed` - Fired after a chat has been permanently closed
- `InliberChatHidden` - Fired after a chat has been hidden
- `InliberChatSubmitted` - Fired after a chat has been submitted
- `InliberChatDone` - Fired after a chat has received the response
- `InliberChatCompacting` - Fired after the chat begins compacting messages to reduce token usage
- `InliberChatStopped` - Fired after a chat has been stopped
- `InliberChatCleared` - Fired after a chat has been cleared
- `InliberChatRestored` - Fired after a chat has been restored to an editable state (e.g. when `on_before_submit` prevents submission)
- `InliberChatAdapter` - Fired after the adapter has been set in the chat
- `InliberChatModel` - Fired after the model has been set in the chat
- `InliberChatSessionSaved` - Fired after a chat has been saved to disk as a session, with `slug` in the data payload
- `InliberChatSessionRestored` - Fired after a session has been restored from disk, with `stem` in the data payload
- `InliberChatSessionsChanged` - Fired after a session has been written or deleted, so the list on disk has moved on
- `InliberCLICreated` - Fired after a CLI buffer has been created for the first time
- `InliberCLIOpened` - Fired after a CLI buffer has been opened
- `InliberCLIClosed` - Fired after a CLI buffer has been closed
- `InliberCLIHidden` - Fired after a CLI buffer has been hidden
- `InliberCLISent` - Fired after data has been sent to a CLI buffer
- `InliberCLISubmitted` - Fired when a CLI agent accepts a prompt, however it was typed. Requires [agent hooks](/configuration/cli#hooks)
- `InliberCLIDone` - Fired when a CLI agent finishes a turn. Requires [agent hooks](/configuration/cli#hooks)
- `InliberCLIApprovalRequested` - Fired when a CLI agent is waiting on the user, with a `message` in the data payload. Requires [agent hooks](/configuration/cli#hooks)
- `InliberCLIApprovalFinished` - Fired when a CLI agent resumes after waiting. Requires [agent hooks](/configuration/cli#hooks)
- `InliberContextChanged` - Fired when the context that a chat buffer follows, changes
- `InliberFileEdited` - Fired after the LLM has edited or created a file; the data payload includes the `path` and what made the change (`tool`)
- `InliberInlineStarted` - Fired at the start of the Inline interaction
- `InliberInlineFinished` - Fired at the end of the Inline interaction
- `InliberMCPServerStart` - Fired when an MCP server is started
- `InliberMCPServerReady` - Fired when an MCP server is ready for requests
- `InliberMCPServerClosed` - Fired when an MCP server is closed
- `InliberMCPServerToolsLoaded` - Fired when tools are loaded for an MCP server
- `InliberRequestStarted` - Fired at the start of any API request, and at the start of a CLI agent's turn when [hooks](/configuration/cli#hooks) are wired up
- `InliberRequestStreaming` - Fired at the start of a streaming API request
- `InliberRequestFinished` - Fired at the end of any API request, and at the end of a CLI agent's turn when [hooks](/configuration/cli#hooks) are wired up
- `InliberToolAdded` - Fired when a tool has been added to a chat
- `InliberToolApprovalRequested` - Fired when a tool is requesting approval to run
- `InliberToolApprovalFinished` - Fired when a user has actioned an approval request
- `InliberToolQuestionAsked` - Fired when a tool asks the user a question
- `InliberToolQuestionAnswered` - Fired when a user has answered or skipped a question
- `InliberToolStarted` - Fired when a tool has started executing
- `InliberToolFinished` - Fired when a tool has finished executing
- `InliberToolsStarted` - Fired when the tool system has been initiated
- `InliberToolsFinished` - Fired when the tool system has finished running all tools
- `InliberToolsJudgeStarted` - Fired when the background judge begins vetting a tool call
- `InliberToolsJudgeFinished` - Fired when the background judge returns its verdict


In addition to these events, the chat buffer has its own **callback system** for hooking into lifecycle events like `on_before_submit`, `on_checkpoint` and `on_tool_output`. These callbacks receive the chat instance and can inspect or mutate chat state. See the [callbacks](/configuration/callbacks) section for details.

There are also events that can be utilized to trigger commands from within the plugin:

- `InliberChatRefreshCache` - Used to refresh conditional elements in the chat buffer

## Event Data

Each event also comes with a data payload. For example, with `InliberRequestStarted`:

```lua
{
  buf = 10,
  data = {
    adapter = {
      formatted_name = "Copilot",
      model = "o3-mini-2025-01-31",
      name = "copilot"
    },
    bufnr = 10,
    id = 6107753,
    interaction = "chat"
  },
  event = "User",
  file = "InliberRequestStarted",
  group = 14,
  id = 30,
  match = "InliberRequestStarted"
}
```

And the `InliberRequestFinished` also has a `data.status` value.

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

You can trigger an event with:

```lua
vim.api.nvim_exec_autocmds("User", {
  pattern = "InliberChatRefreshCache",
})
```
