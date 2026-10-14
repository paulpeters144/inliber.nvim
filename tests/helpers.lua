local Helpers = {}

Helpers = vim.tbl_extend("error", Helpers, require("tests.expectations"))

---Set up the Inliber plugin with test configuration
---@param config? table
---@return nil
Helpers.setup_plugin = function(config)
  local inliber = require("inliber")
  inliber.setup(config)
  return inliber
end

---Get the lines of a buffer
---@param bufnr number
---@return table
Helpers.get_buf_lines = function(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
end

---Setup the inline buffer
---@param config table
---@return Inliber.Inline
Helpers.setup_inline = function(config)
  require("inliber.config").setup(vim.tbl_deep_extend("force", vim.deepcopy(require("tests.config")), config or {}))

  return require("inliber.interactions.inline").new({
    intent = "edit",
    buffer_context = {
      winnr = 0,
      bufnr = 0,
      filetype = "lua",
      start_line = 1,
      end_line = 1,
      start_col = 0,
      end_col = 0,
    },
  })
end

---Start a child Neovim instance with minimal configuration
---@param child table
---@return nil
Helpers.child_start = function(child)
  child.restart({ "-u", "scripts/minimal_init.lua" })
  child.o.statusline = ""
  child.o.laststatus = 0
  child.o.cmdheight = 0
end

return Helpers
