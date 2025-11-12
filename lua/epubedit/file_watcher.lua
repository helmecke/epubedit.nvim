---@class epubedit.file_watcher
local M = {}

local state = {
  handle = nil,
  debounce_timer = nil,
  directory = nil,
  callback = nil,
  opts = {},
}

local DEFAULT_OPTS = {
  debounce = 300,
  file_patterns = { "%.xhtml$", "%.html$", "%.htm$", "%.css$" },
}

---Check if file matches watched patterns
---@param filename string
---@param patterns table
---@return boolean
local function matches_pattern(filename, patterns)
  for _, pattern in ipairs(patterns) do
    if filename:match(pattern) then
      return true
    end
  end
  return false
end

---Debounced callback invocation
---@param filepath string
local function trigger_callback(filepath)
  if state.debounce_timer then
    state.debounce_timer:stop()
    state.debounce_timer:close()
    state.debounce_timer = nil
  end

  state.debounce_timer = vim.loop.new_timer()
  state.debounce_timer:start(
    state.opts.debounce,
    0,
    vim.schedule_wrap(function()
      if state.callback then
        state.callback(filepath)
      end
      if state.debounce_timer then
        state.debounce_timer:close()
        state.debounce_timer = nil
      end
    end)
  )
end

---Start watching a directory for file changes
---@param directory string Directory to watch
---@param callback function Callback function(filepath) called on file changes
---@param opts table|nil Options: debounce (ms), file_patterns (table of patterns)
---@return boolean success
---@return string|nil error
function M.start(directory, callback, opts)
  if state.handle then
    return false, "File watcher already running"
  end

  if not directory or directory == "" then
    return false, "Invalid directory"
  end

  if not callback or type(callback) ~= "function" then
    return false, "Invalid callback function"
  end

  opts = opts or {}
  state.opts = vim.tbl_deep_extend("force", DEFAULT_OPTS, opts)
  state.directory = directory
  state.callback = callback

  state.handle = vim.loop.new_fs_event()
  if not state.handle then
    return false, "Failed to create file system watcher"
  end

  local function on_change(err, filename, events)
    if err then
      vim.notify("File watcher error: " .. tostring(err), vim.log.levels.WARN)
      return
    end

    if filename and matches_pattern(filename, state.opts.file_patterns) then
      local filepath = directory .. "/" .. filename
      trigger_callback(filepath)
    end
  end

  local ok, err = state.handle:start(directory, { recursive = true }, on_change)
  if not ok then
    state.handle:close()
    state.handle = nil
    state.directory = nil
    state.callback = nil
    return false, "Failed to start watching directory: " .. tostring(err)
  end

  return true, nil
end

---Stop the file watcher
function M.stop()
  if state.debounce_timer then
    state.debounce_timer:stop()
    state.debounce_timer:close()
    state.debounce_timer = nil
  end

  if state.handle then
    state.handle:stop()
    state.handle:close()
    state.handle = nil
  end

  state.directory = nil
  state.callback = nil
  state.opts = {}
end

---Check if file watcher is running
---@return boolean
function M.is_running()
  return state.handle ~= nil
end

---Get the directory being watched
---@return string|nil
function M.get_directory()
  return state.directory
end

return M
