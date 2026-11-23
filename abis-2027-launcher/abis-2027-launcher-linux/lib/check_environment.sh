#!/bin/bash
# check_environment.sh - Collect a diagnostic report about this Linux PC.
# Writes abis_check_result.txt next to the launcher scripts so that the
# participant can paste or attach it in the tutorial chat.

# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"

REPORT="$(cd "$(dirname "$0")/.." && pwd)/abis_check_result.txt"
PROBLEMS=0
WARNINGS=0

: > "$REPORT" 2>/dev/null || REPORT="/tmp/abis_check_result.txt"

add_line()    { printf '%s\n' "$1"; printf '%s\n' "$1" >> "$REPORT"; }
add_problem() { PROBLEMS=$((PROBLEMS + 1)); printf '%s\n' "  【要対応】$1" >> "$REPORT.issues"; }
add_warning() { WARNINGS=$((WARNINGS + 1)); printf '%s\n' "  【注意】$1" >> "$REPORT.issues"; }
rm -f "$REPORT.issues"

write_title "ABiS Lin4Neuro - 動作環境チェック"

add_line "ABiS Lin4Neuro 動作環境チェック (Linux)"
add_line "作成日時: $(date '+%Y-%m-%d %H:%M:%S')"
add_line "ランチャーの版: ${LAUNCHER_VERSION}"
add_line "必要なイメージ: ${IMAGE_NAME}"
add_line ""

# ---------------------------------------------------------------------------
# OS and hardware
# ---------------------------------------------------------------------------
add_line "[Linux]"
OS_NAME="$(sed -n 's/^PRETTY_NAME="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' /etc/os-release 2>/dev/null)"
add_line "  ディストリビューション : ${OS_NAME:-不明}"
add_line "  カーネル     : $(uname -r)"
ARCH="$(uname -m)"
add_line "  アーキテクチャ : ${ARCH}"
if [ "$ARCH" != "x86_64" ]; then
  add_problem "この PC は ${ARCH} です。チュートリアル用イメージは x86_64 (linux/amd64) 向けのため、そのままでは動きません (qemu によるエミュレーションは非常に遅くなります)。"
fi
add_line "  CPU コア数   : $(nproc 2>/dev/null)"

RAM_BYTES="$(meminfo_bytes MemTotal)"
SWAP_BYTES="$(meminfo_bytes SwapTotal)"
if [ "$RAM_BYTES" -gt 0 ]; then
  RAM_TEXT="$(bytes_to_gb_text "$RAM_BYTES")"
  RAM_GB="$(bytes_to_gb_round "$RAM_BYTES")"
  add_line "  メモリ       : ${RAM_TEXT} GB"
  if [ "$RAM_GB" -lt "$MIN_MEMORY_GB" ]; then
    add_problem "この PC のメモリは ${RAM_TEXT} GB です。最低 ${MIN_MEMORY_GB} GB、できれば 16 GB 以上が必要です。"
  elif [ "$RAM_GB" -lt 16 ]; then
    add_warning "この PC のメモリは ${RAM_TEXT} GB です。16 GB 以上を推奨します。"
  fi
fi
add_line "  スワップ     : $(bytes_to_gb_text "$SWAP_BYTES") GB"
if [ "$(nproc 2>/dev/null || echo 4)" -lt 4 ]; then
  add_warning "CPU コアが $(nproc) 個しかありません。4 個以上あると解析がかなり速くなります。"
fi
add_line "  ユーザー     : $(id -un) (UID $(id -u))"
if [ "$(id -u)" != "$CONTAINER_UID" ]; then
  add_warning "UID が ${CONTAINER_UID} ではありません。Lin4Neuro は共有フォルダの中身の所有者を UID ${CONTAINER_UID} に変更するため、あなたのユーザーでそのファイルを編集できなくなります。"
fi
if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
  add_line "  画面         : あり (${XDG_CURRENT_DESKTOP:-不明})"
else
  add_line "  画面         : なし (ブラウザは自動では開きません)"
fi
BROWSER=""
for b in google-chrome google-chrome-stable chromium chromium-browser microsoft-edge microsoft-edge-stable firefox; do
  if command -v "$b" >/dev/null 2>&1; then BROWSER="$b"; break; fi
done
add_line "  ブラウザ     : ${BROWSER:-見つかりません}"
add_line "  Bash         : ${BASH_VERSION}"
add_line ""

# ---------------------------------------------------------------------------
# Disk space
# ---------------------------------------------------------------------------
add_line "[ディスク空き容量]"
read -r AVAIL_GB SIZE_GB <<EOF
$(df_gb /)
EOF
if [ -n "$AVAIL_GB" ]; then
  add_line "  /            : 空き ${AVAIL_GB} GB / 全体 ${SIZE_GB} GB"
  if [ "$AVAIL_GB" -lt "$MIN_FREE_DISK_GB" ]; then
    add_problem "/ の空きが ${AVAIL_GB} GB しかありません。${MIN_FREE_DISK_GB} GB 以上必要です (イメージだけで約 ${IMAGE_DISK_GB} GB 使います)。"
  fi
fi
# The home folder (where the share folder usually is) may be another filesystem.
if [ "$(df -P "$HOME" 2>/dev/null | awk 'NR==2{print $1}')" != "$(df -P / 2>/dev/null | awk 'NR==2{print $1}')" ]; then
  read -r H_AVAIL H_SIZE <<EOF
$(df_gb "$HOME")
EOF
  add_line "  ${HOME} : 空き ${H_AVAIL} GB / 全体 ${H_SIZE} GB"
fi
add_line ""

# ---------------------------------------------------------------------------
# Docker
# ---------------------------------------------------------------------------
add_line "[Docker]"
if ! test_docker_installed; then
  add_line "  docker コマンド: 見つかりません"
  add_problem "Docker がインストールされていません。先に Docker Engine をインストールしてください。"
else
  add_line "  クライアント : $(docker --version 2>/dev/null)"
  SERVICE_STATE="$(docker_service_state)"
  add_line "  サービス     : ${SERVICE_STATE:-不明 (systemd なし)}"
  CONTEXT="$(docker context show 2>/dev/null)"
  add_line "  コンテキスト : ${CONTEXT:-不明}"
  if [ "$CONTEXT" = "desktop-linux" ]; then
    add_warning "Docker Desktop for Linux が使われています。このランチャーは Docker Engine を前提にしています。メモリ・ディスクは Docker Desktop の Settings -> Resources で確認してください。"
  fi
  if id -nG | tr ' ' '\n' | grep -qx docker; then
    add_line "  docker グループ: 所属しています"
  else
    add_line "  docker グループ: 所属していません"
  fi

  DOCKER_WAS_STARTED="false"
  if ! test_docker_running && ! test_docker_permission_denied; then
    printf '\n'
    if confirm_docker_ready; then DOCKER_WAS_STARTED="true"; fi
  fi

  if ! test_docker_running; then
    if test_docker_permission_denied; then
      add_line "  エンジン     : 権限がありません (permission denied)"
      add_problem "Docker を使う権限がありません。'sudo usermod -aG docker $(id -un)' を実行し、ログインし直してください。"
      explain_docker_group
    else
      add_line "  エンジン     : 起動していません"
      add_problem "Docker エンジンが起動していません。'sudo systemctl start docker' で起動してから、もう一度このチェックを実行してください。"
    fi
  else
    [ "$DOCKER_WAS_STARTED" = "true" ] && add_line "  (このチェックのために Docker を起動しました)"
    INFO="$(docker info --format '{{.ServerVersion}}|{{.NCPU}}|{{.MemTotal}}|{{.OperatingSystem}}|{{.DockerRootDir}}' 2>/dev/null)"
    if [ -n "$INFO" ]; then
      SRV="$(printf '%s' "$INFO"    | cut -d'|' -f1)"
      NCPU="$(printf '%s' "$INFO"   | cut -d'|' -f2)"
      MEMB="$(printf '%s' "$INFO"   | cut -d'|' -f3)"
      OSNAME="$(printf '%s' "$INFO" | cut -d'|' -f4)"
      ROOT="$(printf '%s' "$INFO"   | cut -d'|' -f5)"
      add_line "  エンジン     : ${SRV}"
      add_line "  OS           : ${OSNAME}"
      add_line "  使える CPU   : ${NCPU}"
      add_line "  使えるメモリ : $(bytes_to_gb_text "$MEMB") GB"
      add_line "  データ保存先 : ${ROOT}"

      # Free space where the images are stored. df only needs to look the
      # path up, so a root-only /var/lib/docker can still be measured.
      read -r D_AVAIL D_SIZE <<EOF
$(df_gb "$ROOT")
EOF
      if [ -n "$D_AVAIL" ]; then
        add_line "  保存先の空き : ${D_AVAIL} GB / 全体 ${D_SIZE} GB"
        if ! test_image_exists && [ "$D_AVAIL" -lt "$MIN_DOCKER_DISK_GB" ]; then
          add_problem "Docker の保存先 (${ROOT}) の空きが ${D_AVAIL} GB しかありません。イメージに約 ${IMAGE_DISK_GB} GB 必要です。'docker system prune -a' などで空けてください。"
        fi
      else
        add_line "  保存先の空き : 測定できませんでした"
      fi
    fi

    add_line ""
    if test_image_exists; then
      IMG_SIZE="$(docker image inspect "$IMAGE_NAME" --format '{{.Size}}' 2>/dev/null)"
      add_line "  チュートリアル用イメージ: ダウンロード済み (ディスク上 $((${IMG_SIZE:-0} / 1024 / 1024 / 1024)) GB)"
      add_line "                            更新の有無は「1_Download_Image.sh」で確認できます。"
    else
      add_line "  チュートリアル用イメージ: 未ダウンロード (${IMAGE_NAME})"
      add_line "                            準備ができたら「1_Download_Image.sh」を実行してください。"
    fi

    STATE="$(get_container_state)"
    [ -n "$STATE" ] && add_line "  Lin4Neuro コンテナ: ${STATE}"
  fi
fi
add_line ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
add_line "[判定]"
if [ "$PROBLEMS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
  add_line "  OK - この PC は必要な条件を満たしています。"
else
  while IFS= read -r issue; do add_line "$issue"; done < "$REPORT.issues"
fi
rm -f "$REPORT.issues"
add_line ""

write_ok "結果を保存しました: $REPORT"

if [ "$PROBLEMS" -gt 0 ]; then
  write_block "動作環境チェックで ${PROBLEMS} 件の問題が見つかりました。
上の内容をご確認ください。判断に迷う場合は
abis_check_result.txt をチュートリアルのチャットに送ってください。"
  finish "" 1
elif [ "$WARNINGS" -gt 0 ]; then
  finish "チェックが終わりました (注意事項があります)。上の内容をご確認ください。" 0
else
  write_block "次の手順: 「1_Download_Image.sh」を実行して、チュートリアル環境を
ダウンロードしてください (${IMAGE_SIZE_TEXT}、${IMAGE_TIME_TEXT})。"
  finish "チェックが終わりました。" 0
fi
