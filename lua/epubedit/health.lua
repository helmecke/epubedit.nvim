local module = require("epubedit")
local core = require("epubedit.module")

local M = {}

local function report_dependency(name, bin, present)
  local msg = string.format("%s binary: %s", name, bin)
  if present then
    vim.health.report_ok(msg)
  else
    vim.health.report_error(
      string.format("%s (missing). Configure via require('epubedit').setup({ %s_bin = 'path/to/%s' })", msg, name, name)
    )
  end
end

function M.check()
  vim.health.report_start("epubedit.nvim")

  local config = module.get_config()
  report_dependency("zip", config.zip_bin, vim.fn.executable(config.zip_bin) == 1)
  report_dependency("unzip", config.unzip_bin, vim.fn.executable(config.unzip_bin) == 1)

  local workspace_root = config.workspace_root
  if workspace_root and workspace_root ~= "" then
    if vim.fn.isdirectory(workspace_root) == 1 then
      vim.health.report_ok(string.format("workspace_root accessible: %s", workspace_root))
    else
      vim.health.report_warn(string.format("workspace_root not found: %s", workspace_root))
    end
  end

  local status = core.dependency_status()
  if status.zip and status.unzip then
    vim.health.report_ok("Required dependencies detected.")
  else
    vim.health.report_error("One or more dependencies missing. See messages above.")
  end

  local ok_xml, _ = pcall(require, "epubedit.parser.opf")
  if ok_xml then
    vim.health.report_ok("OPF parser available.")
  else
    vim.health.report_error("OPF parser unavailable. Check vendor xml2lua installation.")
  end
end

return M
