local h = require("tests.helpers")

local new_set = MiniTest.new_set
local T = MiniTest.new_set()

local child = MiniTest.new_child_neovim()

T["AgentCommands"] = new_set({
  hooks = {
    pre_case = function()
      h.child_start(child)
    end,
    post_once = child.stop,
  },
})

T["AgentCommands"]["OpenCode names nested commands with forward slashes"] = function()
  local result = child.lua([[
    local xdg = vim.fn.tempname()
    vim.env.XDG_CONFIG_HOME = xdg

    local root = vim.fn.tempname()
    local commands_dir = vim.fs.joinpath(root, ".opencode", "commands")
    vim.fn.mkdir(vim.fs.joinpath(commands_dir, "git"), "p")
    vim.fn.writefile({ "body" }, vim.fs.joinpath(commands_dir, "git", "commit.md"))

    local opencode = require("inliber.interactions.shared.agent_commands.providers.opencode")
    local commands = opencode.commands(root)

    vim.fn.delete(root, "rf")
    vim.fn.delete(xdg, "rf")
    return {
      name = commands[1].name,
      namespace = commands[1].namespace,
      scope = commands[1].scope,
      count = #commands,
    }
  ]])

  h.eq("git/commit", result.name)
  h.eq("git", result.namespace)
  h.eq("project", result.scope)
  h.eq(1, result.count)
end

T["AgentCommands"]["OpenCode prefers project commands over global"] = function()
  local result = child.lua([[
    local xdg = vim.fn.tempname()
    vim.fn.mkdir(xdg, "p")
    vim.env.XDG_CONFIG_HOME = xdg
    local global_dir = vim.fs.joinpath(xdg, "opencode", "commands")
    vim.fn.mkdir(global_dir, "p")
    vim.fn.writefile({ "global body" }, vim.fs.joinpath(global_dir, "commit.md"))

    local root = vim.fn.tempname()
    local project_dir = vim.fs.joinpath(root, ".opencode", "commands")
    vim.fn.mkdir(project_dir, "p")
    vim.fn.writefile({ "project body" }, vim.fs.joinpath(project_dir, "commit.md"))

    local opencode = require("inliber.interactions.shared.agent_commands.providers.opencode")
    local commands = opencode.commands(root)
    local body = require("inliber.interactions.shared.agent_commands.discovery").read_body(commands[1].path)

    vim.fn.delete(root, "rf")
    vim.fn.delete(xdg, "rf")
    return { scope = commands[1].scope, body = body, count = #commands }
  ]])

  h.eq("project", result.scope)
  h.eq("project body", result.body)
  h.eq(1, result.count)
end

T["AgentCommands"]["OpenCode prefers the nearer ancestor directory"] = function()
  local result = child.lua([[
    local xdg = vim.fn.tempname()
    vim.env.XDG_CONFIG_HOME = xdg

    local root = vim.fn.tempname()
    local far = vim.fs.joinpath(root, ".opencode", "commands")
    vim.fn.mkdir(far, "p")
    vim.fn.writefile({ "far body" }, vim.fs.joinpath(far, "commit.md"))

    local near = vim.fs.joinpath(root, "sub", ".opencode", "commands")
    vim.fn.mkdir(near, "p")
    vim.fn.writefile({ "near body" }, vim.fs.joinpath(near, "commit.md"))

    local opencode = require("inliber.interactions.shared.agent_commands.providers.opencode")
    local commands = opencode.commands(vim.fs.joinpath(root, "sub"))
    local body = require("inliber.interactions.shared.agent_commands.discovery").read_body(commands[1].path)

    vim.fn.delete(root, "rf")
    vim.fn.delete(xdg, "rf")
    return { body = body }
  ]])

  h.eq("near body", result.body)
end

T["AgentCommands"]["Claude Code names nested commands with colons"] = function()
  local result = child.lua([[
    local root = vim.fn.tempname()
    local commands_dir = vim.fs.joinpath(root, ".claude", "commands")
    vim.fn.mkdir(vim.fs.joinpath(commands_dir, "frontend"), "p")
    vim.fn.writefile({ "body" }, vim.fs.joinpath(commands_dir, "frontend", "component.md"))

    local claude = require("inliber.interactions.shared.agent_commands.providers.claude_code")
    local commands = claude.commands(root)

    local matched
    for _, command in ipairs(commands) do
      if command.name == "frontend:component" then
        matched = command
      end
    end

    vim.fn.delete(root, "rf")
    if matched then
      return { found = true, name = matched.name, namespace = matched.namespace, scope = matched.scope }
    end
    return { found = false }
  ]])

  h.is_true(result.found)
  h.eq("frontend:component", result.name)
  h.eq("frontend", result.namespace)
  h.eq("project", result.scope)
end

T["AgentCommands"]["parses frontmatter description and argument-hint"] = function()
  local result = child.lua([[
    local path = vim.fn.tempname() .. ".md"
    vim.fn.writefile({
      "---",
      "description: Do a thing",
      "argument-hint: [args]",
      "---",
      "body",
    }, path)

    local discovery = require("inliber.interactions.shared.agent_commands.discovery")
    local frontmatter = discovery.parse_frontmatter(path)

    vim.fn.delete(path)
    return frontmatter
  ]])

  h.eq("Do a thing", result.description)
  h.eq("[args]", result["argument-hint"])
end

T["AgentCommands"]["discovers command files without frontmatter"] = function()
  local result = child.lua([[
    local xdg = vim.fn.tempname()
    vim.env.XDG_CONFIG_HOME = xdg

    local root = vim.fn.tempname()
    local commands_dir = vim.fs.joinpath(root, ".opencode", "commands")
    vim.fn.mkdir(commands_dir, "p")
    vim.fn.writefile({ "just a body" }, vim.fs.joinpath(commands_dir, "plain.md"))

    local opencode = require("inliber.interactions.shared.agent_commands.providers.opencode")
    local commands = opencode.commands(root)

    vim.fn.delete(root, "rf")
    vim.fn.delete(xdg, "rf")
    return {
      name = commands[1].name,
      has_description = commands[1].description ~= nil,
      count = #commands,
    }
  ]])

  h.eq("plain", result.name)
  h.is_false(result.has_description)
  h.eq(1, result.count)
end

T["AgentCommands"]["expands a KNOWN tag and keeps an UNKNOWN tag"] = function()
  local result = child.lua([[
    local path = vim.fn.tempname() .. ".md"
    vim.fn.writefile({ "commit body" }, path)

    local providers = require("inliber.interactions.shared.agent_commands.providers")
    providers.register({
      name = "fixture",
      directories = function()
        return {}
      end,
      commands = function()
        return { { name = "commit", path = path } }
      end,
    })

    local agent_commands = require("inliber.interactions.shared.agent_commands")
    local provider = providers.get("fixture")

    local known = agent_commands.new({ provider = provider, prompt = "@commit fix the login bug", root = "" })
    local known_output = known:find():replace():output()

    local unknown = agent_commands.new({ provider = provider, prompt = "hey @someone", root = "" })
    local unknown_output = unknown:find():replace():output()

    vim.fn.delete(path)
    return {
      known_prompt = known.prompt,
      known_output = known_output,
      unknown_prompt = unknown.prompt,
      unknown_count = #unknown_output,
    }
  ]])

  h.eq("", result.known_prompt)
  h.eq({ "commit body\nfix the login bug" }, result.known_output)
  h.eq("hey @someone", result.unknown_prompt)
  h.eq(0, result.unknown_count)
end

T["AgentCommands"]["expands to the args alone when the command file cannot be read"] = function()
  local result = child.lua([[
    local providers = require("inliber.interactions.shared.agent_commands.providers")
    providers.register({
      name = "fixture",
      directories = function()
        return {}
      end,
      commands = function()
        return { { name = "commit", path = vim.fn.tempname() .. "-missing.md" } }
      end,
    })

    local agent_commands = require("inliber.interactions.shared.agent_commands")
    local ac = agent_commands.new({ provider = providers.get("fixture"), prompt = "@commit fix it", root = "" })
    local output = ac:find():replace():output()

    return { prompt = ac.prompt, output = output }
  ]])

  h.eq("", result.prompt)
  h.eq({ "fix it" }, result.output)
end

T["AgentCommands"]["completion items insert the command name"] = function()
  local result = child.lua([[
    local providers = require("inliber.interactions.shared.agent_commands.providers")
    providers.register({
      name = "fixture",
      directories = function()
        return {}
      end,
      commands = function()
        return {
          { name = "commit", description = "Write a commit", argument_hint = "[message]", path = "" },
        }
      end,
    })

    local completion = require("inliber.interactions.shared.agent_commands.completion")
    return completion.items(providers.get("fixture"), "")
  ]])

  h.eq(
    { {
      word = "@commit",
      abbr = "commit",
    } },
    result
  )
end

T["AgentCommands"]["omnifunc locates the trigger when the cursor follows it, but not after a space"] = function()
  local result = child.lua([[
    local providers = require("inliber.interactions.shared.agent_commands.providers")
    providers.register({
      name = "fixture",
      directories = function()
        return {}
      end,
      commands = function()
        return { { name = "commit", path = "" } }
      end,
    })

    local completion = require("inliber.interactions.shared.agent_commands.completion")
    local provider = providers.get("fixture")

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@co" })
    vim.api.nvim_win_set_cursor(0, { 1, 3 })
    completion.attach(bufnr, provider, "")
    local typing = completion._omnifunc(1, "")

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "@commit fix" })
    vim.api.nvim_win_set_cursor(0, { 1, 11 })
    local in_args = completion._omnifunc(1, "")

    return { typing = typing, in_args = in_args }
  ]])

  h.eq(0, result.typing)
  h.eq(-1, result.in_args)
end

T["AgentCommands"]["marks a KNOWN command name and leaves an UNKNOWN tag unmarked"] = function()
  local result = child.lua([[
    local providers = require("inliber.interactions.shared.agent_commands.providers")
    providers.register({
      name = "fixture",
      directories = function()
        return {}
      end,
      commands = function()
        return { { name = "commit", path = "" } }
      end,
    })

    local highlight = require("inliber.interactions.shared.agent_commands.highlight")
    local provider = providers.get("fixture")

    local function marks_for(line)
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { line })
      highlight.attach(bufnr, provider, "")
      vim.api.nvim_exec_autocmds("TextChangedI", { buffer = bufnr, modeline = false })
      local ns = vim.api.nvim_get_namespaces()["inliber_agent_commands"]
      local marks = {}
      for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })) do
        table.insert(marks, {
          row = mark[2],
          col = mark[3],
          end_col = mark[4].end_col,
          hl_group = mark[4].hl_group,
        })
      end
      vim.api.nvim_buf_delete(bufnr, { force = true })
      return marks
    end

    return { known = marks_for("@commit fix it"), unknown = marks_for("@someone fix it") }
  ]])

  h.eq({ { row = 0, col = 0, end_col = 7, hl_group = "InliberAgentCommand" } }, result.known)
  h.eq({}, result.unknown)
end

T["AgentCommands"]["detect returns the first provider with commands on disk"] = function()
  local result = child.lua([[
    local xdg = vim.fn.tempname()
    vim.env.XDG_CONFIG_HOME = xdg
    vim.fn.mkdir(vim.fs.joinpath(xdg, "opencode", "commands"), "p")

    local providers = require("inliber.interactions.shared.agent_commands.providers")
    local detected = providers.detect(vim.fs.joinpath(xdg, "project"))

    vim.fn.delete(xdg, "rf")
    return detected and detected.name or nil
  ]])

  h.eq("opencode", result)
end

T["AgentCommands"]["detect returns nil when no provider has commands on disk"] = function()
  local result = child.lua([[
    vim.env.HOME = vim.fn.tempname()
    local xdg = vim.fn.tempname()
    vim.env.XDG_CONFIG_HOME = xdg

    local providers = require("inliber.interactions.shared.agent_commands.providers")
    local detected = providers.detect(vim.fs.joinpath(xdg, "project"))

    vim.fn.delete(xdg, "rf")
    vim.fn.delete(vim.env.HOME, "rf")
    return detected and detected.name or false
  ]])

  h.eq(false, result)
end

T["AgentCommands"]["attach sets a completeopt that never auto-inserts the first match"] = function()
  local result = child.lua([[
    local providers = require("inliber.interactions.shared.agent_commands.providers")
    providers.register({
      name = "fixture",
      directories = function()
        return {}
      end,
      commands = function()
        return { { name = "commit", path = "" } }
      end,
    })

    local completion = require("inliber.interactions.shared.agent_commands.completion")
    local bufnr = vim.api.nvim_create_buf(false, true)
    completion.attach(bufnr, providers.get("fixture"), "")

    return vim.api.nvim_get_option_value("completeopt", { buf = bufnr })
  ]])

  h.eq("menu,menuone,noinsert,noselect", result)
end

return T
