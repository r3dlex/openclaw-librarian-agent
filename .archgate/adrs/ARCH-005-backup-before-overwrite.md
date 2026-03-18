---
id: ARCH-005
title: Backup Before Overwrite Policy
domain: architecture
rules: false
---

# ARCH-005: Backup Before Overwrite Policy

## Context

The Librarian and humans both edit vault files. When the Librarian needs to update a file that was modified by a human, it must not destroy the human's work.

## Decision

Before overwriting any vault file, `Librarian.Vault.Backup` creates a timestamped copy in `$LIBRARIAN_DATA_FOLDER/backups/`.

### Backup structure

```
$LIBRARIAN_DATA_FOLDER/backups/
├── 2026-03-18/
│   ├── 20260318_143000_document.md
│   └── 20260318_160500_notes.md
└── 2026-03-19/
    └── ...
```

### Retention

- Backups are organized by date
- `Librarian.Vault.Backup.prune/0` removes directories older than 30 days
- Pruning runs daily as part of the Reporter's daily task

### Do's and Don'ts

- **Do** call `Librarian.Vault.Backup.backup/1` before any vault file overwrite
- **Do** log the backup path so it can be found if needed
- **Don't** back up files the Librarian just created (no previous version to preserve)
- **Don't** modify the backup files — they are immutable snapshots

## Consequences

**Positive:** Human work is never lost, provides audit trail.
**Negative:** Disk usage grows with activity (mitigated by 30-day pruning).
