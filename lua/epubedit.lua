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
  local file_watcher = require("epubedit.file_watcher")
  file_watcher.stop()

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

function M.preview()
  local server = require("epubedit.server")
  local file_watcher = require("epubedit.file_watcher")
  local session = module.get_current_session()

  if not session then
    vim.notify("No active EPUB session. Run :EpubEditOpen first.", vim.log.levels.ERROR)
    return
  end

  -- Get current buffer path
  local current_file = vim.api.nvim_buf_get_name(0)
  if current_file == "" then
    vim.notify("No file in current buffer.", vim.log.levels.ERROR)
    return
  end

  -- Get OPF directory (this is what we'll serve)
  local opf_dir = vim.fn.fnamemodify(session.opf, ":h")

  -- Calculate relative path from OPF directory to current file
  local relative_path = vim.fn.fnamemodify(current_file, ":.")

  -- Make it relative to OPF directory
  local opf_dir_normalized = vim.fn.fnamemodify(opf_dir, ":p")
  local current_file_normalized = vim.fn.fnamemodify(current_file, ":p")

  if not current_file_normalized:find(opf_dir_normalized, 1, true) then
    vim.notify("Current file is not within the EPUB workspace.", vim.log.levels.ERROR)
    return
  end

  -- Remove OPF directory prefix and leading slash
  local url_path = current_file_normalized:sub(#opf_dir_normalized + 1):gsub("^/+", ""):gsub("^\\+", "")

  -- Convert backslashes to forward slashes for URL
  url_path = url_path:gsub("\\", "/")

  -- Start server if not running
  if not server.is_running() then
    local ok, err = server.start(opf_dir)
    if not ok then
      vim.notify("Failed to start preview server: " .. (err or "unknown error"), vim.log.levels.ERROR)
      return
    end
    vim.notify(string.format("Preview server started on port %d", server.get_port()), vim.log.levels.INFO)

    -- Use BufWritePost autocmd for browser sync (recursive fs_event doesn't work on Linux)
    local augroup = vim.api.nvim_create_augroup("EpubEditBrowserSync", { clear = true })
    vim.api.nvim_create_autocmd("BufWritePost", {
      group = augroup,
      pattern = { "*.xhtml", "*.html", "*.htm", "*.css" },
      callback = function(args)
        local filepath = vim.fn.expand("%:p")
        -- Only trigger if file is within the EPUB workspace
        if filepath:find(opf_dir, 1, true) then
          server.notify_change(filepath)
        end
      end,
    })
  end

  -- Build URL
  local url = string.format("http://127.0.0.1:%d/%s", server.get_port(), url_path)

  -- Open in browser
  local ok, err = server.open_browser(url)
  if not ok then
    vim.notify("Failed to open browser: " .. (err or "unknown error"), vim.log.levels.ERROR)
    return
  end

  vim.notify(string.format("Opening preview: %s", url), vim.log.levels.INFO)
end

function M.toc()
  local toc_editor = require("epubedit.toc_editor")
  local session = module.get_current_session()
  if not session then
    vim.notify("No active EPUB session.", vim.log.levels.ERROR)
    return
  end
  toc_editor.open(session)
end

function M.toc_generate()
  local toc_generator = require("epubedit.toc_generator")
  local session = module.get_current_session()
  if not session then
    vim.notify("No active EPUB session.", vim.log.levels.ERROR)
    return
  end

  -- Ask user for max depth
  vim.ui.input({ prompt = "Max heading depth (1-6): ", default = "3" }, function(input)
    if not input then
      return
    end

    local max_depth = tonumber(input)
    if not max_depth or max_depth < 1 or max_depth > 6 then
      vim.notify("Invalid depth. Must be between 1 and 6.", vim.log.levels.ERROR)
      return
    end

    -- First, ensure headings have IDs
    local ok, err = toc_generator.add_heading_ids(session)
    if not ok then
      vim.notify("Failed to add heading IDs: " .. (err or "unknown error"), vim.log.levels.ERROR)
      return
    end

    -- Generate TOC from headings
    local entries, gen_err = toc_generator.generate_from_headings(session, { max_depth = max_depth })
    if not entries then
      vim.notify("Failed to generate TOC: " .. (gen_err or "unknown error"), vim.log.levels.ERROR)
      return
    end

    -- Save the generated TOC
    local toc_manager = require("epubedit.toc_manager")
    local save_ok, save_err = toc_manager.set_toc(session, entries)
    if not save_ok then
      vim.notify("Failed to save TOC: " .. (save_err or "unknown error"), vim.log.levels.ERROR)
      return
    end

    vim.notify(
      string.format("Generated and saved TOC with max depth %d from document headings.", max_depth),
      vim.log.levels.INFO
    )
  end)
end

-- ensure internal module has defaults even before setup() is called
module.configure(M.config)

return M
