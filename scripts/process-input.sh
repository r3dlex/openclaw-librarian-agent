#!/usr/bin/env bash
# Manually trigger input folder processing.
# Usage: ./scripts/process-input.sh
set -euo pipefail

echo "Triggering input folder processing..."
docker compose exec librarian mix run -e "Librarian.Input.process_now()"
echo "Done."
