#!/bin/bash
# pull_image.sh - Download the tutorial image, or update an existing copy.
# Run before the course, and again whenever a new build is announced.
# Always pulls: the tag is fixed but the image behind it may be rebuilt. The
# image ID before and after tells an update from an already-current copy.

# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"

write_title "ABiS Lin4Neuro - イメージのダウンロード・更新"

# ---------------------------------------------------------------------------
# [1] Docker engine
# ---------------------------------------------------------------------------
write_step "Docker を確認しています..."
if ! confirm_docker_ready; then
  finish "Docker の準備ができていません。上のメッセージをご確認ください。" 1
fi

# ---------------------------------------------------------------------------
# [2] Confirm
# ---------------------------------------------------------------------------
BEFORE_ID="$(get_image_id)"

if [ -n "$BEFORE_ID" ]; then
  write_block "チュートリアル用のイメージはすでにこの PC にあります:
  ${IMAGE_NAME}

更新されていないかを確認します。最新版であれば、すぐに終わります。
更新されていた場合は、変わった部分だけをダウンロードします
(内容によっては時間がかかることがあります)。"
  QUESTION="確認しますか?"
else
  write_block "これからチュートリアル環境をダウンロードします。

  イメージ       : ${IMAGE_NAME}
  ダウンロード量 : ${IMAGE_SIZE_TEXT}
  所要時間       : 高速な回線で ${IMAGE_TIME_TEXT}
  ディスク使用量 : 展開後 約 ${IMAGE_DISK_GB} GB

安定したネットワークにつなぎ、ノート PC なら電源アダプタを接続してください。
途中で中断しても、このスクリプトをもう一度実行すれば続きから再開できます。"
  QUESTION="ダウンロードを始めますか?"
fi

if ! ask_yes_no "$QUESTION"; then
  finish "キャンセルしました。" 0
fi

# ---------------------------------------------------------------------------
# [3] Pull
# ---------------------------------------------------------------------------
if [ -n "$BEFORE_ID" ]; then
  write_step "${IMAGE_NAME} の更新を確認しています..."
else
  write_step "${IMAGE_NAME} をダウンロードしています..."
fi
printf '\n'

STARTED="$(date +%s)"

# Keep the PC from sleeping during the download. systemd-inhibit can be
# refused by polkit (e.g. over ssh), so it is tried first and the pull runs
# without it in that case - a refused inhibit must not look like a failed pull.
INHIBIT=""
if command -v systemd-inhibit >/dev/null 2>&1 && \
   systemd-inhibit --what=sleep:idle --who=ABiS --why=test true >/dev/null 2>&1; then
  INHIBIT="systemd-inhibit --what=sleep:idle --who=ABiS --why=docker-pull"
fi

# shellcheck disable=SC2086  # INHIBIT is split on purpose
if ! $INHIBIT docker pull --platform "$PLATFORM" "$IMAGE_NAME"; then
  printf '\n'
  if [ -n "$BEFORE_ID" ]; then
    write_block "更新を確認できませんでした。

ネットワークにつながっていないか、Docker Hub につながらないようです。
すでにあるイメージはそのまま使えます。「2_Start_Lin4Neuro.sh」で起動してください。"
    finish "更新は確認できませんでしたが、イメージはこの PC にあります。" 0
  fi

  write_block "ダウンロードが完了しませんでした。

よくある原因:
  - ネットワークが切断された
  - ディスクの空き容量が足りない (「0_Check_Environment.sh」で確認できます)

このスクリプトをもう一度実行すれば、中断したところから再開します。"
  finish "docker pull に失敗しました。" 1
fi

# ---------------------------------------------------------------------------
# [4] Verify
# ---------------------------------------------------------------------------
printf '\n'
write_step "イメージを確認しています..."
AFTER_ID="$(get_image_id)"
if [ -z "$AFTER_ID" ]; then
  finish "ダウンロード後もイメージが見つかりません。講師にご連絡ください。" 1
fi

ELAPSED=$(( $(date +%s) - STARTED ))
IMG_SIZE="$(docker image inspect "$IMAGE_NAME" --format '{{.Size}}' 2>/dev/null)"

if [ "$BEFORE_ID" = "$AFTER_ID" ]; then
  write_ok "イメージは最新版です。ダウンロードするものはありませんでした。"
  finish "「2_Start_Lin4Neuro.sh」で起動してください。" 0
fi

write_ok "イメージの準備ができました。"
if [ -n "$IMG_SIZE" ]; then
  write_info "ディスク使用量 : $((IMG_SIZE / 1024 / 1024 / 1024)) GB"
fi
write_info "所要時間       : $((ELAPSED / 60)) 分 $((ELAPSED % 60)) 秒"

# ---------------------------------------------------------------------------
# [5] Clean up the build that was replaced
# ---------------------------------------------------------------------------
if [ -n "$BEFORE_ID" ]; then
  write_block "イメージを新しい版に更新しました。
前の版がディスクに残っています (約 ${IMAGE_DISK_GB} GB)。
これから使うのは新しい版だけなので、削除して構いません。"

  if ask_yes_no "前の版を削除しますか?"; then
    write_step "前の版を削除しています..."
    if docker image rm "$BEFORE_ID" >/dev/null 2>&1; then
      write_ok "削除しました。"
    else
      write_warn "削除できませんでした。Lin4Neuro が起動中かもしれません。"
      write_info "「3_Stop_Lin4Neuro.sh」で終了してから、次のコマンドで削除してください:"
      write_info "    docker image rm ${BEFORE_ID}"
    fi
  else
    write_info "前の版は次のコマンドで削除できます: docker image rm ${BEFORE_ID}"
  fi
fi

write_block "チュートリアル環境の準備ができました。
「2_Start_Lin4Neuro.sh」で Lin4Neuro を起動してください。
期間中にイメージが更新されることがあります。ときどきこのスクリプトを実行して確認してください。"
finish "ダウンロードが完了しました。" 0
