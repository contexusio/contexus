#!/bin/bash
# Ensure all required data directories exist for Docker Compose volumes
# This script creates missing directories before docker-compose starts

set -e

# Get the data directory from environment or use default
DATA_DIR="${DATA_DIR:-./data}"

echo "📁 Ensuring data directories exist in: $DATA_DIR"

# Create base data directory if it doesn't exist
mkdir -p "$DATA_DIR"

# Create all required subdirectories
directories=(
    "$DATA_DIR/postgres"
    "$DATA_DIR/redis"
    "$DATA_DIR/logs"
    "$DATA_DIR/uploads"
)

for dir in "${directories[@]}"; do
    if [ ! -d "$dir" ]; then
        echo "  Creating: $dir"
        mkdir -p "$dir"
    else
        echo "  ✓ Exists: $dir"
    fi
done

echo "✅ All data directories ready"

