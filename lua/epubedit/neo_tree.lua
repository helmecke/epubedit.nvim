local renderer = require("neo-tree.ui.renderer")
local manager = require("neo-tree.sources.manager")
local common_components = require("neo-tree.sources.common.components")
local common_commands = require("neo-tree.sources.common.commands")

local core = require("epubedit.module")
local opf_view = require("epubedit.opf_view")

local SOURCE_NAME = "epubedit"
local REFRESH_EVENTS = { "EpubEditSessionOpen", "EpubEditSessionSaved", "EpubEditSessionClosed" }

local M = {
  name = SOURCE_NAME,
  display_name = " 󰂺 EPUB ",
  components = common_components,
  commands = common_commands,
  default_config = {
    window = {
      position = "left",
    },
    media_order = opf_view.DEFAULT_MEDIA_ORDER,
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
  local builder_opts = vim.tbl_deep_extend(
    "force",
    {},
    epub_config.neo_tree or {},
    M.source_config or {}
  )

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
