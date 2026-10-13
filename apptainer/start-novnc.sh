#!/bin/bash
# start-novnc.sh - Apptainer 用 noVNC 起動スクリプト
# Xvfb + D-Bus + x11vnc + XFCE + noVNC を直接起動する（supervisord 不使用）

set -u

export HOME=/home/brain
export USER=brain
export DISPLAY=:99
export XDG_RUNTIME_DIR=/tmp/runtime-brain
export XDG_CONFIG_HOME=/tmp/.config
export XDG_CACHE_HOME=/tmp/.cache
export XDG_DATA_HOME=/tmp/.local/share

# ランタイムディレクトリの作成
mkdir -p "$XDG_RUNTIME_DIR" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME"
chmod 700 "$XDG_RUNTIME_DIR"

# XFCE 設定を /tmp にコピー（読み取り専用 .sif 対策）
if [ -d /home/brain/.config/xfce4 ] && [ ! -d "$XDG_CONFIG_HOME/xfce4" ]; then
    cp -a /home/brain/.config/xfce4 "$XDG_CONFIG_HOME/"
fi

# VNC パスワードの準備
mkdir -p /tmp/.vnc
echo "lin4neuro" | vncpasswd -f > /tmp/.vnc/passwd 2>/dev/null
chmod 600 /tmp/.vnc/passwd

# X ロックファイルのクリーンアップ
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99 2>/dev/null
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix 2>/dev/null || true

# プロセスのクリーンアップ用トラップ
cleanup() {
    echo "Shutting down..."
    kill $(jobs -p) 2>/dev/null
    rm -f /tmp/.X99-lock /tmp/.X11-unix/X99
    exit 0
}
trap cleanup SIGTERM SIGINT

# Xvfb 起動
/usr/bin/Xvfb :99 -screen 0 1920x1080x24 -ac +extension GLX +render -noreset &
XVFB_PID=$!
sleep 2

# D-Bus セッションバス起動（XFCE の settings server に必要）
eval $(dbus-launch --sh-syntax)
export DBUS_SESSION_BUS_ADDRESS
DBUS_PID=${DBUS_SESSION_BUS_PID:-0}

# x11vnc 起動（ポートを 5900 に固定）
/usr/bin/x11vnc -display :99 -rfbport 5900 -xkb -forever -shared -rfbauth /tmp/.vnc/passwd -repeat &
X11VNC_PID=$!
sleep 1

# Apptainer のプロンプト上書きを防止（通常の bash プロンプトを使用）
unset APPTAINER_NAME SINGULARITY_NAME 2>/dev/null || true

# XFCE コンポーネントを個別起動（xfce4-session は Apptainer 環境で失敗するため不使用）
xfsettingsd &
xfwm4 &
sleep 1
xfdesktop &
xfce4-panel &
sleep 1
xfce4-terminal &
XFCE_PID=$!

# noVNC 起動（フォアグラウンド）
echo "============================================"
echo " noVNC を起動しました"
echo " ブラウザで接続: http://localhost:6080/vnc.html"
echo " パスワード: lin4neuro"
echo "============================================"

/usr/bin/websockify --web /usr/share/novnc 0.0.0.0:6080 localhost:5900 &
NOVNC_PID=$!

# noVNC プロセスを待機（Ctrl+C でクリーンアップ）
wait $NOVNC_PID
