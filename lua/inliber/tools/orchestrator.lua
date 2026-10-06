local Approvals = require("inliber.tools.approvals")
local Queue = require("inliber.utils.queue")
local Runner = require("inliber.tools.runner")

local log = require("inliber.utils.log")
local os_utils = require("inliber.utils.os")
local ui_utils = require("inliber.utils.ui")
local utils = require("inliber.utils")

local fmt = string.format

---Strip any ANSI color codes which don't render in the chat buffer
---@param tbl table
---@return table
local function strip_ansi(tbl)
  for i, v in ipairs(tbl) do
    tbl[i] = v:gsub("\027%[[0-9;]*%a", "")
  end
  return tbl
end

---Add a response to the loop's messages regarding a tool's execution
---@param exec Inliber.Tools.Orchestrator
---@param llm_message string
---@param user_message? string
local send_response_to_loop = function(exec, llm_message, user_message)
  exec.tools.host:add_tool_output(exec.tool, llm_message, user_message)
end

---Execute a shell command with platform-specific handling
---@param opts { cmd: table, timeout?: number }
---@param callback function
---@return vim.SystemObj
local function execute_shell_command(opts, callback)
  if vim.fn.has("win32") == 1 then
    -- See PR #2186
    local shell_cmd = table.concat(opts.cmd, " ") .. "\r\nEXIT %ERRORLEVEL%\r\n"
    return vim.system({ "cmd.exe", "/Q", "/K" }, {
      stdin = shell_cmd,
      env = { PROMPT = "\r\n" },
      timeout = opts.timeout,
    }, callback)
  end

  return vim.system(os_utils.build_shell_command(opts.cmd), { timeout = opts.timeout }, callback)
end

---Converts a cmd-based tool to a function-based tool.
---@param tool Inliber.Tools.Tool
---@param orchestrator Inliber.Tools.Orchestrator
---@return Inliber.Tools.Tool
local function cmd_to_func_tool(tool, orchestrator)
  local timeout = tool.opts and tool.opts.timeout

  tool.cmds = vim
    .iter(tool.cmds)
    :map(function(cmd)
      if type(cmd) == "function" then
        return cmd
      end

      local flag = cmd.flag
      cmd = cmd.cmd or cmd
      if type(cmd) == "string" then
        cmd = vim.split(cmd, " ", { trimempty = true })
      end

      ---@param tools Inliber.Tools
      return function(tools, _, opts)
        local cb = vim.schedule_wrap(opts.output_cb)
        orchestrator.current_job = execute_shell_command({ cmd = cmd, timeout = timeout }, function(out)
          orchestrator.current_job = nil

          if flag then
            tools.host.registry.flags = tools.host.registry.flags or {}
            tools.host.registry.flags[flag] = (out.code == 0)
          end

          local eol_pattern = vim.fn.has("win32") == 1 and "\r?\n" or "\n"

          if out.code == 0 then
            cb({
              status = "success",
              data = strip_ansi(vim.split(out.stdout, eol_pattern, { trimempty = true })),
            })
          else
            local combined = {}
            if out.code == 124 then
              table.insert(combined, fmt("Command timed out after %dms and was terminated", timeout))
            end
            if out.stderr and out.stderr ~= "" then
              vim.list_extend(combined, strip_ansi(vim.split(out.stderr, eol_pattern, { trimempty = true })))
            end
            if out.stdout and out.stdout ~= "" then
              vim.list_extend(combined, strip_ansi(vim.split(out.stdout, eol_pattern, { trimempty = true })))
            end
            cb({ status = "error", data = combined })
          end
        end)
      end
    end)
    :totable()

  return tool
end

---@class Inliber.Tools.Orchestrator
---@field cancelled boolean Whether the user has stopped the execution
---@field current_job vim.SystemObj? The shell command that's currently running
---@field id number The id of the tools coordinator
---@field index number The index of the current command
---@field handlers table<string, function>
---@field output table<string, function>
---@field queue Inliber.Queue
---@field status string The status of the tool execution "success" | "error"
---@field tool Inliber.Tools.Tool The current tool being executed
---@field tool_output table? The output collected from the tool
---@field tools Inliber.Tools
local Orchestrator = {}

---@param tools Inliber.Tools
---@param id number
function Orchestrator.new(tools, id)
  local self = setmetatable({
    cancelled = false,
    id = id,
    queue = Queue.new(),
    tools = tools,
  }, { __index = Orchestrator })

  return self
end

---Add the tool's handlers to the executor
---@return nil
function Orchestrator:_setup_handlers()
  self.handlers = {
    setup = function()
      if not self.tool then
        return
      end
      if self.tool.handlers and self.tool.handlers.setup then
        return self.tool.handlers.setup(self.tool, { tools = self.tools })
      end
    end,
    prompt_condition = function()
      if not self.tool then
        return
      end

      if self.tool.handlers and self.tool.handlers.prompt_condition then
        return self.tool.handlers.prompt_condition(self.tool, { tools = self.tools })
      end
      return true
    end,
    on_exit = function()
      if not self.tool then
        return
      end

      if self.tool.handlers and self.tool.handlers.on_exit then
        return self.tool.handlers.on_exit(self.tool, { tools = self.tools })
      end
    end,
  }

  self.output = {
    cancelled = function(cmd)
      if not self.tool then
        return
      end

      if self.tool.output and self.tool.output.cancelled then
        self.tool.output.cancelled(self.tool, { cmd = cmd, tools = self.tools })
      else
        send_response_to_loop(
          self,
          fmt("The user cancelled the execution of the %s tool", self.tool.name),
          fmt("Cancelled `%s`", self.tool.name)
        )
      end
    end,

    cmd_string = function()
      if not self.tool then
        return
      end
      if self.tool.output and self.tool.output.cmd_string then
        return self.tool.output.cmd_string(self.tool, { tools = self.tools })
      end
      return nil
    end,

    error = function(cmd)
      if not self.tool then
        return
      end

      if self.tool.output and self.tool.output.error then
        self.tool.output.error(
          self.tool,
          vim.tbl_isempty(self.tools.stderr) and nil or self.tools.stderr,
          { cmd = cmd, tools = self.tools }
        )
      else
        send_response_to_loop(self, fmt("Error calling `%s`", self.tool.name))
      end
    end,

    prompt = function()
      if not self.tool then
        return
      end
      if self.tool.output and self.tool.output.prompt then
        return self.tool.output.prompt(self.tool, { tools = self.tools })
      end
    end,

    rejected = function(cmd, opts)
      if not self.tool then
        return
      end

      opts = opts or {}

      if self.tool.output and self.tool.output.rejected then
        self.tool.output.rejected(self.tool, { cmd = cmd, tools = self.tools, opts = opts })
      else
        local rejection = fmt("\nThe user rejected the execution of the %s tool", self.tool.name)
        if opts.reason then
          rejection = rejection .. fmt(': "%s"', opts.reason)
        end
        -- If no handler is set then return a default message
        send_response_to_loop(self, rejection)
      end
    end,

    success = function(cmd)
      if not self.tool then
        return
      end

      if self.tool.output and self.tool.output.success then
        self.tool.output.success(
          self.tool,
          vim.tbl_isempty(self.tool_output) and nil or self.tool_output,
          { cmd = cmd, tools = self.tools }
        )
      else
        send_response_to_loop(self, fmt("Executed `%s`", self.tool.name))
      end
    end,
  }

  self.gates = {
    judge_context = function()
      if not self.tool then
        return
      end
      if self.tool.gates and self.tool.gates.judge_context then
        return self.tool.gates.judge_context(self.tool, { tools = self.tools })
      end
      return nil
    end,
    is_safe = function()
      if self.tool and self.tool.gates and self.tool.gates.is_safe then
        return self.tool.gates.is_safe(self.tool, { tools = self.tools })
      end
      return false
    end,
  }
end

---Create the label for the tool
---@return string
function Orchestrator:_create_label()
  local ok, cmd_string = pcall(self.output.cmd_string)
  if ok and type(cmd_string) == "string" and cmd_string ~= "" then
    return fmt("%s: %s", self.tool.name, cmd_string)
  end
  return self.tool.name
end

---Report that the current tool has started running
---@return nil
function Orchestrator:_report_started()
  self.tool_status = "failed"
  self.tools.host:report_status(self.tool.name, "started", self:_create_label())
end

---Report the current tool's final status
---@return nil
function Orchestrator:_report_finished()
  self.tools.host:report_status(self.tool.name, self.tool_status or "completed", self:_create_label())
  self.tool_status = nil
end

---When the tools coordinator is finished, finalize it via an autocmd
---@param self Inliber.Tools.Orchestrator
---@return nil
function Orchestrator:_finalize_tools()
  self.tools.tool = nil
  self.tools.host.tool_orchestrator = nil

  return utils.fire("ToolsFinished", {
    id = self.tools.id,
    tool_call_id = self.id,
    status = self.tools.status,
  })
end

---Setup the tool to be executed
---@param input? any
---@return nil
function Orchestrator:setup_next_tool(input)
  if self.cancelled then
    return
  end
  if self.queue:is_empty() then
    return self:_finalize_tools()
  end

  -- Get the next tool to run
  self.tool = self.queue:pop()
  self.tool_output = {}

  self:_setup_handlers()
  self.handlers.setup() -- Call this early as run_command needs to setup its cmds dynamically

  -- Transform cmd-based tools to func-based
  self.tool = cmd_to_func_tool(self.tool, self)

  -- Get the first command to run
  local cmd = self.tool.cmds[1]
  log:debug("[Orchestrator::setup_next_tool] `%s` tool", self.tool.name)

  if
    not self.tool.opts
    or Approvals:is_approved(self.tools.id, { cmd = self.output.cmd_string(), tool_name = self.tool.name })
  then
    log:debug("[Orchestrator::setup_next_tool] No tool approval required")
    return self:execute_tool({ cmd = cmd, input = input })
  end

  local require_approval_before = self.tool.opts.require_approval_before

  if require_approval_before and type(require_approval_before) == "function" then
    require_approval_before = require_approval_before(self.tool, self.tools)
  end
  if require_approval_before and type(require_approval_before) ~= "boolean" then
    require_approval_before = self.handlers.prompt_condition()
  end

  if not require_approval_before then
    return self:execute_tool({ cmd = cmd, input = input })
  end

  if Approvals:get_mode(self.tools.id) == "auto" and not self.tool.opts.protect then
    if self.gates.is_safe() then
      return self:execute_tool({ cmd = cmd, input = input })
    end
  end

  return self:_prompt_for_approval({ cmd = cmd, input = input })
end

---Ask the user to approve the pending tool before it runs
---@param args { cmd: function, input?: any, reason?: string }
---@return nil
function Orchestrator:_prompt_for_approval(args)
  local cmd, input = args.cmd, args.input
  log:debug("[Orchestrator::_prompt_for_approval] Asking for approval")

  local prompt = self.output.prompt()
  if prompt == nil or prompt == "" then
    prompt = ("Run the %q tool?"):format(self.tool.name)
  end
  if args.reason and args.reason ~= "" then
    prompt = fmt('%s\nJudge: _"%s"_', prompt, args.reason)
  end

  local labels = require("inliber.tools.labels")
  require("inliber.tools.ui").approve({
    name = self.tool.name,
    prompt = prompt,
    choices = {
      {
        label = labels.always_accept,
        callback = function()
          Approvals:always(self.tools.id, { cmd = self.output.cmd_string(), tool_name = self.tool.name })
          self:execute_tool({ cmd = cmd, input = input })
        end,
      },
      {
        label = labels.accept,
        callback = function()
          self:execute_tool({ cmd = cmd, input = input })
        end,
      },
      {
        label = labels.reject,
        callback = function()
          ui_utils.input({ prompt = fmt("Reason for rejecting `%s`: ", self.tool.name) }, function(i)
            self.output.rejected(cmd, { reason = i })
            self:setup_next_tool()
          end)
        end,
      },
      {
        label = labels.cancel,
        callback = function()
          self.output.cancelled(cmd)
          self:finalize_tool()
          self:cancel_pending_tools()
          self:_finalize_tools()
        end,
      },
    },
  })
end

---Cancel all pending tools in the queue
---@return nil
function Orchestrator:cancel_pending_tools()
  while not self.queue:is_empty() do
    local pending_tool = self.queue:pop()
    self.tool = pending_tool

    -- Prepare handlers/output first
    self:_setup_handlers()
    local first_cmd = pending_tool.cmds and pending_tool.cmds[1] or nil

    local ok, err = pcall(function()
      self.output.cancelled(first_cmd)
    end)
    if not ok then
      return log:error("Failed to run cancelled handler for tool %s: %s", tostring(pending_tool.name), err)
    end
  end
end

---Stop the tool that's currently running and cancel anything still queued
---@return nil
function Orchestrator:cancel()
  if self.cancelled then
    return
  end
  self.cancelled = true

  if self.current_job then
    pcall(function()
      self.current_job:kill("sigterm")
    end)
    self.current_job = nil
  end

  if self.tool then
    local ok, err = pcall(function()
      self.output.cancelled(self.tool.cmds and self.tool.cmds[1])
    end)
    if not ok then
      log:error("Failed to run cancelled handler for tool %s: %s", tostring(self.tool.name), err)
    end
    self:finalize_tool()
  end

  self:cancel_pending_tools()

  self.tools.tool = nil
  self.tools:reset({ auto_submit = false })
end

---Execute the tool command
---@param args { cmd: function, input?: any }
---@return nil
function Orchestrator:execute_tool(args)
  if self.cancelled then
    return
  end

  self:_report_started()

  utils.fire("ToolStarted", {
    id = self.tools.id,
    tool_call_id = self.id,
    tool = self.tool.name,
    args = self.tool.args,
  })
  return Runner.new({ index = 1, orchestrator = self, cmd = args.cmd }):setup(args.input)
end

---Handle an error from a tool
---@param args { action: table, error?: any }
---@return nil
function Orchestrator:error(args)
  self.tools.status = self.tools.constants.STATUS_ERROR
  self.tool_status = "failed"
  if args.error then
    table.insert(self.tools.stderr, args.error)
  end

  local ok, err = pcall(function()
    self.output.error(args.action)
  end)
  if not ok then
    if self.tool and self.tool.function_call then
      self.tools.host:add_tool_output(
        self.tool,
        string.format("Internal error with `%s` tool: %s", self.tool.name, err)
      )
    end
  end

  self:finalize_tool()
  self:setup_next_tool()
end

---Handle a successful completion of a tool
---@param args { action: table, output?: any }
---@return nil
function Orchestrator:success(args)
  self.tools.status = self.tools.constants.STATUS_SUCCESS
  self.tool_status = "completed"

  if args.output then
    table.insert(self.tools.stdout, args.output)
    if not self.tool_output then
      self.tool_output = {}
    end
    table.insert(self.tool_output, args.output)
  end
  local ok, err = pcall(function()
    self.output.success(args.action)
  end)

  if not ok then
    log:error("Internal error with the %s success handler: %s", self.tool.name, err)
    if self.tool and self.tool.function_call then
      self.tools.host:add_tool_output(self.tool, string.format("Internal error with `%s` tool", self.tool.name))
    end
  end
end

---Finalize the execution of the tool
---@return nil
function Orchestrator:finalize_tool()
  if self.tool then
    pcall(function()
      self.handlers.on_exit()
    end)
    self:_report_finished()
    utils.fire("ToolFinished", {
      id = self.tools.id,
      tool_call_id = self.id,
      name = self.tool.name,
      args = self.tool.args,
    })
    self.tool = nil
  end
end

return Orchestrator
