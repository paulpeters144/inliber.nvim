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
            http = {
              test_adapter = {
                name = "test_adapter",
                url = "http://localhost/v1/chat/completions",
                roles = { llm = "assistant", user = "user" },
                opts = { stream = true },
                headers = { content_type = "application/json" },
                handlers = {
                  form_parameters = function()
                    return {}
                  end,
                  form_messages = function()
                    return {}
                  end,
                  is_complete = function()
                    return false
                  end,
                },
                schema = {
                  model = { default = "gpt-3.5-turbo" },
                },
              },
              fake_adapter = { name = "fake_adapter" },
            },
          },
          interactions = {
            inline = {
              adapter = "test_adapter",
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
  h.expect_starts_with("You are a knowledgeable", prompts[1].content)
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
  h.eq(true, system_prompt:find("NEVER write or modify code", 1, true) ~= nil)
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
  h.eq(true, vim.tbl_contains(lines, "**Inliber**"))
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

T["Inline"]["the ask float shows a thinking indicator until the answer arrives"] = function()
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
  h.eq(true, has_line(state.thinking_lines, "Thinking…"))
  h.eq(false, state.thinking_modifiable)
  h.eq(false, has_line(state.answered_lines, "Thinking…"))
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
    local http = require("inliber.http")
    _G.original_http_new = http.new
    http.new = function()
      return {
        request = function(_, _, actions)
          actions.callback("network error")
        end,
      }
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

  child.lua([[require("inliber.http").new = _G.original_http_new]])
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
