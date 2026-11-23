#!/bin/bash
# start_lin4neuro.sh - Start the ABiS Lin4Neuro container and open it in a browser.
# Usage: 2_Start_Lin4Neuro.sh [share-folder]
# A fresh container is created each time (--rm); all work must be saved in the
# share folder, which is given again on every start.

# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"

write_title "ABiS Lin4Neuro - 起動"

# ---------------------------------------------------------------------------
# [1] Docker engine
# ---------------------------------------------------------------------------
write_step "Docker を確認しています..."
if ! confirm_docker_ready; then
  finish "Docker の準備ができていません。上のメッセージをご確認ください。" 1
fi

# ---------------------------------------------------------------------------
# [2] Container image (never pulled here - that is 1_Download_Image)
# ---------------------------------------------------------------------------
write_step "イメージ ${IMAGE_NAME} を確認しています..."
if ! test_image_exists; then
  write_block "チュートリアル用のイメージがまだこの PC にありません:
  ${IMAGE_NAME}

先に「1_Download_Image.sh」を実行してください。
ダウンロード量は ${IMAGE_SIZE_TEXT}、所要時間は ${IMAGE_TIME_TEXT} です。"
  finish "イメージが見つかりません。" 1
fi
write_ok "イメージを確認しました。"

# ---------------------------------------------------------------------------
# [3] Existing container
# ---------------------------------------------------------------------------
STATE="$(get_container_state)"

if [ "$STATE" = "running" ]; then
  write_ok "Lin4Neuro はすでに起動しています。接続し直します。"
  write_info "別の共有フォルダを使いたい場合は、先に「3_Stop_Lin4Neuro.sh」を実行してください。"
  if ! wait_for_healthy; then
    show_container_log
    finish "デスクトップが応答しません。「3_Stop_Lin4Neuro.sh」を実行してから起動し直してください。" 1
  fi
  open_lin4neuro
  finish "" 0
fi

if [ -n "$STATE" ]; then
  remove_leftover_container
fi

# ---------------------------------------------------------------------------
# [4] Share folder: the argument if given, otherwise asked on the terminal
# ---------------------------------------------------------------------------
write_step "共有フォルダを確認しています..."
write_info "残しておきたいものは、すべてこのフォルダの中に保存してください。"

SHARE_PATH=""
CANDIDATE="${1:-}"
[ -n "$CANDIDATE" ] && CANDIDATE="$(expand_tilde "$CANDIDATE")"
while [ -z "$SHARE_PATH" ]; do
  if [ -z "$CANDIDATE" ]; then
    CANDIDATE="$(read_share_folder)"
    if [ -z "$CANDIDATE" ]; then
      finish "キャンセルしました。Lin4Neuro は起動していません。" 0
    fi
  fi
  SHARE_PATH="$(test_share_folder "$CANDIDATE")"
  CANDIDATE=""   # on failure, ask again
done
write_ok "共有フォルダ: $SHARE_PATH"

# ---------------------------------------------------------------------------
# [5] Start the container
# ---------------------------------------------------------------------------
write_step "Lin4Neuro を起動しています..."

printf '\n%s    docker run -d --rm --name %s --platform %s --shm-size %s -v "%s:%s" -p 127.0.0.1:%s:%s %s%s\n\n' \
  "$C_GRAY" "$CONTAINER_NAME" "$PLATFORM" "$SHM_SIZE" "$SHARE_PATH" "$CONTAINER_SHARE" \
  "$HOST_PORT" "$CONTAINER_PORT" "$IMAGE_NAME" "$C_OFF"

if ! docker run -d --rm \
      --name "$CONTAINER_NAME" \
      --platform "$PLATFORM" \
      --shm-size "$SHM_SIZE" \
      -v "${SHARE_PATH}:${CONTAINER_SHARE}" \
      -p "127.0.0.1:${HOST_PORT}:${CONTAINER_PORT}" \
      "$IMAGE_NAME" >/dev/null; then
  write_block "Lin4Neuro を起動できませんでした。上のエラーメッセージをご確認ください。

よくある原因:
  - ポート ${HOST_PORT} を別のプログラムが使っている
  - ディスクの空き容量が足りない
  - 外付けドライブが取り外されている"
  finish "docker run に失敗しました。" 1
fi
write_ok "コンテナを起動しました。"

# ---------------------------------------------------------------------------
# [6] Wait until the desktop is ready
# ---------------------------------------------------------------------------
if ! wait_for_healthy; then
  show_container_log
  write_block "Lin4Neuro のデスクトップが ${CONTAINER_READY_TIMEOUT} 秒以内に起動しませんでした。
上のコンテナのログ (最後の 50 行) をチュートリアルのチャットに貼り付けてください。"
  finish "起動がタイムアウトしました。" 1
fi

# ---------------------------------------------------------------------------
# [7] Open the browser
# ---------------------------------------------------------------------------
open_lin4neuro

printf '\n'
write_ok "Lin4Neuro の準備ができました。"
write_info "共有フォルダは Lin4Neuro の中では ${CONTAINER_SHARE} です。"
write_warn "作業したファイルは必ず共有フォルダの中に保存してください。"
write_warn "ブラウザを閉じても Lin4Neuro は止まりません。終了するときは「3_Stop_Lin4Neuro.sh」を実行してください。"
finish "" 0
