#!/bin/bash
# Docker Compose wrapper that ensures data directories exist before starting services
# Usage: ./docker-compose-wrapper.sh up -d
#        ./docker-compose-wrapper.sh down
#        ./docker-compose-wrapper.sh [any docker-compose command]

set -e

# Get the data directory from environment or use default
DATA_DIR="${DATA_DIR:-./data}"

# Function to ensure directories exist
ensure_directories() {
    echo "📁 Ensuring data directories exist in: $DATA_DIR"
    mkdir -p "$DATA_DIR/postgres" "$DATA_DIR/redis" "$DATA_DIR/logs" "$DATA_DIR/uploads"
    echo "✅ All data directories ready"
}

# If command is 'up' or 'start', ensure directories first
if [[ "$1" == "up" ]] || [[ "$1" == "start" ]] || [[ "$1" == "restart" ]]; then
    ensure_directories
fi

# Pass all arguments to docker-compose
exec docker-compose "$@"

