local epubedit = require("epubedit")
local core = require("epubedit.module")

local neotree = require("neo-tree")
local sample_epub = vim.fn.fnamemodify("tests/fixtures/sample.epub", ":p")

describe("neo-tree auto hooks", function()
  local original_command
  local command_stub

  before_each(function()
    epubedit.setup({ prompt_overwrite = false })
    neotree.setup({
      enable_git_status = false,
      enable_diagnostics = false,
      sources = { "epubedit" },
      default_source = "epubedit",
    })
    original_command = package.loaded["neo-tree.command"]
    command_stub = {
      calls = {},
    }
    function command_stub.execute(args)
      table.insert(command_stub.calls, args)
    end
    package.loaded["neo-tree.command"] = command_stub
    local integration = require("epubedit.neo_tree_integration")
    assert.is_true(vim.tbl_contains(neotree.ensure_config().sources, "epubedit"))
    integration.open("/tmp/epub-auto-test")
    command_stub.calls = {}
  end)

  after_each(function()
    core.cleanup(epubedit.get_config())
    package.loaded["neo-tree.command"] = original_command
  end)

  it("opens the epub source after :EpubEditOpen and closes on save events", function()
    local ok, err = core.open(sample_epub, epubedit.get_config())
    assert(ok, err or "failed to open sample EPUB")
    assert.are_not_equal(0, #command_stub.calls, "expected neo-tree execute to be called")
    local open_call = command_stub.calls[1]
    assert.are.same("show", open_call.action)
    assert.are.same("epubedit", open_call.source)
    assert.is_not_nil(open_call.dir)

    vim.api.nvim_exec_autocmds("User", { pattern = "EpubEditSessionSaved" })
    assert.are_not_equal(1, #command_stub.calls, "expected close call after save event")
    local close_call = command_stub.calls[#command_stub.calls]
    assert.are.same("close", close_call.action)
    assert.are.same("epubedit", close_call.source)
  end)
end)
