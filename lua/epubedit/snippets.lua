local M = {}

function M.configure_luasnip()
  local ok, luasnip = pcall(require, "luasnip")
  if not ok then
    vim.notify("LuaSnip not found. Install it via LazyVim's coding.luasnip extra or manually.", vim.log.levels.WARN)
    return false
  end

  luasnip.filetype_extend("xhtml", { "html" })
  luasnip.filetype_extend("epub", { "html", "xhtml" })

  vim.notify("epubedit.nvim: Configured LuaSnip for EPUB/XHTML files", vim.log.levels.INFO)
  return true
end

function M.load_snippets()
  local ok_luasnip, luasnip_loader = pcall(require, "luasnip.loaders.from_vscode")
  if not ok_luasnip then
    return false
  end

  local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
  local snippet_path = plugin_root .. "/snippets"

  if vim.fn.isdirectory(snippet_path) == 1 then
    luasnip_loader.lazy_load({ paths = { snippet_path } })
    return true
  end

  return false
end

function M.setup()
  if not M.configure_luasnip() then
    return
  end

  if M.load_snippets() then
    vim.notify("epubedit.nvim: Loaded EPUB snippets", vim.log.levels.INFO)
  end

  local ok_luasnip, luasnip_lua = pcall(require, "luasnip.loaders.from_lua")
  if ok_luasnip then
    local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
    local lua_snippet_path = plugin_root .. "/snippets"

    if vim.fn.isdirectory(lua_snippet_path) == 1 then
      luasnip_lua.lazy_load({ paths = { lua_snippet_path } })
    end
  end
end

return M
