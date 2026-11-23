#!/bin/bash
# 2_Start_Lin4Neuro.sh - ABiS Lin4Neuro launcher (Linux). Run from a terminal:
#   bash 2_Start_Lin4Neuro.sh [share-folder]
# No cd here: a relative share-folder argument must stay relative to the
# caller's directory. The lib scripts locate common.sh from $0 themselves.

exec /bin/bash "$(dirname "$0")/lib/start_lin4neuro.sh" "$@"
