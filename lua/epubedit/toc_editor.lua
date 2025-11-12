local toc_manager = require("epubedit.toc_manager")
local toc_generator = require("epubedit.toc_generator")

---@class epubedit.toc_editor
local M = {}

local state = {
  bufnr = nil,
  session = nil,
  entries = {},
  toc_type = nil,
}

---Close the TOC editor
local function close_editor()
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    pcall(vim.api.nvim_buf_delete, state.bufnr, { force = true })
  end
  state.bufnr = nil
  state.session = nil
  state.entries = {}
  state.toc_type = nil
end

---Parse a TOC line from the buffer
---Format: "  label -> src" where leading spaces = depth * 2
---@param line string
---@return table|nil entry
local function parse_toc_line(line)
  if not line or line == "" or line:match("^%s*#") then
    return nil
  end

  -- Count leading spaces to determine depth
  local spaces, rest = line:match("^(%s*)(.*)")
  local depth = math.floor(#spaces / 2)

  -- Parse label and src
  local label, src = rest:match("^(.-)%s*%->%s*(.*)$")

  if not label or not src then
    -- Try without arrow (just label)
    label = vim.trim(rest)
    src = ""
  end

  label = vim.trim(label)
  src = vim.trim(src)

  if label == "" then
    return nil
  end

  return {
    label = label,
    src = src,
    depth = depth,
    children = {},
  }
end

---Save the TOC back to the EPUB
local function save_toc()
  if not state.session then
    vim.notify("No active EPUB session.", vim.log.levels.ERROR)
    return
  end

  -- Get current buffer lines
  local lines = vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false)

  -- Parse lines into flat entries
  local flat_entries = {}
  for _, line in ipairs(lines) do
    local entry = parse_toc_line(line)
    if entry then
      table.insert(flat_entries, entry)
    end
  end

  if #flat_entries == 0 then
    vim.notify("No valid TOC entries found.", vim.log.levels.ERROR)
    return
  end

  -- Convert flat entries to hierarchical
  local entries = toc_manager.unflatten_entries(flat_entries)

  -- Save to TOC file
  local ok, err = toc_manager.set_toc(state.session, entries)
  if ok then
    vim.notify("TOC saved successfully.", vim.log.levels.INFO)
    vim.bo[state.bufnr].modified = false
  else
    vim.notify("Failed to save TOC: " .. (err or "unknown error"), vim.log.levels.ERROR)
  end
end

---Render the TOC entries in the buffer
local function render_editor()
  local lines = {}

  -- Header comment
  table.insert(lines, "# Table of Contents")
  table.insert(lines, "# Format: label -> src")
  table.insert(lines, "# Use indentation (2 spaces per level) to create hierarchy")
  table.insert(lines, "")

  -- Flatten entries for display
  local flat = toc_manager.flatten_entries(state.entries)

  for _, entry in ipairs(flat) do
    local indent = string.rep("  ", entry.depth or 0)
    local line = string.format("%s%s -> %s", indent, entry.label or "", entry.src or "")
    table.insert(lines, line)
  end

  vim.bo[state.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(state.bufnr, 0, -1, false, lines)
  vim.bo[state.bufnr].modified = false
end

---Generate TOC from headings
local function generate_from_headings()
  if not state.session then
    vim.notify("No active EPUB session.", vim.log.levels.ERROR)
    return
  end

  -- Ask user for max depth
  vim.ui.input({ prompt = "Max heading depth (1-6): ", default = "3" }, function(input)
    if not input then
      return
    end

    local max_depth = tonumber(input)
    if not max_depth or max_depth < 1 or max_depth > 6 then
      vim.notify("Invalid depth. Must be between 1 and 6.", vim.log.levels.ERROR)
      return
    end

    -- Generate entries
    local entries, err = toc_generator.generate_from_headings(state.session, { max_depth = max_depth })
    if not entries then
      vim.notify("Failed to generate TOC: " .. (err or "unknown error"), vim.log.levels.ERROR)
      return
    end

    -- Update state and re-render
    state.entries = entries
    render_editor()

    vim.notify(
      string.format("Generated TOC with max depth %d. Save with :w or <C-s> to write to EPUB.", max_depth),
      vim.log.levels.INFO
    )
  end)
end

---Increase indentation of current line
local function indent_line()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_buf_get_lines(state.bufnr, row - 1, row, false)[1]

  if not line or line:match("^#") then
    return
  end

  vim.bo[state.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(state.bufnr, row - 1, row, false, { "  " .. line })
  vim.bo[state.bufnr].modified = true
end

---Decrease indentation of current line
local function unindent_line()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_buf_get_lines(state.bufnr, row - 1, row, false)[1]

  if not line or line:match("^#") then
    return
  end

  -- Remove up to 2 leading spaces
  local new_line = line:gsub("^  ", "", 1)

  vim.bo[state.bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(state.bufnr, row - 1, row, false, { new_line })
  vim.bo[state.bufnr].modified = true
end

---Open the TOC editor
---@param session table The active EPUB session
function M.open(session)
  if not session or not session.opf then
    vim.notify("No active EPUB session.", vim.log.levels.ERROR)
    return
  end

  -- Get TOC entries
  local entries, toc_type, err = toc_manager.get_toc(session)
  if not entries then
    vim.notify("Failed to get TOC: " .. (err or "unknown error"), vim.log.levels.ERROR)
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
  state.entries = entries
  state.toc_type = toc_type

  -- Configure buffer
  vim.api.nvim_buf_set_name(state.bufnr, "EPUB TOC")
  vim.bo[state.bufnr].filetype = "epubedit-toc"
  vim.bo[state.bufnr].buftype = "acwrite"
  vim.bo[state.bufnr].buflisted = false
  vim.bo[state.bufnr].swapfile = false

  -- Set up keymaps
  vim.keymap.set("n", "<C-s>", save_toc, { buffer = state.bufnr, nowait = true, desc = "Save TOC" })
  vim.keymap.set("n", "q", close_editor, { buffer = state.bufnr, nowait = true, desc = "Close TOC editor" })
  vim.keymap.set(
    "n",
    "g",
    generate_from_headings,
    { buffer = state.bufnr, nowait = true, desc = "Generate TOC from headings" }
  )
  vim.keymap.set("n", ">", indent_line, { buffer = state.bufnr, nowait = true, desc = "Increase indentation" })
  vim.keymap.set("n", "<", unindent_line, { buffer = state.bufnr, nowait = true, desc = "Decrease indentation" })

  -- Set up autocmd for save
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = state.bufnr,
    callback = function()
      save_toc()
    end,
  })

  -- Render content
  render_editor()

  -- Open buffer in current window
  vim.api.nvim_set_current_buf(state.bufnr)

  -- Show help message
  vim.notify(
    "TOC editor: Edit entries (label -> src), use > < to change depth, g to generate from headings. Save with :w or <C-s>, quit with q",
    vim.log.levels.INFO
  )
end

return M
