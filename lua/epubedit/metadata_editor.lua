local opf_manager = require("epubedit.opf_manager")
local Popup = require("nui.popup")

local M = {}

local state = {
  popup = nil,
  metadata = {},
  session = nil,
}

local function close_editor()
  if state.popup then
    state.popup:unmount()
    state.popup = nil
  end
  state.metadata = {}
  state.session = nil
end

local function save_metadata()
  if not state.session then
    return
  end
  local ok, err = opf_manager.update_metadata(state.session, state.metadata)
  if ok then
    vim.notify("Metadata saved successfully.", vim.log.levels.INFO)
  else
    vim.notify("Failed to save metadata: " .. (err or "unknown error"), vim.log.levels.ERROR)
  end
end

local function handle_close()
  local choice = vim.fn.confirm("Save changes to metadata?", "&Yes\n&No\n&Cancel", 1)
  if choice == 1 then -- Yes
    save_metadata()
    close_editor()
  elseif choice == 2 then -- No
    close_editor()
  -- else (Cancel) do nothing, keep popup open
  end
end

local function render_editor()
  local lines = {}
  for _, item in ipairs(state.metadata) do
    table.insert(lines, string.format("%-20s: %s", item.tag, item.text))
  end
  vim.bo[state.popup.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(state.popup.bufnr, 0, -1, false, lines)
  vim.bo[state.popup.bufnr].modifiable = false
end

local function edit_current_line()
  local line_nr = vim.api.nvim_win_get_cursor(0)[1]
  local item = state.metadata[line_nr]
  if not item then
    return
  end

  local new_value = vim.fn.input("New value for " .. item.tag .. ": ", item.text)
  if new_value ~= "" and new_value ~= item.text then
    item.text = new_value
    render_editor()
  end
end

function M.open(session)
  if state.popup then
    vim.api.nvim_set_current_win(state.popup.winid)
    return
  end

  if not session or not session.opf then
    vim.notify("No active EPUB session.", vim.log.levels.ERROR)
    return
  end

  local metadata, err = opf_manager.get_metadata(session)
  if not metadata then
    vim.notify("Failed to get metadata: " .. (err or "unknown error"), vim.log.levels.ERROR)
    return
  end

  local filtered_metadata = {}
  for _, item in ipairs(metadata) do
    if item.text and vim.trim(item.text) ~= "" then
      table.insert(filtered_metadata, item)
    end
  end
  state.metadata = filtered_metadata
  state.session = session

  local width = 80
  local height = #state.metadata + 2

  state.popup = Popup({
    enter = true,
    border = {
      style = "single",
      text = {
        top = "EPUB Metadata",
      },
    },
    relative = "editor",
    position = { row = "50%", col = "50%" },
    size = {
      width = width,
      height = height,
    },
    on_close = function()
      handle_close()
    end,
  })

  -- mount the component
  state.popup:mount()

  vim.bo[state.popup.bufnr].filetype = "epubedit-metadata"
  vim.bo[state.popup.bufnr].buflisted = false
  vim.bo[state.popup.bufnr].swapfile = false
  vim.bo[state.popup.bufnr].modifiable = false

  vim.keymap.set("n", "<CR>", edit_current_line, { buffer = state.popup.bufnr, nowait = true })
  vim.keymap.set("n", "<C-s>", save_metadata, { buffer = state.popup.bufnr, nowait = true })
  vim.keymap.set("n", "q", function()
    handle_close()
  end, { buffer = state.popup.bufnr, nowait = true })

  render_editor()
end

return M
