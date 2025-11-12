local fn = vim.fn

local M = {}

M.sep = package.config:sub(1, 1)
M.escaped_sep = M.sep == "\\" and "\\\\" or M.sep

function M.normalize(path)
  if not path or path == "" then
    return path
  end
  local normalized = fn.fnamemodify(path, ":p")
  if normalized == M.sep then
    return normalized
  end
  if normalized:match("^%a:" .. M.escaped_sep .. "$") then
    return normalized
  end
  return normalized:gsub(M.escaped_sep .. "+$", "")
end

function M.join(...)
  local segments = { ... }
  local parts = {}
  for _, segment in ipairs(segments) do
    if segment and segment ~= "" then
      table.insert(parts, segment)
    end
  end
  return table.concat(parts, M.sep)
end

function M.relative_to(root, relative_path)
  if not relative_path or relative_path == "" then
    return nil
  end
  local sanitized = relative_path:gsub("/", M.sep)
  return M.normalize(M.join(root, sanitized))
end

return M
