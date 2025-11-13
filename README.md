# epubedit.nvim

Edit EPUB archives directly from Neovim. `epubedit.nvim` unpacks an EPUB into a temporary workspace and repacks the archive when you are done.

## Requirements

- Neovim 0.8.0 or newer
- [`MunifTanjim/nui.nvim`](https://github.com/MunifTanjim/nui.nvim)
- System `zip` and `unzip` binaries available on `$PATH` (configurable)
- Optional: [`nvim-neo-tree/neo-tree.nvim`](https://github.com/nvim-neo-tree/neo-tree.nvim) to browse the OPF via a dedicated source

## Installation

Install with your preferred plugin manager. Example using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "helmecke/epubedit.nvim",
  dependencies = { "MunifTanjim/nui.nvim" },
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

After `:EpubEditOpen`, the plugin automatically opens and focuses Neo-tree’s `epubedit` source (as long as neo-tree is installed and the source is registered in your `sources` list) so you can see the OPF spine followed by manifest resources grouped by media type. You can still trigger `:Neotree source=epubedit` manually if you close it. The pane refreshes automatically after `:EpubEditOpen`, `:EpubEditSave`, or when the workspace is cleaned up, and it closes again after `:EpubEditSave`/cleanup so you are not left with a stale tree. When no session is active, the source displays a helpful placeholder instead of throwing errors. Renaming or moving files inside the `epubedit` source updates the manifest `href` inside the OPF and immediately refreshes the tree so the new location is reflected everywhere. File nodes mimic Sigil’s book browser by showing OPF-relative paths (e.g., `OEBPS/Text/Section0001.xhtml`), making it easy to correlate entries with the underlying archive, and the move dialog only asks for the portion after the OPF root (e.g., everything after `OEBPS/`) so the root directory itself stays intact. While focused on a Text entry, press `J`/`K` to move it down/up and the OPF spine order is rewritten to match.
Grouping mirrors Sigil’s “Text / Styles / Images / Fonts / Audio / Video / Misc” structure, and you can rename/reorder those sections via `neo_tree.group_labels` and `neo_tree.group_order`.

Tip: launching Neovim with an EPUB file (`nvim book.epub`) automatically hands the buffer off to `:EpubEditOpen`, so you can jump straight into the unpacked workspace without running the command manually.

### Commands

- `:EpubEditOpen [path]` – Unpack an EPUB into a workspace.
- `:EpubEditSave [path]` – Repack the active workspace. Optional `path` writes to a different location; otherwise the original file is replaced (with confirmation by default).
- `:EpubEditClose` – Abandon the current workspace without saving, clean up the temp directory, and restore the previous working directory.
- `:EpubEditMetadata` – Open a floating window to edit the EPUB's metadata (title, author, etc.).
- `:EpubEditSpine` – Open a buffer to edit the EPUB's reading order (spine).
- `:EpubEditPreview` – Open the current XHTML/HTML file in your default web browser for live preview.
- `:EpubEditCheck` – Run epubcheck and `xmllint --noout` against the active workspace, surfacing diagnostics in the quickfix list.

### Metadata Editor

Run `:EpubEditMetadata` to open a floating window for editing the `content.opf` metadata. This provides a simple form-based view of the EPUB's title, author, language, and other Dublin Core fields. Press `<CR>` on a line to edit the value, and `<C-s>` to save the changes back to the workspace.

### Spine Editor

Run `:EpubEditSpine` to open a special buffer displaying the EPUB's reading order (spine). Each line shows the `href` of a content document in the order readers will encounter them. Reorder lines by cutting and pasting (dd/p), moving blocks with visual mode, or any other Neovim editing commands. Save with `:w` or `<C-s>` to write the new order back to the `content.opf` file. Press `q` to close the editor without saving.

### Preview Mode

Run `:EpubEditPreview` while editing an XHTML or HTML file to open it in your default web browser. The plugin automatically starts a local HTTP server (using Python's `http.server`) serving from the OPF directory on an automatically-selected available port. The server runs in the background and is automatically stopped when you close the EPUB session. URLs are mapped relative to the OPF directory, ensuring that internal links and resources (CSS, images, etc.) load correctly in the browser.

## Snippet Support

epubedit.nvim integrates with [LuaSnip](https://github.com/L3MON4D3/LuaSnip) to provide Sigil-style snippet functionality for EPUB editing.

### Quick Start

#### 1. Enable LuaSnip in LazyVim

```vim
:LazyExtras
```

Select and enable: **`coding.luasnip`**

#### 2. Configure Snippets for EPUB

Run the configuration command:

```vim
:EpubEditConfigureSnippets
```

This automatically:
- Extends XHTML filetype to include HTML snippets
- Loads epubedit.nvim's built-in EPUB snippet library
- Configures LuaSnip to work with EPUB/XHTML files

#### 3. Check Setup Status

```vim
:checkhealth epubedit
```

The health check shows:
- ✅/⚠️ LuaSnip installation status
- Number of available snippet files
- Snippets loaded for current filetype

### Built-in Snippets

#### Structural Elements

| Trigger | Expands To | Description |
|---------|------------|-------------|
| `chap` | Full chapter template | Complete EPUB chapter with XML declaration, namespace, and structure |
| `section` | `<section epub:type="">` | Section element with epub:type attribute |
| `section+` | Section with auto-generated ID | Dynamic section with timestamp-based unique ID |
| `div` | `<div class="">` | Div with class attribute |

#### Text Elements

| Trigger | Expands To | Description |
|---------|------------|-------------|
| `p:` | `<p epub:type="">` | Paragraph with epub:type attribute |
| `bridgehead` | `<p epub:type="bridgehead">` | Bridgehead (unnumbered heading) paragraph |
| `bq` | `<blockquote><p></p></blockquote>` | Blockquote with paragraph |
| `em` | `<em></em>` | Emphasis (italic) |
| `strong` | `<strong></strong>` | Strong (bold) |
| `code` | `<code></code>` | Inline code |

#### Media Elements

| Trigger | Expands To | Description |
|---------|------------|-------------|
| `img` | `<img src="../Images/" alt="" />` | Image with EPUB relative path |
| `img+` | Image with auto-generated ID | Dynamic image with ID based on filename |
| `figure` | Complete figure with caption | Figure element with image and figcaption, auto-generated ID |

#### Links and References

| Trigger | Expands To | Description |
|---------|------------|-------------|
| `alink` | `<a href=".xhtml#">` | Internal chapter link with anchor |
| `alink+` | Link with auto-generated ID | Dynamic link with unique ID |
| `fnref` | `<a epub:type="noteref" href="#fn">` | Footnote reference |
| `footnote` | `<aside epub:type="footnote" id="fn">` | Footnote aside element |

#### Lists

| Trigger | Expands To | Description |
|---------|------------|-------------|
| `ul` | `<ul><li></li></ul>` | Unordered (bulleted) list |
| `ol` | `<ol><li></li></ol>` | Ordered (numbered) list |
| `dl` | `<dl><dt></dt><dd></dd></dl>` | Definition list |

#### Other Elements

| Trigger | Expands To | Description |
|---------|------------|-------------|
| `scene` | `<div class="scenebreak"><hr /></div>` | Scene break separator |
| `pre` | `<pre></pre>` | Preformatted text block |
| `span` | `<span class="">` | Span with class attribute |
| `aside+` | Aside with choices and ID | Dynamic aside with type selection (sidebar/note/warning/tip/footnote) |
| `table+` | Complete table structure | Table with thead, tbody, and auto-generated ID |

#### Utility Snippets

| Trigger | Expands To | Description |
|---------|------------|-------------|
| `date` | Current date | Inserts current date (YYYY-MM-DD) |
| `timestamp` | Current timestamp | Inserts current date and time |
| `meta` | `<meta>` tag | Meta tag with choices for content |

### Using Snippets

#### Basic Usage

1. Type the snippet trigger (e.g., `chap`)
2. Press `Tab` (or your configured expand key)
3. Snippet expands with cursor at first placeholder
4. Type your content
5. Press `Tab` to jump to next placeholder
6. Press `Shift+Tab` to jump to previous placeholder

**Example:**
```
chap<Tab> → [cursor at Chapter Title] → My Chapter<Tab> → [cursor at stylesheet] → mystyle<Tab> → [cursor in body]
```

#### Snippet Placeholders

Snippets use numbered placeholders:
- `$1`, `$2`, `$3` - Tab stops in order
- `$0` - Final cursor position after all tabs
- `${1:default}` - Placeholder with default text

**Example:**
```lua
"body": "<p epub:type=\"${1:normal}\">$2</p>$0"
```
- First tab: select/edit "normal"
- Second tab: enter paragraph content
- Third tab: cursor after `</p>`

#### Dynamic Snippets

Dynamic snippets (those with `+` suffix) include auto-generated content:

**`img+` example:**
```
img+<Tab> → cover.jpg<Tab> → Book cover<Tab>
```
Expands to:
```html
<img src="../Images/cover.jpg" alt="Book cover" id="img_cover" />
```
The ID is automatically generated from the filename.

**`date` example:**
```
date<Tab>
```
Expands to current date:
```
2025-01-13
```

### Creating Custom Snippets

#### Simple Snippets (JSON)

Create `~/.config/nvim/snippets/html.json`:

```json
{
  "My Custom Snippet": {
    "prefix": "mycustom",
    "body": [
      "<div class=\"custom\">",
      "  <p>$1</p>",
      "</div>$0"
    ],
    "description": "My custom EPUB pattern"
  }
}
```

#### Dynamic Snippets (Lua)

Create `~/.config/nvim/LuaSnip/xhtml.lua`:

```lua
local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node

return {
  s("author", {
    t("<meta name=\"author\" content=\""),
    f(function()
      return vim.fn.system("git config user.name"):gsub("\n", "")
    end),
    t("\" />"),
  }),
}
```

This creates a snippet that inserts your git username as the author meta tag.

#### Project-Specific Snippets

For EPUB-specific workflows, create `.luasniprc.lua` in your EPUB workspace:

```lua
local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node

ls.add_snippets("xhtml", {
  s("series", {
    t("<meta property=\"belongs-to-collection\" content=\""),
    i(1, "My Series Name"),
    t("\" id=\"series-name\" />"),
  }),
})
```

### Neovim Clipboard History

Sigil's clipboard history feature is available natively in Neovim through **registers**.

#### Using Registers

Neovim automatically saves your last 9 deletions/yanks:
- `"0` - Last yank
- `"1` through `"9` - Last 9 deletions (most recent first)

#### View Register Contents

```vim
:reg
```

Shows all registers and their contents.

#### Paste from Specific Register

In normal mode:
```vim
"3p    " Paste from register 3 (3rd most recent deletion)
"0p    " Paste last yank
```

In insert mode:
```vim
<C-r>3    " Insert from register 3
<C-r>0    " Insert last yank
```

#### Practical Example

1. Delete a paragraph: `dap` (saved to `"1`)
2. Delete another paragraph: `dap` (saved to `"1`, previous moves to `"2`)
3. Paste first deletion: `"2p`
4. Paste second deletion: `"1p`

### Troubleshooting

#### Snippets Not Working

1. Check LuaSnip is installed:
   ```vim
   :checkhealth epubedit
   ```

2. Verify filetype is correct:
   ```vim
   :set filetype?
   ```
   Should show `xhtml` or `html`.

3. Re-run configuration:
   ```vim
   :EpubEditConfigureSnippets
   ```

#### Custom Snippets Not Loading

1. Check file location:
   - JSON: `~/.config/nvim/snippets/html.json`
   - Lua: `~/.config/nvim/LuaSnip/xhtml.lua`

2. Verify JSON syntax is valid

3. Reload snippets:
   ```vim
   :lua require("luasnip.loaders.from_vscode").lazy_load()
   :lua require("luasnip.loaders.from_lua").lazy_load()
   ```

#### Tab Key Conflict

If Tab doesn't expand snippets, check your completion plugin configuration.

**For nvim-cmp (LazyVim default):**

The Tab key should already be configured to:
- Expand snippet if available
- Navigate completion menu if visible
- Insert tab character otherwise

If not working, add to `lua/plugins/nvim-cmp.lua`:

```lua
return {
  "hrsh7th/nvim-cmp",
  opts = function(_, opts)
    local cmp = require("cmp")
    opts.mapping = opts.mapping or {}
    opts.mapping["<Tab>"] = cmp.mapping(function(fallback)
      if cmp.visible() then
        cmp.select_next_item()
      elseif require("luasnip").expand_or_jumpable() then
        require("luasnip").expand_or_jump()
      else
        fallback()
      end
    end, { "i", "s" })
  end,
}
```

### Advanced Usage

#### Conditional Snippets

Create snippets that only trigger in specific contexts:

```lua
local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node

return {
  s("h1only", {
    t("<h1>"),
    i(1),
    t("</h1>"),
  }, {
    condition = function()
      return vim.fn.line(".") == 1
    end,
  }),
}
```

This `h1only` snippet only expands on the first line of the file.

#### Snippet with Choices

```lua
s("align", {
  t('<p style="text-align: '),
  c(1, {
    t("left"),
    t("center"),
    t("right"),
    t("justify"),
  }),
  t(';">'),
  i(2),
  t("</p>"),
})
```

Press `Ctrl+n` / `Ctrl+p` to cycle through alignment choices.

#### Integration with OPF Manifest

For advanced users, create snippets that read from the OPF manifest:

```lua
s("stylelink", {
  t('<link href="../Styles/'),
  d(1, function()
    local session = require("epubedit.module").state.current
    if session and session.opf then
      local parsed = require("epubedit.opf_parser").parse(session.opf)
      local stylesheets = {}
      for _, item in pairs(parsed.manifest or {}) do
        if item["media-type"] == "text/css" then
          local href = item.href or ""
          local filename = href:match("([^/]+)%.css$")
          if filename then
            table.insert(stylesheets, filename)
          end
        end
      end
      if #stylesheets > 0 then
        return sn(nil, {
          c(1, vim.tbl_map(function(name)
            return t(name .. ".css")
          end, stylesheets))
        })
      end
    end
    return sn(nil, { i(1, "stylesheet.css") })
  end),
  t('" rel="stylesheet" type="text/css" />'),
})
```

This creates a snippet that dynamically lists all CSS files from the EPUB manifest.

### Resources

- [LuaSnip Documentation](https://github.com/L3MON4D3/LuaSnip)
- [LuaSnip Snippet Writing Tutorial](https://github.com/L3MON4D3/LuaSnip/blob/master/DOC.md)
- [VSCode Snippet Format](https://code.visualstudio.com/docs/editor/userdefinedsnippets)
- [friendly-snippets Collection](https://github.com/rafamadriz/friendly-snippets)

### Comparison with Sigil

| Feature | Sigil | epubedit.nvim + LuaSnip |
|---------|-------|-------------------------|
| UI | Panel sidebar | Inline completion menu |
| Activation | Click or keyboard shortcut | Type trigger + Tab |
| Customization | GUI editor | JSON/Lua files |
| Dynamic content | Limited | Full Lua programming |
| Categories | Visual groups | Description field in completion |
| Clipboard history | Built-in panel | Neovim registers (`"0`-`"9`) |
| Performance | GUI overhead | Instant, keyboard-only |
| Extensibility | Plugin system | Native Lua integration |

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
  validators = {
    epubcheck = "epubcheck", -- or { "java", "-jar", "/path/epubcheck.jar" }
    xmllint = "xmllint",    -- set to nil to skip XML linting
  },
})
```

`workspace_root` defaults to the OS temp directory. When set, the plugin creates uniquely named sub-directories inside the provided path. The `neo_tree` section lets you override the Sigil-style grouping order/labels used inside the neo-tree source.

The `validators` table configures external tools used by `:EpubEditCheck`. Provide either a string executable or a list of `{ command, args... }`. Leave a value `nil` to skip that validator.

## Development

- Run the test suite with `make test` (requires Neovim plus `zip`/`unzip`).
- Format Lua code with `stylua lua plugin`.
- Regenerate help docs with `make docs` (CI handles this automatically via `panvimdoc`).
