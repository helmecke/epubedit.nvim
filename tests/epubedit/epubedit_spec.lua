local epubedit = require("epubedit")
local core = require("epubedit.module")
local uv = vim.loop

local sample_epub = vim.fn.fnamemodify("tests/fixtures/sample.epub", ":p")
local initial_cwd = vim.fn.getcwd()

local function ensure_dependencies()
  assert.are.equal(1, vim.fn.executable("zip"), "zip executable required for tests")
  assert.are.equal(1, vim.fn.executable("unzip"), "unzip executable required for tests")
end

local function delete_dir(path)
  local handler = uv.fs_scandir(path)
  if handler then
    while true do
      local name, typ = uv.fs_scandir_next(handler)
      if not name then
        break
      end
      local target = path .. "/" .. name
      if typ == "directory" then
        delete_dir(target)
      else
        uv.fs_unlink(target)
      end
    end
  end
  uv.fs_rmdir(path)
end

local function modify_chapter(bufnr, original, replacement)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local changed = false
  for idx, line in ipairs(lines) do
    local updated = line:gsub(original, replacement)
    if updated ~= line then
      lines[idx] = updated
      changed = true
      break
    end
  end
  assert.is_true(changed, "expected to modify chapter text")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd("silent write")
  end)
end

describe("epubedit workflow", function()
  before_each(function()
    ensure_dependencies()
    epubedit.setup({ prompt_overwrite = false })
  end)

  after_each(function()
    core.cleanup(epubedit.get_config())
    assert.are.equal(initial_cwd, vim.fn.getcwd())
  end)

  it("unpacks an EPUB into a workspace and exposes assets", function()
    local ok, err = core.open(sample_epub, epubedit.get_config())
    assert(ok, err or "open failed")

    local session = core.state.current
    assert.is_not_nil(session)
    assert.is_truthy(session.workspace)
    assert.are.same(1, vim.fn.filereadable(session.opf))
    assert.is_true(#session.assets >= 3, "expected OPF + at least two assets")

    assert.are.equal(0, vim.fn.bufloaded(session.opf))
    assert.is_true(vim.tbl_contains(session.assets, session.opf))
    assert.are.equal(session.workspace, vim.fn.getcwd())
  end)

  it("rebuilds an EPUB with local modifications", function()
    local ok, err = core.open(sample_epub, epubedit.get_config())
    assert(ok, err or "open failed")

    local session = core.state.current
    assert.is_not_nil(session)

    local chapter_path = vim.fn.globpath(session.workspace, "**/chapter1.xhtml", false, true)[1]
    assert.is_not_nil(chapter_path, "chapter1.xhtml not found in workspace")

    vim.cmd("edit " .. vim.fn.fnameescape(chapter_path))
    local chapter_buf = vim.api.nvim_get_current_buf()
    assert.is_not_nil(session.buffers[chapter_buf])

    modify_chapter(chapter_buf, "Hello from the sample EPUB.", "Updated from the spec.")

    local output_dir = uv.fs_mkdtemp(uv.os_tmpdir() .. "/epubedit-output-XXXXXX")
    assert.is_string(output_dir)
    local output_path = output_dir .. "/updated.epub"

    local saved, save_err = core.save(output_path, epubedit.get_config())
    assert(saved, save_err or "save failed")
    assert.are.equal(1, vim.fn.filereadable(output_path))

    local inspect_dir = uv.fs_mkdtemp(uv.os_tmpdir() .. "/epubedit-inspect-XXXXXX")
    assert.is_string(inspect_dir)

    vim.fn.system({ epubedit.get_config().unzip_bin, "-qq", output_path, "-d", inspect_dir })
    assert.are.equal(0, vim.v.shell_error, "failed to inspect rebuilt EPUB")

    local rebuilt_chapter = table.concat(vim.fn.readfile(inspect_dir .. "/OPS/chapter1.xhtml"), "\n")
    assert.is_truthy(rebuilt_chapter:find("Updated from the spec.", 1, true))

    delete_dir(inspect_dir)
    delete_dir(output_dir)
  end)

  it("closes the workspace without saving and restores cwd", function()
    local ok, err = core.open(sample_epub, epubedit.get_config())
    assert(ok, err or "open failed")
    local session = core.state.current
    assert.is_not_nil(session)
    local workspace = session.workspace
    assert.is_truthy(workspace)
    assert.are.equal(1, vim.fn.isdirectory(workspace))
    local closed, close_err = core.close(epubedit.get_config())
    assert(closed, close_err or "close failed")
    assert.is_nil(core.state.current)
    assert.are.equal(0, vim.fn.isdirectory(workspace))
    assert.are.equal(initial_cwd, vim.fn.getcwd())
  end)

  it("auto-opens an EPUB when read via BufReadCmd", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, sample_epub)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_exec_autocmds("BufReadCmd", {
      pattern = sample_epub,
      buffer = buf,
      modeline = false,
    })
    vim.wait(1000, function()
      return core.state.current ~= nil
    end, 20)
    assert.is_not_nil(core.state.current)
    assert.are.equal(vim.fn.fnamemodify(sample_epub, ":p"), core.state.current.source)
    core.close(epubedit.get_config())
  end)
end)
