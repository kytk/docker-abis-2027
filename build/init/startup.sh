#!/bin/bash
# Shared Folder Setup - Cross-platform (Windows/macOS/Linux)
# Author: K. Nemoto
# Version: 1.0.19

echo "=== Setting up shared folder ==="

if [[ -d /home/brain/share ]]; then
    chown -R brain:brain /home/brain/share 2>/dev/null || true
    echo "Shared folder is ready: /home/brain/share"
else
    echo "INFO: No shared folder configured"
fi

echo "=== Starting container ==="
exec su - brain -c "/usr/local/bin/entrypoint.sh < /dev/null"
