#!/usr/bin/env bash

# Script to clean macOS metadata files (._* and .DS_Store) in the shared folder.
# These prevent file manager from opening in GUI on Docker container.
#
# Usage:
#   auto_clean_metadata.sh           clean once
#   auto_clean_metadata.sh --watch   keep cleaning every 10 seconds in background

SHARE=/home/brain/share
PIDFILE=/tmp/auto_clean_metadata.pid
INTERVAL=10

if [ ! -d "$SHARE" ]; then
  echo "No shared folder: $SHARE"
  exit 1
fi

# AppleDouble files (._*) and .DS_Store are regular files; never touch directories
clean() {
  find "$SHARE" -type f \( -name '._*' -o -name '.DS_Store' \) -print -delete 2>/dev/null
}

case "$1" in
  "")
    n=$(clean | wc -l)
    echo "Removed $n macOS metadata file(s) under $SHARE"
    ;;
  --watch)
    if [ -f "$PIDFILE" ]; then
      OLD_PID=$(cat "$PIDFILE")
      if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "Already running (PID: $OLD_PID). To stop: kill $OLD_PID"
        exit 0
      fi
    fi

    export SHARE
    export -f clean
    nohup bash -c "
      while true; do
        clean > /dev/null
        sleep $INTERVAL
      done
    " > /dev/null 2>&1 &

    echo $! > "$PIDFILE"
    echo "Metadata cleanup started (running every $INTERVAL seconds)"
    echo "PID: $!"
    echo "To stop: kill \$(cat $PIDFILE)"
    ;;
  *)
    echo "Usage: $(basename "$0") [--watch]"
    exit 1
    ;;
esac
