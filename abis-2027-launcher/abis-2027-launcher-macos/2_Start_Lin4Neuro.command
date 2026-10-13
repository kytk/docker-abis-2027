#!/bin/bash
# 2_Start_Lin4Neuro.command - Double-click launcher for the ABiS Lin4Neuro tutorial environment.
# Finder starts this in the user's home directory, so the script directory has
# to be resolved explicitly before anything else.

cd "$(dirname "$0")" || exit 1
exec /bin/bash "./lib/start_lin4neuro.sh"
