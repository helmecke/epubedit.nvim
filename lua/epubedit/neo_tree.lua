local renderer = require("neo-tree.ui.renderer")
local manager = require("neo-tree.sources.manager")
local common_components = require("neo-tree.sources.common.components")
local common_commands = require("neo-tree.sources.common.commands")
local fs_actions = require("neo-tree.sources.filesystem.lib.fs_actions")
local inputs = require("neo-tree.ui.inputs")
local utils = require("neo-tree.utils")
local neotree = require("neo-tree")

local core = require("epubedit.module")
local opf_view = require("epubedit.opf_view")
local opf_manager = require("epubedit.opf_manager")

local SOURCE_NAME = "epubedit"
local REFRESH_EVENTS = { "EpubEditSessionOpen", "EpubEditSessionSaved", "EpubEditSessionClosed" }
local path_sep = package.config:sub(1, 1)

local default_group_labels = {}
for id, def in pairs(opf_view.GROUP_DEFS) do
  default_group_labels[id] = def.label
end

local function workspace_paths()
  local session = core.state.current
  if not session or not session.workspace then
    return nil
  end
  local workspace = vim.fn.fnamemodify(session.workspace, ":p")
  local normalized = workspace
  if normalized:sub(-1) == path_sep then
    normalized = normalized:sub(1, -2)
  end
  return normalized
end

local function relative_to_workspace(path)
  local workspace = workspace_paths()
  if not workspace or not path or path == "" then
    return path
  end
  if path:sub(1, #workspace) == workspace then
    local rel = path:sub(#workspace + 1)
    rel = rel:gsub("^" .. path_sep, "")
    return rel
  end
  return path
end

local function absolute_from_workspace(relative)
  local workspace = workspace_paths()
  if not workspace then
    return relative
  end
  local trimmed = (relative or ""):gsub("^[/\\]+", ""):gsub("\\", "/")
  if trimmed == "" then
    return workspace
  end
  local combined = workspace .. path_sep .. trimmed
  return vim.fn.fnamemodify(combined, ":p")
end

local function opf_root_relative()
  local session = core.state.current
  local workspace = workspace_paths()
  if not session or not session.opf or not workspace then
    return ""
  end
  local opf_dir = vim.fn.fnamemodify(session.opf, ":p:h")
  if opf_dir:sub(1, #workspace) ~= workspace then
    return ""
  end
  local relative = opf_dir:sub(#workspace + 1):gsub("^" .. path_sep, "")
  return relative
end

local function opf_root_absolute()
  local relative = opf_root_relative()
  if relative ~= "" then
    return absolute_from_workspace(relative)
  end
  return workspace_paths()
end

local function split_root_prefix(rel_path)
  local root = opf_root_relative()
  if root == "" or not rel_path or rel_path == "" then
    return "", rel_path
  end
  if rel_path == root then
    return root, ""
  end
  local prefix = root .. path_sep
  if rel_path:sub(1, #prefix) == prefix then
    return root, rel_path:sub(#prefix + 1)
  end
  return "", rel_path
end

local function combine_root_with_suffix(root, suffix)
  if root == "" then
    return suffix
  end
  suffix = (suffix or ""):gsub("^[/\\]+", "")
  if suffix == "" then
    return root
  end
  return root .. "/" .. suffix
end

local function with_prompt(prompt, base, fn)
  local original = inputs.input
  local restored = false
  local function restore()
    if not restored then
      inputs.input = original
      restored = true
    end
  end
  inputs.input = function(message, default_value, cb)
    restore()
    return original(prompt or message, base ~= nil and base or default_value, cb)
  end
  local ok, err = pcall(fn)
  restore()
  if not ok then
    error(err)
  end
end

local function get_directory_node(state)
  local tree = state.tree
  if not tree then
    return nil
  end
  local node = tree:get_node()
  if not node then
    return nil
  end
  local last_id = node.get_id and node:get_id()
  while node do
    local insert_as_local = state.config and state.config.insert_as
    local insert_as_global = neotree.config.window.insert_as
    local use_parent = insert_as_local == "sibling" or (insert_as_local == nil and insert_as_global == "sibling")
    local is_open_dir = node.type == "directory" and (node:is_expanded() or node.empty_expanded)
    if use_parent and not is_open_dir then
      local parent = node.get_parent_id and tree:get_node(node:get_parent_id())
      if not parent then
        break
      end
      node = parent
    elseif node.type == "directory" then
      return node
    else
      local parent_id = node.get_parent_id and node:get_parent_id()
      if not parent_id or parent_id == last_id then
        local parent = parent_id and tree:get_node(parent_id) or nil
        return parent or node
      end
      last_id = parent_id
      node = tree:get_node(parent_id)
    end
  end
  return node
end

local function default_relative_directory(folder)
  local root = opf_root_relative()
  if folder and folder.extra and folder.extra.default_dir and folder.extra.default_dir ~= "" then
    return folder.extra.default_dir
  end
  if folder and folder.path and folder.type == "directory" then
    local rel = relative_to_workspace(folder.path)
    if rel ~= "" then
      return rel
    end
  end
  if folder and folder.path and folder.type ~= "directory" then
    local rel = relative_to_workspace(vim.fn.fnamemodify(folder.path, ":h"))
    if rel ~= "" then
      return rel
    end
  end
  if root ~= "" then
    return root
  end
  return ""
end

local function absolute_directory_for(folder)
  local rel = default_relative_directory(folder)
  if rel and rel ~= "" then
    return absolute_from_workspace(rel)
  end
  return workspace_paths()
end

local function group_from_path(path)
  local relative = relative_to_workspace(path)
  if not relative or relative == "" then
    return nil
  end
  local root = opf_root_relative()
  if root ~= "" then
    local prefix = root .. path_sep
    if relative:sub(1, #prefix) == prefix then
      relative = relative:sub(#prefix + 1)
    end
  end
  local segment = relative:match("^([^" .. path_sep .. "/]+)")
  if not segment or segment == "" then
    return nil
  end
  segment = segment:lower()
  local known = {
    text = true,
    styles = true,
    images = true,
    fonts = true,
    audio = true,
    video = true,
    misc = true,
  }
  if known[segment] then
    return segment
  end
  return nil
end

local commands = vim.tbl_extend("force", {}, common_commands, {
  refresh = function(state)
    manager.refresh(state.name)
  end,
  move = function(state, callback)
    local node = assert(state.tree:get_node())
    if node.type == "message" then
      return
    end
    local default_path = relative_to_workspace(node.path)
    local root_prefix, suffix = split_root_prefix(default_path)
    local prompt
    local initial
    if root_prefix ~= "" then
      prompt = string.format('Move "%s" to (relative to %s/):', default_path, root_prefix)
      initial = suffix
    else
      prompt = string.format('Move "%s" to:', default_path)
      initial = default_path
    end
    inputs.input(prompt, initial, function(new_value)
      if not new_value then
        return
      end
      local relative = (root_prefix ~= "") and combine_root_with_suffix(root_prefix, new_value) or new_value
      if relative == "" then
        relative = default_path
      end
      local destination = absolute_from_workspace(relative)
      local wrapped_callback = function(source_path, dest_path)
        if type(callback) == "function" then
          callback(source_path, dest_path)
        end
        manager.refresh(state.name)
      end
      fs_actions.move_node(node.path, destination, wrapped_callback, nil)
    end)
  end,
  add = function(state, callback)
    local folder = get_directory_node(state)
    if not folder then
      return
    end
    local target_dir = absolute_directory_for(folder)
    if not target_dir or target_dir == "" then
      target_dir = workspace_paths()
    end
    if not target_dir then
      return
    end
    local root_abs = opf_root_absolute()
    local default_rel = default_relative_directory(folder)
    local root_prefix, suffix = split_root_prefix(default_rel or "")
    local prompt
    local initial
    if root_prefix ~= "" then
      prompt = string.format("Create entry inside %s/ (relative path):", root_prefix)
      if suffix ~= "" then
        local trimmed = suffix:gsub(utils.path_separator .. "$", "")
        if trimmed ~= "" then
          trimmed = trimmed .. utils.path_separator
        end
        initial = trimmed
      else
        initial = ""
      end
    else
      prompt = "Create entry (relative to workspace root):"
      if default_rel ~= "" then
        local trimmed = default_rel:gsub(utils.path_separator .. "$", "")
        if trimmed ~= "" then
          trimmed = trimmed .. utils.path_separator
        end
        initial = trimmed
      else
        initial = ""
      end
    end
    with_prompt(prompt, initial, function()
      fs_actions.create_node(target_dir, function(new_path)
        if type(callback) == "function" then
          callback(new_path)
        end
        local session = core.state.current
        if session then
          local group_id = (folder.extra and folder.extra.group_id)
            or group_from_path(new_path)
            or group_from_path(target_dir)
          local add_to_spine = group_id == "text"
          local ok = opf_manager.add_manifest_entry(session, new_path, {
            group = group_id,
            add_to_spine = add_to_spine,
          })
          if not ok then
            vim.schedule(function()
              vim.notify(
                "epubedit: failed to update content.opf for new file " .. (new_path or ""),
                vim.log.levels.WARN
              )
            end)
          end
        end
        state.dirty = true
        manager.refresh(state.name)
      end, root_abs or false)
    end)
  end,
})

local M = {
  name = SOURCE_NAME,
  display_name = " 󰂺 EPUB ",
  components = common_components,
  commands = commands,
  default_config = {
    window = {
      position = "left",
    },
    group_order = opf_view.DEFAULT_GROUP_ORDER,
    group_labels = vim.deepcopy(default_group_labels),
  },
}

local refresh_group

local function placeholder(message, path)
  return {
    id = "epubedit:placeholder:" .. message,
    name = message,
    type = "message",
    path = path or "",
    children = {},
  }
end

local function schedule_refresh(pattern)
  if not refresh_group then
    refresh_group = vim.api.nvim_create_augroup("EpubEditNeoTreeRefresh", { clear = true })
  end
  vim.api.nvim_create_autocmd("User", {
    group = refresh_group,
    pattern = pattern,
    callback = function()
      manager.refresh(SOURCE_NAME)
    end,
  })
end

function M.setup(config, _)
  M.source_config = config or {}
  if refresh_group then
    pcall(vim.api.nvim_del_augroup_by_id, refresh_group)
    refresh_group = nil
  end
  for _, pattern in ipairs(REFRESH_EVENTS) do
    schedule_refresh(pattern)
  end
end

local function build_nodes(session)
  local epub_config = require("epubedit").get_config()
  local builder_opts = vim.tbl_deep_extend("force", {}, epub_config.neo_tree or {}, M.source_config or {})

  local ok, result = pcall(opf_view.build, session, builder_opts)
  if not ok then
    return nil, result
  end
  if not result then
    return nil, "Unable to build OPF nodes."
  end
  return result.nodes, nil
end

function M.navigate(state, path, path_to_reveal, callback, _)
  state.dirty = false
  local session = core.state.current
  local nodes

  if not session then
    nodes = { placeholder("No EPUB workspace active") }
  elseif not session.opf or vim.fn.filereadable(session.opf) == 0 then
    nodes = { placeholder("OPF not found for workspace", session.workspace) }
  else
    local built_nodes, err = build_nodes(session)
    if built_nodes then
      nodes = built_nodes
      state.path = session.workspace
    else
      nodes = { placeholder("OPF parse error: " .. tostring(err), session.workspace) }
    end
  end

  renderer.show_nodes(nodes, state)

  if path_to_reveal and state.tree then
    renderer.focus_node(state, path_to_reveal, true)
  end

  if type(callback) == "function" then
    vim.schedule(callback)
  end
end

return M
