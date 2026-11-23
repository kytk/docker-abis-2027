#!/bin/bash
# stop_lin4neuro.sh - Stop the ABiS Lin4Neuro container.
# The container was started with --rm, so stopping it also removes it. Anything
# that was not saved in the share folder is gone afterwards.
# Unlike macOS, the Docker engine itself is left running: there is no VM
# holding on to memory.

# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"

write_title "ABiS Lin4Neuro - 終了"

if ! test_docker_installed; then
  finish "Docker がインストールされていないため、終了する対象はありません。" 0
fi
if ! test_docker_running; then
  if test_docker_permission_denied; then
    explain_docker_group
    finish "Docker を使う権限がありません。" 1
  fi
  finish "Docker が起動していないため、Lin4Neuro も動いていません。" 0
fi

STATE="$(get_container_state)"

if [ -z "$STATE" ]; then
  write_ok "Lin4Neuro は起動していません。"
elif [ "$STATE" = "running" ]; then
  write_warn "共有フォルダの外に置いたファイルは失われます。"
  if ! ask_yes_no "Lin4Neuro を終了しますか?"; then
    finish "キャンセルしました。Lin4Neuro は起動したままです。" 0
  fi

  write_step "Lin4Neuro を終了しています (最大 20 秒かかります)..."
  if ! docker stop -t 20 "$CONTAINER_NAME" >/dev/null 2>&1; then
    write_warn "通常の終了に失敗したため、コンテナを強制的に削除します。"
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
  fi

  if [ -n "$(get_container_state)" ]; then
    remove_leftover_container
  fi
  write_ok "Lin4Neuro を終了しました。"
else
  write_warn "前回のコンテナが残っています (状態: ${STATE})。"
  remove_leftover_container
fi

printf '\n'
finish "完了しました。共有フォルダの中のファイルはそのまま残っています。" 0
