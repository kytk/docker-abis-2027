#!/bin/bash
# make_macos_tarball.sh - Build abis-2027-launcher-macos.tar.gz for distribution.
#
# Participants fetch the archive with curl and unpack it with tar (see
# INSTALL_macos.md). Neither sets com.apple.quarantine, so Gatekeeper never
# blocks the .command files - but only if the archive itself carries no
# extended attributes. macOS tar stores them by default (as ._* entries), and
# this folder lives in Dropbox, which tags every file with com.dropbox.attrs.
# The files are therefore copied without attributes into a staging directory,
# given fixed permissions and packed from there.
#
# VERSION.txt and README.txt are generated into the archive (see
# release_common.sh); they are never written into the source folder.
#
# Normally run through make_release.sh, which builds both archives with the
# same version. Run on a Mac, from anywhere:  ./make_macos_tarball.sh

set -euo pipefail

NAME="abis-2027-launcher-macos"
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/$NAME"
OUT="$HERE/$NAME.tar.gz"

[ -d "$SRC" ] || { echo "not found: $SRC" >&2; exit 1; }

# shellcheck source=release_common.sh
. "$HERE/release_common.sh"
release_init

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# cp -X: do not copy extended attributes or resource forks. -p keeps the mtimes.
cp -RXp "$SRC" "$STAGE/$NAME"

# Leftovers from Finder and from test runs of 0_Check_Environment.
find "$STAGE" \( -name .DS_Store -o -name '._*' -o -name abis_check_result.txt \) -delete

# Version stamp and the participants' README (not kept in the source folder).
release_write_files "$STAGE/$NAME" macos

# Directories and scripts 755, everything else 644. The working copy is 744,
# which is fine for the owner, but the archive should not depend on it.
find "$STAGE/$NAME" -type d -exec chmod 755 {} +
find "$STAGE/$NAME" -type f -exec chmod 644 {} +
find "$STAGE/$NAME" -type f \( -name '*.command' -o -name '*.sh' \) -exec chmod 755 {} +

rm -f "$OUT"
COPYFILE_DISABLE=1 tar --no-mac-metadata --no-xattrs \
    --uid 0 --gid 0 --uname root --gname wheel \
    -czf "$OUT" -C "$STAGE" "$NAME"

# --- verify ------------------------------------------------------------------

fail() { echo "NG: $*" >&2; exit 1; }

LIST="$(tar -tvzf "$OUT")"
echo "$LIST"
echo

echo "$LIST" | grep -q '/\._' && fail "AppleDouble (._*) entries in the archive"
echo "$LIST" | grep -q 'DS_Store' && fail ".DS_Store in the archive"
echo "$LIST" | grep -q 'abis_check_result' && fail "abis_check_result.txt in the archive"
echo "$LIST" | awk '{print $NF}' | grep -qv "^$NAME\(/\|$\)" && fail "entry outside $NAME/"
echo "$LIST" | grep -E '\.(command|sh)$' | grep -qv '^-rwxr-xr-x' && fail "script without the executable bit"

CHECK="$(mktemp -d)"
trap 'rm -rf "$STAGE" "$CHECK"' EXIT
tar -xzf "$OUT" -C "$CHECK"
[ -z "$(xattr -lr "$CHECK")" ] || fail "extended attributes survive extraction"
[ "$(release_read_version < "$CHECK/$NAME/VERSION.txt")" = "$RELEASE_VERSION" ] || fail "VERSION.txt missing or wrong"

echo "OK: $OUT ($(du -h "$OUT" | cut -f1 | tr -d ' '), version $RELEASE_VERSION, commit $RELEASE_COMMIT)"
shasum -a 256 "$OUT"
