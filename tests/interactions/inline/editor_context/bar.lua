local Bar = {}

---@param args table
function Bar.new(args)
  return setmetatable({
    context = args.context,
  }, { __index = Bar })
end

---Fetch and output a bar
---@return string
function Bar:output()
  return "The output from bar editor context"
end

return Bar
