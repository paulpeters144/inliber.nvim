---
description: "Create custom rules parsers in Inliber to post-process and transform rules file content before it's shared with an LLM."
---

# Extending with Rules Parsers

In Inliber, parsers act on the contents of a rules file, carrying out some post-processing activities and returning the content back to the rules class.

Parsers serve as an excellent way to apply modifications and extract metadata prior to sharing them with an LLM.

## Structure of a Parser

A parser has limited restrictions. It is simply required to return a function that the _rules_ class can execute, passing in the file to be processed as a parameter:

```lua
---@class Inliber.Chat.Rules.Parser
---@field content string The content of the rules file
---@field meta? { included_files: string[] } The filename of the rules file

---@param file Inliber.Chat.Rules.ProcessedFile
---@return Inliber.Chat.Rules.Parser
return function(file)
  -- Your logic
end
```

As an output, the function must return a table containing a `content` key.

## Processing Files

Parsers may also return a list of files to be shared with the LLM by the _rules_ class. To enable this, ensure that the parser returns a `meta.included_files` array in its output:

```lua
{
  content = "Your parsed content",
  meta = {
    included_files = {
      ".inliber/acp/acp_json_schema.json",
      "./lua/inliber/acp/init.lua",
      "./lua/inliber/adapters/acp/claude_code.lua",
      "./lua/inliber/adapters/acp/helpers.lua",
      "./lua/inliber/acp/prompt_builder.lua",
      "./lua/inliber/interactions/chat/acp/handler.lua",
      "./lua/inliber/interactions/chat/acp/request_permission.lua",
    },
  },
}
```
