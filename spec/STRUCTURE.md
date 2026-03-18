# Document Structure

> How and where the Librarian stores documents in the vault.

## Vault Layout

```
$LIBRARIAN_VAULT_PATH/
├── _index/                    # Auto-generated indexes (do not edit manually)
│   ├── by-date/              # Date-based indexes (YYYY/MM/)
│   ├── by-topic/             # Topic-based indexes
│   └── relationships.md      # Document relationship graph
├── _glossaries/              # Per-library glossaries
│   ├── <library-key>.md      # e.g., rib.md, ai.md
│   └── global.md             # Cross-library terms
├── <Library>/                # One folder per library (see LIBRARIES.md)
│   ├── _library.md           # Library metadata and description
│   ├── meetings/             # Meeting minutes
│   ├── reports/              # Reports, summaries, handouts
│   ├── documentation/        # Software docs, guides, manuals
│   ├── notes/                # General notes and memos
│   ├── reference/            # Reference materials
│   └── assets/               # Images, diagrams, attachments
└── .obsidian/                # Obsidian configuration (user-managed)
```

## Naming Conventions

### Files
- Format: `YYYY-MM-DD_<descriptive-slug>.md`
- Example: `2026-03-18_sprint-review-notes.md`
- Slugs: lowercase, hyphens, no spaces. Keep under 60 characters.

### Folders
- Library folders: PascalCase matching the library key (e.g., `RIB/`, `Personal/`)
- Subfolders: lowercase with hyphens (e.g., `meeting-minutes/`)

## Document Front Matter

Every document in the vault should have YAML front matter:

```yaml
---
title: Sprint Review Notes
date: 2026-03-18
library: RIB
type: meeting-minutes          # meeting-minutes | report | documentation | note | reference
tags: [sprint, review, q1-2026]
source: sprint-review-2026-03-18.docx
related:                       # Links to related documents
  - 2026-03-11_sprint-review-notes.md
---
```

## Document Types

| Type | Description | Subfolder |
|------|-------------|-----------|
| `meeting-minutes` | Transcribed/summarized meeting notes | `meetings/` |
| `report` | Summaries, handouts, status reports | `reports/` |
| `documentation` | Software docs, guides, how-tos | `documentation/` |
| `note` | General notes, memos, quick captures | `notes/` |
| `reference` | Reference materials, specs, standards | `reference/` |

## Indexing Strategy

Documents are indexed on three axes:

1. **By date** — `_index/by-date/YYYY/MM.md` lists all documents filed that month.
2. **By topic** — `_index/by-topic/<topic>.md` lists documents tagged with that topic.
3. **By relationship** — `_index/relationships.md` tracks explicit connections between documents (e.g., a meeting that references a report).

The SQLite FTS5 index provides full-text search across all documents. The vault's markdown indexes are human-readable projections of the database.

## Glossary Management

Each library has a glossary at `_glossaries/<library-key>.md`.

Format:
```markdown
# Glossary: <Library Name>

## A

**API Gateway** — The central entry point for all REST API calls in the platform.

## B

**Build Pipeline** — The CI/CD process that compiles and deploys artifacts.
```

Glossaries grow over time. The Librarian adds terms when:
- A new term appears frequently in processed documents
- The user explicitly provides a definition
- A term is ambiguous and needs clarification for future reference

## Asset Handling

Binary files (images, PDFs, diagrams) are stored in the library's `assets/` folder.
The markdown document references them with relative paths:

```markdown
![Architecture Diagram](assets/architecture-overview.png)
```

For shared assets used across libraries, use `$LIBRARIAN_VAULT_PATH/assets/shared/`.
