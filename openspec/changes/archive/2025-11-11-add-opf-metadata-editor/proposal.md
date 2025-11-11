# Change: Add OPF Metadata Editor

## Why
The `content.opf` file in an EPUB contains critical metadata (title, author, publisher, etc.). Currently, users can edit the raw XML, but this is error-prone and requires knowledge of the OPF schema. A dedicated metadata editor would provide a user-friendly interface to view and modify this data, reducing errors and improving the editing experience.

## What Changes
- **ADDED**: A new UI component to display and edit the metadata from the `content.opf` file.
- **ADDED**: User commands to open and save the metadata from the editor.
- **MODIFIED**: The editor will write changes back to the `content.opf` file in the workspace.

## Impact
- **Affected specs**: `epub-workflow`
- **Affected code**:
  - `lua/epubedit/opf_manager.lua`: To handle reading and writing metadata.
  - `lua/epubedit/opf_view.lua`: To be updated or replaced with the new editor UI.
  - `plugin/epubedit.lua`: To add new user commands.