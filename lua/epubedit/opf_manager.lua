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

local media_by_ext = {
  css = "text/css",
  xhtml = "application/xhtml+xml",
  html = "application/xhtml+xml",
  htm = "application/xhtml+xml",
  xml = "application/xml",
  ncx = "application/x-dtbncx+xml",
  svg = "image/svg+xml",
  png = "image/png",
  jpg = "image/jpeg",
  jpeg = "image/jpeg",
  gif = "image/gif",
  bmp = "image/bmp",
  webp = "image/webp",
  mp3 = "audio/mpeg",
  mp4 = "video/mp4",
  m4a = "audio/mp4",
  ogg = "audio/ogg",
  wav = "audio/wav",
}

local function infer_media_type(path, opts)
  local group = opts and opts.group
  if group == "text" then
    return "application/xhtml+xml"
  end
  if group == "styles" then
    return "text/css"
  end
  local ext = path and path:match("%.([^%.]+)$")
  if ext then
    ext = ext:lower()
    if media_by_ext[ext] then
      return media_by_ext[ext]
    end
  end
  return "application/octet-stream"
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

local function unique_id(existing, base)
  local candidate = base
  local counter = 1
  while existing[candidate] do
    candidate = string.format("%s-%d", base, counter)
    counter = counter + 1
  end
  return candidate
end

local function sanitize_id(href, group)
  local stem = fn.fnamemodify(href, ":t:r")
  stem = (stem ~= "" and stem or "item"):gsub("[^%w_-]", "-")
  if group and group ~= "" then
    stem = group .. "-" .. stem
  end
  return "epubedit-" .. stem
end

function M.add_manifest_entry(session, file_path, opts)
  if not session or not session.opf then
    return false, "no active OPF"
  end
  local opf_path = session.opf
  local parsed, err = opf_parser.parse(opf_path)
  if not parsed then
    return false, err
  end
  local normalized = normalize_path(file_path)
  if not normalized then
    return false, "invalid path"
  end

  local base_dir = parsed.base_dir or (fn.fnamemodify(opf_path, ":h") .. path_sep)
  local href = rel_href(base_dir, normalized)
  local manifest = parsed.manifest or {}
  local seen_ids = {}
  for key, item in pairs(manifest) do
    if type(key) == "string" then
      seen_ids[key] = true
    end
    if type(item) == "table" then
      if item.id then
        seen_ids[item.id] = true
      end
      if item.href == href then
        return true, href
      end
    end
  end

  local media_type = infer_media_type(file_path, opts)
  local add_to_spine = opts and opts.add_to_spine
  local desired_id = sanitize_id(href, opts and opts.group)
  local final_id = unique_id(seen_ids, desired_id)

  local lines = fn.readfile(opf_path)
  local manifest_close
  for i, line in ipairs(lines) do
    if line:find("</manifest") then
      manifest_close = i
      break
    end
  end
  if not manifest_close then
    return false, "manifest end not found"
  end
  local indent = "    "
  local entry = string.format('%s<item id="%s" href="%s" media-type="%s"/>', indent, final_id, href, media_type)
  table.insert(lines, manifest_close, entry)

  if add_to_spine then
    local spine_close
    for i, line in ipairs(lines) do
      if line:find("</spine") then
        spine_close = i
        break
      end
    end
    if spine_close then
      local spine_entry = string.format('%s<itemref idref="%s"/>', indent, final_id)
      table.insert(lines, spine_close, spine_entry)
    end
  end

  local ok_write, write_err = write_file(opf_path, table.concat(lines, "\n"))
  if not ok_write then
    return false, write_err
  end
  return true, href
end

return M
