local Discovery = require("inliber.interactions.shared.agent_commands.discovery")
local config = require("inliber.config")

---@class Inliber.AgentCommands
---@field provider Inliber.AgentCommands.Provider The resolved provider whose commands are in scope
---@field prompt string The user prompt to scan for command tags; replace() mutates it
---@field root string Project root passed through to discovery
---@field found Inliber.AgentCommands.Found[] Matched commands, in prompt order
local AgentCommands = {}

---A single matched command tag and the text range it spans in the prompt
---@class Inliber.AgentCommands.Found
---@field command Inliber.AgentCommands.Command The matched command
---@field args string Raw argument text following the command name
---@field start integer Byte index of the trigger in the prompt
---@field name_finish integer Byte index just past the command name
---@field finish integer Byte index just past the end of the tag and its args

local function is_boundary(char)
  return char == "" or char:match("%s") ~= nil
end

local function command_end(prompt, position, name, trigger)
  local after = prompt:sub(position, position + #name - 1)
  if after ~= name then
    return nil
  end
  local boundary = prompt:sub(position + #name, position + #name)
  if is_boundary(boundary) or boundary == trigger then
    return position + #name
  end
  return nil
end

local function next_command_start(prompt, from, names, trigger)
  local limit = #prompt
  local newline = prompt:find("\n", from)
  if newline then
    limit = newline - 1
  end

  local position = from
  while position <= limit do
    local at = prompt:find(trigger, position, true)
    if not at or at > limit then
      break
    end
    for _, name in ipairs(names) do
      if command_end(prompt, at + #trigger, name, trigger) then
        return at
      end
    end
    position = at + 1
  end

  return limit + 1
end

---@param args { provider: Inliber.AgentCommands.Provider, prompt: string, root: string }
---@return Inliber.AgentCommands
function AgentCommands.new(args)
  args = args or {}
  return setmetatable({
    provider = args.provider,
    prompt = args.prompt or "",
    root = args.root,
    found = {},
  }, { __index = AgentCommands })
end

---Scan for the trigger, match the longest discovered command name at each position, and record each match with its byte range
---@return Inliber.AgentCommands
function AgentCommands:find()
  local commands = Discovery.commands(self.provider, self.root)

  local by_name = {}
  local names = {}
  for _, command in ipairs(commands) do
    by_name[command.name] = command
    table.insert(names, command.name)
  end
  table.sort(names, function(a, b)
    return #a > #b
  end)

  local trigger = config.interactions.inline.agent_commands.trigger

  local position = 1
  while position <= #self.prompt do
    local at = self.prompt:find(trigger, position, true)
    if not at then
      break
    end

    local matched
    for _, name in ipairs(names) do
      if command_end(self.prompt, at + #trigger, name, trigger) then
        matched = name
        break
      end
    end

    if not matched then
      position = at + 1
    else
      local args_start = at + #trigger + #matched
      local finish = next_command_start(self.prompt, args_start, names, trigger)
      table.insert(self.found, {
        command = by_name[matched],
        args = vim.trim(self.prompt:sub(args_start, finish - 1)),
        start = at,
        name_finish = args_start,
        finish = finish,
      })
      position = finish
    end
  end

  return self
end

---Remove each matched command and its args from self.prompt using their byte ranges, then return self
---@return Inliber.AgentCommands
function AgentCommands:replace()
  local result = {}
  local cursor = 1
  for _, match in ipairs(self.found) do
    table.insert(result, self.prompt:sub(cursor, match.start - 1))
    cursor = match.finish
  end
  table.insert(result, self.prompt:sub(cursor))
  self.prompt = table.concat(result)
  return self
end

---One entry per matched command with content: the body pasted verbatim, then the args appended on their own line
---@return string[]
function AgentCommands:output()
  local outputs = {}
  for _, match in ipairs(self.found) do
    local body = Discovery.read_body(match.command.path)
    if body == "" then
      body = match.args
    elseif match.args ~= "" then
      body = body .. "\n" .. match.args
    end
    if body ~= "" then
      table.insert(outputs, body)
    end
  end
  return outputs
end

return AgentCommands
