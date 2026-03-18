# Architecture

> System design and data flow for the Openclaw Librarian Agent.

## Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Openclaw Gateway                      │
│              (WhatsApp / Telegram / Web)                 │
└──────────────────────┬──────────────────────────────────┘
                       │ Agent session
                       ▼
┌─────────────────────────────────────────────────────────┐
│                  Librarian Agent                         │
│           (AGENTS.md + SOUL.md + IDENTITY.md)           │
│                                                         │
│  Handles: ambiguous decisions, user interaction,         │
│           document understanding, report generation      │
└──────┬──────────────────────────────────┬───────────────┘
       │ delegates repeatable work        │ reads/writes
       ▼                                  ▼
┌──────────────────────┐    ┌─────────────────────────────┐
│  Elixir Service      │    │  Obsidian Vault             │
│  (Docker container)  │    │  ($LIBRARIAN_VAULT_PATH)    │
│                      │    │                             │
│  ┌────────────────┐  │    │  Markdown files, assets,    │
│  │ Vault.Watcher  │──┼────│  glossaries, indexes        │
│  │ (inotify/fsevents)│ │  │                             │
│  └────────────────┘  │    └─────────────────────────────┘
│  ┌────────────────┐  │
│  │ Processor      │  │    ┌─────────────────────────────┐
│  │ (Pandoc shell) │  │    │  Input Folder               │
│  └────────────────┘  │    │  ($LIBRARIAN_DATA_FOLDER/   │
│  ┌────────────────┐  │    │   input/)                   │
│  │ Indexer (FTS5) │  │    │                             │
│  └────────────────┘  │    │  Raw docs + instruction MDs │
│  ┌────────────────┐  │    └─────────────────────────────┘
│  │ Reporter       │  │
│  └────────────────┘  │    ┌─────────────────────────────┐
│          │           │    │  SQLite Database             │
│          └───────────┼────│  ($LIBRARIAN_DB_PATH)       │
│                      │    │                             │
└──────────────────────┘    │  FTS5 index, relationships, │
                            │  processing log             │
                            └─────────────────────────────┘
```

## Components

### 1. Librarian Agent (Openclaw)

The AI agent that handles:
- **Understanding** — Reads documents and determines what they are, where they belong, and how to process them.
- **Decision-making** — Classifies ambiguous documents, resolves conflicts, chooses appropriate summaries.
- **User interaction** — Responds to queries, accepts instructions via companion `.md` files.
- **Reporting** — Generates human-readable daily reports.

The agent delegates all repeatable, mechanical work to the Elixir service.

### 2. Elixir Service (`Librarian` application)

A long-running OTP application inside a Docker container. Supervised processes:

| Module | Responsibility |
|--------|---------------|
| `Librarian.Application` | OTP supervisor tree |
| `Librarian.Vault.Watcher` | FSEvents/inotify watcher on the vault path. Detects human edits with 2s debounce to handle Google Drive sync noise. |
| `Librarian.Vault.Backup` | Creates timestamped backups before overwriting human-edited files. 30-day retention with daily pruning. |
| `Librarian.Processor` | Converts documents via Pandoc. Extracts text, metadata, and structure. |
| `Librarian.Indexer` | Manages SQLite FTS5 index. Handles search queries, relationship tracking, and tag management. |
| `Librarian.Staging` | Manages the staging folder — the handoff point between Elixir (conversion) and the agent (classification). |
| `Librarian.Reporter` | Generates daily/weekly reports from the processing log. Prunes old backups. |
| `Librarian.Input` | Monitors the input folder, converts documents, and stages them for agent classification. |

### 3. SQLite Database

Schema (managed by Ecto migrations):

```sql
-- Full-text search index
CREATE VIRTUAL TABLE documents_fts USING fts5(
  title, content, tags, library,
  content='documents', content_rowid='id'
);

-- Core document metadata
CREATE TABLE documents (
  id INTEGER PRIMARY KEY,
  title TEXT NOT NULL,
  vault_path TEXT NOT NULL UNIQUE,
  library TEXT NOT NULL,
  doc_type TEXT NOT NULL,
  source_file TEXT,
  tags TEXT,          -- JSON array
  created_at TEXT,
  updated_at TEXT,
  checksum TEXT       -- SHA256 for change detection
);

-- Document relationships
CREATE TABLE relationships (
  id INTEGER PRIMARY KEY,
  source_id INTEGER REFERENCES documents(id),
  target_id INTEGER REFERENCES documents(id),
  rel_type TEXT,      -- 'references', 'supersedes', 'related', 'child_of'
  created_at TEXT
);

-- Processing log
CREATE TABLE processing_log (
  id INTEGER PRIMARY KEY,
  source_file TEXT,
  action TEXT,        -- 'ingested', 'updated', 'reindexed', 'deleted'
  destination TEXT,
  library TEXT,
  reasoning TEXT,
  processed_at TEXT
);

-- Glossary terms
CREATE TABLE glossary (
  id INTEGER PRIMARY KEY,
  term TEXT NOT NULL,
  definition TEXT NOT NULL,
  library TEXT,       -- NULL for global terms
  created_at TEXT,
  updated_at TEXT
);
```

### 4. Obsidian Vault

The vault is the user-facing output. It must remain:
- **Human-readable** — Browsable in Obsidian without the Elixir service running.
- **Consistent** — Front matter, naming, and folder structure follow `spec/STRUCTURE.md`.
- **Non-destructive** — Human edits are respected. The Librarian backs up before overwriting.

## Data Flow: Document Ingestion

```
                    ELIXIR SERVICE                          LIBRARIAN AGENT
                    ──────────────                          ───────────────

1. Document appears in input/
   └── Optional companion .md

2. Librarian.Input detects file
   └── Reads companion .md

3. Librarian.Processor converts
   └── Pandoc / OCR / passthrough

4. Librarian.Staging.stage()              5. Agent reads staging/
   └── Writes <id>.md + .meta.json           └── Reads .md content + .meta.json
   └── Removes source from input/            └── Checks user instructions

                                           6. Agent classifies
                                              └── Determines: library, type, tags
                                              └── Adds YAML front matter

                                           7. Agent writes to vault
                                              └── Correct library/subfolder
                                              └── Registers own write (debounce)

                                           8. Agent calls mark_filed(id, path)
                                              └── Updates .meta.json status

9. Librarian.Indexer updates DB
   └── FTS5 index
   └── Relationships

10. Activity logged to logs/

11. Staging cleanup (24h retention)
```

## Data Flow: Vault Change Detection

```
1. Librarian.Vault.Watcher receives FSEvent

2. Debounce (2s window)
   └── Coalesces rapid events from Google Drive sync
   └── If same file fires multiple events within 2s, only the last triggers processing

3. Own-write check
   └── If path was registered via register_own_write() within debounce window → ignore

4. External change detected:
   a. Librarian.Vault.Backup.backup(path)  — timestamped copy to backups/
   b. Librarian.Indexer.reindex(path)      — re-read and update FTS5 index
   c. Check if relationships or tags changed
   d. Update vault indexes if needed
   e. Log the change

5. Backup pruning (daily, 30-day retention)
```

## Health Checks

The Elixir application performs these checks on startup:

1. **Vault path accessible** — `$LIBRARIAN_VAULT_PATH` exists and is writable.
2. **Data folder accessible** — `$LIBRARIAN_DATA_FOLDER` exists and is writable.
3. **Input folder exists** — Creates `$LIBRARIAN_DATA_FOLDER/input/` if missing.
4. **Logs folder exists** — Creates `$LIBRARIAN_DATA_FOLDER/logs/` and `logs/reports/` if missing.
5. **Database accessible** — SQLite file exists and migrations are current.
6. **Pandoc available** — `pandoc --version` succeeds.

If the vault path or data folder is unavailable (e.g., external drive not mounted), the service logs a warning and enters a degraded mode, retrying every 60 seconds.
