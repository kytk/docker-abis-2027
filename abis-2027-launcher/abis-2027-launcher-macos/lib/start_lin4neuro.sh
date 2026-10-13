#!/bin/bash
# start_lin4neuro.sh - Start the ABiS Lin4Neuro container and open it in a browser.
# A fresh container is created each time (--rm); all work must be saved in the
# share folder, which is chosen again on every start.

# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"

write_title "ABiS Lin4Neuro - 起動"

# ---------------------------------------------------------------------------
# [1] Docker engine
# ---------------------------------------------------------------------------
write_step "Docker を確認しています..."
if ! confirm_docker_ready; then
  exit_with_pause "Docker の準備ができていません。上のメッセージをご確認ください。" 1
fi

# ---------------------------------------------------------------------------
# [2] Container image
# ---------------------------------------------------------------------------
# Deliberately no pull here: a silent 20 GB download would leave the
# participant staring at a frozen window. Downloading is a separate, explicit
# step (1_Download_Image).
write_step "イメージ ${IMAGE_NAME} を確認しています..."
if ! test_image_exists; then
  show_dialog "チュートリアル用のイメージがまだこの Mac にありません:

  ${IMAGE_NAME}

先に「1_Download_Image」を実行してください。
ダウンロード量は ${IMAGE_SIZE_TEXT}、所要時間は ${IMAGE_TIME_TEXT} です。" ok caution >/dev/null
  exit_with_pause "イメージが見つかりません。" 1
fi
write_ok "イメージを確認しました。"

# ---------------------------------------------------------------------------
# [3] Existing container
# ---------------------------------------------------------------------------
STATE="$(get_container_state)"

if [ "$STATE" = "running" ]; then
  # Already up - most likely the participant double-clicked twice because
  # startup felt slow. Do not create anything, just reconnect.
  write_ok "Lin4Neuro はすでに起動しています。接続し直します。"
  write_info "別の共有フォルダを使いたい場合は、先に「3_Stop_Lin4Neuro」を実行してください。"
  if ! wait_for_healthy; then
    show_container_log
    exit_with_pause "デスクトップが応答しません。「3_Stop_Lin4Neuro」を実行してから起動し直してください。" 1
  fi
  open_lin4neuro
  exit_with_pause "" 0
fi

if [ -n "$STATE" ]; then
  # A stopped container with our name exists. With --rm this should not
  # happen, but an abnormal exit can leave one behind - and it would block
  # "docker run --name abis" with a name conflict.
  remove_leftover_container
fi

# ---------------------------------------------------------------------------
# [4] Choose the share folder
# ---------------------------------------------------------------------------
# Asked every time: the container is disposable, so the mount is decided fresh
# on each run. This also catches a disconnected external drive here, rather
# than producing a container with an empty share folder.
write_step "共有フォルダを選んでください..."
write_info "残しておきたいものは、すべてこのフォルダの中に保存してください。"

SHARE_PATH=""
while [ -z "$SHARE_PATH" ]; do
  SELECTED="$(select_share_folder)"
  if [ -z "$SELECTED" ]; then
    exit_with_pause "キャンセルしました。Lin4Neuro は起動していません。" 0
  fi
  # "choose folder" returns a trailing slash; docker does not need it.
  SELECTED="${SELECTED%/}"
  if test_share_folder "$SELECTED"; then
    SHARE_PATH="$SELECTED"
  fi
  # Otherwise loop and let them choose again.
done

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
  show_dialog "Lin4Neuro を起動できませんでした。

よくある原因:
  - ポート ${HOST_PORT} を別のプログラムが使っている
  - ディスクの空き容量が足りない
  - 外付けドライブが取り外されている

詳しい内容は、このダイアログの後ろのターミナルに表示されています。" ok stop >/dev/null
  exit_with_pause "docker run に失敗しました。" 1
fi
write_ok "コンテナを起動しました。"

# ---------------------------------------------------------------------------
# [6] Wait until the desktop is ready
# ---------------------------------------------------------------------------
if ! wait_for_healthy; then
  show_container_log
  show_dialog "Lin4Neuro のデスクトップが ${CONTAINER_READY_TIMEOUT} 秒以内に起動しませんでした。

ターミナルにコンテナのログ (最後の 50 行) を表示しています。
その内容をチュートリアルのチャットに貼り付けてください。" ok stop >/dev/null
  exit_with_pause "起動がタイムアウトしました。" 1
fi

# ---------------------------------------------------------------------------
# [7] Open the browser
# ---------------------------------------------------------------------------
open_lin4neuro

printf '\n'
write_ok "Lin4Neuro の準備ができました。"
write_info "共有フォルダは Lin4Neuro の中では ${CONTAINER_SHARE} です。"
write_warn "作業したファイルは必ず共有フォルダの中に保存してください。"
write_warn "ブラウザを閉じても Lin4Neuro は止まりません。終了するときは「3_Stop_Lin4Neuro」を実行してください。"
exit_with_pause "" 0
