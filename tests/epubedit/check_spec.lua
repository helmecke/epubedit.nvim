local stub = require("luassert.stub")

local epubedit = require("epubedit")
local module = require("epubedit.module")

local sample_epub = vim.fn.fnamemodify("tests/fixtures/sample.epub", ":p")
local sample_epub3 = vim.fn.fnamemodify("tests/fixtures/sample-epub3.epub", ":p")

describe(":EpubEditCheck", function()
  local original_runner
  local original_executable
  local original_setqflist
  local original_cmd
  local original_notify
  local entries
  local copen_calls
  local cclose_calls
  local notifications

  local function prepare_workspace(target)
    local epub = target or sample_epub
    local ok, err = module.open(epub, epubedit.get_config())
    assert(ok, err)
    vim.wait(200)
    return module.state.current
  end

  local executable_status

  before_each(function()
    epubedit.setup({
      prompt_overwrite = false,
      validators = {
        epubcheck = "fake-epubcheck",
        xmllint = "fake-xmllint",
      },
    })
    entries = nil
    copen_calls = 0
    cclose_calls = 0
    notifications = {}
    executable_status = {
      ["fake-epubcheck"] = 1,
      ["fake-xmllint"] = 1,
    }

    original_runner = module._set_validation_runner(function(command, extra_args)
      if command[1] == "fake-epubcheck" then
        return 1, { "ERROR(RSC-005): OPS/chapter1.xhtml(12,5): Missing closing tag" }, {}
      end
      if command[1] == "fake-xmllint" then
        return 0, {}, {}
      end
      return 0, {}, {}
    end)

    original_executable = stub(vim.fn, "executable", function(bin)
      if executable_status[bin] ~= nil then
        return executable_status[bin]
      end
      return 1
    end)

    original_setqflist = stub(vim.fn, "setqflist", function(list, _, opts)
      if opts and opts.items and #opts.items > 0 then
        entries = opts.items
      end
    end)

    original_cmd = stub(vim, "cmd", function(command)
      if command == "copen" then
        copen_calls = copen_calls + 1
        return
      end
      if command == "cclose" then
        cclose_calls = cclose_calls + 1
        return
      end
      return command
    end)

    original_notify = stub(vim, "notify", function(msg)
      table.insert(notifications, msg)
    end)
  end)

  after_each(function()
    module.close(epubedit.get_config())
    if original_runner then
      module._set_validation_runner(original_runner)
    end
    if original_executable then
      original_executable:revert()
    end
    if original_setqflist then
      original_setqflist:revert()
    end
    if original_cmd then
      original_cmd:revert()
    end
    if original_notify then
      original_notify:revert()
    end
  end)

  it("populates quickfix with validator diagnostics", function()
    prepare_workspace()
    module.check(epubedit.get_config())
    assert.is_not_nil(entries)
    assert.are.equal(1, #entries)
    local entry = entries[1]
    assert.truthy(entry.filename:match("chapter1%.xhtml$"))
    assert.are.equal(12, entry.lnum)
    assert.are.equal("[epubcheck] Missing closing tag", entry.text)
    assert.are.equal(0, cclose_calls)
    assert.is_true(copen_calls > 0)
  end)

  it("closes quickfix and notifies on success", function()
    module._set_validation_runner(function()
      return 0, {}, {}
    end)
    prepare_workspace()
    module.check(epubedit.get_config())
    assert.is_nil(entries)
    assert.is_true(cclose_calls > 0)
    assert.is_truthy(table.concat(notifications, "\n"):match("validation succeeded"))
  end)

  it("warns when validators are missing but still runs available ones", function()
    module._set_validation_runner(function(command)
      if command[1] == "fake-xmllint" then
        return 0, {}, {}
      end
      return 0, {}, {}
    end)
    executable_status["fake-epubcheck"] = 0
    prepare_workspace()
    local ok = module.check(epubedit.get_config())
    assert.is_true(ok)
    assert.is_nil(entries)
    local joined = table.concat(notifications, "\n")
    assert.matches("epubedit:%s+epubcheck binary 'fake%-epubcheck' not found", joined)
    assert.is_truthy(joined:match("validation succeeded"))
  end)

  it("filters summary lines and maps archive paths to workspace files", function()
    local session = prepare_workspace(sample_epub3)
    module._set_validation_runner(function(command)
      if command[1] == "fake-epubcheck" then
        return 1, {
          "Validating using EPUB version 3.3 rules.",
          "ERROR(PKG-006): /tmp/nvim.tmp/1.epub(-1,-1): Mimetype file entry is missing or is not the first file in the archive.",
          'ERROR(RSC-005): /tmp/nvim.tmp/1.epub/OEBPS/Text/Section0001.xhtml(6,10): Error while parsing file: Element "title" must not be empty.',
          "Check finished with errors",
        }, {}
      end
      if command[1] == "fake-xmllint" then
        return 0, {}, {}
      end
      return 0, {}, {}
    end)
    module.check(epubedit.get_config())
    assert.is_not_nil(entries)
    assert.are.equal(1, #entries)

    local entry = entries[1]
    assert.are.equal(6, entry.lnum)
    assert.are.equal(10, entry.col)
    local expected_path = vim.fn.fnamemodify(session.workspace .. "/OEBPS/Text/Section0001.xhtml", ":p")
    assert.are.equal(expected_path, entry.filename)
    assert.are.equal(
      "[epubcheck] Error while parsing file: Element \"title\" must not be empty.",
      entry.text
    )
  end)
end)
