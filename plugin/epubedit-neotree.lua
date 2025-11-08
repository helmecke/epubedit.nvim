if package.preload["neo-tree.sources.epubedit"] == nil then
  package.preload["neo-tree.sources.epubedit"] = function()
    local mod = require("epubedit.neo_tree")
    package.loaded["neo-tree.sources.epubedit"] = mod
    return mod
  end
end

local neotree_integration = require("epubedit.neo_tree_integration")

local function subscribe_rename_hook()
  if vim.g._epubedit_neotree_rename_subscribed then
    return true
  end
  local ok, events = pcall(require, "neo-tree.events")
  if not ok then
    return false
  end
  local handler = function(args)
    neotree_integration.handle_path_change(args)
  end
  for _, ev in ipairs({ events.FILE_RENAMED, events.FILE_MOVED }) do
    events.subscribe({
      event = ev,
      id = "epubedit-neo-tree-" .. ev,
      handler = handler,
    })
  end
  vim.g._epubedit_neotree_rename_subscribed = true
  return true
end

local augroup = vim.api.nvim_create_augroup("EpubEditNeoTreeHooks", { clear = true })

vim.api.nvim_create_autocmd("User", {
  group = augroup,
  pattern = "EpubEditSessionOpen",
  callback = function(event)
    subscribe_rename_hook()
    local workspace = event and event.data and event.data.workspace or nil
    neotree_integration.open(workspace, { focus = true })
  end,
})

local function close_epub_source()
  subscribe_rename_hook()
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

subscribe_rename_hook()
