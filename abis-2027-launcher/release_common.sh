# shellcheck shell=bash
# release_common.sh - Shared by make_release.sh, make_macos_tarball.sh,
# make_windows_zip.sh and publish_release.sh. Not meant to be run on its own.
#
# The version is the build date, YYYY.MM.DD, with .2, .3, ... for a second or
# third build on the same day. make_release.sh decides it once and exports
# RELEASE_VERSION / RELEASE_BUILT / RELEASE_COMMIT, so that both archives carry
# the same values; a make_*.sh run on its own fills them in itself.

RELEASE_REPO="kytk/abis-web-2027"
RELEASE_URL="https://github.com/${RELEASE_REPO}/releases"

# Directory of the launcher sources (this file lives next to them).
RELEASE_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

release_fail() { echo "NG: $*" >&2; exit 1; }

# The image tag configured in the two launchers. They must agree.
release_image_tag() {
    local mac win
    mac="$(sed -n 's/^IMAGE_TAG="\(.*\)".*/\1/p' "$RELEASE_HERE/abis-2027-launcher-macos/lib/common.sh")"
    win="$(sed -n "s/^\$Script:ImageTag *= *'\(.*\)'.*/\1/p" "$RELEASE_HERE/abis-2027-launcher-windows/lib/common.ps1")"
    if [ -z "$mac" ] || [ "$mac" != "$win" ]; then
        release_fail "image tag differs between macOS ($mac) and Windows ($win) - see README 'Before distributing' step 1"
    fi
    printf '%s' "$mac"
}

# Fill in RELEASE_* if make_release.sh did not.
release_init() {
    : "${RELEASE_VERSION:=$(date +%Y.%m.%d)}"
    : "${RELEASE_BUILT:=$(date '+%Y-%m-%d %H:%M %Z')}"
    if [ -z "${RELEASE_COMMIT:-}" ]; then
        if RELEASE_COMMIT="$(git -C "$RELEASE_HERE" rev-parse --short HEAD 2>/dev/null)"; then
            # Untracked files count: a launcher folder that was never committed
            # cannot be reproduced from the commit either.
            if [ -n "$(git -C "$RELEASE_HERE" status --porcelain -- . 2>/dev/null)" ]; then
                RELEASE_COMMIT="$RELEASE_COMMIT (dirty)"
            fi
        else
            RELEASE_COMMIT="unknown"
        fi
    fi
    RELEASE_IMAGE="kytk/abis-2027:$(release_image_tag)"
    export RELEASE_VERSION RELEASE_BUILT RELEASE_COMMIT RELEASE_IMAGE
}

# Write VERSION.txt and README.txt into <dir> for <platform> (macos|windows).
#
# VERSION.txt is ASCII only, so that bash 3.2, PowerShell 5.1 and Notepad all
# read it the same way; the launchers take the "version:" line from it.
# README.txt is for participants and is Japanese: UTF-8 without BOM and LF on
# macOS, UTF-8 with BOM and CRLF on Windows (the same rules as the scripts).
release_write_files() {
    local dir="$1" platform="$2" nl
    [ "$platform" = windows ] && nl=$'\r\n' || nl=$'\n'

    {
        printf 'ABiS Lin4Neuro launcher (%s)%s' "$platform" "$nl"
        printf 'version: %s%s' "$RELEASE_VERSION" "$nl"
        printf 'built:   %s%s' "$RELEASE_BUILT" "$nl"
        printf 'commit:  %s%s' "$RELEASE_COMMIT" "$nl"
        printf 'image:   %s%s' "$RELEASE_IMAGE" "$nl"
        printf 'url:     %s%s' "$RELEASE_URL" "$nl"
    } > "$dir/VERSION.txt"

    local body
    body="$(sed -e "s|@VERSION@|$RELEASE_VERSION|g" \
                -e "s|@BUILT@|$RELEASE_BUILT|g" \
                -e "s|@IMAGE@|$RELEASE_IMAGE|g" \
                -e "s|@URL@|$RELEASE_URL|g" \
                "$RELEASE_HERE/templates/README-$platform.txt")"
    if [ "$platform" = windows ]; then
        { printf '\357\273\277'; printf '%s\n' "$body" | awk '{ printf "%s\r\n", $0 }'; } > "$dir/README.txt"
    else
        printf '%s\n' "$body" > "$dir/README.txt"
    fi
    chmod 644 "$dir/VERSION.txt" "$dir/README.txt"
}

# The "version:" line of a VERSION.txt read from stdin.
release_read_version() {
    sed -n 's/^version:[[:space:]]*//p' | tr -d '\r' | head -1
}

release_sha256() {
    if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1"; else sha256sum "$1"; fi | cut -d' ' -f1
}
