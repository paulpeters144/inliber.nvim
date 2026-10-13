local buf_utils = require("inliber.utils.buffers")
local helpers = require("inliber.tools.builtin.helpers")
local log = require("inliber.utils.log")
local markdown = require("inliber.utils.markdown")

local api = vim.api
local diff_fn = vim.text.diff or vim.diff
local fmt = string.format

---@param winid number
---@return boolean
local function is_floating(winid)
  return api.nvim_win_get_config(winid).relative ~= ""
end

---@param current_bufnr number
---@return string
local function list_buffers(current_bufnr)
  local lines = {}
  for _, bufnr in ipairs(api.nvim_list_bufs()) do
    if vim.bo[bufnr].buflisted then
      local info = buf_utils.get_info(bufnr)
      table.insert(
        lines,
        fmt(
          "- bufnr=%d path=%q filetype=%q modified=%s loaded=%s lines=%d%s",
          bufnr,
          info.relative_path,
          info.filetype,
          tostring(vim.bo[bufnr].modified),
          tostring(api.nvim_buf_is_loaded(bufnr)),
          api.nvim_buf_line_count(bufnr),
          bufnr == current_bufnr and " (current)" or ""
        )
      )
    end
  end
  return fmt('<editorState type="buffers">\n%s\n</editorState>', table.concat(lines, "\n"))
end

---@param current_bufnr number
---@return string
local function list_windows(current_bufnr)
  local lines = {}
  for _, winid in ipairs(api.nvim_list_wins()) do
    if not is_floating(winid) then
      local bufnr = api.nvim_win_get_buf(winid)
      local cursor = api.nvim_win_get_cursor(winid)
      table.insert(
        lines,
        fmt(
          "- winid=%d tab=%d bufnr=%d path=%q cursor=%d:%d visible_lines=%d-%d%s",
          winid,
          api.nvim_tabpage_get_number(api.nvim_win_get_tabpage(winid)),
          bufnr,
          buf_utils.get_info(bufnr).relative_path,
          cursor[1],
          cursor[2],
          vim.fn.line("w0", winid),
          vim.fn.line("w$", winid),
          bufnr == current_bufnr and " (current buffer)" or ""
        )
      )
    end
  end
  return fmt('<editorState type="windows">\n%s\n</editorState>', table.concat(lines, "\n"))
end

---@return string
local function list_tabs()
  local current_tab = api.nvim_get_current_tabpage()
  local lines = {}
  for _, tab in ipairs(api.nvim_list_tabpages()) do
    local paths = {}
    for _, winid in ipairs(api.nvim_tabpage_list_wins(tab)) do
      if not is_floating(winid) then
        table.insert(paths, buf_utils.get_info(api.nvim_win_get_buf(winid)).relative_path)
      end
    end
    table.insert(
      lines,
      fmt(
        "- tab=%d%s windows: %s",
        api.nvim_tabpage_get_number(tab),
        tab == current_tab and " (current)" or "",
        table.concat(paths, ", ")
      )
    )
  end
  return fmt('<editorState type="tabs">\n%s\n</editorState>', table.concat(lines, "\n"))
end

---@param args { bufnr?: number, start_line?: number, end_line?: number }
---@param opts { max_lines: number }
---@return { status: "success"|"error", data: string }
local function read_buffer(args, opts)
  local bufnr = args.bufnr
  if not bufnr or not api.nvim_buf_is_valid(bufnr) then
    return { status = "error", data = fmt("Invalid buffer number: %s", tostring(bufnr)) }
  end
  if not api.nvim_buf_is_loaded(bufnr) then
    return { status = "error", data = fmt("Buffer %d is not loaded", bufnr) }
  end

  local start_line = math.max(args.start_line or 1, 1)
  local end_line = args.end_line or api.nvim_buf_line_count(bufnr)
  local lines = api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)

  local is_truncated = #lines > opts.max_lines
  if is_truncated then
    lines = vim.list_slice(lines, 1, opts.max_lines)
  end

  local numbered = {}
  for i, line in ipairs(lines) do
    table.insert(numbered, fmt("%d |%s", start_line + i - 1, line))
  end
  if is_truncated then
    table.insert(numbered, "... (buffer output truncated)")
  end

  local info = buf_utils.get_info(bufnr)
  return {
    status = "success",
    data = fmt(
      '<buffer bufnr="%d" path="%s">\n%s\n</buffer>',
      bufnr,
      info.relative_path,
      markdown.form_codeblock(table.concat(numbered, "\n"), { ft = info.filetype })
    ),
  }
end

---@param bufnr number
---@return string
local function get_text(bufnr)
  return table.concat(api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n") .. "\n"
end

---@param opts { max_lines: number }
---@return { status: "success"|"error", data: string }
local function read_diff(opts)
  local diff_wins = vim.tbl_filter(function(winid)
    return vim.wo[winid].diff
  end, api.nvim_tabpage_list_wins(0))
  if #diff_wins < 2 then
    return { status = "error", data = "No diff is open in the current tab" }
  end

  local old_bufnr = api.nvim_win_get_buf(diff_wins[1])
  local new_bufnr = api.nvim_win_get_buf(diff_wins[2])
  local diff = diff_fn(get_text(old_bufnr), get_text(new_bufnr), { result_type = "unified", ctxlen = 3 })
  if diff == "" then
    return { status = "success", data = "The diff windows have no differences" }
  end

  local lines = vim.split(diff, "\n", { trimempty = true })
  if #lines > opts.max_lines then
    lines = vim.list_slice(lines, 1, opts.max_lines)
    table.insert(lines, "... (diff output truncated)")
  end

  return {
    status = "success",
    data = fmt(
      '<diff old_bufnr="%d" old_path="%s" new_bufnr="%d" new_path="%s">\n%s\n</diff>',
      old_bufnr,
      buf_utils.get_info(old_bufnr).relative_path,
      new_bufnr,
      buf_utils.get_info(new_bufnr).relative_path,
      markdown.form_codeblock(table.concat(lines, "\n"), { ft = "diff" })
    ),
  }
end

---@param host_bufnr number
---@param args { action: string, bufnr?: number, start_line?: number, end_line?: number }
---@param opts { max_lines: number }
---@return { status: "success"|"error", data: string }
local function get_editor_state(host_bufnr, args, opts)
  local current_bufnr = host_bufnr > 0 and host_bufnr or api.nvim_get_current_buf()

  if args.action == "list_buffers" then
    return { status = "success", data = list_buffers(current_bufnr) }
  elseif args.action == "list_windows" then
    return { status = "success", data = list_windows(current_bufnr) }
  elseif args.action == "list_tabs" then
    return { status = "success", data = list_tabs() }
  elseif args.action == "read_buffer" then
    return read_buffer(args, opts)
  elseif args.action == "read_diff" then
    return read_diff(opts)
  end

  return { status = "error", data = fmt("Unknown action: %s", tostring(args.action)) }
end

---@class Inliber.Tool.GetEditorState: Inliber.Tools.Tool
return {
  name = "get_editor_state",
  cmds = {
    ---@param self Inliber.Tool.GetEditorState
    ---@param args table
    ---@param input? any
    function(self, args, input)
      return get_editor_state(self.host.bufnr or 0, args, self.tool.opts)
    end,
  },
  schema = {
    type = "function",
    ["function"] = {
      name = "get_editor_state",
      description = "Inspect the user's Neovim editor. List open buffers, windows or tabs, read a buffer's current contents including unsaved changes, or read the diff the user is viewing.",
      parameters = {
        type = "object",
        properties = {
          action = {
            type = "string",
            enum = { "list_buffers", "list_windows", "list_tabs", "read_buffer", "read_diff" },
            description = "What to inspect. Use 'read_buffer' with a bufnr from 'list_buffers' to read a buffer's contents. Use 'read_diff' for the unified diff between the diff windows in the current tab, such as a pull request review.",
          },
          bufnr = {
            type = "integer",
            description = "The buffer number to read. Required for 'read_buffer'.",
          },
          start_line = {
            type = "integer",
            description = "The 1-based line to start reading from. Defaults to the first line.",
          },
          end_line = {
            type = "integer",
            description = "The 1-based line to stop reading at, inclusive. Defaults to the last line.",
          },
        },
        required = { "action" },
      },
    },
  },
  handlers = {
    ---@param self Inliber.Tool.GetEditorState
    ---@param meta { tools: Inliber.Tools }
    ---@return nil
    on_exit = function(self, meta)
      log:trace("[Get Editor State Tool] on_exit handler executed")
    end,
  },
  output = {
    ---@param self Inliber.Tool.GetEditorState
    ---@param meta { tools: Inliber.Tools }
    prompt = function(self, meta)
      return "Get the editor state?"
    end,

    ---@param self Inliber.Tool.GetEditorState
    ---@param stdout table
    ---@param meta { tools: Inliber.Tools, cmd: table }
    success = function(self, stdout, meta)
      local output = vim.iter(stdout):flatten():join("\n")
      meta.tools.host:add_tool_output(self, output, "")
    end,

    ---@param self Inliber.Tool.GetEditorState
    ---@param stderr table
    ---@param meta { tools: Inliber.Tools, cmd: table }
    error = function(self, stderr, meta)
      local errors = vim.iter(stderr):flatten():join("\n")
      meta.tools.host:add_tool_output(self, errors)
    end,

    ---@param self Inliber.Tool.GetEditorState
    ---@param meta { tools: Inliber.Tools, cmd: string, opts: table }
    ---@return nil
    rejected = function(self, meta)
      local message = "The user rejected the get editor state tool"
      meta = vim.tbl_extend("force", { message = message }, meta or {})
      helpers.rejected(self, meta)
    end,
  },
}
