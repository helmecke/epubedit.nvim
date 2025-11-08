local stub = require("luassert.stub")

local opf_view = require("epubedit.opf_view")
local opf_parser = require("epubedit.parser.opf")

describe("opf view labels", function()
  local parse_stub

  after_each(function()
    if parse_stub then
      parse_stub:revert()
      parse_stub = nil
    end
  end)

  it("includes the OPF base directory in node names", function()
    local workspace = vim.fn.fnamemodify(vim.loop.fs_mkdtemp("/tmp/epub-label-XXXXXX"), ":p")
    local session = {
      workspace = workspace,
      opf = workspace .. "OEBPS/content.opf",
    }
    local text_item = {
      href = "Text/nav.xhtml",
      media_type = "application/xhtml+xml",
    }
    parse_stub = stub(opf_parser, "parse").returns({
      manifest = {
        nav = text_item,
      },
      spine = { text_item },
      base_dir = workspace .. "OEBPS/",
    })

    local result = opf_view.build(session, {})
    assert.is_table(result)
    local nodes = result.nodes or {}
    local text_group = nodes[1]
    assert.are.equal("Text", text_group.name)
    local child = assert(text_group.children[1])
    assert.are.equal("OEBPS/Text/nav.xhtml", child.name)
  end)
end)
