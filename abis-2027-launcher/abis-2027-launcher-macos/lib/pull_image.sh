#!/bin/bash
# pull_image.sh - Download the tutorial image, or update an existing copy.
# Run before the course, and again whenever a new build is announced.

# shellcheck source=common.sh
. "$(dirname "$0")/common.sh"

write_title "ABiS Lin4Neuro - イメージのダウンロード・更新"

# ---------------------------------------------------------------------------
# [1] Docker engine
# ---------------------------------------------------------------------------
write_step "Docker を確認しています..."
if ! confirm_docker_ready; then
  exit_with_pause "Docker の準備ができていません。上のメッセージをご確認ください。" 1
fi

# ---------------------------------------------------------------------------
# [2] Confirm - a first download is long and large, an update usually is not
# ---------------------------------------------------------------------------
# The tag stays 26.12 for the whole season, but the image behind it is rebuilt
# when something has to be fixed. So an existing local copy is not necessarily
# current: always ask Docker Hub, and let it transfer only the layers that
# actually changed. The ID taken here is compared with the one after the pull.
BEFORE_ID="$(get_image_id)"

if [ -n "$BEFORE_ID" ]; then
  ANSWER="$(show_dialog "チュートリアル用のイメージはすでにこの Mac にあります:

  ${IMAGE_NAME}

更新されていないかを確認します。最新版であれば、すぐに終わります。
更新されていた場合は、変わった部分だけをダウンロードします
(内容によっては時間がかかることがあります)。

確認しますか?" yesno note)"
else
  ANSWER="$(show_dialog "これからチュートリアル環境をダウンロードします。

  イメージ       : ${IMAGE_NAME}
  ダウンロード量 : ${IMAGE_SIZE_TEXT}
  所要時間       : 高速な回線で ${IMAGE_TIME_TEXT}
  ディスク使用量 : 展開後 約 ${IMAGE_DISK_GB} GB

有線または安定した Wi-Fi でつなぎ、電源アダプタを接続したまま、
スリープしないようにしてください。途中で中断しても、このスクリプトを
もう一度実行すれば続きから再開できます。

ダウンロードを始めますか?" yesno note)"
fi

if [ "$ANSWER" != "Yes" ]; then
  exit_with_pause "キャンセルしました。" 0
fi

# ---------------------------------------------------------------------------
# [3] Pull
# ---------------------------------------------------------------------------
if [ -n "$BEFORE_ID" ]; then
  write_step "${IMAGE_NAME} の更新を確認しています..."
else
  write_step "${IMAGE_NAME} をダウンロードしています..."
fi
write_info "進行状況は下に表示されます。このウィンドウは裏に回しても構いません。"
printf '\n'

STARTED="$(date +%s)"

# caffeinate keeps the Mac awake for the duration of the download; without it
# a long pull can be interrupted by sleep.
if ! caffeinate -i docker pull --platform "$PLATFORM" "$IMAGE_NAME"; then
  printf '\n'

  # With a usable copy already on the Mac, a failed update check is not a
  # fatal error - most often it just means there is no network right now.
  # Saying so, and letting the participant start the tutorial, matters more
  # than the update.
  if [ -n "$BEFORE_ID" ]; then
    show_dialog "更新を確認できませんでした。

ネットワークにつながっていないか、Docker Hub につながらないようです。
すでにあるイメージはそのまま使えます。「2_Start_Lin4Neuro」で
起動してください。" ok caution >/dev/null
    exit_with_pause "更新は確認できませんでしたが、イメージはこの Mac にあります。" 0
  fi

  show_dialog "ダウンロードが完了しませんでした。

よくある原因:
  - ネットワークが切断された
  - Docker の仮想ディスクの空き容量が足りない
    (Docker Desktop -> Settings -> Resources -> Virtual disk limit)

このスクリプトをもう一度実行すれば、中断したところから再開します。" ok stop >/dev/null
  exit_with_pause "docker pull に失敗しました。" 1
fi

# ---------------------------------------------------------------------------
# [4] Verify
# ---------------------------------------------------------------------------
printf '\n'
write_step "イメージを確認しています..."
AFTER_ID="$(get_image_id)"
if [ -z "$AFTER_ID" ]; then
  exit_with_pause "ダウンロード後もイメージが見つかりません。講師にご連絡ください。" 1
fi

ELAPSED=$(( $(date +%s) - STARTED ))
IMG_SIZE="$(docker image inspect "$IMAGE_NAME" --format '{{.Size}}' 2>/dev/null)"

# Nothing changed: the local copy was already the build on Docker Hub.
if [ "$BEFORE_ID" = "$AFTER_ID" ]; then
  write_ok "イメージは最新版です。ダウンロードするものはありませんでした。"
  show_dialog "チュートリアル用のイメージは最新版でした。

「2_Start_Lin4Neuro」で起動してください。" ok note >/dev/null
  exit_with_pause "" 0
fi

write_ok "イメージの準備ができました。"
if [ -n "$IMG_SIZE" ]; then
  write_info "ディスク使用量 : $((IMG_SIZE / 1024 / 1024 / 1024)) GB"
fi
write_info "所要時間       : $((ELAPSED / 60)) 分 $((ELAPSED % 60)) 秒"

# ---------------------------------------------------------------------------
# [5] Clean up the build that was replaced
# ---------------------------------------------------------------------------
# An updated image leaves the previous build behind, untagged and still taking
# its full size on disk. Nothing uses it any more, and ~38 GB is more than most
# participants can spare, so offer to remove it here. "docker image rm" without
# -f refuses while a container is still using it, which is the behaviour we
# want.
if [ -n "$BEFORE_ID" ]; then
  ANSWER="$(show_dialog "イメージを新しい版に更新しました。

前の版がディスクに残っています (約 ${IMAGE_DISK_GB} GB)。
これから使うのは新しい版だけなので、削除して構いません。

前の版を削除しますか?" yesno note)"

  if [ "$ANSWER" = "Yes" ]; then
    write_step "前の版を削除しています..."
    if docker image rm "$BEFORE_ID" >/dev/null 2>&1; then
      write_ok "削除しました。"
    else
      write_warn "削除できませんでした。Lin4Neuro が起動中かもしれません。"
      write_info "「3_Stop_Lin4Neuro」で終了してから、Docker Desktop の Images 画面で"
      write_info "<none> と表示されているイメージを削除してください。"
    fi
  else
    write_info "前の版は Docker Desktop の Images 画面 (<none> の行) から削除できます。"
  fi
fi

show_dialog "チュートリアル環境の準備ができました。

「2_Start_Lin4Neuro」で Lin4Neuro を起動してください。
チュートリアルの期間中にイメージが更新されることがあります。
ときどきこの「1_Download_Image」を実行して、確認してください。" ok note >/dev/null

exit_with_pause "ダウンロードが完了しました。" 0
