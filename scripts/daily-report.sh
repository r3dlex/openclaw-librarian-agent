#!/usr/bin/env bash
# Manually generate today's daily report.
# Usage: ./scripts/daily-report.sh
set -euo pipefail

echo "Generating daily report..."
docker compose exec librarian mix run -e "Librarian.Reporter.generate_now()"
echo "Done."
