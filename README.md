# epubedit.nvim

Edit EPUB archives directly from Neovim. `epubedit.nvim` unpacks an EPUB into a temporary workspace and repacks the archive when you are done.

## Requirements

- Neovim 0.8.0 or newer
- System `zip` and `unzip` binaries available on `$PATH` (configurable)
- Optional: [`nvim-neo-tree/neo-tree.nvim`](https://github.com/nvim-neo-tree/neo-tree.nvim) to browse the OPF via a dedicated source

## Installation

Install with your preferred plugin manager. Example using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "helmecke/epubedit.nvim",
  config = function()
    require("epubedit").setup()
  end,
}
```

## Usage

1. Run `:EpubEditOpen path/to/book.epub` (or omit the path to be prompted). The plugin unpacks the archive into a managed workspace on disk and switches Neovim's current working directory to that location.
2. Edit any buffer inside the workspace using normal Neovim navigation—`:edit`, Telescope, fuzzy finders, etc. Saving a buffer writes back to the unpacked copy.
3. Run `:EpubEditSave` to repack the archive in place, or `:EpubEditSave path/to/output.epub` to create a new copy.

If unsaved buffers exist, `:EpubEditSave` refuses to proceed and lists the files to write. Workspaces are cleaned up automatically after saving unless `preserve_workspace = true`, and the working directory is restored when the session ends.

### Neo-tree source

If you navigate with [neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim), add the `epubedit` source to its configuration:

```lua
require("neo-tree").setup({
  sources = { "filesystem", "buffers", "git_status", "epubedit" },
  default_source = "filesystem",
  epubedit = {
    window = { position = "right" }, -- pick any location you prefer
  },
})
```

After opening an EPUB workspace, run `:Neotree source=epubedit` (or use the source selector) to see the OPF spine followed by manifest resources grouped by media type. The source refreshes automatically after `:EpubEditOpen`, `:EpubEditSave`, or when the workspace is cleaned up; it displays a helpful placeholder when no session is active.
Grouping mirrors Sigil’s “Text / Styles / Images / Fonts / Audio / Video / Misc” structure, and you can rename/reorder those sections via `neo_tree.group_labels` and `neo_tree.group_order`.

### Commands

- `:EpubEditOpen [path]` – Unpack an EPUB into a workspace.
- `:EpubEditSave [path]` – Repack the active workspace. Optional `path` writes to a different location; otherwise the original file is replaced (with confirmation by default).

### Health Check

Run `:checkhealth epubedit` to verify the `zip`/`unzip` dependencies and workspace configuration.

## Configuration

```lua
require("epubedit").setup({
  zip_bin = "zip",          -- custom path to `zip`
  unzip_bin = "unzip",      -- custom path to `unzip`
  workspace_root = nil,     -- optional directory for unpacked workspaces
  preserve_workspace = false, -- keep workspaces after saving
  prompt_overwrite = true,  -- confirm before overwriting the source EPUB
  neo_tree = {
    group_order = { "text", "styles", "images", "fonts", "audio", "video", "misc" },
    group_labels = {
      text = "Text",
      styles = "Styles",
      images = "Images",
      fonts = "Fonts",
      audio = "Audio",
      video = "Video",
      misc = "Misc",
    },
  },
})
```

`workspace_root` defaults to the OS temp directory. When set, the plugin creates uniquely named sub-directories inside the provided path. The `neo_tree` section lets you override the Sigil-style grouping order/labels used inside the neo-tree source.

## Development

- Run the test suite with `make test` (requires Neovim plus `zip`/`unzip`).
- Format Lua code with `stylua lua plugin`.
- Regenerate help docs with `make docs` (CI handles this automatically via `panvimdoc`).
