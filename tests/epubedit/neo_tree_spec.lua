local epubedit = require("epubedit")
local core = require("epubedit.module")

local manager = require("neo-tree.sources.manager")
local renderer = require("neo-tree.ui.renderer")
local neotree = require("neo-tree")

local sample_epub = vim.fn.fnamemodify("tests/fixtures/sample.epub", ":p")

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

  it("provides a refresh command for default mappings", function()
    local state = manager.get_state("epubedit")
    assert.is_function(state.commands.refresh)
  end)
end)
