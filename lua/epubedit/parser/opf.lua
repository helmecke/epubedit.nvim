local xml2lua = require("epubedit.vendor.xml2lua")
local TreeHandler = require("epubedit.vendor.xmlhandler_tree")

local M = {}

local path_sep = package.config:sub(1, 1)

local function normalize_dir(path)
  if not path or path == "" then
    return ""
  end
  if path:sub(-1) == path_sep then
    return path
  end
  return path .. path_sep
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

local function find_child(node, name)
  for _, child in ipairs(node._children or {}) do
    if type(child) == "table" and child._name == name then
      return child
    end
  end
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

---@param opf_path string
---@return table|nil, string|nil
function M.parse(opf_path)
  local file = io.open(opf_path, "r")
  if not file then
    return nil, string.format("OPF not found: %s", opf_path)
  end
  local content = file:read("*a")
  file:close()

  local handler = TreeHandler:new()
  local parser = xml2lua.parser(handler)

  local ok, err = pcall(parser.parse, content)
  if not ok then
    return nil, err
  end

  local root = handler.root
  local package_node = find_child(root, "package")
  if not package_node then
    return nil, "Invalid OPF: missing <package>"
  end

  local metadata_node = find_child(package_node, "metadata") or {}
  local manifest = find_child(package_node, "manifest") or {}
  local spine = find_child(package_node, "spine") or {}

  local manifest_items = {}
  for _, item in ipairs(flatten_children(manifest)) do
    if item._attr and item._attr.id then
      manifest_items[item._attr.id] = {
        id = item._attr.id,
        href = item._attr.href,
        media_type = item._attr["media-type"],
        properties = item._attr.properties,
      }
    end
  end

  local spine_items = {}
  for _, itemref in ipairs(flatten_children(spine)) do
    local ref = itemref._attr and itemref._attr.idref
    if ref and manifest_items[ref] then
      table.insert(spine_items, manifest_items[ref])
    end
  end

  local resources_by_type = {}
  for _, item in pairs(manifest_items) do
    local media = item.media_type or "unknown"
    resources_by_type[media] = resources_by_type[media] or {}
    table.insert(resources_by_type[media], item)
  end

  local metadata = {}
  local title = nil
  for _, child in ipairs(flatten_children(metadata_node)) do
    if child._name then
      local item = {
        tag = child._name,
        text = text_content(child),
        attr = child._attr,
      }
      table.insert(metadata, item)
      if not title and child._name:match("title$") then
        title = item.text
      end
    end
  end

  local base_dir = opf_path:gsub(path_sep .. "[^" .. path_sep .. "]*$", "")
  base_dir = normalize_dir(base_dir)

  return {
    title = title,
    metadata = metadata,
    manifest = manifest_items,
    spine = spine_items,
    resources = resources_by_type,
    base_dir = base_dir,
  }
end

return M
