#!/bin/bash

# systemd が動作しているか確認
if [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
    sudo systemctl start xrdp
else
    # systemd が使えない場合のフォールバック
    sudo /etc/init.d/xrdp start
fi

echo "============================================"
echo " xrdp が起動しました"
echo " Windows のリモートデスクトップで接続:"
echo "   アドレス: localhost:3390"
echo "   ユーザー名: brain"
echo "   パスワード: lin4neuro"
echo "============================================"
