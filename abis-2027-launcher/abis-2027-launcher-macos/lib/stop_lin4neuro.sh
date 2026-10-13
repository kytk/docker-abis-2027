#!/bin/bash
# stop_lin4neuro.sh - Stop the ABiS Lin4Neuro container.
# The container was started with --rm, so stopping it also removes it. Anything
# that was not saved in the share folder is gone afterwards.

# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"

write_title "ABiS Lin4Neuro - 終了"

# ---------------------------------------------------------------------------
# [1] Docker engine
# ---------------------------------------------------------------------------
if [ ! -d "/Applications/Docker.app" ] || ! test_docker_installed; then
  exit_with_pause "Docker Desktop がインストールされていないため、終了する対象はありません。" 0
fi
if ! test_docker_running; then
  exit_with_pause "Docker が起動していないため、Lin4Neuro も動いていません。" 0
fi

# ---------------------------------------------------------------------------
# [2] Stop the container
# ---------------------------------------------------------------------------
STATE="$(get_container_state)"

if [ -z "$STATE" ]; then
  write_ok "Lin4Neuro は起動していません。"
elif [ "$STATE" = "running" ]; then
  ANSWER="$(show_dialog "Lin4Neuro を終了しますか?

共有フォルダの外に置いたファイルは失われます。" yesno caution)"
  if [ "$ANSWER" != "Yes" ]; then
    exit_with_pause "キャンセルしました。Lin4Neuro は起動したままです。" 0
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

# ---------------------------------------------------------------------------
# [3] Offer to quit Docker Desktop
# ---------------------------------------------------------------------------
# Docker Desktop keeps a virtual machine running in the background and holds
# on to several GB of memory, which is worth reclaiming after a session.
ANSWER="$(show_dialog "Docker Desktop も終了しますか?

Docker は Lin4Neuro を止めた後も仮想マシンを動かし続けており、
数 GB のメモリを使っています。

すぐにまた Lin4Neuro を起動する場合は「No」を選んでください。" yesno note)"
# The buttons of show_dialog are "Yes"/"No" (not localised), so the text above
# names "No" rather than いいえ.

if [ "$ANSWER" = "Yes" ]; then
  write_step "Docker Desktop を終了しています..."
  # stop_docker_desktop (common.sh) tries "docker desktop stop" first and
  # waits up to 60 s for the app to go away.
  if stop_docker_desktop; then
    write_ok "Docker Desktop を終了しました。"
  else
    write_warn "Docker Desktop がまだ動いています。メニューバーのアイコンから終了できます。"
  fi
else
  write_info "Docker Desktop は起動したままです。"
fi

printf '\n'
write_ok "完了しました。共有フォルダの中のファイルはそのまま残っています。"
exit_with_pause "" 0
