#!/bin/bash

# Path to our Git-managed list inside the container
LIST_FILE="/etc/pihole/adlists.list"
DB_FILE="/etc/pihole/pihole-FTL.db"

echo "=== Starting GitOps Adlist Sync ==="

if [ -f "$LIST_FILE" ]; then
    # Read the file line by line
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip lines that are empty or start with a comment (#)
        [[ "$line" =~ ^#.* ]] || [ -z "$line" ] && continue
        
        # Inject the URL into the Pi-hole database safely
        sqlite3 "$DB_FILE" "INSERT OR IGNORE INTO adlist (address, enabled) VALUES ('$line', 1);"
        echo "Synced list: $line"
    done < "$LIST_FILE"
    
    # Tell Pi-hole to instantly update its core gravity database
    echo "Updating Pi-hole gravity definitions..."
    pihole -g
else
    echo "No adlists.list file found to sync."
fi

echo "=== GitOps Adlist Sync Complete ==="
