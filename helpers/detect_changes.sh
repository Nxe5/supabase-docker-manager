#!/bin/bash

# Detect if databases.env has changed and needs regeneration
# Returns 0 if changes detected, 1 if no changes

# Get the project root (parent of helpers directory)
HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "${HELPER_DIR}/.." && pwd)"
CENTRAL_ENV="${SCRIPT_DIR}/databases.env"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
HASH_FILE="${SCRIPT_DIR}/.databases.env.hash"

# Calculate hash of databases.env
current_hash=$(md5sum "$CENTRAL_ENV" 2>/dev/null | cut -d' ' -f1 || echo "")

# Check if hash file exists and compare
if [ -f "$HASH_FILE" ]; then
    stored_hash=$(cat "$HASH_FILE" 2>/dev/null || echo "")
    if [ "$current_hash" == "$stored_hash" ] && [ -f "$COMPOSE_FILE" ]; then
        # No changes
        exit 1
    fi
fi

# Changes detected - save new hash
echo "$current_hash" > "$HASH_FILE"
exit 0

