local module = require("epubedit.module")

---@class epubedit.Config
---@field zip_bin string Executable used to create EPUB archives.
---@field unzip_bin string Executable used to unpack EPUB archives.
---@field workspace_root string|nil Directory for unpacked workspaces; defaults to OS temp dir.
---@field preserve_workspace boolean When true, keep workspace directories after saving.
---@field prompt_overwrite boolean When true, confirm before overwriting the original EPUB.
---@field neo_tree table|nil Neo-tree integration config.
---@field validators table|nil External validator configuration.
local defaults = {
  zip_bin = "zip",
  unzip_bin = "unzip",
  workspace_root = nil,
  preserve_workspace = false,
  prompt_overwrite = true,
  neo_tree = {
    group_order = { "text", "styles", "images", "fonts", "audio", "video", "misc" },
    group_labels = {
      text = "Text",
      styles = "Styles",
      images = "Images",
      fonts = "Fonts",
      audio = "Audio",
      video = "Video",
      misc = "Misc",
    },
  },
  validators = {
    epubcheck = "epubcheck",
    xmllint = "xmllint",
  },
}

---@class epubedit.Module
local M = {}

---@type epubedit.Config
M.config = vim.deepcopy(defaults)

local function merge_config(opts)
  return vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

---@param opts? epubedit.Config
function M.setup(opts)
  M.config = merge_config(opts)
  module.configure(M.config)
end

---@return epubedit.Config
function M.get_config()
  return M.config
end

---@param path? string
function M.open(path)
  local target = path or ""
  if target == "" then
    target = vim.fn.input("EPUB file: ", "", "file")
  end

  if target == "" then
    return
  end

  target = vim.fn.fnamemodify(target, ":p")
  local ok, err = module.open(target, M.config)
  if not ok then
    vim.notify(err, vim.log.levels.ERROR)
  end
end

---@param path? string
function M.save(path)
  local output = path or ""
  if output ~= "" then
    output = vim.fn.fnamemodify(output, ":p")
  end

  local ok, err = module.save(output ~= "" and output or nil, M.config)
  if not ok then
    vim.notify(err, vim.log.levels.ERROR)
  end
end

---@return boolean
function M.cleanup()
  local ok, err = module.cleanup(M.config)
  if not ok and err then
    vim.notify(err, vim.log.levels.ERROR)
  end
  return ok
end

function M.close()
  local ok, err = module.close(M.config)
  if not ok and err then
    vim.notify(err, vim.log.levels.ERROR)
  end
  return ok
end

function M._auto_open(path, bufnr)
  if not path or path == "" then
    return
  end
  local target = vim.fn.fnamemodify(path, ":p")
  local stat = vim.loop.fs_stat(target)
  if not stat or stat.type ~= "file" then
    return
  end
  vim.schedule(function()
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
    vim.cmd("silent! EpubEditOpen " .. vim.fn.fnameescape(target))
  end)
end

function M.check()
  local ok, err = module.check(M.config)
  if not ok and err then
    vim.notify(err, vim.log.levels.ERROR)
  end
  return ok
end

function M.metadata()
  local metadata_editor = require("epubedit.metadata_editor")
  local session = module.get_current_session()
  if not session then
    vim.notify("No active EPUB session.", vim.log.levels.ERROR)
    return
  end
  metadata_editor.open(session)
end

function M.spine()
  local spine_editor = require("epubedit.spine_editor")
  local session = module.get_current_session()
  if not session then
    vim.notify("No active EPUB session.", vim.log.levels.ERROR)
    return
  end
  spine_editor.open(session)
end

-- ensure internal module has defaults even before setup() is called
module.configure(M.config)

return M
