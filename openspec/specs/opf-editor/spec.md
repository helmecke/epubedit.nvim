# opf-editor Specification

## Purpose
TBD - created by archiving change add-opf-metadata-editor. Update Purpose after archive.
## Requirements
### Requirement: Read OPF Metadata
The system SHALL parse metadata from the `.opf` file, including standard Dublin Core elements and EPUB 3 meta properties.

#### Scenario: Read EPUB 2 Dublin Core
- **GIVEN** an `.opf` file with `<dc:title>`, `<dc:creator>`, and `<dc:language>` elements.
- **WHEN** the metadata editor is opened.
- **THEN** the system correctly reads the title, creator, and language values.

#### Scenario: Read EPUB 3 Meta Properties
- **GIVEN** an `.opf` file with `<meta property="dcterms:title">`, `<meta property="dcterms:creator">`, and `<meta property="dcterms:language">` elements.
- **WHEN** the metadata editor is opened.
- **THEN** the system correctly reads the title, creator, and language values.

#### Scenario: Read Cover Image
- **GIVEN** an `.opf` file with a cover image defined in the manifest (`<item id="cover-image" ...>`) and referenced in the metadata (`<meta name="cover" content="cover-image">`).
- **WHEN** the metadata editor is opened.
- **THEN** the system correctly identifies the cover image item.

### Requirement: Display and Edit Metadata
The system SHALL present the parsed metadata in a user interface that allows for modification.

#### Scenario: Open Metadata Editor
- **GIVEN** an open EPUB session.
- **WHEN** the user executes the `:EpubEditMetadata` command.
- **THEN** a UI appears displaying the current title, author, and other parsed metadata.

#### Scenario: User Edits Title
- **GIVEN** the metadata editor is open.
- **WHEN** the user modifies the title field and confirms.
- **THEN** the internal state of the metadata manager reflects the new title.

### Requirement: Write OPF Metadata
The system SHALL write the modified metadata back to the `.opf` file, normalizing to a consistent format.

#### Scenario: Save Metadata Changes
- **GIVEN** the user has modified the creator name in the editor.
- **WHEN** the user saves the changes.
- **THEN** the `.opf` file on disk is updated to reflect the new creator name.
- **AND** the new creator name is stored using the `<meta property="dcterms:creator">` syntax.

#### Scenario: Namespace Preservation
- **GIVEN** an `.opf` file with existing namespaces.
- **WHEN** metadata is written back to the file.
- **THEN** all original namespaces and prefixes (e.g., `xmlns:dc="..."`) are preserved.
- **AND** the XML structure remains well-formed.

