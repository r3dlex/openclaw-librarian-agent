# Architecture

> System design and data flow for the Openclaw Librarian Agent.
> Key decisions are recorded as ADRs in `.archgate/adrs/`. This document is the overview; ADRs are the source of truth for *why*.

## Architecture Decision Records

Each major decision has a corresponding ADR. Read this document for *what* and *how*; read the ADR for *why*.

| ADR | Decision | Status |
|-----|----------|--------|
| [ARCH-001](/.archgate/adrs/ARCH-001-two-stage-pipeline.md) | Two-stage pipeline (Elixir converts, Agent classifies) | Accepted |
| [ARCH-002](/.archgate/adrs/ARCH-002-vault-storage.md) | Obsidian vault as primary storage | Accepted |
| [ARCH-003](/.archgate/adrs/ARCH-003-zero-install-containers.md) | Zero-install policy via Docker containers | Accepted |
| [ARCH-004](/.archgate/adrs/ARCH-004-debounce-strategy.md) | 2-second debounce for Google Drive sync | Accepted |
| [ARCH-005](/.archgate/adrs/ARCH-005-backup-before-overwrite.md) | Backup before overwrite policy | Accepted |
| [ARCH-006](/.archgate/adrs/ARCH-006-pipeline-testing.md) | Pipeline-driven testing and validation | Accepted |

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
│                      │    │  → ARCH-002                 │
│  ┌────────────────┐  │    └─────────────────────────────┘
│  │ Vault.Watcher  │──┼──→ ARCH-004 (debounce)
│  │ Vault.Backup   │──┼──→ ARCH-005 (backup)
│  └────────────────┘  │
│  ┌────────────────┐  │    ┌─────────────────────────────┐
│  │ Input          │  │    │  Input / Staging Folders     │
│  │ Processor      │──┼──→ │  → ARCH-001 (two-stage)     │
│  │ Staging        │  │    └─────────────────────────────┘
│  └────────────────┘  │
│  ┌────────────────┐  │    ┌─────────────────────────────┐
│  │ Indexer (FTS5) │  │    │  SQLite Database             │
│  │ Reporter       │──┼──→ │  ($LIBRARIAN_DB_PATH)       │
│  └────────────────┘  │    └─────────────────────────────┘
│                      │
└──────────────────────┘    ┌─────────────────────────────┐
                            │  Pipeline Runner (Python)    │
                            │  (Docker container)          │
                            │  → ARCH-003 (zero-install)   │
                            │  → ARCH-006 (testing)        │
                            └─────────────────────────────┘
```

## Components

### 1. Librarian Agent (Openclaw)

The AI agent that handles:
- **Understanding** — Reads documents and determines what they are, where they belong, and how to process them.
- **Decision-making** — Classifies ambiguous documents, resolves conflicts, chooses appropriate summaries.
- **User interaction** — Responds to queries, accepts instructions via companion `.md` files.
- **Reporting** — Generates human-readable daily reports.

The agent delegates all repeatable, mechanical work to the Elixir service (ARCH-001).

### 2. Elixir Service (`Librarian` application)

A long-running OTP application inside a Docker container (ARCH-003). Supervised processes:

| Module | Responsibility |
|--------|---------------|
| `Librarian.Application` | OTP supervisor tree |
| `Librarian.Vault.Watcher` | FSEvents/inotify watcher with 2s debounce (ARCH-004) |
| `Librarian.Vault.Backup` | Timestamped backups before overwrite (ARCH-005) |
| `Librarian.Processor` | Converts documents via Pandoc/OCR |
| `Librarian.Staging` | Staging folder handoff (ARCH-001) |
| `Librarian.Indexer` | SQLite FTS5 index, search, relationships |
| `Librarian.Input` | Input folder monitor, triggers conversion pipeline |
| `Librarian.Reporter` | Daily reports, backup pruning |
| `Librarian.Repo` | Ecto SQLite3 database access |

### 3. Pipeline Runner (Python)

A CLI tool for CI/CD and operational pipelines (ARCH-006). Runs inside its own Docker container (ARCH-003).

See `spec/PIPELINES.md` for pipeline definitions and `spec/TESTING.md` for the testing strategy.

### 4. SQLite Database

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

### 5. Obsidian Vault (ARCH-002)

The vault is the user-facing output. It must remain:
- **Human-readable** — Browsable in Obsidian without the Elixir service running.
- **Consistent** — Front matter, naming, and folder structure follow `spec/STRUCTURE.md`.
- **Non-destructive** — Human edits are respected. The Librarian backs up before overwriting (ARCH-005).

## Data Flow: Document Ingestion (ARCH-001)

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
                                              └── Registers own write (ARCH-004)

                                           8. Agent calls mark_filed(id, path)
                                              └── Updates .meta.json status

9. Librarian.Indexer updates DB
   └── FTS5 index
   └── Relationships

10. Activity logged to logs/

11. Staging cleanup (24h retention)
```

## Data Flow: Vault Change Detection (ARCH-004, ARCH-005)

```
1. Librarian.Vault.Watcher receives FSEvent

2. Debounce (2s window) — ARCH-004
   └── Coalesces rapid events from Google Drive sync
   └── If same file fires multiple events within 2s, only the last triggers processing

3. Own-write check — ARCH-004
   └── If path was registered via register_own_write() within debounce window → ignore

4. External change detected:
   a. Librarian.Vault.Backup.backup(path) — ARCH-005
   b. Librarian.Indexer.reindex(path)
   c. Check if relationships or tags changed
   d. Update vault indexes if needed
   e. Log the change

5. Backup pruning (daily, 30-day retention) — ARCH-005
```

## Health Checks

The Elixir application performs these checks on startup:

1. **Vault path accessible** — `$LIBRARIAN_VAULT_PATH` exists and is writable.
2. **Data folder accessible** — `$LIBRARIAN_DATA_FOLDER` exists and is writable.
3. **Input folder exists** — Creates `$LIBRARIAN_DATA_FOLDER/input/` if missing.
4. **Staging folder exists** — Creates `$LIBRARIAN_DATA_FOLDER/staging/` if missing.
5. **Logs folder exists** — Creates `$LIBRARIAN_DATA_FOLDER/logs/` and `logs/reports/` if missing.
6. **Backups folder exists** — Creates `$LIBRARIAN_DATA_FOLDER/backups/` if missing.
7. **Database accessible** — SQLite file exists and migrations are current.
8. **Pandoc available** — `pandoc --version` succeeds.

If the vault path or data folder is unavailable (e.g., external drive not mounted), the service logs a warning and enters a degraded mode, retrying every 60 seconds.

## Related

- `spec/PIPELINES.md` — Pipeline definitions and usage
- `spec/TESTING.md` — Testing strategy
- `spec/STRUCTURE.md` — Document organization rules
- `.archgate/adrs/` — Architecture Decision Records
