local opf_parser = require("epubedit.parser.opf")

describe("opf parser", function()
  it("extracts manifest and spine entries", function()
    local path = vim.fn.fnamemodify("tests/fixtures/sample.epub", ":p")

    local tmp = vim.loop.fs_mkdtemp(vim.loop.os_tmpdir() .. "/opf-parser-XXXXXX")
    assert.is_string(tmp)

    vim.fn.system({ "unzip", "-qq", path, "-d", tmp })
    assert.are.equal(0, vim.v.shell_error)

    local parsed, err = opf_parser.parse(tmp .. "/OPS/content.opf")
    assert(parsed, err)

    assert.is_not_nil(parsed.manifest["chapter1"])
    assert.is_truthy(#parsed.spine > 0)
    assert.are.equal("chapter1.xhtml", parsed.spine[1].href)
    assert(parsed.resources["text/css"])

    vim.fn.delete(tmp, "rf")
  end)
end)
