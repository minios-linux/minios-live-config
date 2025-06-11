#!/usr/bin/env bash

# Path to the directory containing .po files
PO_DIR="$PWD/po"

# Ensure msguniq is available
if ! command -v msguniq >/dev/null 2>&1; then
    echo "Error: msguniq command not found! Please install gettext-tools."
    exit 1
fi

# Check if the directory exists
if [ ! -d "$PO_DIR" ]; then
    echo "Error: Directory '$PO_DIR' not found!"
    exit 1
fi

# Process all .po files in the directory
find "$PO_DIR" -type f -name "*.po" -print0 | while IFS= read -r -d '' FILE; do
    echo "Cleaning duplicates in '$FILE'..."

    # Use msguniq to remove duplicate entries in-place
    if ! msguniq --output="$FILE" "$FILE"; then
        echo "Error: msguniq failed on '$FILE'!"
        exit 1
    fi
done

echo "Cleanup completed!"
