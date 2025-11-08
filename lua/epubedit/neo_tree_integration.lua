local SOURCE_NAME = "epubedit"

local opf_manager = require("epubedit.opf_manager")
local core = require("epubedit.module")

local M = {}

local function get_command()
  local ok, command = pcall(require, "neo-tree.command")
  if not ok then
    return nil, "neo-tree.command not available"
  end
  if type(command.execute) ~= "function" then
    return nil, "neo-tree.command.execute missing"
  end
  return command
end

function M.open(workspace, opts)
  local command, err = get_command()
  if not command then
    return false, err
  end
  local args = {
    source = SOURCE_NAME,
    action = "show",
  }
  opts = opts or {}
  if opts.action then
    args.action = opts.action
  elseif opts.focus then
    args.action = "focus"
  end
  if workspace and workspace ~= "" then
    args.dir = workspace
  end
  local ok, exec_err = pcall(command.execute, args)
  if not ok then
    return false, exec_err
  end
  return true
end

function M.close()
  local command, err = get_command()
  if not command then
    return false, err
  end
  local ok, exec_err = pcall(command.execute, {
    action = "close",
    source = SOURCE_NAME,
  })
  if not ok then
    return false, exec_err
  end
  return true
end

local function normalize_path(path)
  if not path or path == "" then
    return nil
  end
  return vim.fn.fnamemodify(path, ":p")
end

local function update_session_assets(session, old_path, new_path)
  if not session or not session.assets then
    return
  end
  for idx, value in ipairs(session.assets) do
    if normalize_path(value) == old_path then
      session.assets[idx] = new_path
      return
    end
  end
end

function M.handle_path_change(event)
  local args = event or {}
  local old_path = normalize_path(args.source)
  local new_path = normalize_path(args.destination)
  if not old_path or not new_path then
    return
  end

  local session = core.state.current
  if not session or not session.workspace then
    return
  end

  local workspace = normalize_path(session.workspace)
  if not workspace or old_path:sub(1, #workspace) ~= workspace then
    return
  end

  local updated = opf_manager.rename_manifest_entry(session, old_path, new_path)
  if not updated then
    return
  end

  update_session_assets(session, old_path, new_path)

  local ok_manager, manager = pcall(require, "neo-tree.sources.manager")
  if ok_manager then
    pcall(manager.refresh, SOURCE_NAME)
  end
end

return M
