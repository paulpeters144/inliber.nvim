local log = require("inliber.utils.log")

return log.set_root(log.new({
  handlers = {
    {
      type = "file",
      filename = "inliber_test.log",
      level = vim.log.levels["DEBUG"],
    },
  },
}))
