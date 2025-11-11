## ADDED Requirements
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
