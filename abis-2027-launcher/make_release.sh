#!/bin/bash
# make_release.sh - Build both launcher archives with one version number.
#
#   ./make_release.sh              version = today (YYYY.MM.DD), or .2, .3, ...
#                                  if that is already released
#   ./make_release.sh 2026.10.13.2 version given explicitly
#
# Then test the archives (TESTING.md) and publish them with
# ./publish_release.sh. Run on a Mac: the archive scripts use BSD cp/tar and
# xattr.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=release_common.sh
. "$HERE/release_common.sh"

[ "$(uname)" = Darwin ] || release_fail "run this on a Mac (the archive scripts need BSD cp/tar and xattr)"

# --- version -----------------------------------------------------------------

# A release tag exists if its page answers 200; 404 means the version is still
# free. The repository is public, so this works without gh or a login.
# No -f/-S: a 404 is the normal answer and must not print a curl error. Any
# other status (network down, rate limit) stops the script instead of being
# taken as "not released".
release_exists() {
    local code
    code="$(curl -sI -o /dev/null -w '%{http_code}' \
        "https://github.com/${RELEASE_REPO}/releases/tag/launcher-$1" || true)"
    case "$code" in
        200) return 0 ;;
        404) return 1 ;;
        *)   release_fail "cannot check launcher-$1 on GitHub (HTTP ${code:-none})" ;;
    esac
}

if [ $# -ge 1 ]; then
    RELEASE_VERSION="$1"
    echo "$RELEASE_VERSION" | grep -Eq '^[0-9]{4}\.[0-9]{2}\.[0-9]{2}(\.[0-9]+)?$' || \
        release_fail "version must look like 2026.10.13 or 2026.10.13.2"
    if release_exists "$RELEASE_VERSION"; then
        release_fail "launcher-$RELEASE_VERSION is already released"
    fi
else
    base="$(date +%Y.%m.%d)"
    RELEASE_VERSION="$base"
    n=1
    while release_exists "$RELEASE_VERSION"; do
        n=$((n + 1))
        RELEASE_VERSION="$base.$n"
    done
fi

release_init   # fills in RELEASE_BUILT, RELEASE_COMMIT, RELEASE_IMAGE

echo "version : $RELEASE_VERSION"
echo "built   : $RELEASE_BUILT"
echo "commit  : $RELEASE_COMMIT"
echo "image   : $RELEASE_IMAGE"
echo

# An archive built from uncommitted files cannot be traced back to a commit.
case "$RELEASE_COMMIT" in
    *dirty*|unknown)
        echo "The launcher folder has changes that are not committed:"
        git -C "$HERE" status --short -- . 2>/dev/null | sed 's/^/    /' | head -20
        echo
        printf 'Build anyway? [y/N] '
        read -r reply
        case "$reply" in [yY]*) ;; *) echo "Cancelled. Commit first, then run again."; exit 1 ;; esac
        echo
        ;;
esac

# --- build ---------------------------------------------------------------------

echo "=== macOS ======================================================================"
# Called through bash: Dropbox can drop the executable bit.
/bin/bash "$HERE/make_macos_tarball.sh"
echo
echo "=== Windows ===================================================================="
/bin/bash "$HERE/make_windows_zip.sh"
echo

cat <<EOF
Built launcher $RELEASE_VERSION:
    $HERE/abis-2027-launcher-macos.tar.gz
    $HERE/abis-2027-launcher-windows.zip

Next:
    1. Test both archives (TESTING.md).
    2. ./publish_release.sh
EOF
