local opf_manager = require("epubedit.opf_manager")
local core = require("epubedit.module")

describe("Spine Editor - OPF Manager Functions", function()
  local sample_epub
  local tmp_dir
  local session

  before_each(function()
    sample_epub = vim.fn.fnamemodify("tests/fixtures/sample-epub3.epub", ":p")
    tmp_dir = vim.loop.fs_mkdtemp(vim.loop.os_tmpdir() .. "/spine-test-XXXXXX")
    assert.is_string(tmp_dir)

    -- Unpack EPUB
    vim.fn.system({ "unzip", "-qq", sample_epub, "-d", tmp_dir })
    assert.are.equal(0, vim.v.shell_error)

    -- Create session manually (EPUB3 uses OEBPS)
    local opf_path = tmp_dir .. "/OEBPS/content.opf"
    session = {
      opf = opf_path,
      workspace = tmp_dir,
    }
  end)

  after_each(function()
    if tmp_dir then
      vim.fn.delete(tmp_dir, "rf")
    end
  end)

  it("should get spine items from OPF", function()
    local spine, err = opf_manager.get_spine(session)
    assert.is_nil(err)
    assert.is_not_nil(spine)
    assert.is_true(#spine > 0)

    -- Verify spine items have required fields
    for _, item in ipairs(spine) do
      assert.is_not_nil(item.id)
      assert.is_not_nil(item.href)
    end
  end)

  it("should set spine order", function()
    -- Get original spine
    local original_spine, err = opf_manager.get_spine(session)
    assert.is_nil(err)
    assert.is_not_nil(original_spine)
    assert.is_true(#original_spine >= 2, "Need at least 2 items to test reordering")

    -- Reverse the order
    local reversed_spine = {}
    for i = #original_spine, 1, -1 do
      table.insert(reversed_spine, original_spine[i])
    end

    -- Set new spine order
    local ok, set_err = opf_manager.set_spine(session, reversed_spine)
    assert.is_true(ok)
    assert.is_nil(set_err)

    -- Verify the order changed
    local new_spine, get_err = opf_manager.get_spine(session)
    assert.is_nil(get_err)
    assert.is_not_nil(new_spine)
    assert.equals(#reversed_spine, #new_spine)

    -- Check first and last items swapped
    assert.equals(reversed_spine[1].id, new_spine[1].id)
    assert.equals(reversed_spine[#reversed_spine].id, new_spine[#new_spine].id)
  end)

  it("should handle empty session gracefully", function()
    local empty_session = {}
    local spine, err = opf_manager.get_spine(empty_session)
    assert.is_nil(spine)
    assert.is_not_nil(err)
    assert.equals("no active OPF", err)
  end)
end)
