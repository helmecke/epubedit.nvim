local xml2lua = require("epubedit.vendor.xml2lua")
local TreeHandler = require("epubedit.vendor.xmlhandler_tree")
local opf_parser = require("epubedit.parser.opf")
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

---Extract text content from an XML node
local function text_content(node)
  if not node then
    return ""
  end

  local parts = {}
  for _, child in ipairs(node._children or {}) do
    if type(child) == "string" then
      table.insert(parts, child)
    elseif type(child) == "table" then
      table.insert(parts, text_content(child))
    end
  end

  return table.concat(parts, " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

---Find all heading nodes in an HTML document
local function find_headings(node, headings, file_href)
  headings = headings or {}

  if not node or type(node) ~= "table" then
    return headings
  end

  -- Check if this node is a heading (h1-h6)
  local heading_level = node._name and node._name:match("^h([1-6])$")
  if heading_level then
    local level = tonumber(heading_level)
    local text = text_content(node)
    local id = node._attr and node._attr.id

    -- Generate an ID if missing
    if not id or id == "" then
      id = "heading-" .. #headings
    end

    table.insert(headings, {
      level = level,
      text = text,
      id = id,
      file = file_href,
    })
  end

  -- Recursively process children
  for _, child in ipairs(node._children or {}) do
    if type(child) == "table" then
      find_headings(child, headings, file_href)
    end
  end

  return headings
end

---Parse HTML file and extract headings
---@param file_path string Path to the HTML file
---@param file_href string Relative href for the file
---@return table|nil headings List of headings
---@return string|nil error message
local function parse_html_headings(file_path, file_href)
  local content = io_util.read_file(file_path)
  if not content then
    return nil, "Failed to read file: " .. file_path
  end

  -- Try to parse as XML/XHTML
  local handler = TreeHandler:new()
  local parser = xml2lua.parser(handler)

  local ok, err = pcall(parser.parse, content)
  if not ok then
    -- If XML parsing fails, try simple pattern matching
    return parse_html_headings_simple(content, file_href)
  end

  local headings = {}
  find_headings(handler.root, headings, file_href)

  return headings
end

---Simple pattern-based heading extraction (fallback)
---@param content string HTML content
---@param file_href string Relative href for the file
---@return table headings List of headings
local function parse_html_headings_simple(content, file_href)
  local headings = {}
  local counter = 0

  for level_str, attrs, text in content:gmatch("<h([1-6])([^>]*)>(.-)</h%1>") do
    local level = tonumber(level_str)
    local id = attrs:match('id="([^"]+)"') or attrs:match("id='([^']+)'")

    if not id or id == "" then
      counter = counter + 1
      id = "heading-" .. counter
    end

    -- Strip HTML tags from text
    local clean_text = text:gsub("<[^>]+>", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")

    table.insert(headings, {
      level = level,
      text = clean_text,
      id = id,
      file = file_href,
    })
  end

  return headings
end

local function is_nav_file(href, manifest)
  for _, item in pairs(manifest or {}) do
    if item.href == href and item.properties and item.properties:find("nav") then
      return true
    end
  end
  return false
end

---Generate TOC entries from spine documents
---@param session table EPUB session
---@param opts table|nil Options: max_depth (default 6), min_level (default 1)
---@return table|nil entries TOC entries
---@return string|nil error message
function M.generate_from_headings(session, opts)
  opts = opts or {}
  local max_depth = opts.max_depth or 6
  local min_level = opts.min_level or 1

  if not session or not session.opf then
    return nil, "No active OPF"
  end

  local opf_path = session.opf
  local parsed, err = opf_parser.parse(opf_path)
  if not parsed then
    return nil, err
  end

  local base_dir = parsed.base_dir or (vim.fn.fnamemodify(opf_path, ":h") .. path_sep)
  local all_headings = {}

  -- Process each spine item
  for _, spine_item in ipairs(parsed.spine or {}) do
    if is_nav_file(spine_item.href, parsed.manifest) then
      goto continue
    end

    local file_path = base_dir .. spine_item.href
    file_path = normalize_path(file_path)

    if file_path and vim.fn.filereadable(file_path) == 1 then
      local headings, parse_err = parse_html_headings(file_path, spine_item.href)
      if headings then
        for _, heading in ipairs(headings) do
          if heading.level >= min_level and heading.level <= (min_level + max_depth - 1) then
            table.insert(all_headings, heading)
          end
        end
      else
        vim.notify("Failed to parse " .. spine_item.href .. ": " .. tostring(parse_err), vim.log.levels.WARN)
      end
    end

    ::continue::
  end

  if #all_headings == 0 then
    return nil, "No headings found in spine documents"
  end

  -- Convert flat headings to hierarchical TOC entries
  local entries = {}
  local stack = { { children = entries, level = 0 } }

  for _, heading in ipairs(all_headings) do
    -- Adjust depth relative to min_level
    local depth = heading.level - min_level

    -- Pop stack to find parent
    while #stack > 0 and stack[#stack].level >= heading.level do
      table.remove(stack)
    end

    local parent = stack[#stack]

    local entry = {
      label = heading.text,
      src = heading.file .. "#" .. heading.id,
      depth = depth,
      level = heading.level,
      children = {},
    }

    table.insert(parent.children, entry)
    table.insert(stack, entry)
  end

  return entries
end

---Add missing IDs to headings in HTML files
---@param session table EPUB session
---@return boolean success
---@return string|nil error message
function M.add_heading_ids(session)
  if not session or not session.opf then
    return false, "No active OPF"
  end

  local opf_path = session.opf
  local parsed, err = opf_parser.parse(opf_path)
  if not parsed then
    return false, err
  end

  local base_dir = parsed.base_dir or (vim.fn.fnamemodify(opf_path, ":h") .. path_sep)
  local modified_count = 0

  -- Process each spine item
  for _, spine_item in ipairs(parsed.spine or {}) do
    if is_nav_file(spine_item.href, parsed.manifest) then
      goto continue
    end

    local file_path = base_dir .. spine_item.href
    file_path = normalize_path(file_path)

    if file_path and vim.fn.filereadable(file_path) == 1 then
      local content = io_util.read_file(file_path)
      if content then
        local modified = false
        local counter = 0

        -- Add IDs to headings without them
        local updated_content = content:gsub("(<h[1-6])([^>]*)(>)", function(tag, attrs, close)
          if not attrs:match('id="') and not attrs:match("id='") then
            counter = counter + 1
            local id = "heading-" .. counter
            modified = true
            return tag .. ' id="' .. id .. '"' .. attrs .. close
          end
          return tag .. attrs .. close
        end)

        if modified then
          local ok, write_err = io_util.write_file(file_path, updated_content)
          if ok then
            modified_count = modified_count + 1
          else
            vim.notify("Failed to write " .. spine_item.href .. ": " .. tostring(write_err), vim.log.levels.WARN)
          end
        end
      end
    end

    ::continue::
  end

  if modified_count > 0 then
    vim.notify(string.format("Added IDs to headings in %d file(s)", modified_count), vim.log.levels.INFO)
  end

  return true
end

return M
