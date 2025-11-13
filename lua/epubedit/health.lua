local module = require("epubedit")
local core = require("epubedit.module")

local M = {}

local health = vim.health or require("health")
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local error = health.error or health.report_error
local warn = health.warn or health.report_warn
local info = health.info or health.report_info

local function report_dependency(name, bin, present)
  local msg = string.format("%s binary: %s", name, bin)
  if present then
    ok(msg)
  else
    error(
      string.format("%s (missing). Configure via require('epubedit').setup({ %s_bin = 'path/to/%s' })", msg, name, name)
    )
  end
end

function M.check()
  start("epubedit.nvim")

  local config = module.get_config()
  report_dependency("zip", config.zip_bin, vim.fn.executable(config.zip_bin) == 1)
  report_dependency("unzip", config.unzip_bin, vim.fn.executable(config.unzip_bin) == 1)

  local workspace_root = config.workspace_root
  if workspace_root and workspace_root ~= "" then
    if vim.fn.isdirectory(workspace_root) == 1 then
      ok(string.format("workspace_root accessible: %s", workspace_root))
    else
      warn(string.format("workspace_root not found: %s", workspace_root))
    end
  end

  local status = core.dependency_status()
  if status.zip and status.unzip then
    ok("Required dependencies detected.")
  else
    error("One or more dependencies missing. See messages above.")
  end

  local ok_xml, _ = pcall(require, "epubedit.parser.opf")
  if ok_xml then
    ok("OPF parser available.")
  else
    error("OPF parser unavailable. Check vendor xml2lua installation.")
  end

  start("Snippet Support")

  local ok_luasnip = pcall(require, "luasnip")
  if not ok_luasnip then
    warn("LuaSnip not installed")
    info("Install via: :LazyExtras → enable 'coding.luasnip'")
  else
    ok("LuaSnip installed")

    local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
    local snippet_path = plugin_root .. "/snippets"

    if vim.fn.isdirectory(snippet_path) == 1 then
      local json_count = #vim.fn.glob(snippet_path .. "/*.json", false, true)
      local lua_count = #vim.fn.glob(snippet_path .. "/*.lua", false, true)
      ok(string.format("Found %d JSON + %d Lua snippet files", json_count, lua_count))
    else
      warn("Snippet directory not found: " .. snippet_path)
    end

    local ok, luasnip = pcall(require, "luasnip")
    if ok then
      local ft = vim.bo.filetype
      if ft == "xhtml" or ft == "html" or ft == "epub" then
        local snippets = luasnip.get_snippets(ft)
        if snippets and #snippets > 0 then
          ok(string.format("%d snippets available for %s", #snippets, ft))
        else
          warn(string.format("No snippets loaded for %s", ft))
          info("Run :EpubEditConfigureSnippets to load snippet library")
        end
      else
        info("Snippet check skipped (not in EPUB file)")
      end
    end
  end
end

return M
