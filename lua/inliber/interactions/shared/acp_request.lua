local acp = require("inliber.acp")
local acp_defaults = require("inliber.interactions.inline.acp.defaults")
local async = require("inliber.utils.async")

local M = {}

-- One cached connection per (purpose, adapter name); processes stay alive for reuse
local connections = {}

---@class Inliber.ACPRequest.Opts
---@field purpose "inline"
---@field adapter Inliber.ACPAdapter
---@field messages table[] Messages already run through adapter:map_roles()
---@field on_done fun(output: string)
---@field on_error? fun(err: string)
---@field bufnr? number
---@field silent? boolean

---Return the connection to use for a one-shot request, reusing an idle cached one when possible
---@param purpose string
---@param adapter Inliber.ACPAdapter
---@return Inliber.ACP.Connection
local function get_connection(purpose, adapter)
  local key = purpose .. ":" .. adapter.name
  local cached = connections[key]

  if cached and cached:is_ready() and not cached._active_prompt then
    return cached
  end

  -- Strip fs from a copy so a one-shot agent can't edit files directly
  local stripped = vim.deepcopy(adapter)
  if stripped.parameters and stripped.parameters.clientCapabilities then
    stripped.parameters.clientCapabilities.fs = nil
  end

  local conn = acp.new({ adapter = stripped })

  -- A busy cached connection is still alive: leave it cached and run this request
  -- on its own process, so concurrent prompts never share a connection
  if not cached or not cached:is_ready() then
    connections[key] = conn
  end

  return conn
end

---Fold non-user content into a leading user message and tag user messages with _meta,
---which is what the ACP form_messages handler filters on
---@param messages table[]
---@param roles table
---@return table[]
local function shape_messages(messages, roles)
  local shaped = {}
  local folded = {}

  for _, message in ipairs(messages or {}) do
    if message.role == roles.user then
      if message._meta == nil then
        message._meta = {}
      end
      table.insert(shaped, message)
    elseif message.content then
      table.insert(folded, message.content)
    end
  end

  local prefix = table.concat(folded, "\n\n")

  if #shaped == 0 then
    return { { role = roles.user, content = prefix, _meta = {} } }
  end

  if prefix ~= "" then
    shaped[1].content = prefix .. "\n\n" .. (shaped[1].content or "")
  end

  return shaped
end

---Submit a one-shot prompt over ACP and hand the streamed text to opts.on_done
---@param opts Inliber.ACPRequest.Opts
---@return { cancel: function }
function M.submit(opts)
  opts = opts or {}
  local request = {}
  request.cancel = function()
    request.cancelled = true
    if request.prompt then
      request.prompt.cancel()
    end
  end

  -- Keep the agent boot off the main loop
  async.sync(function()
    local conn = get_connection(opts.purpose, opts.adapter)
    -- connect_and_authenticate returns Connection|nil, not a boolean
    local ready = conn:connect_and_authenticate() and conn:renew_session()

    if request.cancelled then
      return
    end
    if not ready then
      if opts.on_error then
        opts.on_error("Could not establish an ACP session for " .. opts.adapter.name)
      end
      return
    end

    -- Apply adapter defaults (e.g. the inline model override) to the fresh session
    acp_defaults.apply(opts.adapter, conn)

    local output = {}
    -- session_prompt returns nil (via log:error) when there is no session
    local builder = conn:session_prompt(shape_messages(opts.messages, conn.adapter.roles))
    if not builder then
      if opts.on_error then
        opts.on_error("Could not build an ACP prompt for " .. opts.adapter.name)
      end
      return
    end

    builder
      :on_message_chunk(function(chunk)
        table.insert(output, chunk)
      end)
      :on_complete(function(stop_reason)
        if request.cancelled then
          return
        end
        -- handle_done("canceled") also fires when the agent process dies
        if stop_reason ~= "end_turn" and stop_reason ~= nil then
          if opts.on_error then
            opts.on_error("Agent turn ended unexpectedly: " .. tostring(stop_reason))
          end
          return
        end
        opts.on_done(table.concat(output))
      end)
      :on_error(function(err)
        if opts.on_error then
          opts.on_error(err)
        end
      end)
      :with_options({ bufnr = opts.bufnr, interaction = opts.purpose, silent = opts.silent })

    request.prompt = builder
    builder:send()
  end)()

  return request
end

return M
