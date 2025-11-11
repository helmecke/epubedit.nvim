local opf_manager = require("epubedit.opf_manager")

---@class epubedit.spine_editor
local M = {}

local state = {
  bufnr = nil,
  session = nil,
  spine_items = {},
}

---Close the spine editor
local function close_editor()
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    pcall(vim.api.nvim_buf_delete, state.bufnr, { force = true })
  end
  state.bufnr = nil
  state.session = nil
  state.spine_items = {}
end

---Save the spine order back to the OPF file
local function save_spine()
  if not state.session then
    vim.notify("No active EPUB session.", vim.log.levels.ERROR)
    return
  end

  -- Get current buffer lines
  local lines = vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false)

  -- Build new spine order by matching hrefs to original items
  local new_spine = {}
  local href_to_item = {}

  -- Create lookup map
  for _, item in ipairs(state.spine_items) do
    if item.href then
      href_to_item[item.href] = item
    end
  end

  -- Build new spine based on buffer line order
  for _, line in ipairs(lines) do
    local href = vim.trim(line)
    if href ~= "" and href_to_item[href] then
      table.insert(new_spine, href_to_item[href])
    end
  end

  -- Save to OPF
  local ok, err = opf_manager.set_spine(state.session, new_spine)
  if ok then
    vim.notify("Spine order saved successfully.", vim.log.levels.INFO)
    vim.bo[state.bufnr].modified = false
  else
    vim.notify("Failed to save spine: " .. (err or "unknown error"), vim.log.levels.ERROR)
  end
end

---Render the spine items in the buffer
local function render_editor()
  local lines = {}
  for _, item in ipairs(state.spine_items) do
    if item.href then
      table.insert(lines, item.href)
    end
  end

  vim.bo[state.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, lines)
  vim.bo[state.bufnr].modified = false
end

---Open the spine editor
---@param session table The active EPUB session
function M.open(session)
  if not session or not session.opf then
    vim.notify("No active EPUB session.", vim.log.levels.ERROR)
    return
  end

  -- Get spine items from OPF
  local spine_items, err = opf_manager.get_spine(session)
  if not spine_items then
    vim.notify("Failed to get spine: " .. (err or "unknown error"), vim.log.levels.ERROR)
    return
  end

  -- If editor already open, just focus it
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    local wins = vim.fn.win_findbuf(state.bufnr)
    if #wins > 0 then
      vim.api.nvim_set_current_win(wins[1])
      return
    end
  end

  -- Create new buffer
  state.bufnr = vim.api.nvim_create_buf(false, true)
  state.session = session
  state.spine_items = spine_items

  -- Configure buffer
  vim.api.nvim_buf_set_name(state.bufnr, "EPUB Spine")
  vim.bo[state.bufnr].filetype = "epubedit-spine"
  vim.bo[state.bufnr].buftype = "acwrite"
  vim.bo[state.bufnr].buflisted = false
  vim.bo[state.bufnr].swapfile = false

  -- Set up keymaps
  vim.keymap.set("n", "<C-s>", save_spine, { buffer = state.bufnr, nowait = true, desc = "Save spine order" })
  vim.keymap.set("n", "q", close_editor, { buffer = state.bufnr, nowait = true, desc = "Close spine editor" })

  -- Set up autocmd for save
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = state.bufnr,
    callback = function()
      save_spine()
    end,
  })

  -- Render content
  render_editor()

  -- Open buffer in current window
  vim.api.nvim_set_current_buf(state.bufnr)

  -- Show help message
  vim.notify("Spine editor: Reorder lines to change reading order. Save with :w or <C-s>, quit with q", vim.log.levels.INFO)
end

return M
