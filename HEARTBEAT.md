# Heartbeat

Periodic tasks for the Librarian. Each task runs on the specified interval.

## On demand
- When the user sends a document or asks you to process something directly in chat, run Stage 1 (convert + stage) and Stage 2 (classify + file) immediately — don't wait for the next heartbeat.
- When another agent sends a request via IAMQ, process it and reply promptly.

## Every 15 minutes
- Check all configured input folders (`$LIBRARIAN_INPUT_PATHS`) for new documents. Convert and stage any found.
- Clean up staged items marked "filed" older than 24 hours.
- Verify Docker containers are still running. Restart if needed (`docker compose up -d`).

## Every 30 seconds (automatic)
- `Librarian.IAMQ` polls inbox for new messages from other agents. Incoming messages are saved to `$LIBRARIAN_DATA_FOLDER/log/iamq-*.json`.

## Every hour
- **Check IAMQ inbox logs** — review any messages received from other agents in `$LIBRARIAN_DATA_FOLDER/log/iamq-*.json` and act on requests.
- **Check workspace inbox** — process any messages in `inbox/` written directly by other agents. Delete or archive after acting.
- **Classify and file all pending staged items** (Stage 2 of the pipeline). For each item with status "pending" in `$LIBRARIAN_DATA_FOLDER/staging/`:
  1. Read the `.md` content and `.meta.json` metadata.
  2. Classify: determine target library, document type, tags, relationships.
  3. Add YAML front matter per `spec/STRUCTURE.md`.
  4. Check for duplicates at the target path (see § Deduplication in `AGENTS.md`).
  5. Write to vault. Call `Librarian.Staging.mark_filed(id, vault_path)`.
  6. Update index and relationship graph. Log reasoning.
- Scan the vault for filesystem changes. Reprocess modified files and update the index.

## Daily (midnight UTC)
- Generate the daily report: documents processed, where they landed, any issues encountered.
- Write the report to `$LIBRARIAN_DATA_FOLDER/log/reports/YYYY-MM-DD.md`.
- Prune backups older than 30 days from `$LIBRARIAN_DATA_FOLDER/backups/`.
- **Deep staging cleanup** (`Librarian.Staging.deep_cleanup/0`): remove all filed items, stale pending items (>48h), and orphaned files.
- Update `spec/LEARNINGS.md` if new patterns or issues were discovered.

## Weekly (Sunday midnight UTC)
- Archive all files in each data folder's `processed/` directory into `processed-documents-WeekWW-YYYY.tar.gz`.
- Remove archived originals after successful compression.
- Log the archive operation to `$LIBRARIAN_DATA_FOLDER/log/archiver.log`.
