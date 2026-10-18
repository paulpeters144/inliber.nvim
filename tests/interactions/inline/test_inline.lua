local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = MiniTest.new_set()

local child = MiniTest.new_child_neovim()

T["Inline"] = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
      child.lua([[
        h = require('tests.helpers')

        -- Setup inline in child process
        inline = h.setup_inline({
          adapters = {
            acp = {
              test_adapter = {
                name = "test_adapter",
                type = "acp",
                roles = { llm = "assistant", user = "user" },
                commands = {
                  default = { "test-agent", "--acp" },
                },
                defaults = {
                  mcpServers = {},
                  timeout = 20000,
                },
              },
              fake_adapter = {
                name = "fake_adapter",
                type = "acp",
                roles = { llm = "assistant", user = "user" },
                commands = {
                  default = { "fake-agent", "--acp" },
                },
                defaults = {
                  mcpServers = {},
                  timeout = 20000,
                },
              },
            },
          },
          interactions = {
            inline = {
              adapter = "test_adapter",
              editor_state = { enabled = false },
            },
          },
          display = {
            diff = {
              enabled = true,
            },
          },
        })
      ]])
    end,
    post_case = function()
      child.lua([[inline = nil]])
    end,
    post_once = child.stop,
  },
})

T["Inline"]["can parse json output correctly"] = function()
  local json_str = [[{
  "code": "function test() end",
  "placement": "add"
}]]

  local json = child.lua([[return inline:parse_output(...)]], { json_str })
  h.eq("function test() end", json.code)
  h.eq("add", json.placement)
end

T["Inline"]["can parse markdown output correctly"] = function()
  local markdown_str = [[```json
{
  "code": "function test() end",
  "placement": "add"
}
```]]

  local json = child.lua([[return inline:parse_output(...)]], { markdown_str })
  h.eq("function test() end", json.code)
  h.eq("add", json.placement)
end

T["Inline"]["can parse Ollama output correctly"] = function()
  local ollama_response_str = "{\n"
    .. '  "code": "\\n\\n/**\\n * Executes an action based on the current action type.\\n */\\n",\n'
    .. '  "language": "lua",\n'
    .. '  "placement": "before"\n'
    .. "}"

  local json = child.lua_get([[inline:parse_output(...)]], { ollama_response_str })
  local expected_code_block = [[


/**
 * Executes an action based on the current action type.
 */
]]

  h.eq(expected_code_block, json.code)
  h.eq("before", json.placement)
end

T["Inline"]["forms correct prompts"] = function()
  child.lua([[
    local prompts = {
      {
        role = "user",
        content = "test prompt",
        opts = { contains_code = true },
      },
    }

    inline.prompts = prompts
    inline.buffer_context.is_visual = true
    inline.buffer_context.lines = { "local x = 1" }

    inline:prompt("Hello World")
  ]])

  local prompts = child.lua([[return inline.prompts]])
  h.eq(#prompts, 4)
  h.expect_starts_with("You are writing lua code", prompts[1].content)
  h.eq(
    "For context, this is the code that I've visually selected in the buffer, which is relevant to my prompt:\n<code>\n````lua\nlocal x = 1\n````\n</code>",
    prompts[3].content
  )
  h.eq("<prompt>Hello World</prompt>", prompts[#prompts].content)
end

T["Inline"]["uses the ask system prompt when the intent is ask"] = function()
  child.lua([[
    _G.submitted_prompts = {}
    function inline:submit(prompts)
      _G.submitted_prompts = prompts
    end

    inline.intent = "ask"
    inline:prompt("what does this do?")
  ]])

  local system_prompt = child.lua([[return _G.submitted_prompts[1].content]])
  h.eq(true, system_prompt:find("Never write or modify code", 1, true) ~= nil)
  h.eq(true, system_prompt:find('"message"', 1, true) ~= nil)
  h.eq(false, system_prompt:find('"placement"', 1, true) ~= nil)
end

T["Inline"]["reply resends the full conversation history"] = function()
  child.lua([[
    _G.submitted_prompts = {}
    function inline:submit(prompts)
      _G.submitted_prompts = prompts
    end

    inline.intent = "ask"
    inline:prompt("first question")
    table.insert(inline.messages, { role = "llm", content = "first answer" })
    table.insert(inline.turns, { question = "first question", answer = "first answer" })

    inline:reply("second question")
  ]])

  local prompts = child.lua([[return _G.submitted_prompts]])
  h.eq(4, #prompts)
  h.eq("system", prompts[1].role)
  h.eq("user", prompts[2].role)
  h.eq("<prompt>first question</prompt>", prompts[2].content)
  h.eq("llm", prompts[3].role)
  h.eq("first answer", prompts[3].content)
  h.eq("user", prompts[4].role)
  h.eq("<prompt>second question</prompt>", prompts[4].content)
end

T["Inline"]["records the answer and turn when the intent is ask"] = function()
  child.lua([[
    _G.recorded = nil
    function inline:_show_answer()
      _G.recorded = { turns = inline.turns, messages = inline.messages }
    end

    inline.intent = "ask"
    inline.current_question = "what does this do?"
    inline.current_asked_at = "10:00"
    inline:done('{"message": "it prints"}')
  ]])

  local recorded = child.lua([[return _G.recorded]])
  h.eq(1, #recorded.turns)
  h.eq("what does this do?", recorded.turns[1].question)
  h.eq("it prints", recorded.turns[1].answer)
  h.eq("10:00", recorded.turns[1].asked_at)
  h.eq(true, recorded.turns[1].answered_at:match("^%d%d:%d%d$") ~= nil)
  h.eq(1, #recorded.messages)
  h.eq("llm", recorded.messages[1].role)
  h.eq("it prints", recorded.messages[1].content)
end

T["Inline"]["ask starts the conversation and continues with follow-ups"] = function()
  child.lua([[
    _G.submitted = {}
    function inline:submit(prompts)
      table.insert(_G.submitted, prompts)
    end

    inline.intent = "ask"
    inline:ask("first question")
    table.insert(inline.messages, { role = "llm", content = "first answer" })
    inline:ask("second question")
  ]])

  local first = child.lua([[return (_G.submitted[1])]])
  h.eq(2, #first)
  h.eq("system", first[1].role)
  h.eq("<prompt>first question</prompt>", first[2].content)

  local second = child.lua([[return (_G.submitted[2])]])
  h.eq(4, #second)
  h.eq("<prompt>first question</prompt>", second[2].content)
  h.eq("first answer", second[3].content)
  h.eq("<prompt>second question</prompt>", second[4].content)
end

T["Inline"]["the ask float renders speaker labels and an input line"] = function()
  local lines = child.lua([[
    local float = require("inliber.interactions.inline.ask_float").new()
    float:show({
      turns = {
        { question = "why?", answer = "because.", asked_at = "10:00", answered_at = "10:01" },
      },
      on_submit = function() end,
    })
    local lines = vim.api.nvim_buf_get_lines(float.bufnr, 0, -1, false)
    float:close()
    return lines
  ]])

  h.eq(true, vim.tbl_contains(lines, "**You**"))
  h.eq(true, vim.tbl_contains(lines, "why?"))
  h.eq(true, vim.tbl_contains(lines, "**Agent**"))
  h.eq(true, vim.tbl_contains(lines, "because."))
  h.eq("", lines[#lines])
end

T["Inline"]["the ask float shows the token count in the winbar"] = function()
  local winbar = child.lua([[
    local float = require("inliber.interactions.inline.ask_float").new()
    float:show({
      turns = {
        { question = "one?", answer = "first.", asked_at = "10:00", answered_at = "10:01" },
      },
      tokens = 42,
      on_submit = function() end,
    })
    local winbar = vim.api.nvim_get_option_value("winbar", { win = float.winnr })
    float:close()
    return winbar
  ]])

  h.eq(true, winbar:find("42 tokens") ~= nil)
end

T["Inline"]["the ask float shows the pending question and locks the input until the answer arrives"] = function()
  local state = child.lua([[
    local float = require("inliber.interactions.inline.ask_float").new()
    float:show({ on_submit = function() end })
    float:set_thinking("is it alive?")

    local thinking_lines = vim.api.nvim_buf_get_lines(float.bufnr, 0, -1, false)
    local thinking_modifiable = vim.api.nvim_get_option_value("modifiable", { buf = float.bufnr })

    float:show({ turns = { { question = "is it alive?", answer = "yes" } } })
    local answered_lines = vim.api.nvim_buf_get_lines(float.bufnr, 0, -1, false)
    local answered_modifiable = vim.api.nvim_get_option_value("modifiable", { buf = float.bufnr })
    float:close()

    return {
      thinking_lines = thinking_lines,
      thinking_modifiable = thinking_modifiable,
      answered_lines = answered_lines,
      answered_modifiable = answered_modifiable,
    }
  ]])

  local function has_line(lines, pattern)
    for _, line in ipairs(lines) do
      if line:find(pattern, 1, true) then
        return true
      end
    end
    return false
  end

  h.eq(true, has_line(state.thinking_lines, "is it alive?"))
  h.eq(false, has_line(state.thinking_lines, "yes"))
  h.eq(false, state.thinking_modifiable)
  h.eq(true, has_line(state.answered_lines, "yes"))
  h.eq(true, state.answered_modifiable)
end

T["Inline"]["the ask float submits the question from the input line"] = function()
  local submitted = child.lua([[
    _G.captured = nil
    local float = require("inliber.interactions.inline.ask_float").new()
    float:show({ on_submit = function(question) _G.captured = question end })
    local last = vim.api.nvim_buf_line_count(float.bufnr)
    vim.api.nvim_buf_set_lines(float.bufnr, last - 1, last, false, { "  why is it slow?  " })
    float:_submit_input()
    float:close()
    return _G.captured
  ]])

  h.eq("why is it slow?", submitted)
end

T["Inline"]["the ask float submits a multi-line paste from the input line"] = function()
  local submitted = child.lua([[
    _G.captured = nil
    local float = require("inliber.interactions.inline.ask_float").new()
    float:show({ on_submit = function(question) _G.captured = question end })
    local last = vim.api.nvim_buf_line_count(float.bufnr)
    vim.api.nvim_buf_set_lines(float.bufnr, last - 1, last, false, {
      "class Game1",
      "    {",
      "    }",
      "}",
    })
    float:_submit_input()
    float:close()
    return _G.captured
  ]])

  h.eq("class Game1\n    {\n    }\n}", submitted)
end

T["Inline"]["the ask float DOES NOT submit a question while waiting for an answer"] = function()
  local submitted = child.lua([[
    _G.captured = nil
    local float = require("inliber.interactions.inline.ask_float").new()
    float:show({ on_submit = function(question) _G.captured = question end })
    float:set_thinking("first question")
    vim.api.nvim_set_option_value("modifiable", true, { buf = float.bufnr })
    local last = vim.api.nvim_buf_line_count(float.bufnr)
    vim.api.nvim_buf_set_lines(float.bufnr, last - 1, last, false, { "second question" })
    float:_submit_input()
    float:close()
    return _G.captured or "nothing"
  ]])

  h.eq("nothing", submitted)
end

T["Inline"]["the input modal collects the first prompt and closes"] = function()
  local result = child.lua([[
    _G.asked = nil
    local modal = require("inliber.interactions.inline.input_modal").new()
    modal:prompt(function(prompt) _G.asked = prompt end)
    local bufnr = modal.bufnr
    vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { "  what is this?  " })
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "i")) do
      if map.lhs == "<CR>" then
        map.callback()
      end
    end
    return { asked = _G.asked, closed = modal.winnr == nil }
  ]])

  h.eq("what is this?", result.asked)
  h.eq(true, result.closed)
end

T["Inline"]["the input modal collects a multi-line paste as the first prompt"] = function()
  local result = child.lua([[
    _G.asked = nil
    local modal = require("inliber.interactions.inline.input_modal").new()
    modal:prompt(function(prompt) _G.asked = prompt end)
    local bufnr = modal.bufnr
    vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { "class Game1", "{", "}" })
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "i")) do
      if map.lhs == "<CR>" then
        map.callback()
      end
    end
    return { asked = _G.asked, closed = modal.winnr == nil }
  ]])

  h.eq("class Game1\n{\n}", result.asked)
  h.eq(true, result.closed)
end

T["Inline"]["the input modal Esc leaves insert mode instead of closing, then closes on a second Esc"] = function()
  local result = child.lua([[
    _G.asked = nil
    local modal = require("inliber.interactions.inline.input_modal").new()
    modal:prompt(function(prompt) _G.asked = prompt end)
    local bufnr = modal.bufnr

    local function find(mode, lhs)
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, mode)) do
        if map.lhs == lhs then
          return map
        end
      end
    end

    -- Esc is deliberately unmapped in insert mode so it falls back to leaving insert mode
    local insert_esc = find("i", "<Esc>")
    local normal_esc = find("n", "<Esc>")
    normal_esc.callback()

    return {
      insert_esc_missing = insert_esc == nil,
      closed_on_normal_esc = modal.winnr == nil,
      prompt = _G.asked,
    }
  ]])

  h.eq(true, result.insert_esc_missing)
  h.eq(true, result.closed_on_normal_esc)
  h.eq(nil, result.prompt)
end

T["Inline"]["the input modal recalls the previous prompt with Up"] = function()
  local result = child.lua([[
    local input_modal = require("inliber.interactions.inline.input_modal")

    local function submit(text)
      local modal = input_modal.new()
      modal:prompt(function() end)
      local bufnr = modal.bufnr
      vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { text })
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "i")) do
        if map.lhs == "<CR>" then
          map.callback()
        end
      end
    end

    submit("first prompt")
    submit("second prompt")

    local modal = input_modal.new()
    modal:prompt(function() end)
    local bufnr = modal.bufnr
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "i")) do
      if map.lhs == "<Up>" then
        map.callback()
      end
    end
    local recalled = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
    modal:close()
    return recalled
  ]])

  h.eq("second prompt", result)
end

T["Inline"]["the input modal Down restores the unsubmitted draft after Up"] = function()
  local result = child.lua([[
    local input_modal = require("inliber.interactions.inline.input_modal")

    local function submit(text)
      local modal = input_modal.new()
      modal:prompt(function() end)
      local bufnr = modal.bufnr
      vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { text })
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "i")) do
        if map.lhs == "<CR>" then
          map.callback()
        end
      end
    end

    submit("older message")

    local modal = input_modal.new()
    modal:prompt(function() end)
    local bufnr = modal.bufnr
    vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { "draft in progress" })

    local function press(lhs)
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "i")) do
        if map.lhs == lhs then
          map.callback()
        end
      end
    end

    press("<Up>")
    local after_up = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
    press("<Down>")
    local after_down = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
    modal:close()
    return { after_up = after_up, after_down = after_down }
  ]])

  h.eq("older message", result.after_up)
  h.eq("draft in progress", result.after_down)
end

T["Inline"]["the input modal caps history at 15 prompts"] = function()
  local oldest = child.lua([[
    local input_modal = require("inliber.interactions.inline.input_modal")

    local function submit(text)
      local modal = input_modal.new()
      modal:prompt(function() end)
      local bufnr = modal.bufnr
      vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { text })
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "i")) do
        if map.lhs == "<CR>" then
          map.callback()
        end
      end
    end

    for i = 1, 16 do
      submit("message " .. i)
    end

    local modal = input_modal.new()
    modal:prompt(function() end)
    local bufnr = modal.bufnr
    for _ = 1, 16 do
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "i")) do
        if map.lhs == "<Up>" then
          map.callback()
        end
      end
    end
    local recalled = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
    modal:close()
    return recalled
  ]])

  h.eq("message 2", oldest)
end

T["Inline"]["the input modal keeps ask and edit histories separate"] = function()
  local result = child.lua([[
    local input_modal = require("inliber.interactions.inline.input_modal")

    local function submit(intent, text)
      local modal = input_modal.new({ intent = intent })
      modal:prompt(function() end)
      local bufnr = modal.bufnr
      vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { text })
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "i")) do
        if map.lhs == "<CR>" then
          map.callback()
        end
      end
    end

    submit("ask", "ask message")
    submit("edit", "edit message")

    local function recall(intent)
      local modal = input_modal.new({ intent = intent })
      modal:prompt(function() end)
      local bufnr = modal.bufnr
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "i")) do
        if map.lhs == "<Up>" then
          map.callback()
        end
      end
      local recalled = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
      modal:close()
      return recalled
    end

    return { ask = recall("ask"), edit = recall("edit") }
  ]])

  h.eq("ask message", result.ask)
  h.eq("edit message", result.edit)
end

T["Inline"]["generates correct prompt structure"] = function()
  child.lua([[
    _G.submitted_prompts = {}
    function inline:submit(prompts)
      _G.submitted_prompts = prompts
    end

    inline:prompt("Test prompt")
  ]])

  local submitted_prompts = child.lua([[return _G.submitted_prompts]])
  h.eq(#submitted_prompts, 2)
  h.eq(submitted_prompts[1].role, "system")
  h.eq(submitted_prompts[2].role, "user")
  h.eq(submitted_prompts[2].content, "<prompt>Test prompt</prompt>")
end

T["Inline"]["sends the editor state before the prompt WHEN enabled"] = function()
  child.lua([[
    _G.submitted_prompts = {}
    function inline:submit(prompts)
      _G.submitted_prompts = prompts
    end

    require("inliber.config").interactions.inline.editor_state.enabled = true
    inline:prompt("Test prompt")
  ]])

  local submitted_prompts = child.lua([[return _G.submitted_prompts]])
  h.eq(3, #submitted_prompts)
  h.expect_contains("<editor_state>", submitted_prompts[2].content)
  h.eq("<prompt>Test prompt</prompt>", submitted_prompts[3].content)
end

T["Inline"]["the first word can be an adapter"] = function()
  child.lua([[
    _G.submitted_prompts = {}
    function inline:submit(prompts)
      _G.submitted_prompts = prompts
    end
  ]])

  h.eq(child.lua([[return inline.adapter.name]]), "test_adapter")

  child.lua([[inline:prompt("fake_adapter print hello world")]])

  h.eq("fake_adapter", child.lua([[return inline.adapter.name]]))

  local submitted_prompts = child.lua([[return _G.submitted_prompts]])
  h.eq(submitted_prompts[2].content, "<prompt>print hello world</prompt>")
end

T["Inline"]["can parse adapter syntax"] = function()
  child.lua([[
    _G.submitted_prompts = {}
    function inline:submit(prompts)
      _G.submitted_prompts = prompts
    end

    _G.original_buffer_variable = require("inliber.config").interactions.inline.editor_context.buffer
    require("inliber.config").interactions.inline.editor_context.buffer = {
      callback = function()
        return "mocked buffer content"
      end,
      description = "Mock buffer for testing",
    }
  ]])

  h.eq(child.lua([[return inline.adapter.name]]), "test_adapter")

  child.lua([[inline:prompt("adapter=fake_adapter #{buffer} print hello world")]])
  h.eq("fake_adapter", child.lua([[return inline.adapter.name]]))

  local submitted_prompts = child.lua([[return _G.submitted_prompts]])
  h.eq(3, #submitted_prompts)
  h.eq("mocked buffer content", submitted_prompts[2].content)
  h.eq("<prompt>print hello world</prompt>", submitted_prompts[#submitted_prompts].content)

  child.lua([[
    require("inliber.config").interactions.inline.editor_context.buffer = _G.original_buffer_variable
  ]])
end

T["Inline"]["clears the stop keymap as soon as the request completes"] = function()
  child.lua([[
    local acp_request = require("inliber.interactions.shared.acp_request")
    _G.original_submit = acp_request.submit
    acp_request.submit = function(opts)
      opts.on_error("network error")
      return { cancel = function() end }
    end

    inline:submit({ { role = "user", content = "test prompt" } })
  ]])

  local has_stop_keymap = child.lua([[
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
      if map.lhs == "q" then
        return true
      end
    end
    return false
  ]])

  h.eq(false, has_stop_keymap)

  child.lua([[require("inliber.interactions.shared.acp_request").submit = _G.original_submit]])
end

T["Inline"]["applies the edit to the REQUESTED buffer WHEN another buffer is focused"] = function()
  child.lua([[
    local api = vim.api
    local config = require("inliber.config")
    local original_diff_enabled = config.display.diff.enabled
    config.display.diff.enabled = false

    local buf_a = api.nvim_create_buf(true, false)
    api.nvim_buf_set_lines(buf_a, 0, -1, false, { "local a = 1", "local b = 2", "local c = 3" })
    api.nvim_set_current_buf(buf_a)
    vim.bo[buf_a].filetype = "lua"

    local inline = require("inliber.interactions.inline").new({
      intent = "edit",
      buffer_context = {
        bufnr = buf_a,
        winnr = api.nvim_get_current_win(),
        filetype = "lua",
        start_line = 2,
        end_line = 2,
        start_col = 1,
        end_col = 2147483647,
      },
    })

    local buf_b = api.nvim_create_buf(true, false)
    api.nvim_buf_set_lines(buf_b, 0, -1, false, { "beta" })
    api.nvim_set_current_buf(buf_b)

    _G.buf_a = buf_a
    _G.buf_b = buf_b

    inline:done(vim.json.encode({ code = "local b = 22", language = "lua", placement = "replace" }))
    vim.wait(200)

    config.display.diff.enabled = original_diff_enabled
  ]])

  h.eq(
    { "local a = 1", "local b = 22", "local c = 3" },
    child.lua([[return vim.api.nvim_buf_get_lines(_G.buf_a, 0, -1, true)]])
  )
  h.eq({ "beta" }, child.lua([[return vim.api.nvim_buf_get_lines(_G.buf_b, 0, -1, true)]]))
  h.eq(child.lua([[return _G.buf_b]]), child.lua([[return vim.api.nvim_get_current_buf()]]))
end

---Start two edits in one buffer and land their answers, the lower edit asked first
local function start_two_edits()
  child.lua([[
    local api = vim.api
    local lines = {}
    for i = 1, 10 do
      lines[i] = "line " .. i
    end
    api.nvim_buf_set_lines(0, 0, -1, false, lines)

    local function start_edit(start_line, end_line)
      local edit = require("inliber.interactions.inline").new({
        intent = "edit",
        buffer_context = {
          bufnr = api.nvim_get_current_buf(),
          winnr = api.nvim_get_current_win(),
          filetype = "lua",
          start_line = start_line,
          end_line = end_line,
          start_col = 1,
          end_col = 2147483647,
        },
      })
      edit:_track_selection()
      return edit
    end

    local function answer(edit, code)
      edit:done(vim.json.encode({ code = code, language = "lua", placement = "replace" }))
      vim.wait(50)
    end

    _G.lower_edit = start_edit(8, 8)
    _G.upper_edit = start_edit(3, 3)
    answer(_G.upper_edit, "upper 1\nupper 2\nupper 3")
    answer(_G.lower_edit, "lower")
  ]])
end

T["Inline"]["edits the selected lines AFTER an earlier edit moves them"] = function()
  start_two_edits()

  local lines = child.lua([[return vim.api.nvim_buf_get_lines(0, 0, -1, false)]])
  h.eq({ "line 1", "line 2", "upper 1", "upper 2", "upper 3", "line 4" }, vim.list_slice(lines, 1, 6))
  h.eq({ "line 7", "lower", "line 9" }, vim.list_slice(lines, 9, 11))
end

T["Inline"]["DOES NOT undo another edit WHEN rejecting a diff"] = function()
  start_two_edits()

  local lines = child.lua([[
    _G.upper_edit.diff_ui.keymaps.on_reject()
    return vim.api.nvim_buf_get_lines(0, 0, -1, false)
  ]])
  h.eq({ "line 1", "line 2", "line 3", "line 4", "line 5", "line 6", "line 7", "lower", "line 9", "line 10" }, lines)
end

T["Inline"]["accepts the diff nearest the cursor WHEN a buffer has two"] = function()
  start_two_edits()

  local resolved = child.lua([[
    vim.api.nvim_win_set_cursor(0, { 10, 0 })
    local accept = require("inliber.config").interactions.shared.keymaps.accept_change.modes.n
    vim.api.nvim_feedkeys(accept, "x", false)
    return { upper = _G.upper_edit.diff_ui ~= nil, lower = _G.lower_edit.diff_ui ~= nil }
  ]])
  h.eq({ upper = true, lower = false }, resolved)
end

---Start two requests in one buffer that wait on the LLM until stopped
local function start_two_requests()
  child.lua([[
    local api = vim.api
    local lines = {}
    for i = 1, 10 do
      lines[i] = "line " .. i
    end
    api.nvim_buf_set_lines(0, 0, -1, false, lines)

    _G.cancelled = {}
    require("inliber.interactions.shared.acp_request").submit = function(opts)
      local line = opts.messages[1].content:match("edit line (%d+)")
      return {
        cancel = function()
          table.insert(_G.cancelled, tonumber(line))
        end,
      }
    end

    local function start_request(line)
      local request = require("inliber.interactions.inline").new({
        intent = "edit",
        buffer_context = {
          bufnr = api.nvim_get_current_buf(),
          winnr = api.nvim_get_current_win(),
          filetype = "lua",
          start_line = line,
          end_line = line,
          start_col = 1,
          end_col = 2147483647,
        },
      })
      request:submit({ { role = "user", content = "<prompt>edit line " .. line .. "</prompt>" } })
    end

    start_request(2)
    start_request(9)
  ]])
end

---Press the stop key with the cursor on a line
local function press_stop(line)
  child.lua(string.format(
    [[
      vim.api.nvim_win_set_cursor(0, { %d, 0 })
      vim.api.nvim_feedkeys(require("inliber.config").interactions.inline.keymaps.stop.modes.n, "x", false)
    ]],
    line
  ))
end

T["Inline"]["stops the request nearest the cursor WHEN a buffer has two"] = function()
  start_two_requests()
  press_stop(1)

  h.eq({ 2 }, child.lua([[return _G.cancelled]]))
end

T["Inline"]["DOES NOT remove the stop key WHILE another request runs"] = function()
  start_two_requests()
  press_stop(1)
  press_stop(1)

  h.eq({ 2, 9 }, child.lua([[return _G.cancelled]]))
end

T["Inline"]["Inline.remember and Inline.last_ask round-trip the instance"] = function()
  local same = child.lua([[
    local Inline = require("inliber.interactions.inline")
    local inst = Inline.new({
      intent = "ask",
      buffer_context = { bufnr = 0, filetype = "lua", winnr = 0 },
    })
    Inline.remember(inst)
    return Inline.last_ask() == inst
  ]])
  h.eq(true, same)
end

T["Inline"]["resume with prior turns reopens the chat float showing them"] = function()
  local turns_and_question = child.lua([[
    local Inline = require("inliber.interactions.inline")
    local inst = Inline.new({
      intent = "ask",
      buffer_context = { bufnr = 0, filetype = "lua", winnr = 0 },
    })
    inst.turns = {
      { question = "what?", answer = "this." },
    }
    inst.messages = { { role = "user", content = "what?" } }
    Inline.remember(inst)
    inst:resume()
    local float = inst.ask_float
    local lines = vim.api.nvim_buf_get_lines(float.bufnr, 0, -1, false)
    local has_what = vim.tbl_contains(lines, "what?")
    local has_this = vim.tbl_contains(lines, "this.")
    local win_valid = vim.api.nvim_win_is_valid(float.winnr)
    float:close()
    return { has_what = has_what, has_this = has_this, win_valid = win_valid }
  ]])
  h.eq(true, turns_and_question.has_what)
  h.eq(true, turns_and_question.has_this)
  h.eq(true, turns_and_question.win_valid)
end

T["Inline"]["resume with no prior turns opens the input modal"] = function()
  local result = child.lua([[
    local Inline = require("inliber.interactions.inline")
    local inst = Inline.new({
      intent = "ask",
      buffer_context = { bufnr = 0, filetype = "lua", winnr = 0 },
    })
    inst:resume()
    local modal = inst.input_modal
    local win_valid = vim.api.nvim_win_is_valid(modal.winnr)
    local cfg = vim.api.nvim_win_get_config(modal.winnr)
    modal:close()
    return { win_valid = win_valid, title = cfg.title[1][1] }
  ]])
  h.eq(true, result.win_valid)
  h.eq(" Ask ", result.title)
end

return T
