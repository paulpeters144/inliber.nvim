return {
  adapters = {
    acp = {
      test_acp = {
        name = "test_acp",
        type = "acp",
        command = { "node", "test-agent.js" },
        roles = { user = "user", assistant = "assistant" },
        defaults = {},
        opts = { vision = true },
      },
      test_no_vision = {
        name = "test_no_vision",
        type = "acp",
        command = { "node", "test-agent.js" },
        roles = { user = "user", assistant = "assistant" },
        defaults = {},
      },
    },
    opts = {
      cmd_timeout = 10e3,
    },
  },
  interactions = {
    inline = {
      adapter = "test_acp",
    },
  },
  display = {
    diff = {
      enabled = false,
    },
  },
}
