local fn = vim.fn
local opf_parser = require("epubedit.parser.opf")

local path_sep = package.config:sub(1, 1)

local DEFAULT_MEDIA_ORDER = { "application/xhtml+xml", "text/html", "text/css", "application/x-dtbncx+xml" }

local M = {
  DEFAULT_MEDIA_ORDER = DEFAULT_MEDIA_ORDER,
}

local function resolve_path(session, parsed, entry)
  if not entry or not entry.href or entry.href == "" then
    return nil
  end
  local base = parsed.base_dir or (session.workspace .. path_sep)
  local path = fn.fnamemodify(base .. entry.href, ":p")
  return path
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

  local function make_leaf(item)
    local path = resolve_path(session, parsed, item)
    if not path or seen_paths[path] then
      return nil
    end
    seen_paths[path] = true
    total_nodes = total_nodes + 1
    local label = item.href or path
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

  local nodes = {}

  local spine_children = build_children(parsed.spine or {}, make_leaf)
  if #spine_children > 0 then
    table.insert(nodes, {
      id = "epubedit:spine",
      name = "Spine",
      type = "directory",
      path = session.workspace,
      children = spine_children,
    })
  end

  local order = opts.media_order or DEFAULT_MEDIA_ORDER
  local resources = parsed.resources or {}
  local added_groups = {}

  for _, media in ipairs(order) do
    local group_children = build_children(resources[media] or {}, make_leaf)
    if #group_children > 0 then
      table.insert(nodes, {
        id = "epubedit:media:" .. media,
        name = media,
        type = "directory",
        path = session.workspace,
        children = group_children,
      })
      added_groups[media] = true
    end
  end

  for media, items in pairs(resources) do
    if not added_groups[media] then
      local group_children = build_children(items, make_leaf)
      if #group_children > 0 then
        table.insert(nodes, {
          id = "epubedit:media:" .. media,
          name = media,
          type = "directory",
          path = session.workspace,
          children = group_children,
        })
      end
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

  return {
    nodes = nodes,
    title = parsed.title,
    count = total_nodes,
  }
end

return M
