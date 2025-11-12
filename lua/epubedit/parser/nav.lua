local xml2lua = require("epubedit.vendor.xml2lua")
local TreeHandler = require("epubedit.vendor.xmlhandler_tree")
local XmlWriter = require("epubedit.vendor.xmlwriter")

local M = {}

local function find_child(node, name)
  for _, child in ipairs(node._children or {}) do
    if type(child) == "table" and child._name == name then
      return child
    end
  end
end

local function flatten_children(node, acc)
  acc = acc or {}
  for _, child in ipairs(node._children or {}) do
    if type(child) == "table" then
      table.insert(acc, child)
    end
  end
  return acc
end

local function text_content(node)
  local parts = {}
  for _, child in ipairs(node._children or {}) do
    if type(child) == "string" then
      table.insert(parts, child)
    end
  end
  return table.concat(parts, " ")
end

local function parse_ol(ol, depth)
  depth = depth or 0
  local entries = {}

  for _, li in ipairs(flatten_children(ol)) do
    if li._name == "li" then
      -- Find the <a> element for the label and href
      local a = find_child(li, "a")
      if a then
        local label = text_content(a)
        local href = a._attr and a._attr.href or ""

        local entry = {
          label = label,
          src = href,
          depth = depth,
          children = {},
        }

        -- Check for nested <ol> (sub-entries)
        local nested_ol = find_child(li, "ol")
        if nested_ol then
          entry.children = parse_ol(nested_ol, depth + 1)
        end

        table.insert(entries, entry)
      end
    end
  end

  return entries
end

---Parse EPUB 3 navigation document (nav.xhtml)
---@param nav_path string Path to the nav.xhtml file
---@return table|nil, string|nil TOC entries or nil with error message
function M.parse(nav_path)
  local file = io.open(nav_path, "r")
  if not file then
    return nil, string.format("Nav file not found: %s", nav_path)
  end
  local content = file:read("*a")
  file:close()

  local handler = TreeHandler:new()
  local parser = xml2lua.parser(handler)

  local ok, err = pcall(parser.parse, content)
  if not ok then
    return nil, "Failed to parse nav document: " .. tostring(err)
  end

  local root = handler.root
  local html = find_child(root, "html")
  if not html then
    return nil, "Invalid nav document: missing <html> root element"
  end

  local body = find_child(html, "body")
  if not body then
    return nil, "Invalid nav document: missing <body>"
  end

  -- Find the <nav epub:type="toc"> element
  local toc_nav = nil
  for _, child in ipairs(flatten_children(body)) do
    if child._name == "nav" then
      local epub_type = child._attr and child._attr["epub:type"]
      if epub_type == "toc" then
        toc_nav = child
        break
      end
    end
  end

  if not toc_nav then
    return nil, 'Invalid nav document: missing <nav epub:type="toc">'
  end

  -- Find the <ol> element inside the nav
  local ol = find_child(toc_nav, "ol")
  if not ol then
    return nil, "Invalid nav document: missing <ol> in TOC nav"
  end

  local entries = parse_ol(ol, 0)

  -- Also try to get the nav title
  local nav_title = ""
  local h1 = find_child(toc_nav, "h1")
  if h1 then
    nav_title = text_content(h1)
  end

  return {
    entries = entries,
    nav_title = nav_title,
  }
end

local function write_ol(writer, entries, depth)
  writer:startElement("ol")

  for _, entry in ipairs(entries) do
    writer:startElement("li")

    writer:startElement("a")
    writer:writeAttribute("href", entry.src or "")
    writer:text(entry.label or "")
    writer:endElement() -- a

    -- Write children if present
    if entry.children and #entry.children > 0 then
      write_ol(writer, entry.children, depth + 1)
    end

    writer:endElement() -- li
  end

  writer:endElement() -- ol
end

---Write TOC entries back to EPUB 3 nav document
---@param nav_path string Path to the nav.xhtml file
---@param data table TOC data with entries and nav_title
---@return boolean, string|nil Success status and error message if any
function M.write(nav_path, data)
  local writer = XmlWriter:new()

  writer:writeProcessingInstruction("xml", 'version="1.0" encoding="UTF-8"')
  writer:startElement("html")
  writer:writeAttribute("xmlns", "http://www.w3.org/1999/xhtml")
  writer:writeAttribute("xmlns:epub", "http://www.idpf.org/2007/ops")

  writer:startElement("head")
  writer:startElement("title")
  writer:text("Table of Contents")
  writer:endElement() -- title
  writer:endElement() -- head

  writer:startElement("body")
  writer:startElement("nav")
  writer:writeAttribute("epub:type", "toc")

  writer:startElement("h1")
  writer:text(data.nav_title or "Contents")
  writer:endElement() -- h1

  write_ol(writer, data.entries or {}, 0)

  writer:endElement() -- nav
  writer:endElement() -- body
  writer:endElement() -- html

  local xml_content = writer:toString()

  local file, err = io.open(nav_path, "w")
  if not file then
    return false, "Failed to open nav file for writing: " .. tostring(err)
  end

  file:write(xml_content)
  file:close()

  return true
end

return M
