#!/usr/bin/env bash
# Health check for the Librarian service.
# Verifies that critical paths and services are accessible.
set -euo pipefail

errors=0

# Check vault path
if [ -n "${LIBRARIAN_VAULT_PATH:-}" ] && [ -d "$LIBRARIAN_VAULT_PATH" ]; then
    echo "OK: Vault path accessible"
else
    echo "WARN: Vault path not accessible: ${LIBRARIAN_VAULT_PATH:-unset}"
    errors=$((errors + 1))
fi

# Check data folder
if [ -n "${LIBRARIAN_DATA_FOLDER:-}" ] && [ -d "$LIBRARIAN_DATA_FOLDER" ]; then
    echo "OK: Data folder accessible"
else
    echo "WARN: Data folder not accessible: ${LIBRARIAN_DATA_FOLDER:-unset}"
    errors=$((errors + 1))
fi

# Check Pandoc
if command -v pandoc &> /dev/null; then
    echo "OK: Pandoc available ($(pandoc --version | head -1))"
else
    echo "ERROR: Pandoc not found"
    errors=$((errors + 1))
fi

# Check database
db_path="${LIBRARIAN_DB_PATH:-${LIBRARIAN_DATA_FOLDER:-/app/priv/data}/librarian.db}"
if [ -f "$db_path" ]; then
    echo "OK: Database exists at $db_path"
else
    echo "WARN: Database not found at $db_path (will be created on first run)"
fi

if [ "$errors" -gt 1 ]; then
    echo "UNHEALTHY: $errors critical checks failed"
    exit 1
fi

echo "HEALTHY"
exit 0
