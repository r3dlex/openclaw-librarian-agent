#!/usr/bin/env bash
# First-time setup for the Openclaw Librarian Agent.
# Creates required directories and initializes configuration.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Openclaw Librarian Agent Setup ==="

# Check for .env
if [ ! -f "$PROJECT_DIR/.env" ]; then
    echo "Creating .env from .env.example..."
    cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
    echo "IMPORTANT: Edit .env with your actual paths and API keys before proceeding."
    echo "  vim $PROJECT_DIR/.env"
    exit 1
fi

# Source .env
set -a
source "$PROJECT_DIR/.env"
set +a

# Create data folder structure
echo "Creating data folder structure..."
mkdir -p "${LIBRARIAN_DATA_FOLDER}/input"
mkdir -p "${LIBRARIAN_DATA_FOLDER}/logs/reports"

# Create LIBRARIES.md from example if it doesn't exist
if [ ! -f "$PROJECT_DIR/spec/LIBRARIES.md" ]; then
    echo "Creating spec/LIBRARIES.md from example..."
    cp "$PROJECT_DIR/spec/LIBRARIES.md.example" "$PROJECT_DIR/spec/LIBRARIES.md"
    echo "IMPORTANT: Edit spec/LIBRARIES.md with your actual library definitions."
fi

# Build and start the container
echo "Building Docker image..."
docker compose -f "$PROJECT_DIR/docker-compose.yml" build

echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Edit .env with your actual paths and API keys"
echo "  2. Edit spec/LIBRARIES.md with your library definitions"
echo "  3. Run: docker compose up -d"
echo "  4. Check health: docker compose exec librarian /app/scripts/healthcheck.sh"
