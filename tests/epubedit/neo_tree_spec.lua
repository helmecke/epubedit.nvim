local epubedit = require("epubedit")
local core = require("epubedit.module")

local stub = require("luassert.stub")
local match = require("luassert.match")

local manager = require("neo-tree.sources.manager")
local renderer = require("neo-tree.ui.renderer")
local neotree = require("neo-tree")
local fs_actions = require("neo-tree.sources.filesystem.lib.fs_actions")
local inputs = require("neo-tree.ui.inputs")

local sample_epub = vim.fn.fnamemodify("tests/fixtures/sample.epub", ":p")
local sample_epub3 = vim.fn.fnamemodify("tests/fixtures/sample-epub3.epub", ":p")

local neotree_ready = false
local original_show_nodes = renderer.show_nodes

local function ensure_neotree()
  if neotree_ready then
    manager._clear_state()
    return
  end

  package.loaded["neo-tree.sources.epubedit"] = require("epubedit.neo_tree")

  neotree.setup({
    enable_git_status = false,
    enable_diagnostics = false,
    use_default_mappings = false,
    close_if_last_window = false,
    sources = { "epubedit" },
    default_source = "epubedit",
    source_selector = {
      sources = {
        { source = "epubedit", display_name = "EPUB" },
      },
    },
    epubedit = {
      window = {
        position = "current",
      },
    },
  })

  neotree_ready = true
end

local function collect_nodes()
  manager.navigate("epubedit")
  local state = manager.get_state("epubedit")
  assert.is_not_nil(state._test_nodes, "neo-tree did not render nodes")
  return state._test_nodes
end

describe("neo-tree source", function()
  before_each(function()
    ensure_neotree()
    epubedit.setup({ prompt_overwrite = false })
    _G.__epubedit_swapfile = vim.o.swapfile
    vim.o.swapfile = false
    renderer.show_nodes = function(nodes, state)
      state._test_nodes = nodes
    end
  end)

  after_each(function()
    core.cleanup(epubedit.get_config())
    manager._clear_state()
    renderer.show_nodes = original_show_nodes
    if _G.__epubedit_swapfile ~= nil then
      vim.o.swapfile = _G.__epubedit_swapfile
      _G.__epubedit_swapfile = nil
    end
  end)

  it("shows placeholder when no session is active", function()
    local nodes = collect_nodes()
    assert.is_true(#nodes >= 1, "expected at least one placeholder node")
    assert.are.equal("message", nodes[1].type)
  end)

  it("lists spine entries after opening an EPUB", function()
    local ok, err = core.open(sample_epub, epubedit.get_config())
    assert(ok, err or "failed to open EPUB")

    local roots = collect_nodes()

    local text_group
    for _, node in ipairs(roots) do
      if node.name == "Text" then
        text_group = node
        break
      end
    end
    assert.is_not_nil(text_group, "expected a Text group node")

    local text_children = text_group.children or {}
    assert.is_true(#text_children > 0, "expected text entries")
    local first = text_children[1]
    assert.are.equal("file", first.type)
    assert.are.equal(1, vim.fn.filereadable(first.path))
  end)

  it("provides custom refresh/move commands for default mappings", function()
    local state = manager.get_state("epubedit")
    assert.is_function(state.commands.refresh)
    assert.is_function(state.commands.move)
  end)

  it("moves files using workspace-relative prompts", function()
    local ok, err = core.open(sample_epub, epubedit.get_config())
    assert(ok, err or "failed to open EPUB")
    collect_nodes()
    local state = manager.get_state("epubedit")
    local session = core.state.current
    local workspace = session.workspace
    local source = vim.fn.fnamemodify(workspace .. "/OPS/chapter1.xhtml", ":p")
    local original_tree = state.tree
    state.tree = {
      get_node = function()
        return {
          path = source,
          type = "file",
        }
      end,
    }
    local move_spy = stub(fs_actions, "move_node")
    local input_spy = stub(inputs, "input", function(prompt, default_value, cb)
      assert.is_truthy(prompt:match("relative to OPS/"))
      assert.are.equal("chapter1.xhtml", default_value)
      cb("Text/Section0001.xhtml")
    end)

    state.commands.move(state)
    local expected = vim.fn.fnamemodify(workspace .. "/OPS/Text/Section0001.xhtml", ":p")
    assert.stub(move_spy).was_called_with(source, expected, match.is_function(), nil)

    move_spy:revert()
    input_spy:revert()
    state.tree = original_tree
    core.cleanup(epubedit.get_config())
  end)

  it("keeps OPF root prefix intact for EPUB3 layouts", function()
    local ok, err = core.open(sample_epub3, epubedit.get_config())
    assert(ok, err or "failed to open EPUB3")
    collect_nodes()
    local state = manager.get_state("epubedit")
    local workspace = core.state.current.workspace
    local source = vim.fn.fnamemodify(workspace .. "/OEBPS/Text/nav.xhtml", ":p")
    local original_tree = state.tree
    state.tree = {
      get_node = function()
        return {
          path = source,
          type = "file",
        }
      end,
    }
    local move_spy = stub(fs_actions, "move_node")
    local input_spy = stub(inputs, "input", function(prompt, default_value, cb)
      assert.is_truthy(prompt:match("relative to OEBPS/"))
      assert.are.equal("Text/nav.xhtml", default_value)
      cb("Styles/nav.xhtml")
    end)

    state.commands.move(state)
    local expected = vim.fn.fnamemodify(workspace .. "/OEBPS/Styles/nav.xhtml", ":p")
    assert.stub(move_spy).was_called_with(source, expected, match.is_function(), nil)

    move_spy:revert()
    input_spy:revert()
    state.tree = original_tree
    core.cleanup(epubedit.get_config())
  end)
end)
