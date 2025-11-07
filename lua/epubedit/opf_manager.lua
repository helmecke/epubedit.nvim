local fn = vim.fn
local opf_parser = require("epubedit.parser.opf")

local path_sep = package.config:sub(1, 1)

local function normalize_path(path)
  if not path or path == "" then
    return nil
  end
  return fn.fnamemodify(path, ":p")
end

local function read_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil, string.format("failed to read %s", path)
  end
  local content = file:read("*a")
  file:close()
  return content
end

local function write_file(path, content)
  local file, err = io.open(path, "w")
  if not file then
    return false, err
  end
  file:write(content)
  file:close()
  return true
end

local function normalize_href(path)
  return (path or ""):gsub("\\", "/")
end

local function rel_href(base_dir, target)
  local normalized_base = normalize_path(base_dir) or base_dir
  local normalized_target = normalize_path(target)
  if not normalized_target then
    return ""
  end
  if normalized_base:sub(-1) ~= path_sep then
    normalized_base = normalized_base .. path_sep
  end
  local rel
  if normalized_target:sub(1, #normalized_base) == normalized_base then
    rel = normalized_target:sub(#normalized_base + 1)
  else
    rel = fn.fnamemodify(target, ":t")
  end
  rel = rel:gsub("^%./", "")
  return normalize_href(rel)
end

local function resolve_item_path(base_dir, item)
  if not item or not item.href then
    return nil
  end
  local full = base_dir .. item.href
  return normalize_path(full)
end

local M = {}

---@param session table
---@param old_path string
---@param new_path string
---@return boolean updated
---@return string? new_href_or_err
function M.rename_manifest_entry(session, old_path, new_path)
  if not session or not session.opf then
    return false, "no active OPF"
  end
  local opf_path = session.opf
  local parsed, err = opf_parser.parse(opf_path)
  if not parsed then
    return false, err
  end

  local normalized_old = normalize_path(old_path)
  local normalized_new = normalize_path(new_path)
  if not normalized_old or not normalized_new then
    return false, "invalid paths"
  end

  local base_dir = parsed.base_dir or (fn.fnamemodify(opf_path, ":h") .. path_sep)
  local target_item = nil
  for _, item in pairs(parsed.manifest or {}) do
    if resolve_item_path(base_dir, item) == normalized_old then
      target_item = item
      break
    end
  end

  if not target_item or not target_item.href then
    return false, "asset not registered in OPF"
  end

  local new_href = rel_href(base_dir, normalized_new)
  if new_href == target_item.href then
    return true, new_href
  end

  local content, read_err = read_file(opf_path)
  if not content then
    return false, read_err
  end

  local escaped_old = vim.pesc(target_item.href)
  local updated, replacements =
    content:gsub('href="' .. escaped_old .. '"', 'href="' .. new_href .. '"', 1)
  if replacements == 0 then
    return false, "href not found in OPF"
  end

  local ok_write, write_err = write_file(opf_path, updated)
  if not ok_write then
    return false, write_err
  end

  return true, new_href
end

return M
