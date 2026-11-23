#!/bin/bash
# 1_Download_Image.sh - ABiS Lin4Neuro launcher (Linux). Run from a terminal:
#   bash 1_Download_Image.sh
# No cd here: a relative share-folder argument must stay relative to the
# caller's directory. The lib scripts locate common.sh from $0 themselves.

exec /bin/bash "$(dirname "$0")/lib/pull_image.sh" "$@"
