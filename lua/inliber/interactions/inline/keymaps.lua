local log = require("inliber.utils.log")

local M = {}

---Clear a keymap from a specific buffer
---@param keymaps table
---@param bufnr? number
function M.clear_map(keymaps, bufnr)
  bufnr = bufnr or 0

  for _, map in pairs(keymaps) do
    for mode, lhs in pairs(map.modes) do
      pcall(vim.keymap.del, mode, lhs, { buffer = bufnr })
    end
  end
end

M.stop = {
  callback = function(inline)
    local request = require("inliber.interactions.inline").get_request_at_cursor(inline.bufnr) or inline
    request:stop()
    log:trace("[Inline] Cancelling the request")
  end,
}

return M
