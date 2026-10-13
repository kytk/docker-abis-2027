# shellcheck shell=bash
# shellcheck disable=SC2034  # configuration variables are used by the sourcing scripts
# common.sh - Shared settings and helper functions for the ABiS Lin4Neuro launcher.
# Sourced by the other scripts in this folder; not meant to be run on its own.
#
# Target: /bin/bash on macOS, which is bash 3.2. No associative arrays, no
# ${var,,}, no mapfile - those are bash 4 features and would fail silently or
# loudly on a stock Mac.

# =============================================================================
# CONFIGURATION - review this section before distributing to participants
# =============================================================================

# Container image. A FIXED tag (not "latest") so that every participant runs
# byte-for-byte the same environment for the whole season.
IMAGE_REPO="kytk/abis-2027"
IMAGE_TAG="26.12"
IMAGE_NAME="${IMAGE_REPO}:${IMAGE_TAG}"

# Shown in the download confirmation dialog. The size is the compressed
# download (measured: 18.3 GB), not the ~38 GB the image occupies on disk.
# Messages shown to participants are Japanese; comments and identifiers are
# English. The files are UTF-8 without BOM, which bash 3.2 handles as bytes.
IMAGE_SIZE_TEXT="約 20 GB"
IMAGE_TIME_TEXT="40〜60 分"

# Disk space the image needs once unpacked, plus room to work in.
IMAGE_DISK_GB=38

# Container settings
CONTAINER_NAME="abis"
CONTAINER_SHARE="/home/brain/share"   # mount point inside the container
# The container always serves noVNC on 6080 (EXPOSE 6080 in the image); only
# the port on this Mac can be changed, e.g. if 6080 is already taken.
CONTAINER_PORT=6080
HOST_PORT=6080
SHM_SIZE="2g"                         # the 64MB default is too small for FSL/FreeSurfer

# The image is built for linux/amd64. On Apple Silicon this runs under
# emulation (Rosetta); passing --platform explicitly avoids Docker's warning
# and makes the behaviour identical on Intel and Apple Silicon Macs.
PLATFORM="linux/amd64"

# noVNC. The query parameters skip the settings gear, the Connect button and
# the password prompt, so the desktop appears immediately.
# 127.0.0.1 rather than localhost: localhost can resolve to ::1, which does not
# reach a port published on 127.0.0.1.
VNC_PASSWORD="lin4neuro"
VNC_URL="http://127.0.0.1:${HOST_PORT}/vnc.html?resize=scale&autoconnect=1&password=${VNC_PASSWORD}"

# Minimum requirements checked by 0_Check_Environment. The memory assigned to
# the Docker VM is checked against docker_memory_target_gb below.
MIN_FREE_DISK_GB=100     # free space on the startup disk
MIN_DOCKER_DISK_GB=60    # space available inside the Docker VM

# Timeouts (seconds)
DOCKER_START_TIMEOUT=180     # Docker Desktop can be slow on first launch
CONTAINER_READY_TIMEOUT=180  # until the image reports HEALTHCHECK "healthy"

# Open noVNC in a borderless app window instead of a normal browser tab.
# A normal tab can be closed by accident with Cmd+W, which hides the session
# view mid-analysis. Set to "false" to use the default browser instead.
OPEN_IN_APP_MODE="true"

# Launcher version, from the VERSION.txt that make_release.sh puts next to the
# .command files. Absent when the scripts are run from the repository.
LAUNCHER_VERSION="$(sed -n 's/^version:[[:space:]]*//p' "$(dirname "${BASH_SOURCE[0]}")/../VERSION.txt" 2>/dev/null | tr -d '\r' | head -1)"
[ -n "$LAUNCHER_VERSION" ] || LAUNCHER_VERSION="dev"

# A .command launched from Finder inherits a minimal PATH that does not
# include Docker's CLI. Add the usual locations before anything else runs.
PATH="/usr/local/bin:/opt/homebrew/bin:${HOME}/.docker/bin:/Applications/Docker.app/Contents/Resources/bin:${PATH}"
export PATH

# =============================================================================
# Console output helpers
# =============================================================================

if [ -t 1 ]; then
  C_CYAN="$(printf '\033[36m')"; C_GREEN="$(printf '\033[32m')"
  C_YELLOW="$(printf '\033[33m')"; C_RED="$(printf '\033[31m')"
  C_GRAY="$(printf '\033[90m')";  C_OFF="$(printf '\033[0m')"
else
  C_CYAN=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_GRAY=""; C_OFF=""
fi

write_step() { printf '%s==> %s%s\n' "$C_CYAN"   "$1" "$C_OFF"; }
write_ok()   { printf '%s    %s%s\n' "$C_GREEN"  "$1" "$C_OFF"; }
write_warn() { printf '%s    %s%s\n' "$C_YELLOW" "$1" "$C_OFF"; }
write_fail() { printf '%s    %s%s\n' "$C_RED"    "$1" "$C_OFF"; }
write_info() { printf '    %s\n' "$1"; }

# A fixed-width rule: deriving the width from the title would count Japanese
# characters as one column each, while the terminal draws them two columns wide.
write_title() {
  printf '\n  %s  %s(launcher %s)%s\n' "$1" "$C_GRAY" "$LAUNCHER_VERSION" "$C_OFF"
  printf '%s  --------------------------------%s\n\n' "$C_GRAY" "$C_OFF"
}

# Print a message and wait for a key press, so the Terminal window does not
# look finished before the participant has read what went wrong.
exit_with_pause() {
  message="$1"; code="${2:-0}"
  if [ -n "$message" ]; then
    if [ "$code" = "0" ]; then write_ok "$message"; else write_fail "$message"; fi
  fi
  printf '\n%sなにかキーを押すとこのウィンドウを閉じます...%s\n' "$C_GRAY" "$C_OFF"
  # -n 1 needs a terminal; if there is none, just pause briefly.
  if [ -t 0 ]; then read -n 1 -r -s _unused || true; else sleep 3; fi
  exit "$code"
}

# =============================================================================
# Unit helpers
# =============================================================================

# Bytes -> whole GB, rounded to the nearest one rather than truncated. Used for
# every comparison against a minimum requirement, so that 7.9 GB counts as
# 8 GB: Docker reports the memory of its VM minus the VM's own overhead.
bytes_to_gb_round() {
  printf '%s' "$(( ($1 + 536870912) / 1073741824 ))"
}

# Bytes -> GB with one decimal, for display only. bash 3.2 has no floating
# point arithmetic, so the value is computed in tenths of a GB, rounded by
# adding half a tenth (1 GB / 20) before the division.
bytes_to_gb_text() {
  _tenths=$(( ($1 * 10 + 53687091) / 1073741824 ))
  printf '%d.%d' "$(( _tenths / 10 ))" "$(( _tenths % 10 ))"
}

# =============================================================================
# GUI dialog helpers (AppleScript)
# =============================================================================

# Escape a string for embedding in an AppleScript string literal.
escape_applescript() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# show_dialog <message> [buttons: ok|yesno] [icon: note|caution|stop]
# Prints "Yes", "No" or "OK".
show_dialog() {
  msg="$(escape_applescript "$1")"
  buttons="${2:-ok}"
  icon="${3:-note}"

  if [ "$buttons" = "yesno" ]; then
    answer="$(osascript -e "display dialog \"${msg}\" with title \"ABiS Lin4Neuro\" buttons {\"No\", \"Yes\"} default button \"Yes\" with icon ${icon}" 2>/dev/null)"
    case "$answer" in
      *"button returned:Yes"*) printf 'Yes\n' ;;
      *)                       printf 'No\n'  ;;
    esac
  else
    osascript -e "display dialog \"${msg}\" with title \"ABiS Lin4Neuro\" buttons {\"OK\"} default button \"OK\" with icon ${icon}" >/dev/null 2>&1
    printf 'OK\n'
  fi
}

# Ask the participant to pick the "share" folder.
# Prints the selected POSIX path, or nothing if the dialog was cancelled.
select_share_folder() {
  osascript -e 'try' \
            -e 'set f to choose folder with prompt "共有フォルダ (share) を選んでください。"' \
            -e 'POSIX path of f' \
            -e 'end try' 2>/dev/null
}

# =============================================================================
# Docker helpers
# =============================================================================

test_docker_installed() {
  command -v docker >/dev/null 2>&1
}

# Is the Docker engine actually answering? Docker Desktop's process can be
# running long before the engine is ready, so the server version is queried.
test_docker_running() {
  test_docker_installed || return 1
  docker info --format '{{.ServerVersion}}' >/dev/null 2>&1
}

# Make sure the Docker engine is up: start Docker Desktop if needed and poll
# until it answers. Returns 0 on success.
confirm_docker_ready() {
  if test_docker_running; then
    write_ok "Docker は起動しています。"
    return 0
  fi

  if [ ! -d "/Applications/Docker.app" ]; then
    show_dialog "Docker Desktop がインストールされていないようです。

チュートリアルの Wiki に従って Docker Desktop をインストールしてから、
もう一度このスクリプトを実行してください。" ok stop >/dev/null
    return 1
  fi

  write_step "Docker Desktop を起動しています (最大 ${DOCKER_START_TIMEOUT} 秒かかります)..."
  open -a Docker >/dev/null 2>&1

  waited=0
  while [ "$waited" -lt "$DOCKER_START_TIMEOUT" ]; do
    sleep 3
    waited=$((waited + 3))
    if test_docker_running; then
      printf '\n'
      write_ok "Docker は起動しています。"
      return 0
    fi
    printf '.'
  done
  printf '\n'

  # A timeout usually means Docker Desktop is waiting for user input
  # (licence agreement, update prompt, sign-in screen).
  show_dialog "Docker Desktop が ${DOCKER_START_TIMEOUT} 秒以内に起動しませんでした。

Docker Desktop の画面を開き、操作待ちになっていないか確認してください
(使用許諾への同意、アップデート、サインインなど)。
\"Engine running\" と表示されたら、もう一度このスクリプトを実行してください。" ok caution >/dev/null
  return 1
}

test_image_exists() {
  docker image inspect "$IMAGE_NAME" >/dev/null 2>&1
}

# Image ID of the local copy, or empty if there is none. Comparing the ID
# before and after a pull tells "a newer build was downloaded" from "the local
# copy was already current", without parsing docker's (localised) output.
get_image_id() {
  docker image inspect "$IMAGE_NAME" --format '{{.Id}}' 2>/dev/null
}

# Container state: "running", "exited"/"created" (a leftover), or empty (none).
get_container_state() {
  docker ps -a --filter "name=^${CONTAINER_NAME}$" --format '{{.State}}' 2>/dev/null | head -1
}

# Remove a stopped container. Needed even with --rm, because a container that
# died abnormally can survive and then block "docker run --name abis".
remove_leftover_container() {
  write_step "前回のコンテナが残っているので削除します..."
  if docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1; then
    write_ok "削除しました。"
  else
    write_warn "削除するものはありませんでした。"
  fi
}

test_docker_desktop_process() {
  pgrep -q -x "Docker Desktop" 2>/dev/null || pgrep -q -x com.docker.backend 2>/dev/null
}

# Quit Docker Desktop and wait until it is gone (up to 60 s). Returns 0 once
# no Docker Desktop process is left.
# "docker desktop stop" (Docker Desktop 4.37+) shuts down the app and its
# virtual machine and waits until it is done. Older versions fall back to
# quitting the app by bundle ID: "quit app <name>" opens a "Where is ...?"
# chooser when the name does not match, and the display name has changed
# between Docker Desktop releases.
stop_docker_desktop() {
  if ! docker desktop stop >/dev/null 2>&1; then
    osascript -e 'quit app id "com.docker.docker"' >/dev/null 2>&1
  fi
  _waited=0
  while test_docker_desktop_process && [ "$_waited" -lt 60 ]; do
    sleep 2
    _waited=$((_waited + 2))
  done
  ! test_docker_desktop_process
}

# =============================================================================
# Docker Desktop settings (settings-store.json)
# =============================================================================
# Docker Desktop for Mac keeps the VM's resources in this JSON file (4.35 and
# later; older versions used settings.json with lower-case keys). The keys
# below were checked against a real installation on 2026-10-13. It is an
# internal file, not a documented interface - which is why the configuration
# script only touches these keys, records their original values, and refuses
# to run when the file is missing.
DOCKER_SETTINGS="${HOME}/Library/Group Containers/group.com.docker/settings-store.json"
DOCKER_SETTINGS_KEYS="MemoryMiB SwapMiB Cpus DiskSizeMiB UseVirtualizationFramework UseVirtualizationFrameworkRosetta"
# Original values of the keys changed by 4_Configure_Docker, one "Key=value"
# per line ("Key=" if absent). Its presence means "changed by the launcher".
DOCKER_SETTINGS_ORIGINAL="${HOME}/.abis-docker-settings"

DOCKER_SETTINGS_JS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/docker_settings.js"

# Print "Key=value" for the given keys (all of DOCKER_SETTINGS_KEYS if none).
# shellcheck disable=SC2120  # called both with and without arguments
docker_settings_get() {
  if [ $# -eq 0 ]; then
    # shellcheck disable=SC2086  # the key list is split on purpose
    set -- $DOCKER_SETTINGS_KEYS
  fi
  osascript -l JavaScript "$DOCKER_SETTINGS_JS" get "$DOCKER_SETTINGS" "$@" 2>/dev/null
}

# Value of one key from "Key=value" lines on stdin.
docker_settings_value() {
  sed -n "s/^$1=//p" | head -1
}

# Set keys: docker_settings_set Key=value ... ("Key=" removes the key).
# Docker Desktop must have been quit first.
docker_settings_set() {
  osascript -l JavaScript "$DOCKER_SETTINGS_JS" set "$DOCKER_SETTINGS" "$@" >/dev/null
}

# Installed RAM in whole GB (rounded).
installed_ram_gb() {
  bytes_to_gb_round "$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
}

# Memory to give the Docker VM. Below the recommended 16 GB, half of the RAM
# so that macOS stays usable; from 16 GB, everything but 8 GB for macOS and
# the browser, at most 32 GB. Same rule as Windows.
#   8 -> 4, 12 -> 6, 16 -> 8, 32 -> 24, 40 and above -> 32
docker_memory_target_gb() {
  if [ "$1" -lt 16 ]; then
    _t=$(( $1 / 2 ))
  else
    _t=$(( $1 - 8 ))
    [ "$_t" -gt 32 ] && _t=32
  fi
  printf '%s' "$_t"
}

# Apple Silicon, also when this shell itself runs under Rosetta (where
# "uname -m" would say x86_64).
is_apple_silicon() {
  [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ]
}

# =============================================================================
# Share folder validation
# =============================================================================

# Check the selected folder for the problems that are known to cause trouble.
# Returns 0 if it is safe to continue.
test_share_folder() {
  path="$1"

  if [ ! -d "$path" ]; then
    show_dialog "選んだフォルダが見つかりません:

$path" ok stop >/dev/null
    return 1
  fi

  # --- Non-ASCII characters --------------------------------------------
  # Mixed encodings between macOS, the Docker VM and the container are a
  # reliable source of hard-to-diagnose failures. (macOS stores file names in
  # decomposed Unicode, which the Linux side sees differently.)
  if printf '%s' "$path" | LC_ALL=C grep -q '[^ -~]'; then
    answer="$(show_dialog "選んだパスに日本語などの文字が含まれています:

$path

コンテナの中で問題が起きることがあります。半角の英数字・ハイフン・
アンダースコアだけのパスを強くおすすめします。

このまま続けますか?" yesno caution)"
    [ "$answer" = "Yes" ] || return 1
  fi

  # --- Cloud-synced folders --------------------------------------------
  # Sync clients will try to upload every intermediate file that FreeSurfer
  # and FSL produce, which is slow at best and corrupting at worst.
  # Box is matched as a whole path component (~/Box, ~/Box Sync); a bare *Box*
  # also hit VirtualBox, Sandbox and the like. Current Box Drive lives under
  # ~/Library/CloudStorage, which is caught by *CloudStorage*.
  case "$path" in
    *OneDrive*|*Dropbox*|*"Google Drive"*|*CloudStorage*|*"Mobile Documents"*|*/Box|*/Box/*|*"/Box Sync"|*"/Box Sync/"*)
      answer="$(show_dialog "選んだフォルダはクラウド同期フォルダの中にあるようです:

$path

解析では大量の中間ファイルが作られます。これらが同期されると
Mac が非常に遅くなり、結果が壊れることもあります。

内蔵ディスクか外付けドライブのフォルダを選び直してください。

このまま続けますか?" yesno caution)"
      [ "$answer" = "Yes" ] || return 1
      ;;
  esac

  # --- Write test -------------------------------------------------------
  probe="${path}/.abis_write_test"
  if ! ( : > "$probe" ) 2>/dev/null; then
    show_dialog "選んだフォルダに書き込めません:

$path

外付けドライブの場合、読み取り専用でマウントされている可能性があります。
取り出してから接続し直してみてください。" ok stop >/dev/null
    return 1
  fi
  rm -f "$probe" 2>/dev/null

  # --- File sharing with Docker ----------------------------------------
  # Docker Desktop only exports a fixed set of directories to its VM. A folder
  # outside those (notably /Volumes on some configurations) mounts as empty.
  case "$path" in
    /Users/*|/Volumes/*|/private/tmp/*|/tmp/*) : ;;
    *)
      answer="$(show_dialog "このフォルダは Docker が既定で共有する場所の外にあります:

$path

Lin4Neuro で共有フォルダが空に見える場合は、
Docker Desktop -> Settings -> Resources -> File sharing に
このパスを追加してください。

このまま続けますか?" yesno caution)"
      [ "$answer" = "Yes" ] || return 1
      ;;
  esac

  write_ok "共有フォルダ: $path"
  return 0
}

# =============================================================================
# Container readiness and browser
# =============================================================================

# Wait until the container reports "healthy". The image ships a HEALTHCHECK
# that passes once the window manager is running AND noVNC serves its page, so
# there is no need to guess a fixed waiting time or to poll the port directly.
wait_for_healthy() {
  write_step "Lin4Neuro のデスクトップが起動するのを待っています..."
  waited=0

  while [ "$waited" -lt "$CONTAINER_READY_TIMEOUT" ]; do
    status="$(docker inspect --format '{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null)"
    if [ -z "$status" ]; then
      printf '\n'
      write_fail "コンテナが予期せず停止しました。"
      return 1
    fi
    case "$status" in
      healthy)
        printf '\n'
        write_ok "デスクトップの準備ができました。"
        return 0
        ;;
      unhealthy)
        printf '\n'
        write_fail "デスクトップを起動できませんでした (コンテナの状態が unhealthy です)。"
        return 1
        ;;
    esac
    printf '.'
    sleep 2
    waited=$((waited + 2))
  done

  printf '\n'
  return 1
}

# Open noVNC. App mode gives a window with no tab bar, so Cmd+W cannot close
# the session by accident.
open_lin4neuro() {
  write_step "ブラウザで Lin4Neuro を開いています..."

  if [ "$OPEN_IN_APP_MODE" = "true" ]; then
    for app in "Google Chrome" "Microsoft Edge"; do
      if [ -d "/Applications/${app}.app" ]; then
        open -na "$app" --args --app="$VNC_URL" >/dev/null 2>&1
        write_ok "専用ウィンドウで開きました。"
        return 0
      fi
    done
    write_warn "Chrome / Edge が見つかりませんでした。既定のブラウザで開きます。"
  fi

  open "$VNC_URL" >/dev/null 2>&1
  write_ok "既定のブラウザで開きました。"
}

# Show the tail of the container log. Used when start-up fails, so the
# participant has something concrete to paste into the support chat.
show_container_log() {
  printf '\n'
  write_step "コンテナのログ (最後の 50 行):"
  printf -- '--------------------------------------------------------------\n'
  docker logs --tail 50 "$CONTAINER_NAME" 2>&1
  printf -- '--------------------------------------------------------------\n'
}
