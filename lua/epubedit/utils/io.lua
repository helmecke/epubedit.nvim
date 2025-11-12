local fn = vim.fn
local uv = vim.loop

local M = {}

function M.file_exists(path)
  return path and uv.fs_stat(path) ~= nil
end

function M.read_file(path)
  if not M.file_exists(path) then
    return nil, string.format("file not found: %s", path)
  end
  local content = table.concat(fn.readfile(path), "\n")
  return content
end

function M.write_file(path, content)
  local file, err = io.open(path, "w")
  if not file then
    return false, err
  end
  file:write(content)
  file:close()
  return true
end

return M
