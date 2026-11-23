# shellcheck shell=bash
# shellcheck disable=SC2034  # configuration variables are used by the sourcing scripts
# common.sh - Shared settings and helper functions for the ABiS Lin4Neuro launcher (Linux).
# Sourced by the other scripts in this folder; not meant to be run on its own.
#
# Linux counterpart of abis-2027-launcher-macos/lib/common.sh. Differences:
#   - terminal only: questions are answered with y/N, the share folder is
#     typed (or given as an argument) instead of chosen in a dialog;
#   - Docker Engine runs natively (no VM), started with systemctl;
#   - the image's startup.sh runs "chown -R brain:brain" (uid 1000) on the
#     share folder, which on native Linux really changes the host files'
#     owner - hence the uid check in test_share_folder.

# =============================================================================
# CONFIGURATION - keep in sync with the macOS and Windows launchers
# =============================================================================

IMAGE_REPO="kytk/abis-2027"
IMAGE_TAG="26.12"
IMAGE_NAME="${IMAGE_REPO}:${IMAGE_TAG}"

IMAGE_SIZE_TEXT="約 20 GB"
IMAGE_TIME_TEXT="40〜60 分"
IMAGE_DISK_GB=38

CONTAINER_NAME="abis"
CONTAINER_SHARE="/home/brain/share"
CONTAINER_PORT=6080
HOST_PORT=6080
SHM_SIZE="2g"
CONTAINER_UID=1000                    # uid of "brain" in the image

PLATFORM="linux/amd64"

VNC_PASSWORD="lin4neuro"
VNC_URL="http://127.0.0.1:${HOST_PORT}/vnc.html?resize=scale&autoconnect=1&password=${VNC_PASSWORD}"

MIN_FREE_DISK_GB=100     # free space on /
MIN_MEMORY_GB=8          # Docker uses the host's memory directly
MIN_DOCKER_DISK_GB=60    # free space where Docker keeps its images

DOCKER_START_TIMEOUT=60
CONTAINER_READY_TIMEOUT=180

# Open noVNC in a borderless Chrome/Chromium/Edge app window if one is
# installed, so that Ctrl+W cannot close the session view by accident.
OPEN_IN_APP_MODE="true"

LAUNCHER_VERSION="$(sed -n 's/^version:[[:space:]]*//p' "$(dirname "${BASH_SOURCE[0]}")/../VERSION.txt" 2>/dev/null | tr -d '\r' | head -1)"
[ -n "$LAUNCHER_VERSION" ] || LAUNCHER_VERSION="dev"

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

# A multi-line message, indented, with an empty line before and after.
# Replaces the dialogs of the macOS launcher.
write_block() {
  printf '\n'
  printf '%s\n' "$1" | sed 's/^/    /'
  printf '\n'
}

write_title() {
  printf '\n  %s  %s(launcher %s)%s\n' "$1" "$C_GRAY" "$LAUNCHER_VERSION" "$C_OFF"
  printf '%s  --------------------------------%s\n\n' "$C_GRAY" "$C_OFF"
}

# finish <message> [code]: print the message (green for 0, red otherwise) and exit.
finish() {
  _message="$1"; _code="${2:-0}"
  if [ -n "$_message" ]; then
    if [ "$_code" = "0" ]; then write_ok "$_message"; else write_fail "$_message"; fi
  fi
  exit "$_code"
}

# ask_yes_no <question>: 0 for yes. Default is no; without a terminal, no.
ask_yes_no() {
  printf '%s    %s [y/N]: %s' "$C_YELLOW" "$1" "$C_OFF"
  if [ ! -t 0 ]; then printf '\n'; return 1; fi
  read -r _reply || return 1
  case "$_reply" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *)                 return 1 ;;
  esac
}

# =============================================================================
# Unit helpers
# =============================================================================

# Bytes -> whole GB, rounded (7.9 GB counts as 8 GB).
bytes_to_gb_round() {
  printf '%s' "$(( ($1 + 536870912) / 1073741824 ))"
}

# Bytes -> GB with one decimal, for display.
bytes_to_gb_text() {
  _tenths=$(( ($1 * 10 + 53687091) / 1073741824 ))
  printf '%d.%d' "$(( _tenths / 10 ))" "$(( _tenths % 10 ))"
}

# A field of /proc/meminfo (in kB there) in bytes, or 0.
meminfo_bytes() {
  _kb="$(sed -n "s/^$1:[[:space:]]*\([0-9]*\).*/\1/p" /proc/meminfo 2>/dev/null)"
  printf '%s' "$(( ${_kb:-0} * 1024 ))"
}

# Free / total GB of the filesystem holding <path>: prints "avail size", or nothing.
df_gb() {
  df -Pk "$1" 2>/dev/null | awk 'NR==2 { printf "%d %d", $4/1048576, $2/1048576 }'
}

# =============================================================================
# Docker helpers
# =============================================================================

test_docker_installed() {
  command -v docker >/dev/null 2>&1
}

test_docker_running() {
  test_docker_installed || return 1
  docker info --format '{{.ServerVersion}}' >/dev/null 2>&1
}

# The engine is there but this user may not talk to it (not in "docker").
test_docker_permission_denied() {
  docker info 2>&1 >/dev/null | grep -qi 'permission denied'
}

# "active", "inactive", "failed", ... or empty without systemd.
docker_service_state() {
  command -v systemctl >/dev/null 2>&1 || return 0
  systemctl is-active docker 2>/dev/null
}

# Explain how to get access to the Docker engine without sudo.
explain_docker_group() {
  if getent group docker 2>/dev/null | cut -d: -f4 | tr ',' '\n' | grep -qx "$(id -un)"; then
    write_block "Docker を使う権限がありません。

あなたのユーザーは docker グループに追加済みですが、まだ反映されていません。
一度ログアウトしてログインし直すか、PC を再起動してから、
もう一度このスクリプトを実行してください。"
  else
    write_block "Docker を使う権限がありません。

次のコマンドで、あなたのユーザーを docker グループに追加してください:

    sudo usermod -aG docker $(id -un)

その後、一度ログアウトしてログインし直すか、PC を再起動してから、
もう一度このスクリプトを実行してください。"
  fi
}

# Make sure the Docker engine answers: offer to start the service if it is
# stopped and poll until it is up. Returns 0 on success.
confirm_docker_ready() {
  if ! test_docker_installed; then
    write_block "Docker がインストールされていないようです。

チュートリアルの Wiki に従って Docker Engine をインストールしてから、
もう一度このスクリプトを実行してください。"
    return 1
  fi

  if test_docker_running; then
    write_ok "Docker は起動しています。"
    return 0
  fi

  if test_docker_permission_denied; then
    explain_docker_group
    return 1
  fi

  _state="$(docker_service_state)"
  if [ -n "$_state" ] && [ "$_state" != "active" ]; then
    write_warn "Docker が起動していません (状態: ${_state})。"
    if ! ask_yes_no "Docker を起動しますか? (sudo のパスワードを聞かれます)"; then
      return 1
    fi
    if ! sudo systemctl start docker; then
      write_fail "Docker を起動できませんでした。'systemctl status docker' で原因を確認してください。"
      return 1
    fi
  fi

  write_step "Docker の応答を待っています (最大 ${DOCKER_START_TIMEOUT} 秒)..."
  _waited=0
  while [ "$_waited" -lt "$DOCKER_START_TIMEOUT" ]; do
    if test_docker_running; then
      printf '\n'
      write_ok "Docker は起動しています。"
      return 0
    fi
    printf '.'
    sleep 2
    _waited=$((_waited + 2))
  done
  printf '\n'

  if test_docker_permission_denied; then
    explain_docker_group
  else
    write_block "Docker が ${DOCKER_START_TIMEOUT} 秒以内に応答しませんでした。
'systemctl status docker' と 'docker info' で状態を確認してください。"
  fi
  return 1
}

test_image_exists() {
  docker image inspect "$IMAGE_NAME" >/dev/null 2>&1
}

get_image_id() {
  docker image inspect "$IMAGE_NAME" --format '{{.Id}}' 2>/dev/null
}

get_container_state() {
  docker ps -a --filter "name=^${CONTAINER_NAME}$" --format '{{.State}}' 2>/dev/null | head -1
}

remove_leftover_container() {
  write_step "前回のコンテナが残っているので削除します..."
  if docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1; then
    write_ok "削除しました。"
  else
    write_warn "削除するものはありませんでした。"
  fi
}

# =============================================================================
# Share folder
# =============================================================================

# Expand a leading ~ in a typed path.
expand_tilde() {
  case "$1" in
    "~")   printf '%s' "$HOME" ;;
    "~/"*) printf '%s/%s' "$HOME" "${1#\~/}" ;;
    *)     printf '%s' "$1" ;;
  esac
}

# Ask for the share folder on the terminal. Prints the typed path (with ~
# expanded), or nothing if the input was empty (= cancel).
read_share_folder() {
  [ -t 0 ] || return 0
  printf '    共有フォルダのパスを入力してください (Tab で補完、空のまま Enter でキャンセル)\n' >&2
  read -e -r -p "    > " _p || return 0
  expand_tilde "$_p"
}

# Check the folder for the problems that are known to cause trouble. Offers
# to create it if it does not exist. Prints the absolute path on success.
# All messages go to stderr, because stdout is the result.
test_share_folder() {
  _path="$1"

  if [ ! -e "$_path" ]; then
    write_warn "フォルダがありません: $_path" >&2
    ask_yes_no "このフォルダを作成しますか?" >&2 || return 1
    mkdir -p "$_path" 2>/dev/null || { write_fail "作成できませんでした。" >&2; return 1; }
  fi
  if [ ! -d "$_path" ]; then
    write_fail "フォルダではありません: $_path" >&2
    return 1
  fi
  _path="$(cd "$_path" && pwd -P)"

  # --- Folders that must not be chowned ---------------------------------
  # The container runs "chown -R" on the share folder at every start.
  case "$_path" in
    /|"$HOME"|/home|/root|/etc|/usr|/usr/*|/var|/var/*|/bin|/sbin|/lib|/lib*|/opt|/boot|/boot/*)
      write_block "このフォルダは共有フォルダに使えません: $_path

Lin4Neuro は起動のたびに共有フォルダの中身の所有者を変更します。
ホームフォルダそのものやシステムのフォルダではなく、
専用のフォルダ (例: ~/abis-share) を作って指定してください。" >&2
      return 1
      ;;
  esac

  # --- Owner of the files (uid) -----------------------------------------
  if [ "$(id -u)" != "$CONTAINER_UID" ]; then
    write_block "あなたのユーザー ID (UID) は $(id -u) です。

Lin4Neuro は起動のたびに共有フォルダの中身の所有者を UID ${CONTAINER_UID} に変更します。
そのため、このフォルダのファイルをあなたのユーザーで編集できなくなります。
(元に戻すには: sudo chown -R $(id -un): \"$_path\")" >&2
    ask_yes_no "このまま続けますか?" >&2 || return 1
  fi

  # --- Non-ASCII characters ---------------------------------------------
  if printf '%s' "$_path" | LC_ALL=C grep -q '[^ -~]'; then
    write_block "選んだパスに日本語などの文字が含まれています:
$_path

コンテナの中で問題が起きることがあります。半角の英数字・ハイフン・
アンダースコアだけのパスを強くおすすめします。" >&2
    ask_yes_no "このまま続けますか?" >&2 || return 1
  fi

  # --- Cloud-synced folders ---------------------------------------------
  case "$_path" in
    *Dropbox*|*OneDrive*|*"Google Drive"*|*GoogleDrive*|*pCloud*|*/Box|*/Box/*|*/Nextcloud*|*/ownCloud*)
      write_block "選んだフォルダはクラウド同期フォルダの中にあるようです:
$_path

解析では大量の中間ファイルが作られます。これらが同期されると
PC が非常に遅くなり、結果が壊れることもあります。
同期されない場所のフォルダを選び直すことをおすすめします。" >&2
      ask_yes_no "このまま続けますか?" >&2 || return 1
      ;;
  esac

  # --- Write test -------------------------------------------------------
  _probe="${_path}/.abis_write_test"
  if ! ( : > "$_probe" ) 2>/dev/null; then
    write_fail "選んだフォルダに書き込めません: $_path" >&2
    return 1
  fi
  rm -f "$_probe" 2>/dev/null

  printf '%s' "$_path"
}

# =============================================================================
# Container readiness and browser
# =============================================================================

wait_for_healthy() {
  write_step "Lin4Neuro のデスクトップが起動するのを待っています..."
  _waited=0

  while [ "$_waited" -lt "$CONTAINER_READY_TIMEOUT" ]; do
    _status="$(docker inspect --format '{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null)"
    if [ -z "$_status" ]; then
      printf '\n'
      write_fail "コンテナが予期せず停止しました。"
      return 1
    fi
    case "$_status" in
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
    _waited=$((_waited + 2))
  done

  printf '\n'
  return 1
}

# Open noVNC: a Chrome/Chromium/Edge app window if available, else the
# default browser. Without a graphical session, only print the URL.
open_lin4neuro() {
  write_step "ブラウザで Lin4Neuro を開いています..."

  if [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    write_warn "画面のある環境ではないため、ブラウザは開きません。"
    write_info "次の URL をブラウザで開いてください:"
    write_info "$VNC_URL"
    return 0
  fi

  if [ "$OPEN_IN_APP_MODE" = "true" ]; then
    for _b in google-chrome google-chrome-stable chromium chromium-browser microsoft-edge microsoft-edge-stable; do
      if command -v "$_b" >/dev/null 2>&1; then
        setsid "$_b" --app="$VNC_URL" >/dev/null 2>&1 < /dev/null &
        write_ok "専用ウィンドウで開きました (${_b})。"
        write_info "開かない場合は次の URL をブラウザで開いてください: $VNC_URL"
        return 0
      fi
    done
  fi

  if command -v xdg-open >/dev/null 2>&1; then
    setsid xdg-open "$VNC_URL" >/dev/null 2>&1 < /dev/null &
    write_ok "既定のブラウザで開きました。"
    write_info "開かない場合は次の URL をブラウザで開いてください: $VNC_URL"
  else
    write_info "次の URL をブラウザで開いてください: $VNC_URL"
  fi
}

show_container_log() {
  printf '\n'
  write_step "コンテナのログ (最後の 50 行):"
  printf -- '--------------------------------------------------------------\n'
  docker logs --tail 50 "$CONTAINER_NAME" 2>&1
  printf -- '--------------------------------------------------------------\n'
}
