#!/bin/bash
# check_environment.sh - Collect a diagnostic report about this Mac.
# Writes abis_check_result.txt next to the launcher scripts so that the
# participant can paste or attach it in the tutorial chat.
#
# Comments and identifiers are English; the text shown to the participant is
# Japanese. The file is UTF-8 without BOM.

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

add_line "ABiS Lin4Neuro 動作環境チェック"
add_line "作成日時: $(date '+%Y-%m-%d %H:%M:%S')"
add_line "ランチャーの版: ${LAUNCHER_VERSION}"
add_line "必要なイメージ: ${IMAGE_NAME}"
add_line ""

# ---------------------------------------------------------------------------
# macOS
# ---------------------------------------------------------------------------
add_line "[macOS]"
add_line "  バージョン   : $(sw_vers -productVersion 2>/dev/null) ($(sw_vers -buildVersion 2>/dev/null))"
ARCH="$(uname -m)"
add_line "  アーキテクチャ : ${ARCH}"
add_line "  機種         : $(sysctl -n hw.model 2>/dev/null)"
add_line "  CPU コア数   : $(sysctl -n hw.ncpu 2>/dev/null)"
RAM_BYTES="$(sysctl -n hw.memsize 2>/dev/null)"
if [ -n "$RAM_BYTES" ]; then
  # Shown with one decimal, compared after rounding: a machine that reports
  # 15.9 GB has 16 GB installed and must not be warned about.
  RAM_TEXT="$(bytes_to_gb_text "$RAM_BYTES")"
  add_line "  メモリ       : ${RAM_TEXT} GB"
  if [ "$(bytes_to_gb_round "$RAM_BYTES")" -lt 16 ]; then
    add_warning "この Mac のメモリは ${RAM_TEXT} GB です。16 GB 以上を推奨します。"
  fi
fi
add_line "  Bash         : ${BASH_VERSION}"

# hw.optional.arm64 rather than "uname -m": a shell running under Rosetta
# reports x86_64 on an Apple Silicon Mac.
if is_apple_silicon; then
  add_line ""
  add_line "  この Mac は Apple Silicon です。チュートリアル用イメージは Intel 向け"
  add_line "  (linux/amd64) のため、エミュレーションで動作します。"
  if /usr/bin/pgrep -q oahd 2>/dev/null; then
    add_line "  Rosetta 2    : インストール済み"
  else
    add_line "  Rosetta 2    : 検出できませんでした"
    add_warning "Rosetta 2 が見つかりません。次のコマンドでインストールしてください: softwareupdate --install-rosetta"
  fi
fi
add_line ""

# ---------------------------------------------------------------------------
# Disk space on the startup disk
# ---------------------------------------------------------------------------
add_line "[ディスク空き容量]"
DF_LINE="$(df -Pk / 2>/dev/null | tail -1)"
if [ -n "$DF_LINE" ]; then
  AVAIL_KB="$(printf '%s' "$DF_LINE" | awk '{print $4}')"
  SIZE_KB="$(printf '%s' "$DF_LINE" | awk '{print $2}')"
  AVAIL_GB=$((AVAIL_KB / 1024 / 1024))
  SIZE_GB=$((SIZE_KB / 1024 / 1024))
  add_line "  起動ディスク : 空き ${AVAIL_GB} GB / 全体 ${SIZE_GB} GB"
  if [ "$AVAIL_GB" -lt "$MIN_FREE_DISK_GB" ]; then
    add_problem "起動ディスクの空きが ${AVAIL_GB} GB しかありません。${MIN_FREE_DISK_GB} GB 以上必要です (イメージだけで約 ${IMAGE_DISK_GB} GB 使います)。"
  fi
else
  add_line "  (ディスク情報を取得できませんでした)"
fi
add_line ""

# ---------------------------------------------------------------------------
# Docker Desktop
# ---------------------------------------------------------------------------
add_line "[Docker]"
if [ ! -d "/Applications/Docker.app" ]; then
  add_line "  Docker Desktop: インストールされていません"
  add_problem "Docker Desktop がインストールされていません。先にインストールしてください。"
elif ! test_docker_installed; then
  add_line "  docker コマンド: 見つかりません"
  add_problem "Docker Desktop はありますが、コマンドライン版が見つかりません。"
else
  add_line "  クライアント : $(docker --version 2>/dev/null)"

  # Docker Desktop's own settings file: readable even while the engine is
  # down, and the only place that says whether Rosetta is used. ASCII values.
  if [ -f "$DOCKER_SETTINGS" ]; then
    # shellcheck disable=SC2119  # no arguments: all keys
    SETTINGS_NOW="$(docker_settings_get)"
    SETTINGS_SET_BY=""
    [ -f "$DOCKER_SETTINGS_ORIGINAL" ] && SETTINGS_SET_BY=" (set by 4_Configure_Docker)"
    add_line "  設定ファイル : $(printf '%s' "$SETTINGS_NOW" | tr '\n' ' ')${SETTINGS_SET_BY}"
    if is_apple_silicon && [ "$(printf '%s\n' "$SETTINGS_NOW" | docker_settings_value UseVirtualizationFrameworkRosetta)" != "true" ]; then
      add_warning "Docker で Rosetta が使われていません。「4_Configure_Docker」を実行すると有効にでき、解析がかなり速くなります。"
    fi
  else
    add_line "  設定ファイル : 見つかりません (${DOCKER_SETTINGS})"
  fi

  # Offer to start Docker Desktop from here. Without a running engine the rest
  # of this section (VM memory, VM disk, whether the image is present) cannot
  # be measured at all, so a report that stops at "not running" tells a tutor
  # almost nothing.
  DOCKER_WAS_STARTED="false"
  if ! test_docker_running; then
    printf '\n'
    ANSWER="$(show_dialog "Docker が起動していません。

チェックを最後まで行うには Docker Desktop を起動する必要があります。
いま起動しますか? (最大 ${DOCKER_START_TIMEOUT} 秒かかります)" yesno note)"
    if [ "$ANSWER" = "Yes" ]; then
      if confirm_docker_ready; then DOCKER_WAS_STARTED="true"; fi
    else
      write_warn "Docker Desktop を起動せずにチェックを続けます。"
    fi
  fi

  if ! test_docker_running; then
    add_line "  エンジン     : 起動していません"
    add_problem "Docker エンジンが起動していません。Docker Desktop を起動してから、もう一度このチェックを実行してください。"
  else
    if [ "$DOCKER_WAS_STARTED" = "true" ]; then
      add_line "  (このチェックのために Docker Desktop を起動しました)"
    fi
    INFO="$(docker info --format '{{.ServerVersion}}|{{.NCPU}}|{{.MemTotal}}|{{.OperatingSystem}}|{{.DockerRootDir}}' 2>/dev/null)"
    if [ -n "$INFO" ]; then
      SRV="$(printf '%s' "$INFO"  | cut -d'|' -f1)"
      NCPU="$(printf '%s' "$INFO" | cut -d'|' -f2)"
      MEMB="$(printf '%s' "$INFO" | cut -d'|' -f3)"
      OSNAME="$(printf '%s' "$INFO" | cut -d'|' -f4)"
      ROOT="$(printf '%s' "$INFO" | cut -d'|' -f5)"
      # Docker subtracts the VM's own overhead from the memory it was given,
      # so 8 GB assigned is reported as 7.9 GB. Show the exact figure, but
      # compare the rounded one - otherwise a correctly configured machine is
      # told to increase a setting that is already at 8 GB.
      MEM_TEXT="$(bytes_to_gb_text "$MEMB")"
      add_line "  エンジン     : ${SRV}"
      add_line "  バックエンド : ${OSNAME}"
      add_line "  仮想マシンの CPU   : ${NCPU}"
      add_line "  仮想マシンのメモリ : ${MEM_TEXT} GB"
      add_line "  データ保存先 : ${ROOT}"
      # 8 GB is enough for the tutorial, so a large Mac is not told to raise
      # memory towards what 4_Configure_Docker would set. Below 16 GB RAM the
      # target is lower than 8 GB; using it keeps such a Mac, already warned
      # about above, from being sent to a script that has nothing to raise.
      # 0 (RAM unknown) never warns.
      MEM_MIN_GB="$(docker_memory_target_gb "$(installed_ram_gb)")"
      [ "$MEM_MIN_GB" -gt "$MIN_DOCKER_MEMORY_GB" ] && MEM_MIN_GB="$MIN_DOCKER_MEMORY_GB"
      if [ "$(bytes_to_gb_round "$MEMB")" -lt "$MEM_MIN_GB" ]; then
        add_warning "Docker に割り当てられたメモリが ${MEM_TEXT} GB しかありません。「4_Configure_Docker」を実行すると増やせます。"
      fi
      if [ "$NCPU" -lt 4 ]; then
        add_warning "Docker に割り当てられた CPU が ${NCPU} 個しかありません。4 個以上にすると解析がかなり速くなります。"
      fi
    fi

    # Space inside the Docker VM. This is what actually limits "docker pull",
    # and it is not the same as the free space on the startup disk.
    add_line ""
    add_line "  Docker が使えるディスク容量 (Docker の仮想マシン内):"
    VM_DF="$(docker run --rm --platform "$PLATFORM" alpine df -P / 2>/dev/null | tail -1)"
    if [ -n "$VM_DF" ]; then
      VM_AVAIL_GB=$(( $(printf '%s' "$VM_DF" | awk '{print $4}') / 1024 / 1024 ))
      VM_SIZE_GB=$(( $(printf '%s' "$VM_DF" | awk '{print $2}') / 1024 / 1024 ))
      add_line "    空き ${VM_AVAIL_GB} GB / 全体 ${VM_SIZE_GB} GB"
      if [ "$VM_AVAIL_GB" -lt "$MIN_DOCKER_DISK_GB" ]; then
        add_problem "Docker が使える空き容量が ${VM_AVAIL_GB} GB しかありません。イメージに約 ${IMAGE_DISK_GB} GB 必要です。Docker Desktop の Settings -> Resources で仮想ディスクの上限を増やすか、'docker system prune -a' で空けてください。"
      fi
    else
      add_line "    (測定できませんでした。ネットワークに接続していないか、Docker が小さなテスト用イメージを取得できません)"
      add_warning "Docker が使えるディスク容量を測定できませんでした。ネットワーク接続を確認してください。"
    fi

    # Is the tutorial image already here?
    add_line ""
    if test_image_exists; then
      IMG_SIZE="$(docker image inspect "$IMAGE_NAME" --format '{{.Size}}' 2>/dev/null)"
      if [ -n "$IMG_SIZE" ]; then
        add_line "  チュートリアル用イメージ: ダウンロード済み (ディスク上 $((IMG_SIZE / 1024 / 1024 / 1024)) GB)"
      else
        add_line "  チュートリアル用イメージ: ダウンロード済み"
      fi
      add_line "                            更新の有無は「1_Download_Image」で確認できます。"
    else
      add_line "  チュートリアル用イメージ: 未ダウンロード (${IMAGE_NAME})"
      add_line "                            準備ができたら「1_Download_Image」を実行してください。"
    fi
  fi
fi
add_line ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
add_line "[判定]"
if [ "$PROBLEMS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
  add_line "  OK - この Mac は必要な条件を満たしています。"
else
  while IFS= read -r issue; do add_line "$issue"; done < "$REPORT.issues"
fi
rm -f "$REPORT.issues"
add_line ""

printf '\n'
write_ok "結果を保存しました: $REPORT"

if [ "$PROBLEMS" -gt 0 ]; then
  show_dialog "動作環境チェックで ${PROBLEMS} 件の問題が見つかりました。

ターミナルウィンドウの内容をご確認ください。判断に迷う場合は
abis_check_result.txt をチュートリアルのチャットに送ってください。" ok caution >/dev/null
  exit_with_pause "" 1
elif [ "$WARNINGS" -gt 0 ]; then
  exit_with_pause "チェックが終わりました (注意事項があります)。上の内容をご確認ください。" 0
else
  show_dialog "この Mac は必要な条件を満たしています。

次の手順: 「1_Download_Image」を実行して、チュートリアル環境を
ダウンロードしてください (${IMAGE_SIZE_TEXT}、${IMAGE_TIME_TEXT})。" ok note >/dev/null
  exit_with_pause "チェックが終わりました。" 0
fi
