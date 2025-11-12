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

local function parse_navpoint(navpoint, depth)
  depth = depth or 0
  local nav_label = find_child(navpoint, "navLabel")
  local content = find_child(navpoint, "content")

  if not nav_label or not content then
    return nil
  end

  local text_node = find_child(nav_label, "text")
  local label = text_node and text_content(text_node) or ""

  local entry = {
    id = navpoint._attr and navpoint._attr.id or "",
    play_order = navpoint._attr and navpoint._attr.playOrder or "",
    label = label,
    src = content._attr and content._attr.src or "",
    depth = depth,
    children = {},
  }

  for _, child in ipairs(flatten_children(navpoint)) do
    if child._name == "navPoint" then
      local child_entry = parse_navpoint(child, depth + 1)
      if child_entry then
        table.insert(entry.children, child_entry)
      end
    end
  end

  return entry
end

---Parse NCX file and return TOC structure
---@param ncx_path string Path to the NCX file
---@return table|nil, string|nil TOC entries or nil with error message
function M.parse(ncx_path)
  local file = io.open(ncx_path, "r")
  if not file then
    return nil, string.format("NCX file not found: %s", ncx_path)
  end
  local content = file:read("*a")
  file:close()

  local handler = TreeHandler:new()
  local parser = xml2lua.parser(handler)

  local ok, err = pcall(parser.parse, content)
  if not ok then
    return nil, "Failed to parse NCX: " .. tostring(err)
  end

  local root = handler.root
  local ncx_node = find_child(root, "ncx")
  if not ncx_node then
    return nil, "Invalid NCX: missing <ncx> root element"
  end

  local nav_map = find_child(ncx_node, "navMap")
  if not nav_map then
    return nil, "Invalid NCX: missing <navMap>"
  end

  local entries = {}
  for _, child in ipairs(flatten_children(nav_map)) do
    if child._name == "navPoint" then
      local entry = parse_navpoint(child, 0)
      if entry then
        table.insert(entries, entry)
      end
    end
  end

  -- Also parse docTitle if present
  local doc_title_node = find_child(ncx_node, "docTitle")
  local doc_title = ""
  if doc_title_node then
    local text_node = find_child(doc_title_node, "text")
    if text_node then
      doc_title = text_content(text_node)
    end
  end

  -- Parse head metadata
  local head_node = find_child(ncx_node, "head")
  local uid = ""
  if head_node then
    for _, meta in ipairs(flatten_children(head_node)) do
      if meta._name == "meta" and meta._attr then
        if meta._attr.name == "dtb:uid" then
          uid = meta._attr.content or ""
        end
      end
    end
  end

  return {
    entries = entries,
    doc_title = doc_title,
    uid = uid,
  }
end

local function write_navpoint(writer, entry, play_order_counter)
  writer:startElement("navPoint")
  writer:writeAttribute("id", entry.id or ("navPoint-" .. play_order_counter[1]))
  writer:writeAttribute("playOrder", tostring(play_order_counter[1]))

  writer:startElement("navLabel")
  writer:startElement("text")
  writer:text(entry.label or "")
  writer:endElement() -- text
  writer:endElement() -- navLabel

  writer:startElement("content")
  writer:writeAttribute("src", entry.src or "")
  writer:endElement() -- content

  play_order_counter[1] = play_order_counter[1] + 1

  -- Write children recursively
  for _, child in ipairs(entry.children or {}) do
    write_navpoint(writer, child, play_order_counter)
  end

  writer:endElement() -- navPoint
end

---Write TOC entries back to NCX file
---@param ncx_path string Path to the NCX file
---@param data table TOC data with entries, doc_title, uid
---@return boolean, string|nil Success status and error message if any
function M.write(ncx_path, data)
  local writer = XmlWriter:new()

  writer:writeProcessingInstruction("xml", 'version="1.0" encoding="UTF-8"')
  writer:startElement("ncx")
  writer:writeAttribute("xmlns", "http://www.daisy.org/z3986/2005/ncx/")
  writer:writeAttribute("version", "2005-1")

  -- Write head
  writer:startElement("head")
  writer:startElement("meta")
  writer:writeAttribute("name", "dtb:uid")
  writer:writeAttribute("content", data.uid or "")
  writer:endElement() -- meta
  writer:endElement() -- head

  -- Write docTitle
  writer:startElement("docTitle")
  writer:startElement("text")
  writer:text(data.doc_title or "")
  writer:endElement() -- text
  writer:endElement() -- docTitle

  -- Write navMap
  writer:startElement("navMap")

  local play_order_counter = { 1 } -- Use table to pass by reference
  for _, entry in ipairs(data.entries or {}) do
    write_navpoint(writer, entry, play_order_counter)
  end

  writer:endElement() -- navMap
  writer:endElement() -- ncx

  local xml_content = writer:toString()

  local file, err = io.open(ncx_path, "w")
  if not file then
    return false, "Failed to open NCX file for writing: " .. tostring(err)
  end

  file:write(xml_content)
  file:close()

  return true
end

return M
