local fn = vim.fn
local opf_parser = require("epubedit.parser.opf")

local path_sep = package.config:sub(1, 1)

local DEFAULT_GROUP_ORDER = { "text", "styles", "images", "fonts", "audio", "video", "misc" }

local GROUP_DEFS = {
  text = {
    label = "Text",
    matcher = function(item)
      local media = item.media_type or ""
      if media == "" then
        return false
      end
      if media == "application/xhtml+xml" or media == "text/html" or media == "application/x-dtbncx+xml" then
        return true
      end
      if media == "application/xml" and item.href and item.href:match("%.x?html$") then
        return true
      end
      return false
    end,
  },
  styles = {
    label = "Styles",
    matcher = function(item)
      return (item.media_type or "") == "text/css"
    end,
  },
  images = {
    label = "Images",
    matcher = function(item)
      return (item.media_type or ""):match("^image/")
    end,
  },
  fonts = {
    label = "Fonts",
    matcher = function(item)
      local media = item.media_type or ""
      if media:match("^font/") then
        return true
      end
      if media:match("opentype") or media:match("truetype") then
        return true
      end
      return media == "application/font-woff" or media == "application/x-font-ttf" or media == "application/vnd.ms-opentype"
    end,
  },
  audio = {
    label = "Audio",
    matcher = function(item)
      return (item.media_type or ""):match("^audio/")
    end,
  },
  video = {
    label = "Video",
    matcher = function(item)
      return (item.media_type or ""):match("^video/")
    end,
  },
  misc = {
    label = "Misc",
    matcher = function()
      return true
    end,
  },
}

local M = {
  DEFAULT_GROUP_ORDER = DEFAULT_GROUP_ORDER,
  GROUP_DEFS = GROUP_DEFS,
}

local function resolve_path(session, parsed, entry)
  if not entry or not entry.href or entry.href == "" then
    return nil
  end
  local base = parsed.base_dir or (session.workspace .. path_sep)
  local path = fn.fnamemodify(base .. entry.href, ":p")
  return path
end

local function normalize_href(path)
  return (path or ""):gsub("\\", "/")
end

local function compute_display_prefix(session, parsed)
  if not session or not session.workspace or not parsed.base_dir then
    return ""
  end
  local workspace = fn.fnamemodify(session.workspace, ":p"):gsub(path_sep .. "$", "")
  local base_dir = fn.fnamemodify(parsed.base_dir, ":p"):gsub(path_sep .. "$", "")
  if base_dir == workspace then
    return ""
  end
  if base_dir:sub(1, #workspace) == workspace then
    local remainder = base_dir:sub(#workspace + 2)
    if remainder and remainder ~= "" then
      return normalize_href(remainder)
    end
  end
  return normalize_href(base_dir)
end

---@param entries table[]
---@param make_node fun(item: table): table|nil
---@return table[]
local function build_children(entries, make_node)
  local nodes = {}
  for _, item in ipairs(entries or {}) do
    local node = make_node(item)
    if node then
      table.insert(nodes, node)
    end
  end
  return nodes
end

---@param session table
---@param opts table|nil
---@return table|nil, string|nil
function M.build(session, opts)
  opts = opts or {}
  if not session or not session.opf or session.opf == "" then
    return nil, "No OPF located for workspace."
  end

  local parsed, err = opf_parser.parse(session.opf)
  if not parsed then
    return nil, err
  end

  local seen_paths = {}
  local total_nodes = 0

  local display_prefix = compute_display_prefix(session, parsed)

  local function display_label(item, fallback)
    local href = item and item.href or nil
    if href and href ~= "" then
      if display_prefix ~= "" then
        return normalize_href(display_prefix .. "/" .. href)
      end
      return normalize_href(href)
    end
    return fallback
  end

  local function make_leaf(item)
    local path = resolve_path(session, parsed, item)
    if not path or seen_paths[path] then
      return nil
    end
    seen_paths[path] = true
    total_nodes = total_nodes + 1
    local label = display_label(item, path)
    return {
      id = path,
      name = label,
      type = "file",
      path = path,
      extra = {
        media_type = item.media_type,
        href = item.href,
      },
    }
  end

  local manifest_items = {}
  for _, item in pairs(parsed.manifest or {}) do
    table.insert(manifest_items, item)
  end

  local group_order = opts.group_order or DEFAULT_GROUP_ORDER
  local group_labels = vim.tbl_deep_extend("force", {}, GROUP_DEFS)
  if opts.group_labels then
    for key, label in pairs(opts.group_labels) do
      group_labels[key] = group_labels[key] or {}
      group_labels[key].label = label
    end
  end

  local groups = {}
  local function ensure_group(id)
    local def = group_labels[id] or GROUP_DEFS[id] or { label = id }
    if not groups[id] then
      groups[id] = {
        id = "epubedit:group:" .. id,
        name = def.label or id,
        type = "directory",
        path = session.workspace,
        children = {},
      }
    end
    return groups[id]
  end

  local function add_item(group_id, item)
    local node = make_leaf(item)
    if node then
      local group = ensure_group(group_id)
      table.insert(group.children, node)
    end
  end

  -- Prioritize spine order within the text group.
  for _, entry in ipairs(parsed.spine or {}) do
    add_item("text", entry)
  end

  -- Assign remaining items to groups based on matchers.
  for _, item in ipairs(manifest_items) do
    local target_group = nil
    for _, group_id in ipairs(group_order) do
      local def = GROUP_DEFS[group_id]
      if def and def.matcher(item) then
        target_group = group_id
        break
      end
    end
    target_group = target_group or "misc"
    add_item(target_group, item)
  end

  local nodes = {}
  for _, group_id in ipairs(group_order) do
    local group = groups[group_id]
    if group and #group.children > 0 then
      table.insert(nodes, group)
    end
  end

  if #nodes == 0 then
    nodes = {
      {
        id = "epubedit:empty",
        name = "(no OPF entries found)",
        type = "message",
        path = session.opf or session.workspace,
        children = {},
      },
    }
  end

  if session.opf and fn.filereadable(session.opf) == 1 then
    local display = session.opf
    if session.workspace and display:sub(1, #session.workspace) == session.workspace then
      display = display:sub(#session.workspace + 1)
      display = display:gsub("^" .. path_sep, "")
    end
    table.insert(nodes, {
      id = session.opf,
      name = display,
      type = "file",
      path = session.opf,
      children = {},
    })
  end

  return {
    nodes = nodes,
    title = parsed.title,
    count = total_nodes,
  }
end

return M
