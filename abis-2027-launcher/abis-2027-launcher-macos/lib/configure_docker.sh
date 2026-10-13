#!/bin/bash
# configure_docker.sh - Show, set or undo Docker Desktop's VM settings on macOS.
# Counterpart of 4_Configure_WSL on Windows. Docker Desktop for Mac has
# sliders for all of this, but a script saves walking participants through
# the settings screens. It changes only:
#   MemoryMiB                          half of RAM under 16 GB, else RAM - 8 GB, at most 32 GB (as on Windows)
#   SwapMiB                            raised to DOCKER_SWAP_MIB if smaller
#   UseVirtualizationFrameworkRosetta  true on Apple Silicon (much faster amd64)
# The virtual disk size is only reported: shrinking it deletes every image,
# and whether an edited DiskSizeMiB is grown in place has not been tested.

# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"

# 4 GB: assumed to be the top of the swap slider in Settings -> Resources
# (to be confirmed on a real Mac, see TESTING.md).
DOCKER_SWAP_MIB=4096
DOCKER_DISK_ADVICE_GB=100  # below this, advise raising the limit in the GUI

write_title "ABiS Lin4Neuro - Docker の設定"

# ---------------------------------------------------------------------------
# [1] Preconditions
# ---------------------------------------------------------------------------
if [ ! -d "/Applications/Docker.app" ]; then
  exit_with_pause "Docker Desktop がインストールされていません。" 1
fi
if [ ! -f "$DOCKER_SETTINGS" ]; then
  show_dialog "Docker Desktop の設定ファイルが見つかりません:

$DOCKER_SETTINGS

Docker Desktop を一度起動してから、もう一度実行してください。
それでも見つからない場合は、Docker Desktop が古い可能性があります。
その場合は Docker Desktop の Settings -> Resources で設定してください。" ok caution >/dev/null
  exit_with_pause "変更はしていません。" 1
fi

CURRENT="$(docker_settings_get)"
if [ -z "$CURRENT" ]; then
  exit_with_pause "設定ファイルを読み取れませんでした。講師にご連絡ください。" 1
fi

# Restarting Docker Desktop would cut off a running tutorial session.
DOCKER_WAS_RUNNING="false"
if test_docker_running; then
  DOCKER_WAS_RUNNING="true"
  if [ "$(get_container_state)" = "running" ]; then
    show_dialog "Lin4Neuro が起動中です。

設定を反映するために Docker Desktop を再起動すると、Lin4Neuro も止まります。
先に「3_Stop_Lin4Neuro」で終了してから、もう一度実行してください。" ok caution >/dev/null
    exit_with_pause "変更はしていません。" 0
  fi
elif test_docker_desktop_process; then
  DOCKER_WAS_RUNNING="true"   # starting up; it will be restarted all the same
fi

# ---------------------------------------------------------------------------
# [2] Current state
# ---------------------------------------------------------------------------
RAM_GB="$(installed_ram_gb)"
TARGET_MEM_GB="$(docker_memory_target_gb "$RAM_GB")"

CUR_MEM="$(printf '%s\n' "$CURRENT" | docker_settings_value MemoryMiB)"
CUR_SWAP="$(printf '%s\n' "$CURRENT" | docker_settings_value SwapMiB)"
CUR_CPUS="$(printf '%s\n' "$CURRENT" | docker_settings_value Cpus)"
CUR_DISK="$(printf '%s\n' "$CURRENT" | docker_settings_value DiskSizeMiB)"
CUR_VZ="$(printf '%s\n' "$CURRENT" | docker_settings_value UseVirtualizationFramework)"
CUR_ROSETTA="$(printf '%s\n' "$CURRENT" | docker_settings_value UseVirtualizationFrameworkRosetta)"

mib_text() { if [ -n "$1" ]; then printf '%s GB' "$(( ($1 + 512) / 1024 ))"; else printf '(未設定)'; fi; }

write_step "現在の設定"
write_info "搭載メモリ   : ${RAM_GB} GB"
write_info "メモリ       : $(mib_text "$CUR_MEM")"
write_info "スワップ     : $(mib_text "$CUR_SWAP")"
write_info "CPU          : ${CUR_CPUS:-(未設定)}"
write_info "仮想ディスク : $(mib_text "$CUR_DISK")"
if is_apple_silicon; then
  write_info "Rosetta      : ${CUR_ROSETTA:-(未設定)}"
fi
if [ -f "$DOCKER_SETTINGS_ORIGINAL" ]; then
  write_info "(このランチャーで変更した設定です)"
fi
printf '\n'

# The disk is only advised on: see the header comment.
if [ -n "$CUR_DISK" ] && [ "$CUR_DISK" -lt $((DOCKER_DISK_ADVICE_GB * 1024)) ]; then
  write_warn "仮想ディスクの上限が $(mib_text "$CUR_DISK") です。イメージだけで約 ${IMAGE_DISK_GB} GB 使います。"
  write_warn "Docker Desktop の Settings -> Resources -> Advanced -> Virtual disk limit を"
  write_warn "${DOCKER_DISK_ADVICE_GB} GB 程度に増やしてください (減らすとイメージがすべて消えます)。"
  printf '\n'
fi

# ---------------------------------------------------------------------------
# [3] Decide what to do
# ---------------------------------------------------------------------------
CHANGES=""      # "Key=value" assignments, space separated
SUMMARY=""      # lines for the confirmation dialog

if [ -f "$DOCKER_SETTINGS_ORIGINAL" ]; then
  # Already changed by this script: the only action offered is to undo it.
  while IFS= read -r line; do
    [ -n "$line" ] && CHANGES="$CHANGES $line"
  done < "$DOCKER_SETTINGS_ORIGINAL"
  ANSWER="$(show_dialog "Docker の設定は、以前このスクリプトで変更しています。

元の設定に戻しますか?
(チュートリアル中は、このままにしておいてください)

戻すには Docker Desktop をいったん終了します。" yesno note)"
  if [ "$ANSWER" != "Yes" ]; then
    exit_with_pause "変更はしていません。" 0
  fi
  UNDO="true"
else
  UNDO="false"
  if [ -z "$CUR_MEM" ] || [ "$CUR_MEM" -lt $((TARGET_MEM_GB * 1024)) ]; then
    CHANGES="$CHANGES MemoryMiB=$((TARGET_MEM_GB * 1024))"
    SUMMARY="${SUMMARY}  メモリ   : $(mib_text "$CUR_MEM") -> ${TARGET_MEM_GB} GB
"
  fi
  if [ -z "$CUR_SWAP" ] || [ "$CUR_SWAP" -lt "$DOCKER_SWAP_MIB" ]; then
    CHANGES="$CHANGES SwapMiB=$DOCKER_SWAP_MIB"
    SUMMARY="${SUMMARY}  スワップ : $(mib_text "$CUR_SWAP") -> $(mib_text "$DOCKER_SWAP_MIB")
"
  fi
  if is_apple_silicon && [ "$CUR_ROSETTA" != "true" ]; then
    # Rosetta in Docker needs the Apple Virtualization framework as the VMM
    # (UseVirtualizationFramework) and Rosetta 2 itself on the Mac.
    if [ "$CUR_VZ" = "false" ]; then
      write_warn "Rosetta を使うには Settings -> General -> Virtual Machine Options で"
      write_warn "\"Apple Virtualization framework\" を選ぶ必要があります。この項目は変更しません。"
    elif ! /usr/bin/pgrep -q oahd 2>/dev/null; then
      write_warn "この Mac には Rosetta 2 がインストールされていません。ターミナルで次を実行してから、"
      write_warn "もう一度このスクリプトを実行してください: softwareupdate --install-rosetta"
    else
      CHANGES="$CHANGES UseVirtualizationFrameworkRosetta=true"
      SUMMARY="${SUMMARY}  Rosetta  : ${CUR_ROSETTA:-未設定} -> true (Intel 用イメージが速く動きます)
"
    fi
  fi

  if [ -z "$CHANGES" ]; then
    show_dialog "Docker の設定は十分です。変更の必要はありません。" ok note >/dev/null
    exit_with_pause "変更の必要はありません。" 0
  fi

  ANSWER="$(show_dialog "Docker Desktop の設定を次のように変更します。

${SUMMARY}
ほかの設定はそのままです。このスクリプトをもう一度実行すると元に戻せます。
変更するには Docker Desktop をいったん終了し、起動し直します。

変更しますか?" yesno note)"
  if [ "$ANSWER" != "Yes" ]; then
    exit_with_pause "キャンセルしました。変更はしていません。" 0
  fi
fi

# ---------------------------------------------------------------------------
# [4] Quit Docker Desktop, write, start it again
# ---------------------------------------------------------------------------
# Docker Desktop keeps its settings in memory and writes them back when it
# quits, so the file may only be changed while it is not running.
if test_docker_desktop_process; then
  write_step "Docker Desktop を終了しています..."
  if ! stop_docker_desktop; then
    exit_with_pause "Docker Desktop を終了できませんでした。メニューバーのアイコンから終了して、もう一度実行してください。" 1
  fi
  write_ok "Docker Desktop を終了しました。"
fi

write_step "設定を書き換えています..."
if [ "$UNDO" = "false" ]; then
  # Record the original values of exactly the keys about to change.
  KEYS=""
  for c in $CHANGES; do KEYS="$KEYS ${c%%=*}"; done
  # shellcheck disable=SC2086  # the key list is split on purpose
  if ! docker_settings_get $KEYS > "$DOCKER_SETTINGS_ORIGINAL" || [ ! -s "$DOCKER_SETTINGS_ORIGINAL" ]; then
    rm -f "$DOCKER_SETTINGS_ORIGINAL"
    exit_with_pause "元の設定を保存できなかったため、変更を中止しました。" 1
  fi
fi
# shellcheck disable=SC2086  # the assignments are split on purpose
if ! docker_settings_set $CHANGES; then
  [ "$UNDO" = "false" ] && rm -f "$DOCKER_SETTINGS_ORIGINAL"
  exit_with_pause "設定ファイルを書き換えられませんでした。変更はしていません。" 1
fi
if [ "$UNDO" = "true" ]; then
  rm -f "$DOCKER_SETTINGS_ORIGINAL"
  write_ok "元の設定に戻しました。"
else
  write_ok "設定を書き換えました。"
fi

if [ "$DOCKER_WAS_RUNNING" = "true" ]; then
  write_step "Docker Desktop を起動し直しています..."
  if ! confirm_docker_ready; then
    exit_with_pause "設定は保存しました。Docker Desktop を手動で起動してください。" 1
  fi
  MEMB="$(docker info --format '{{.MemTotal}}' 2>/dev/null)"
  if [ -n "$MEMB" ]; then
    write_ok "Docker が使えるメモリ: $(bytes_to_gb_text "$MEMB") GB"
  fi
else
  write_info "Docker Desktop を次に起動したときから新しい設定が使われます。"
fi

printf '\n'
exit_with_pause "完了しました。" 0
