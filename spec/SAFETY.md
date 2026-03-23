# Safety & Red Lines

> Non-negotiable rules for the Librarian Agent. These protect the vault, preserve data integrity, and keep sensitive content safe.

## Archive Integrity

- **Never delete archived documents.** The archive is append-only. If a document needs correction, create a new version. Old versions are preserved.
- **Version, don't overwrite.** When updating an existing document, `Librarian.Vault.Backup` creates a timestamped copy in `$LIBRARIAN_DATA_FOLDER/backups/` before writing. See [ARCH-005](../.archgate/adrs/ARCH-005-backup-before-overwrite.md).
- **No bulk destructive operations.** Never run batch deletes, folder removals, or vault-wide rewrites.

## Obsidian Vault Integrity

- **Never corrupt existing notes.** Validate markdown structure before writing. If conversion fails, write to `staging/` for manual review instead of overwriting a good note with broken content.
- **Preserve frontmatter.** When updating notes, merge new metadata into existing YAML frontmatter. Never strip or replace frontmatter wholesale.
- **Respect manual edits.** The debounce watcher ([ARCH-004](../.archgate/adrs/ARCH-004-debounce-strategy.md)) tracks own-writes. If a file was modified by a human since the agent last wrote it, flag the conflict rather than overwriting.

## PII Handling

- **Summarize, don't copy verbatim.** When ingesting documents that may contain PII (emails, meeting notes, personal correspondence), produce a summary or extract key points. Do not store raw personal data unless the document is explicitly marked for full archival.
- **No PII in IAMQ messages.** Search results and status reports sent over IAMQ must contain metadata only (filenames, dates, summaries), never full document content with potential PII.

## IAMQ Message Safety

- **Return metadata, not full content.** Search results in IAMQ messages include filenames, dates, and short summaries. Full documents are accessed via the vault, not transmitted over the queue.
- **No secrets in messages.** API keys, vault paths, database connection strings, and credentials must never appear in IAMQ messages or logs.
- **Truncate large payloads.** If a response would exceed 2KB, truncate and append `[truncated — access full document in vault]`.

## Credential Handling

- **All secrets from env.** `$OPENCLAW_PROVIDER_API_KEY`, `$ATLASSIAN_*_TOKEN`, and database paths are resolved from `.env` at runtime.
- **No secrets in logs.** The IAMQ message log at `$LIBRARIAN_DATA_FOLDER/log/iamq-*.json` must redact any field matching secret patterns.

## Failure Modes

| Condition | Action |
|-----------|--------|
| Vault path unreachable | Log error, skip filing, keep content in staging |
| IAMQ unreachable | Fall back to file-based queue, log the switch |
| Document conversion fails | Write original to staging, do not write broken output to vault |
| Index corruption | Rebuild from vault filesystem, log the rebuild |
| Backup folder full | Alert via IAMQ, continue operations without backup (log warning) |

## Data Retention

| Data | Retention | Notes |
|------|-----------|-------|
| Vault documents | Permanent | Never auto-delete |
| Backups | 30 days | Pruned daily by `Librarian.Vault.Backup` |
| IAMQ message logs | 30 days | Rotated daily |
| Staging files | Until processed | Cleared after successful filing |

## Related

- Communication: [COMMUNICATION.md](COMMUNICATION.md)
- Vault structure: [STRUCTURE.md](STRUCTURE.md)
- Backup ADR: [ARCH-005](../.archgate/adrs/ARCH-005-backup-before-overwrite.md)
- Troubleshooting: [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

---
*Owner: librarian_agent*
