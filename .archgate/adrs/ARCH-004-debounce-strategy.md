---
id: ARCH-004
title: Debounce Strategy for Google Drive Sync
domain: architecture
rules: false
---

# ARCH-004: Debounce Strategy for Google Drive Sync

## Context

The vault lives on Google Drive. When Drive syncs a file, it can generate multiple filesystem events (create temp file, rename, modify attributes) for a single logical change. Without debouncing, the watcher would reprocess the same file multiple times.

Additionally, the Librarian itself writes to the vault. Without own-write tracking, the watcher would trigger reprocessing of files the Librarian just wrote.

## Decision

`Librarian.Vault.Watcher` implements two mechanisms:

1. **2-second debounce window**: Filesystem events for the same path are coalesced. Only the last event within a 2-second window triggers processing.
2. **Timestamp-based own-write tracking**: Before writing to the vault, callers register the path via `register_own_write/1`. Events for registered paths within the debounce window are suppressed.

### Implementation

- Debounce is per-path, not global — changes to different files process independently
- Own-write registrations expire after the debounce window (2s)
- The debounce timer uses `Process.send_after/3` with `:debounce_fire` messages

### Do's and Don'ts

- **Do** call `Librarian.Vault.Watcher.register_own_write/1` before every vault write
- **Do** write atomically (temp file + rename) to minimize the event window
- **Don't** reduce the debounce below 2 seconds — Google Drive sync needs it
- **Don't** rely on event types (`:modified`, `:created`) — they vary by OS and sync tool

## Consequences

**Positive:** Eliminates redundant reprocessing, prevents infinite loops.
**Negative:** Adds 2-second latency to detecting genuine external changes.
