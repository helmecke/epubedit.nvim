local uv = vim.loop
local fn = vim.fn

local path_sep = package.config:sub(1, 1)
local escaped_sep = path_sep == "\\" and "\\\\" or path_sep

local function join_paths(...)
  local segments = { ... }
  local parts = {}
  for _, segment in ipairs(segments) do
    if segment and segment ~= "" then
      table.insert(parts, segment)
    end
  end
  return table.concat(parts, path_sep)
end

local function normalize_path(path)
  if not path or path == "" then
    return path
  end
  local normalized = fn.fnamemodify(path, ":p")
  if normalized == path_sep then
    return normalized
  end
  if normalized:match("^%a:" .. escaped_sep .. "$") then
    return normalized
  end
  return normalized:gsub(escaped_sep .. "+$", "")
end

local function ensure_directory(path)
  if not path or path == "" then
    return nil, "invalid directory"
  end
  if fn.isdirectory(path) == 0 then
    local ok = fn.mkdir(path, "p")
    if ok ~= 1 then
      return nil, string.format("could not create directory: %s", path)
    end
  end
  return path
end

local function file_exists(path)
  return path and uv.fs_stat(path) ~= nil
end

local function read_file(path)
  if not file_exists(path) then
    return nil, string.format("file not found: %s", path)
  end
  local content = table.concat(fn.readfile(path), "\n")
  return content
end

local function unique_insert(list, value, seen)
  if not value or value == "" then
    return
  end
  seen = seen or {}
  if seen[value] then
    return
  end
  table.insert(list, value)
  seen[value] = true
end

local function run_command(cmd, args, opts)
  opts = opts or {}
  local stdout, stderr = {}, {}
  local job_id = fn.jobstart(vim.list_extend({ cmd }, args or {}), {
    cwd = opts.cwd,
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if not data then
        return
      end
      for _, line in ipairs(data) do
        if line ~= "" then
          table.insert(stdout, line)
        end
      end
    end,
    on_stderr = function(_, data)
      if not data then
        return
      end
      for _, line in ipairs(data) do
        if line ~= "" then
          table.insert(stderr, line)
        end
      end
    end,
  })

  if job_id <= 0 then
    return false, string.format("failed to start %s", cmd)
  end

  local status = fn.jobwait({ job_id }, opts.timeout or 60000)[1]
  if status == -1 then
    fn.jobstop(job_id)
    return false, string.format("%s timed out", cmd)
  end

  if status ~= 0 then
    local message = table.concat(stderr, "\n")
    if message == "" then
      message = string.format("%s failed with exit code %d", cmd, status)
    end
    return false, message
  end

  return true, table.concat(stdout, "\n")
end

local function delete_directory(path)
  if not file_exists(path) then
    return true
  end

  local handle = uv.fs_scandir(path)
  if handle then
    while true do
      local name, typ = uv.fs_scandir_next(handle)
      if not name then
        break
      end
      local target = join_paths(path, name)
      if typ == "directory" then
        delete_directory(target)
      else
        uv.fs_unlink(target)
      end
    end
  end

  uv.fs_rmdir(path)
  return true
end

local function relative_to(root, relative_path)
  if not relative_path or relative_path == "" then
    return nil
  end
  local sanitized = relative_path:gsub("/", path_sep)
  return normalize_path(join_paths(root, sanitized))
end

local M = {
  state = {
    sessions = {},
    current = nil,
  },
  config = {},
}

local function dependency_status(config)
  local zip_bin = config.zip_bin or "zip"
  local unzip_bin = config.unzip_bin or "unzip"
  local status = {
    zip = vim.fn.executable(zip_bin) == 1,
    unzip = vim.fn.executable(unzip_bin) == 1,
    zip_bin = zip_bin,
    unzip_bin = unzip_bin,
  }
  return status
end

local function ensure_dependencies(config)
  local status = dependency_status(config)
  local missing = {}

  if not status.zip then
    table.insert(missing, string.format("zip binary '%s' not found", status.zip_bin))
  end

  if not status.unzip then
    table.insert(missing, string.format("unzip binary '%s' not found", status.unzip_bin))
  end

  if #missing > 0 then
    return false, table.concat(missing, " | ")
  end

  return true
end

local function emit_event(pattern, payload)
  local ok, err = pcall(vim.api.nvim_exec_autocmds, "User", {
    pattern = pattern,
    modeline = false,
    data = payload,
  })
  if not ok then
    vim.schedule(function()
      vim.notify(string.format("epubedit: failed to emit %s: %s", pattern, err), vim.log.levels.DEBUG)
    end)
  end
end

local function create_workspace(config)
  if config.workspace_root and config.workspace_root ~= "" then
    local base, err = ensure_directory(config.workspace_root)
    if not base then
      return nil, err
    end
    local name = string.format("epubedit-%s", tostring(uv.now()))
    local path = normalize_path(join_paths(base, name))
    local ok = fn.mkdir(path, "p")
    if ok ~= 1 then
      return nil, string.format("failed to create workspace at %s", path)
    end
    return path
  end

  local template = join_paths(uv.os_tmpdir(), "epubedit-XXXXXX")
  local dir = uv.fs_mkdtemp(template)
  if not dir then
    return nil, "failed to create workspace directory"
  end
  return normalize_path(dir)
end

local function locate_opf(workspace)
  local container_path = join_paths(workspace, "META-INF", "container.xml")
  local content = read_file(container_path)
  if content then
    local relative_path = content:match('full%-path="([^"]+)"')
    if relative_path and relative_path ~= "" then
      local opf_path = relative_to(workspace, relative_path)
      if file_exists(opf_path) then
        return opf_path
      end
    end
  end

  local matches = fn.globpath(workspace, "**/*.opf", false, true)
  if #matches > 0 then
    return normalize_path(matches[1])
  end
end

local function list_assets(workspace, opf_path)
  local assets = {}
  local seen = {}

  if opf_path and file_exists(opf_path) then
    unique_insert(assets, normalize_path(opf_path), seen)
  end

  local root = workspace
  if opf_path then
    root = fn.fnamemodify(opf_path, ":h")
  end

  local function gather_from(base, extensions)
    for _, ext in ipairs(extensions) do
      local matches = fn.globpath(base, "**/*" .. ext, false, true)
      for _, match in ipairs(matches) do
        match = normalize_path(match)
        if match:sub(1, #workspace) == workspace then
          unique_insert(assets, match, seen)
        end
      end
    end
  end

  gather_from(root, { ".xhtml", ".html", ".htm" })
  gather_from(root, { ".css" })
  gather_from(root, { ".ncx" })

  gather_from(workspace, { ".xhtml", ".html", ".htm", ".css", ".ncx" })

  table.sort(assets)
  if opf_path then
    table.sort(assets, function(a, b)
      if a == opf_path then
        return true
      end
      if b == opf_path then
        return false
      end
      return a < b
    end)
  end

  return assets
end

local function unsaved_buffers(session)
  local dirty = {}
  for bufnr, info in pairs(session.buffers) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
      if vim.bo[bufnr].modified then
        table.insert(dirty, info.path)
      end
    end
  end
  return dirty
end

local function write_session_buffers(session)
  for bufnr, _ in pairs(session.buffers) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_is_loaded(bufnr) then
      vim.api.nvim_buf_call(bufnr, function()
        vim.cmd("silent keepalt write")
      end)
    end
  end
end

local function cleanup_session(session, config, opts)
  opts = opts or {}
  for bufnr, _ in pairs(session.buffers or {}) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      pcall(vim.api.nvim_buf_detach, bufnr)
    end
  end

  session.buffers = {}

  if session.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, session.augroup)
    session.augroup = nil
  end

  if session.prev_directory then
    vim.o.directory = session.prev_directory
    session.prev_directory = nil
  end

  if session.prev_cwd then
    pcall(vim.fn.chdir, session.prev_cwd)
    session.prev_cwd = nil
  end

  if not (config.preserve_workspace or opts.preserve_workspace) then
    delete_directory(session.workspace)
  end

  M.state.sessions[session.source] = nil
  if M.state.current == session then
    M.state.current = nil
  end

  emit_event("EpubEditSessionClosed", {
    source = session.source,
    workspace = session.workspace,
  })
end

function M.configure(config)
  M.config = config or {}
end

function M.open(path, config)
  config = config or M.config

  local ok, err = ensure_dependencies(config)
  if not ok then
    return false, err
  end

  if not file_exists(path) then
    return false, string.format("EPUB not found: %s", path)
  end

  if M.state.current then
    cleanup_session(M.state.current, M.config, { preserve_workspace = true })
  end

  local workspace, workspace_err = create_workspace(config)
  if not workspace then
    return false, workspace_err
  end

  local unzip_args = { "-qq", "-o", path, "-d", workspace }
  local unzip_ok, unzip_err = run_command(config.unzip_bin or "unzip", unzip_args, {})
  if not unzip_ok then
    delete_directory(workspace)
    return false, unzip_err
  end

  local opf_path = locate_opf(workspace)
  local assets = list_assets(workspace, opf_path)

  local session = {
    source = normalize_path(path),
    workspace = workspace,
    opf = opf_path,
    assets = assets,
    buffers = {},
    prev_directory = vim.o.directory,
    prev_cwd = vim.fn.getcwd(),
  }

  vim.o.directory = session.workspace
  pcall(vim.fn.chdir, session.workspace)

  M.state.sessions[session.source] = session
  M.state.current = session

  local function buffer_path(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if not name then
      return nil
    end
    return normalize_path(name)
  end

  local function path_in_workspace(path)
    if not path or path == "" then
      return false
    end
    return path:sub(1, #session.workspace) == session.workspace
  end

  session.augroup = vim.api.nvim_create_augroup(string.format("EpubEditSession_%d", uv.now()), { clear = true })
  vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile" }, {
    group = session.augroup,
    callback = function(args)
      if vim.api.nvim_buf_is_valid(args.buf) then
        local file = args.file ~= "" and args.file or buffer_path(args.buf)
        if path_in_workspace(normalize_path(file)) then
          vim.bo[args.buf].swapfile = false
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufReadPost", {
    group = session.augroup,
    callback = function(args)
      local buf = args.buf
      if not vim.api.nvim_buf_is_loaded(buf) then
        return
      end
      local path = buffer_path(buf)
      if path_in_workspace(path) then
        vim.bo[args.buf].swapfile = false
        session.buffers[buf] = { path = path }
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufUnload", {
    group = session.augroup,
    callback = function(args)
      local path = buffer_path(args.buf)
      if path_in_workspace(path) then
        session.buffers[args.buf] = nil
      end
    end,
  })

  local message = string.format("EPUB unpacked to %s", workspace)
  vim.notify(message, vim.log.levels.INFO)

  emit_event("EpubEditSessionOpen", {
    source = session.source,
    workspace = session.workspace,
    opf = session.opf,
  })

  return true
end

local function determine_output_path(session, target)
  if target and target ~= "" then
    return normalize_path(target)
  end
  return session.source
end

function M.save(target, config)
  config = config or M.config
  local session = M.state.current
  if not session then
    return false, "No active EPUB session. Run :EpubEditOpen first."
  end

  local ok, err = ensure_dependencies(config)
  if not ok then
    return false, err
  end

  local dirty = unsaved_buffers(session)
  if #dirty > 0 then
    return false, "Unsaved buffers: " .. table.concat(dirty, ", ")
  end

  local output_path = determine_output_path(session, target)

  if not target and config.prompt_overwrite then
    local choice = fn.confirm(string.format("Overwrite original EPUB at %s?", session.source), "&Yes\n&No", 2)
    if choice ~= 1 then
      return false, "Save aborted by user."
    end
  end

  local output_dir = fn.fnamemodify(output_path, ":h")
  local dir_ok, dir_err = ensure_directory(output_dir)
  if not dir_ok and dir_err then
    return false, dir_err
  end

  write_session_buffers(session)

  local tmp_output = output_path
  if output_path == session.source then
    tmp_output = output_path .. ".tmp"
  end

  if file_exists(tmp_output) then
    os.remove(tmp_output)
  end

  local zip_args = { "-X", "-q", "-r", tmp_output, "." }
  local zip_ok, zip_err = run_command(config.zip_bin or "zip", zip_args, { cwd = session.workspace })
  if not zip_ok then
    return false, zip_err
  end

  if tmp_output ~= output_path then
    os.remove(output_path)
    local ok_rename = os.rename(tmp_output, output_path)
    if not ok_rename then
      return false, string.format("failed to replace EPUB at %s", output_path)
    end
  end

  local message = string.format("EPUB saved to %s", output_path)
  vim.notify(message, vim.log.levels.INFO)

  emit_event("EpubEditSessionSaved", {
    source = session.source,
    workspace = session.workspace,
    output = output_path,
  })

  cleanup_session(session, config)

  return true
end

function M.cleanup(config)
  config = config or M.config
  local session = M.state.current
  if not session then
    return true
  end
  cleanup_session(session, config, { preserve_workspace = false })
  return true
end

function M.dependency_status()
  return dependency_status(M.config)
end

local function current_session()
  local session = M.state.current
  if not session then
    return nil, "No active EPUB session. Run :EpubEditOpen first."
  end
  return session
end

return M
