# Heartbeat

Periodic tasks for the Librarian. Each task runs on the specified interval.

## Every 15 minutes
- Check `$LIBRARIAN_DATA_FOLDER/input/` for new documents. Process any found.

## Every hour
- Scan the vault for filesystem changes. Reprocess modified files and update the index.

## Daily (end of day)
- Generate the daily report: documents processed, where they landed, any issues encountered.
- Write the report to `$LIBRARIAN_DATA_FOLDER/logs/reports/YYYY-MM-DD.md`.
- Update `spec/LEARNINGS.md` if new patterns or issues were discovered.
