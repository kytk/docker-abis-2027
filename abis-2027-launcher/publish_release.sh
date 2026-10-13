#!/bin/bash
# publish_release.sh - Publish the archives built by make_release.sh as a
# GitHub Release of kytk/abis-web-2027, then check that the download URLs in
# INSTALL_*.md serve exactly these files.
#
#   ./publish_release.sh            create release launcher-<version>
#   ./publish_release.sh --replace  replace the assets of that release instead
#                                   (same version re-uploaded, e.g. after a
#                                   packaging mistake)
#
# The version is read from VERSION.txt inside the archives, never typed in,
# so the tag cannot disagree with what participants see. Needs gh (logged in
# with write access to the repository), curl, tar and unzip.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=release_common.sh
. "$HERE/release_common.sh"

MAC="$HERE/abis-2027-launcher-macos.tar.gz"
WIN="$HERE/abis-2027-launcher-windows.zip"

REPLACE=false
case "${1:-}" in
    "") ;;
    --replace) REPLACE=true ;;
    *) release_fail "unknown option: $1 (only --replace)" ;;
esac

# --- preconditions ---------------------------------------------------------------

command -v gh >/dev/null 2>&1 || release_fail "gh is not installed (https://cli.github.com/)"
gh auth status >/dev/null 2>&1 || release_fail "gh is not logged in - run: gh auth login"
[ -f "$MAC" ] || release_fail "not found: $MAC - run ./make_release.sh first"
[ -f "$WIN" ] || release_fail "not found: $WIN - run ./make_release.sh first"

V_MAC="$(tar -xzOf "$MAC" abis-2027-launcher-macos/VERSION.txt 2>/dev/null | release_read_version)"
V_WIN="$(unzip -p "$WIN" VERSION.txt 2>/dev/null | release_read_version)"
[ -n "$V_MAC" ] || release_fail "no VERSION.txt in $MAC - rebuild with ./make_release.sh"
[ -n "$V_WIN" ] || release_fail "no VERSION.txt in $WIN - rebuild with ./make_release.sh"
[ "$V_MAC" = "$V_WIN" ] || release_fail "versions differ: macOS $V_MAC, Windows $V_WIN - rebuild both with ./make_release.sh"

VERSION="$V_MAC"
TAG="launcher-$VERSION"
INFO="$(tar -xzOf "$MAC" abis-2027-launcher-macos/VERSION.txt)"
COMMIT="$(printf '%s\n' "$INFO" | sed -n 's/^commit:[[:space:]]*//p')"
IMAGE="$(printf '%s\n' "$INFO" | sed -n 's/^image:[[:space:]]*//p')"
SHA_MAC="$(release_sha256 "$MAC")"
SHA_WIN="$(release_sha256 "$WIN")"

if gh release view "$TAG" -R "$RELEASE_REPO" >/dev/null 2>&1; then
    $REPLACE || release_fail "$TAG is already released. Rebuild with ./make_release.sh for a new version, or use --replace to overwrite its files."
else
    $REPLACE && release_fail "$TAG does not exist yet - run without --replace"
fi

# --- confirm -------------------------------------------------------------------

MODE=""
$REPLACE && MODE="(REPLACE ASSETS)"
cat <<EOF
Repository : $RELEASE_REPO
Release    : $TAG $MODE
Commit     : $COMMIT
Image      : $IMAGE
Files      :
    abis-2027-launcher-macos.tar.gz   $SHA_MAC
    abis-2027-launcher-windows.zip    $SHA_WIN

EOF
case "$COMMIT" in *dirty*|unknown) echo "WARNING: built from uncommitted files."; echo ;; esac
printf 'Publish? Participants get these files immediately. [y/N] '
read -r reply
case "$reply" in [yY]*) ;; *) echo "Cancelled."; exit 1 ;; esac

# --- publish -------------------------------------------------------------------

if $REPLACE; then
    gh release upload "$TAG" "$MAC" "$WIN" --clobber -R "$RELEASE_REPO"
else
    NOTES="ABiS 2027 Lin4Neuro launcher $VERSION

- image: \`$IMAGE\`
- source commit: \`$COMMIT\`

| file | sha256 |
|---|---|
| abis-2027-launcher-macos.tar.gz | \`$SHA_MAC\` |
| abis-2027-launcher-windows.zip | \`$SHA_WIN\` |

Install / update: run the one-line command from the tutorial instructions again."
    # --latest: releases/latest/download/... (the URL in INSTALL_*.md) only
    # follows the newest release that is neither a draft nor a pre-release.
    gh release create "$TAG" "$MAC" "$WIN" -R "$RELEASE_REPO" \
        --title "Launcher $VERSION" --notes "$NOTES" --latest
fi

# --- verify --------------------------------------------------------------------
# Download through the same URLs participants use and compare the checksums.
# The CDN can take a moment to serve a new asset, so retry a few times.
# With --replace the release may not be the latest one, so its own tag URL is
# checked instead.
if $REPLACE; then BASE="$RELEASE_URL/download/$TAG"; else BASE="$RELEASE_URL/latest/download"; fi

echo
echo "Checking the download URLs..."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ok=true
for pair in "abis-2027-launcher-macos.tar.gz:$SHA_MAC" "abis-2027-launcher-windows.zip:$SHA_WIN"; do
    file="${pair%%:*}"; want="${pair#*:}"
    url="$BASE/$file"
    got=""
    for _ in 1 2 3 4 5; do
        if curl -fsSL -o "$TMP/$file" "$url"; then
            got="$(release_sha256 "$TMP/$file")"
            [ "$got" = "$want" ] && break
        fi
        sleep 5
    done
    if [ "$got" = "$want" ]; then
        echo "  OK  $url"
    else
        echo "  NG  $url (sha256 ${got:-download failed})"
        ok=false
    fi
done

echo
if $ok; then
    echo "Published $TAG: $RELEASE_URL/tag/$TAG"
else
    echo "Published $TAG, but a download URL does not serve the new file yet."
    echo "Check $RELEASE_URL/tag/$TAG and run the curl check again in a few minutes."
    exit 1
fi
