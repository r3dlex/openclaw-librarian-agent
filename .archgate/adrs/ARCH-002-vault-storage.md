---
id: ARCH-002
title: Obsidian-Compatible Vault as Primary Storage
domain: architecture
rules: false
---

# ARCH-002: Obsidian-Compatible Vault as Primary Storage

## Context

Documents need to be stored in a way that is both machine-indexable and human-browsable. The user already uses Obsidian for knowledge management and Google Drive for sync.

**Alternatives considered:**
1. Database-only storage → not human-readable, vendor lock-in
2. Git repository → merge conflicts, binary files problematic
3. **Obsidian vault on Google Drive** → human-readable, synced, existing workflow

## Decision

Use an Obsidian-compatible vault as the primary storage layer. The vault is a directory of markdown files with YAML front matter, organized into libraries. A SQLite database serves as a secondary index for fast search — the vault is the source of truth.

### Key constraints

- Vault must be browsable in Obsidian without the Elixir service running
- All documents must have YAML front matter (see `spec/STRUCTURE.md`)
- Binary assets go in library-specific `assets/` folders
- The SQLite index is derived from the vault and can be rebuilt

### Do's and Don'ts

- **Do** write markdown files atomically (write to temp, then rename) to avoid sync conflicts
- **Do** use `Librarian.Vault.Watcher.register_own_write/1` before writing
- **Don't** store structured data only in SQLite — the vault must be self-contained
- **Don't** modify `.obsidian/` configuration — that belongs to the user

## Consequences

**Positive:** Human-readable, works with existing tools, no vendor lock-in.
**Negative:** Google Drive sync can cause conflicts, filesystem as database has performance limits.
**Risks:** Sync conflicts between Google Drive, Obsidian, and the Librarian writing simultaneously.
