#!/bin/bash
# make_windows_zip.sh - Build abis-2027-launcher-windows.zip for distribution.
#
# Participants fetch the zip with curl.exe and unpack it with tar.exe (see
# INSTALL_windows.md). Neither writes the Mark of the Web, so SmartScreen does
# not warn on the .bat files. The zip is kept (rather than a tar.gz) because
# a participant who downloads it in a browser instead can still unblock it
# and use Explorer's "Extract All", which Windows 10 cannot do for a tar.gz.
#
# The archive holds the folder's *contents*, with no top-level folder: Explorer
# names the extraction folder after the zip, and the curl one-liner extracts
# into a folder it creates. Either way there is exactly one level.
#
# The encoding rules in README.md are checked here as well, because a .bat
# saved as UTF-8 by an editor is the easiest way to break the launcher.
#
# VERSION.txt and README.txt are generated into the archive (see
# release_common.sh); they are never written into the source folder.
#
# Normally run through make_release.sh, which builds both archives with the
# same version. Run on a Mac, from anywhere:  ./make_windows_zip.sh

set -euo pipefail

NAME="abis-2027-launcher-windows"
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/$NAME"
OUT="$HERE/$NAME.zip"

[ -d "$SRC" ] || { echo "not found: $SRC" >&2; exit 1; }

# shellcheck source=release_common.sh
. "$HERE/release_common.sh"
release_init

fail() { echo "NG: $*" >&2; exit 1; }

STAGE="$(mktemp -d)"
CHECK="$(mktemp -d)"
trap 'rm -rf "$STAGE" "$CHECK"' EXIT

# cp -X: do not copy extended attributes or resource forks. -p keeps the mtimes.
cp -RXp "$SRC" "$STAGE/$NAME"

# Leftovers from Finder and from test runs of 0_Check_Environment.
find "$STAGE" \( -name .DS_Store -o -name '._*' -o -name abis_check_result.txt \) -delete

# Version stamp and the participants' README (not kept in the source folder).
release_write_files "$STAGE/$NAME" windows

# --- encoding rules ----------------------------------------------------------

for f in "$STAGE/$NAME"/*.bat; do
    b="$(basename "$f")"
    [ "$(head -c3 "$f" | xxd -p)" = efbbbf ] && fail "$b has a BOM (must be Shift-JIS)"
    iconv -f CP932 -t UTF-8 "$f" >/dev/null 2>&1 || fail "$b is not valid Shift-JIS"
    if LC_ALL=C grep -q '[^ -~[:space:]]' "$f" && iconv -f UTF-8 -t UTF-8 "$f" >/dev/null 2>&1; then
        fail "$b looks like UTF-8 (must be Shift-JIS)"
    fi
    LC_ALL=C grep -qv $'\r$' "$f" && fail "$b has a line without CRLF"
done

for f in "$STAGE/$NAME"/lib/*.ps1 "$STAGE/$NAME/README.txt"; do
    [ "$(head -c3 "$f" | xxd -p)" = efbbbf ] || fail "$(basename "$f") has no UTF-8 BOM"
done
LC_ALL=C grep -q '[^ -~[:space:]]' "$STAGE/$NAME/VERSION.txt" && fail "VERSION.txt is not ASCII"

# --- pack ----------------------------------------------------------------------

rm -f "$OUT"    # zip adds to an existing archive instead of replacing it
(cd "$STAGE/$NAME" && zip -r -X -q "$OUT" .)

# --- verify ----------------------------------------------------------------------

LIST="$(unzip -Z1 "$OUT")"
unzip -l "$OUT"
echo

echo "$LIST" | grep -q '__MACOSX\|/\._\|^\._' && fail "macOS metadata in the archive"
echo "$LIST" | grep -q 'DS_Store' && fail ".DS_Store in the archive"
echo "$LIST" | grep -q 'abis_check_result' && fail "abis_check_result.txt in the archive"
echo "$LIST" | grep -q "^$NAME/" && fail "top-level $NAME/ folder in the archive"

# Extract with bsdtar - the same libarchive as tar.exe on Windows - and
# compare byte for byte with what was packed.
tar -xf "$OUT" -C "$CHECK"
diff -r "$STAGE/$NAME" "$CHECK" >/dev/null || fail "extracted files differ from the source"
[ "$(release_read_version < "$CHECK/VERSION.txt")" = "$RELEASE_VERSION" ] || fail "VERSION.txt missing or wrong"

echo "OK: $OUT ($(du -h "$OUT" | cut -f1 | tr -d ' '), version $RELEASE_VERSION, commit $RELEASE_COMMIT)"
shasum -a 256 "$OUT"
