if vim.g.loaded_inliber then
  return
end
vim.g.loaded_inliber = true

if vim.fn.has("nvim-0.11") == 0 then
  return vim.notify("inliber.nvim requires Neovim 0.11+", vim.log.levels.ERROR)
end

local api = vim.api

api.nvim_set_hl(0, "InliberChatInfo", { link = "DiagnosticInfo", default = true })
api.nvim_set_hl(0, "InliberChatSubtext", { link = "Comment", default = true })
api.nvim_set_hl(0, "InliberChatTokens", { link = "Comment", default = true })
api.nvim_set_hl(0, "InliberChatWarn", { link = "DiagnosticWarn", default = true })
api.nvim_set_hl(0, "InliberDiffAdd", { link = "DiffAdd", default = true })
api.nvim_set_hl(0, "InliberDiffDelete", { link = "DiffDelete", default = true })
api.nvim_set_hl(0, "InliberDiffText", { link = "DiffText", default = true })
api.nvim_set_hl(0, "InliberDiffTextDelete", { link = "DiffTextDelete", default = true })
api.nvim_set_hl(0, "InliberDiffBanner", { link = "DiagnosticHint", default = true })
api.nvim_set_hl(0, "InliberDiffBannerInline", { link = "Comment", default = true })
api.nvim_set_hl(0, "InliberVirtualText", { link = "Comment", default = true })
api.nvim_set_hl(0, "InliberAgentCommand", { link = "Special", default = true })
