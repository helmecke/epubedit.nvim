local SOURCE_NAME = "epubedit"

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

function M.open(workspace)
  local command, err = get_command()
  if not command then
    return false, err
  end
  local args = {
    source = SOURCE_NAME,
    action = "show",
  }
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

return M
