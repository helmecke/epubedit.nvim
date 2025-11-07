if package.preload["neo-tree.sources.epubedit"] == nil then
  package.preload["neo-tree.sources.epubedit"] = function()
    local mod = require("epubedit.neo_tree")
    package.loaded["neo-tree.sources.epubedit"] = mod
    return mod
  end
end

local neotree_integration = require("epubedit.neo_tree_integration")
local augroup = vim.api.nvim_create_augroup("EpubEditNeoTreeHooks", { clear = true })

vim.api.nvim_create_autocmd("User", {
  group = augroup,
  pattern = "EpubEditSessionOpen",
  callback = function(event)
    local workspace = event and event.data and event.data.workspace or nil
    neotree_integration.open(workspace)
  end,
})

local function close_epub_source()
  neotree_integration.close()
end

vim.api.nvim_create_autocmd("User", {
  group = augroup,
  pattern = "EpubEditSessionSaved",
  callback = close_epub_source,
})

vim.api.nvim_create_autocmd("User", {
  group = augroup,
  pattern = "EpubEditSessionClosed",
  callback = close_epub_source,
})
