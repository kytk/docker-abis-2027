#!/bin/bash
# 3_Stop_Lin4Neuro.sh - ABiS Lin4Neuro launcher (Linux). Run from a terminal:
#   bash 3_Stop_Lin4Neuro.sh
# No cd here: a relative share-folder argument must stay relative to the
# caller's directory. The lib scripts locate common.sh from $0 themselves.

exec /bin/bash "$(dirname "$0")/lib/stop_lin4neuro.sh" "$@"
