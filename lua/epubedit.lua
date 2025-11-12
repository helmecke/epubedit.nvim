local module = require("epubedit.module")
local opf_manager = require("epubedit.opf_manager")

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

function M.add_file()
  local session = module.get_current_session()
  if not session then
    vim.notify("No active EPUB session.", vim.log.levels.ERROR)
    return
  end

  local opf_dir = vim.fn.fnamemodify(session.opf, ":h")
  local workspace = vim.fn.fnamemodify(session.workspace, ":p")

  vim.ui.input({ prompt = "Source file path: ", completion = "file" }, function(source_path)
    if not source_path or source_path == "" then
      return
    end

    source_path = source_path:gsub("^['\"]", ""):gsub("['\"]$", "")
    source_path = vim.fn.fnamemodify(source_path, ":p")

    if vim.fn.filereadable(source_path) == 0 then
      vim.notify("epubedit: file not found or not readable: " .. source_path, vim.log.levels.ERROR)
      return
    end

    local source_filename = vim.fn.fnamemodify(source_path, ":t")
    local default_dest = opf_dir .. "/" .. source_filename

    vim.ui.input({ prompt = "Destination path (relative or absolute): ", default = default_dest }, function(dest_input)
      if not dest_input or dest_input == "" then
        return
      end

      dest_input = dest_input:gsub("^['\"]", ""):gsub("['\"]$", "")

      local dest_path
      if vim.fn.fnamemodify(dest_input, ":p") == dest_input then
        dest_path = vim.fn.fnamemodify(dest_input, ":p")
        if dest_path:sub(1, #workspace) ~= workspace then
          vim.notify("epubedit: destination must be within workspace: " .. workspace, vim.log.levels.ERROR)
          return
        end
      else
        dest_path = opf_dir .. "/" .. dest_input
        dest_path = vim.fn.fnamemodify(dest_path, ":p")
      end

      local source_ext = source_path:match("%.([^%.]+)$")
      local dest_ext = dest_path:match("%.([^%.]+)$")
      if source_ext and dest_ext then
        source_ext = source_ext:lower()
        dest_ext = dest_ext:lower()
        if source_ext ~= dest_ext then
          vim.notify(
            string.format("epubedit: file extension mismatch: source .%s != destination .%s", source_ext, dest_ext),
            vim.log.levels.ERROR
          )
          return
        end
      end

      local function get_group_from_path(path)
        local relative = path:sub(#workspace + 1):gsub("^[/\\]+", "")
        local opf_relative = opf_dir:sub(#workspace + 1):gsub("^[/\\]+", "")
        if opf_relative ~= "" then
          local prefix = opf_relative .. "/"
          if relative:sub(1, #prefix) == prefix then
            relative = relative:sub(#prefix + 1)
          end
        end
        local segment = relative:match("^([^/\\]+)")
        if segment then
          segment = segment:lower()
          local known = { text = true, styles = true, images = true, fonts = true, audio = true, video = true, misc = true }
          if known[segment] then
            return segment
          end
        end
        return nil
      end

      local dest_group = get_group_from_path(dest_path)
      if dest_group then
        local expected_groups = {
          xhtml = "text",
          html = "text",
          htm = "text",
          css = "styles",
          jpg = "images",
          jpeg = "images",
          png = "images",
          gif = "images",
          svg = "images",
          webp = "images",
          ttf = "fonts",
          otf = "fonts",
          woff = "fonts",
          woff2 = "fonts",
          mp3 = "audio",
          mp4 = "video",
        }
        if dest_ext and expected_groups[dest_ext] and expected_groups[dest_ext] ~= dest_group then
          vim.notify(
            string.format(
              "epubedit: file type mismatch: .%s files should be in '%s' group, not '%s'",
              dest_ext,
              expected_groups[dest_ext],
              dest_group
            ),
            vim.log.levels.ERROR
          )
          return
        end
      end

      local dest_dir = vim.fn.fnamemodify(dest_path, ":h")
      if vim.fn.isdirectory(dest_dir) == 0 then
        vim.fn.mkdir(dest_dir, "p")
      end

      local ok, err = pcall(vim.loop.fs_copyfile, source_path, dest_path)
      if not ok then
        vim.notify("epubedit: failed to copy file: " .. tostring(err), vim.log.levels.ERROR)
        return
      end

      local add_to_spine = dest_group == "text"
      local ok_manifest = opf_manager.add_manifest_entry(session, dest_path, {
        group = dest_group,
        add_to_spine = add_to_spine,
      })
      if not ok_manifest then
        vim.notify("epubedit: failed to update content.opf for new file " .. dest_path, vim.log.levels.WARN)
        return
      end

      vim.notify(string.format("Added file: %s", dest_path), vim.log.levels.INFO)
    end)
  end)
end

-- ensure internal module has defaults even before setup() is called
module.configure(M.config)

return M
