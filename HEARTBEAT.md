# Heartbeat

Periodic tasks for the Librarian. Each task runs on the specified interval.

## Every 15 minutes
- Check all configured input folders (`$LIBRARIAN_INPUT_PATHS`) for new documents. Convert and stage any found.
- Clean up staged items marked "filed" older than 24 hours.
- Verify Docker containers are still running. Restart if needed (`docker compose up -d`).

## Every hour
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
