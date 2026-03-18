# Troubleshooting

> Known issues and their solutions. Update this file as new issues are discovered.

## Common Issues

### Vault path not accessible

**Symptom**: Librarian logs `vault_path_unavailable` warnings. No documents are processed.

**Cause**: The Google Drive sync folder is not mounted or the path has changed.

**Fix**:
1. Verify the path in `.env` (`LIBRARIAN_VAULT_PATH`) is correct.
2. Ensure Google Drive is synced and the folder exists.
3. Restart the service: `docker compose restart librarian`.

### External volume not mounted

**Symptom**: Input folder unavailable. Librarian enters degraded mode.

**Cause**: The external volume (`$LIBRARIAN_DATA_FOLDER`) is not mounted.

**Fix**:
1. Mount the external volume.
2. The service retries automatically every 60 seconds.
3. If the volume path changed, update `.env` and restart.

### Pandoc conversion fails

**Symptom**: Processing log shows `conversion_error` for a specific file.

**Cause**: Corrupted input file or unsupported format variant.

**Fix**:
1. Check the file opens correctly in its native application.
2. Try manual conversion: `docker compose exec librarian pandoc -f <format> -t markdown <file>`.
3. If the format is genuinely unsupported, convert manually and place the `.md` in the input folder.

### SQLite database locked

**Symptom**: Index operations fail with `database is locked`.

**Cause**: Multiple processes accessing the database simultaneously, or a crashed process left a lock.

**Fix**:
1. Check for zombie processes: `docker compose exec librarian ps aux`.
2. Restart the service: `docker compose restart librarian`.
3. If persistent, check for `.db-wal` and `.db-shm` files and remove them (after stopping the service).

### Google Drive sync conflicts

**Symptom**: Duplicate files with `(1)` or `conflict` in their names appear in the vault.

**Cause**: The Librarian and Google Drive sync wrote to the same file simultaneously.

**Fix**:
1. Identify the correct version (check timestamps and content).
2. Remove the duplicate.
3. The Librarian's watcher will detect the cleanup and reindex.

**Prevention**: The Librarian should write to files atomically (write to temp, then rename) to minimize the sync conflict window.

### Document misclassified

**Symptom**: A document landed in the wrong library.

**Fix**:
1. Move the file to the correct library folder in the vault.
2. The filesystem watcher will detect the move and reindex.
3. Check the processing log to understand why it was misclassified.
4. If a pattern emerges, update `spec/LEARNINGS.md`.
