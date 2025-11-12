local opf_parser = require("epubedit.parser.opf")
local ncx_parser = require("epubedit.parser.ncx")
local nav_parser = require("epubedit.parser.nav")
local path_util = require("epubedit.utils.path")
local io_util = require("epubedit.utils.io")

local M = {}

local path_sep = path_util.sep

local function normalize_path(path)
  if not path or path == "" then
    return nil
  end
  return path_util.normalize(path)
end

---Find the TOC file in the EPUB
---@param session table
---@return string|nil toc_path Path to the TOC file
---@return string|nil toc_type "ncx" or "nav"
---@return string|nil error message
local function find_toc_file(session)
  if not session or not session.opf then
    return nil, nil, "no active OPF"
  end

  local opf_path = session.opf
  local parsed, err = opf_parser.parse(opf_path)
  if not parsed then
    return nil, nil, err
  end

  local base_dir = parsed.base_dir or (vim.fn.fnamemodify(opf_path, ":h") .. path_sep)

  -- First, try to find EPUB 3 navigation document
  -- Look for manifest item with properties="nav"
  for _, item in pairs(parsed.manifest or {}) do
    if item.properties and item.properties:find("nav") then
      local nav_path = base_dir .. (item.href or "")
      nav_path = normalize_path(nav_path)
      if nav_path and vim.fn.filereadable(nav_path) == 1 then
        return nav_path, "nav", nil
      end
    end
  end

  -- Fall back to EPUB 2 NCX file
  -- Read the spine toc attribute from OPF file directly
  local opf_content = io_util.read_file(opf_path)
  if opf_content then
    local toc_id = opf_content:match('<spine[^>]*toc="([^"]+)"')
    if toc_id then
      local item = parsed.manifest[toc_id]
      if item and item.href then
        local ncx_path = base_dir .. item.href
        ncx_path = normalize_path(ncx_path)
        if ncx_path and vim.fn.filereadable(ncx_path) == 1 then
          return ncx_path, "ncx", nil
        end
      end
    end
  end

  -- Last resort: look for any NCX file
  for _, item in pairs(parsed.manifest or {}) do
    if item.media_type == "application/x-dtbncx+xml" then
      local ncx_path = base_dir .. (item.href or "")
      ncx_path = normalize_path(ncx_path)
      if ncx_path and vim.fn.filereadable(ncx_path) == 1 then
        return ncx_path, "ncx", nil
      end
    end
  end

  return nil, nil, "No TOC file found (neither NCX nor nav document)"
end

---Get TOC entries from the EPUB
---@param session table
---@return table|nil entries TOC entries
---@return string|nil toc_type "ncx" or "nav"
---@return string|nil error message
function M.get_toc(session)
  local toc_path, toc_type, err = find_toc_file(session)
  if not toc_path then
    return nil, nil, err or "TOC file not found"
  end

  local data, parse_err
  if toc_type == "ncx" then
    data, parse_err = ncx_parser.parse(toc_path)
  elseif toc_type == "nav" then
    data, parse_err = nav_parser.parse(toc_path)
  else
    return nil, nil, "Unknown TOC type: " .. tostring(toc_type)
  end

  if not data then
    return nil, nil, parse_err
  end

  return data.entries, toc_type, nil
end

---Set TOC entries in the EPUB
---@param session table
---@param entries table TOC entries
---@return boolean success
---@return string|nil error message
function M.set_toc(session, entries)
  local toc_path, toc_type, err = find_toc_file(session)
  if not toc_path then
    return false, err or "TOC file not found"
  end

  -- First read existing data to preserve metadata
  local existing_data, parse_err
  if toc_type == "ncx" then
    existing_data, parse_err = ncx_parser.parse(toc_path)
  elseif toc_type == "nav" then
    existing_data, parse_err = nav_parser.parse(toc_path)
  end

  if not existing_data then
    return false, parse_err or "Failed to parse existing TOC"
  end

  -- Update entries while preserving other data
  existing_data.entries = entries

  -- Write back
  local ok, write_err
  if toc_type == "ncx" then
    ok, write_err = ncx_parser.write(toc_path, existing_data)
  elseif toc_type == "nav" then
    ok, write_err = nav_parser.write(toc_path, existing_data)
  else
    return false, "Unknown TOC type: " .. tostring(toc_type)
  end

  if not ok then
    return false, write_err
  end

  return true
end

---Flatten TOC entries for display (converts hierarchical to flat list with indentation)
---@param entries table TOC entries
---@param result table|nil Accumulator for recursion
---@return table flat list of entries with depth indicators
function M.flatten_entries(entries, result)
  result = result or {}

  for _, entry in ipairs(entries) do
    table.insert(result, {
      label = entry.label,
      src = entry.src,
      depth = entry.depth or 0,
      id = entry.id,
      play_order = entry.play_order,
    })

    if entry.children and #entry.children > 0 then
      M.flatten_entries(entry.children, result)
    end
  end

  return result
end

---Unflatten TOC entries (converts flat list with depth to hierarchical)
---@param flat_entries table Flat list of entries with depth
---@return table hierarchical entries
function M.unflatten_entries(flat_entries)
  local root = {}
  local stack = { { children = root, depth = -1 } }

  for _, entry in ipairs(flat_entries) do
    local depth = entry.depth or 0

    -- Pop stack until we find the parent
    while #stack > 0 and stack[#stack].depth >= depth do
      table.remove(stack)
    end

    local parent = stack[#stack]

    local new_entry = {
      label = entry.label,
      src = entry.src,
      depth = depth,
      id = entry.id,
      play_order = entry.play_order,
      children = {},
    }

    table.insert(parent.children, new_entry)
    table.insert(stack, new_entry)
  end

  return root
end

return M
