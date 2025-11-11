# epub-workflow Specification

## Purpose
TBD - created by archiving change add-epub-editing-workflow. Update Purpose after archive.
## Requirements
### Requirement: Open EPUB Archive
The system MUST allow users to open an EPUB file and unpack it into a workspace managed by the plugin.

#### Scenario: Unpack to managed workspace
- **GIVEN** the user runs `:EpubEditOpen path/to/book.epub`
- **WHEN** the command executes successfully
- **THEN** the EPUB archive is unpacked into a dedicated workspace directory
- **AND** primary assets (HTML/XHTML, CSS, OPF, NCX) are discovered and listed for editing
- **AND** the user is notified of the workspace location or error states

### Requirement: Edit EPUB Assets
The system MUST expose the unpacked EPUB assets for editing inside Neovim buffers.

#### Scenario: Open buffers for key assets
- **GIVEN** an EPUB has been opened via `:EpubEditOpen`
- **WHEN** the plugin prepares buffers for editing
- **THEN** the primary OPF file and nearby HTML/XHTML, CSS, and NCX files are opened or made available through navigation helpers
- **AND** saving a buffer writes changes to the workspace copy
- **AND** the plugin tracks which files have unsaved changes relative to the archive

### Requirement: Repack EPUB Archive
The system MUST repack the modified workspace into a valid EPUB file on user request.

#### Scenario: Rebuild EPUB with modifications
- **GIVEN** the user edits EPUB assets after unpacking
- **WHEN** `:EpubEditSave` is executed (optionally with an output path)
- **THEN** the workspace contents are compressed into an EPUB archive
- **AND** the resulting file contains the latest versions of the edited HTML/XHTML, CSS, OPF, and NCX files
- **AND** the plugin cleans up temporary workspace directories unless preservation is configured
- **AND** the user receives success or error feedback describing the outcome

### Requirement: Report Dependency Health
The system MUST provide a Neovim health check that verifies required external dependencies.

#### Scenario: Health check flags missing `zip`/`unzip`
- **GIVEN** the user runs `:checkhealth epubedit`
- **WHEN** the plugin evaluates dependency availability
- **THEN** it reports success when both `zip` and `unzip` commands are executable
- **AND** it reports actionable error messages when either dependency is missing or misconfigured

### Requirement: Navigate EPUB Structure Tree
The system MUST provide an interactive tree view of the OPF manifest/spine so users can navigate EPUB contents from within Neovim.

#### Scenario: Toggle OPF tree with Nui
- **GIVEN** an EPUB workspace is active after `:EpubEditOpen` (with optional auto-open controlled by configuration)
- **WHEN** the user runs `:EpubEditTreeToggle`
- **THEN** a Nui-based floating window opens displaying the OPF spine in reading order and grouped resource sections
- **AND** selecting a node opens the corresponding file in Neovim using the configured keymaps (defaults: `<CR>` open, `s` split)
- **AND** closing the tree cleans up the Nui components without leaving stray buffers

#### Scenario: Tree refreshes after workspace changes
- **GIVEN** the user modifies the OPF or workspace files that affect the manifest
- **WHEN** the user runs `:EpubEditTreeRefresh`
- **THEN** the tree re-parses the OPF and updates nodes to reflect the latest manifest/spine
- **AND** failures to parse gracefully warn the user while leaving existing navigation (quickfix) available

### Requirement: Neo-tree OPF Source
The system MUST expose the active EPUB workspace through a neo-tree source so users can browse the OPF manifest/spine alongside other navigation panes.

#### Scenario: Render OPF structure inside neo-tree
- **GIVEN** an EPUB workspace is active after `:EpubEditOpen`
- **WHEN** the user runs `:Neotree source=epubedit` (or reveals the source via neo-tree UI)
- **THEN** the source renders the manifest in Sigil-style groups (“Text”, “Styles”, “Images”, “Fonts”, “Audio”, “Video”, “Misc”), keeping the Text section ordered by spine reading order
- **AND** selecting a node opens the corresponding workspace file (respecting the user's default neo-tree open/split actions)
- **AND** the source automatically refreshes after `:EpubEditOpen`, `:EpubEditSave`, or workspace cleanup so it always reflects the current session

#### Scenario: Gracefully handle missing context
- **GIVEN** neo-tree is loaded but no EPUB workspace is active or the OPF cannot be parsed
- **WHEN** the user requests the `epubedit` source
- **THEN** the source displays an informative placeholder node instead of crashing (e.g., "No EPUB workspace" or the parse error message)
- **AND** the placeholder disappears once a valid workspace is opened and parsed successfully

#### Scenario: Auto open/close the neo-tree source
- **GIVEN** neo-tree is installed and configured with the `epubedit` source
- **WHEN** `:EpubEditOpen` completes successfully
- **THEN** the plugin automatically opens the `epubedit` source without stealing focus
- **AND** after `:EpubEditSave` or workspace cleanup the pane closes so stale workspaces do not linger
- **AND** when neo-tree is absent the plugin skips these hooks without generating errors

#### Scenario: Sync OPF manifest after neo-tree rename
- **GIVEN** an EPUB workspace is active and the user renames or moves an asset from Neo-tree’s `epubedit` source
- **WHEN** the rename completes
- **THEN** the plugin updates the OPF manifest entry for that asset so its `href` points to the new filename
- **AND** the `epubedit` source automatically refreshes so the renamed file appears immediately

### Requirement: Edit OPF Metadata
The system MUST provide a user interface to edit the core metadata of the EPUB from the OPF file.

#### Scenario: Open metadata editor
- **GIVEN** an EPUB workspace is active.
- **WHEN** the user runs a command like `:EpubEditMetadata`.
- **THEN** a dedicated editor view opens, displaying the current values for metadata fields like `dc:title`, `dc:creator`, `dc:language`, `dc:publisher`, and `dc:date`.

#### Scenario: Modify and save metadata
- **GIVEN** the metadata editor is open.
- **WHEN** the user modifies one or more metadata fields and triggers a save action.
- **THEN** the changes are written back to the `content.opf` file in the workspace.
- **AND** the user receives feedback confirming that the metadata was saved.

#### Scenario: Handle missing metadata
- **GIVEN** the metadata editor is open.
- **WHEN** the `content.opf` file is missing optional metadata fields (e.g., publisher).
- **THEN** the editor displays the fields as empty and allows the user to add values.

