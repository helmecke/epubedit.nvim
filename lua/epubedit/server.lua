---@class epubedit.server
local M = {}

local state = {
  handle = nil, -- Process handle
  port = nil, -- Server port
  base_dir = nil, -- Directory being served
}

---Find an available port starting from the given port
---@param start_port number Starting port to check
---@return number|nil port Available port or nil if none found
local function find_available_port(start_port)
  start_port = start_port or 8080
  local max_attempts = 100

  for i = 0, max_attempts do
    local port = start_port + i
    local handle = vim.loop.new_tcp()
    if handle then
      -- Wrap bind in pcall to ensure handle is always closed even if bind throws
      local success, result = pcall(handle.bind, handle, "127.0.0.1", port)
      handle:close()
      if success and result then
        return port
      end
    end
  end

  return nil
end

---Check if Python is available
---@return boolean available
local function is_python_available()
  return vim.fn.executable("python3") == 1 or vim.fn.executable("python") == 1
end

---Get the Python command
---@return string python_cmd
local function get_python_cmd()
  if vim.fn.executable("python3") == 1 then
    return "python3"
  elseif vim.fn.executable("python") == 1 then
    return "python"
  end
  return "python3"
end

---Start HTTP server in the given directory
---@param base_dir string Directory to serve
---@return boolean success
---@return string|nil error
function M.start(base_dir)
  if state.handle then
    -- Check if it's serving the same directory
    if state.base_dir == base_dir then
      return true, nil -- Already running with correct directory
    else
      -- Stop the old server first
      M.stop()
      vim.loop.sleep(100) -- Give it time to release the port
    end
  end

  if not is_python_available() then
    return false, "Python is required for preview mode but not found in PATH"
  end

  -- Find available port
  local port = find_available_port(8080)
  if not port then
    return false, "Could not find an available port"
  end

  -- Start Python sync server
  local python_cmd = get_python_cmd()
  local script_path = vim.fn.stdpath("config") .. "/lua/epubedit/sync_server.py"

  if vim.fn.filereadable(script_path) == 0 then
    script_path = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h") .. "/sync_server.py"
  end

  local stdout = vim.loop.new_pipe(false)
  local stderr = vim.loop.new_pipe(false)

  local handle, pid
  handle, pid = vim.loop.spawn(python_cmd, {
    args = { script_path, tostring(port), base_dir },
    cwd = base_dir,
    stdio = { nil, stdout, stderr },
  }, function(code, signal)
    -- Server stopped
    if state.handle then
      state.handle:close()
      state.handle = nil
      state.port = nil
      state.base_dir = nil
    end
    if stdout and not stdout:is_closing() then
      stdout:close()
    end
    if stderr and not stderr:is_closing() then
      stderr:close()
    end
  end)

  if not handle then
    return false, "Failed to start HTTP server"
  end

  -- Read stderr for error detection
  local startup_error = nil
  if stderr then
    stderr:read_start(function(err, data)
      if data then
        if data:match("Address already in use") or data:match("OSError") then
          startup_error = "Port " .. port .. " is already in use"
          vim.schedule(function()
            vim.notify("Server startup failed: " .. startup_error, vim.log.levels.ERROR)
          end)
        elseif data:match("Error") or data:match("Traceback") then
          vim.schedule(function()
            vim.notify("Server error: " .. data, vim.log.levels.ERROR)
          end)
        end
      end
    end)
  end

  state.handle = handle
  state.port = port
  state.base_dir = base_dir

  -- Give server a moment to start and check for errors
  vim.defer_fn(function()
    if startup_error then
      vim.schedule(function()
        if state.handle then
          state.handle:kill("sigterm")
          state.handle = nil
          state.port = nil
          state.base_dir = nil
        end
        vim.notify("Server startup failed: " .. startup_error, vim.log.levels.ERROR)
      end)
    end
  end, 200)

  return true, nil
end

---Stop the HTTP server
function M.stop()
  if state.handle then
    state.handle:kill("sigterm")
    state.handle = nil
    state.port = nil
    state.base_dir = nil
  end
end

---Get the server port
---@return number|nil port Server port or nil if not running
function M.get_port()
  return state.port
end

---Check if server is running
---@return boolean running
function M.is_running()
  return state.handle ~= nil
end

---Get the base directory being served
---@return string|nil base_dir
function M.get_base_dir()
  return state.base_dir
end

---Notify the server of a file change to trigger browser reload
---@param filepath string Path to the changed file
---@return boolean success
function M.notify_change(filepath)
  if not state.port then
    return false
  end

  local url = string.format("http://127.0.0.1:%d/__epubedit_reload__", state.port)
  local payload = vim.fn.json_encode({ file = filepath })

  local handle = vim.loop.spawn("curl", {
    args = {
      "-X",
      "POST",
      "-H",
      "Content-Type: application/json",
      "-d",
      payload,
      "--max-time",
      "1",
      "-s",
      url,
    },
    detached = true,
    stdio = { nil, nil, nil },
  }, function() end)

  if handle then
    vim.loop.close(handle)
    return true
  end

  return false
end

---Check if running in WSL
---@return boolean is_wsl
local function is_wsl()
  local version_file = io.open("/proc/version", "r")
  if version_file then
    local version = version_file:read("*a")
    version_file:close()
    return version:lower():find("microsoft") ~= nil or version:lower():find("wsl") ~= nil
  end
  return false
end

---Detect OS and get the command to open a URL in the default browser
---@return string[]|nil command Browser command or nil if unsupported
local function get_browser_command()
  local os_name = vim.loop.os_uname().sysname

  if os_name == "Linux" then
    -- Check for WSL first
    if is_wsl() then
      -- Try wslview first (from wslu package)
      if vim.fn.executable("wslview") == 1 then
        return { "wslview" }
      end
      -- Fallback to PowerShell start command
      if vim.fn.executable("powershell.exe") == 1 then
        return { "powershell.exe", "-Command", "Start-Process" }
      end
      -- Last resort: cmd.exe
      if vim.fn.executable("cmd.exe") == 1 then
        return { "cmd.exe", "/c", "start", '""' } -- Empty title for start command
      end
    end

    -- Regular Linux
    if vim.fn.executable("xdg-open") == 1 then
      return { "xdg-open" }
    end
  elseif os_name == "Darwin" then
    return { "open" }
  elseif os_name:match("Windows") then
    return { "cmd.exe", "/c", "start", '""' }
  end

  return nil
end

---Open a URL in the default browser
---@param url string URL to open
---@return boolean success
---@return string|nil error
function M.open_browser(url)
  local cmd = get_browser_command()
  if not cmd then
    return false, "Could not detect browser command for your OS"
  end

  -- Build the full command with URL
  local full_cmd = vim.list_extend({}, cmd)
  table.insert(full_cmd, url)

  -- For cmd.exe start command, the URL needs to come after the empty title
  if full_cmd[1] == "cmd.exe" and full_cmd[3] == "start" then
    -- cmd.exe /c start "" <url>
    -- Args will be: ["/c", "start", '""', url]
  end

  local handle = vim.loop.spawn(full_cmd[1], {
    args = vim.list_slice(full_cmd, 2),
    detached = true,
  }, function() end)

  if not handle then
    return false, "Failed to launch browser"
  end

  -- Close handle immediately since we don't need to track it
  vim.loop.close(handle)

  return true, nil
end

return M
