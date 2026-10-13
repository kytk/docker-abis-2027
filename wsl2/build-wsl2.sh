#!/bin/bash

# Dockerfile.wsl2 copies from build/desktop/, so the build context has to be the
# repository root. Move there regardless of where this script was started from.
cd "$(dirname "$0")/.." || exit 1
set -e

IMAGE_NAME="abis-2027-wsl2:latest"
CONTAINER_NAME="tmp-wsl2"
OUTPUT_FILE="abis-2027-wsl2.tar.gz"

echo "=== Step 1/5: Building base image ==="
docker build --platform linux/amd64 -t kytk/abis-2027:latest .

echo "=== Step 2/5: Building WSL2 image ==="
docker build --platform linux/amd64 -t "$IMAGE_NAME" -f wsl2/Dockerfile.wsl2 .

echo "=== Step 3/5: Creating temporary container ==="
docker create --name "$CONTAINER_NAME" "$IMAGE_NAME"

echo "=== Step 4/5: Exporting to $OUTPUT_FILE ==="
docker export "$CONTAINER_NAME" | gzip > "$OUTPUT_FILE"

echo "=== Step 5/5: Removing temporary container ==="
docker rm "$CONTAINER_NAME"

echo "=== Done: $OUTPUT_FILE ==="
ls -lh "$OUTPUT_FILE"
