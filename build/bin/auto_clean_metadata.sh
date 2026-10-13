#!/usr/bin/env bash

# Script to clean macOS metadata files and directories
# These prevent file manager from opening in GUI on Docker container.

if [ $(uname) != "Linux" ]; then
  echo "This script is for Lin4Neuro only."
  exit 1
fi

PIDFILE=/tmp/auto_clean_metadata.pid

if [ -f "$PIDFILE" ]; then
  OLD_PID=$(cat "$PIDFILE")
  if kill -0 "$OLD_PID" 2>/dev/null; then
    echo "Already running (PID: $OLD_PID). To stop: kill $OLD_PID"
    exit 0
  fi
fi

nohup bash -c '
  while true; do
    find /home/brain/share -depth -name "._*" -exec rm -rf {} + 2>/dev/null
    find /home/brain/share -name ".DS_Store" -delete 2>/dev/null
    sleep 10
  done
' > /dev/null 2>&1 &

echo $! > "$PIDFILE"
echo "Metadata cleanup started (running every 10 seconds)"
echo "PID: $!"
echo "To stop: kill \$(cat $PIDFILE)"
