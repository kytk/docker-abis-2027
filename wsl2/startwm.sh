#!/bin/sh
# startwm.sh - XFCE desktop for WSL2 + xrdp
#
# Notes:
# - xfce4-session causes SIGSEGV in WSL2 + xorgxrdp, so we start
#   XFCE components individually
# - dbus-run-session also causes SIGSEGV, so we use dbus-launch
# - GDK_BACKEND=x11 prevents WSLg Wayland from interfering
# - xfwm4 --compositor=off is required (compositor not supported by xorgxrdp)

export HOME=/home/brain
export LANG=ja_JP.UTF-8
export LANGUAGE=ja_JP:ja
export GDK_BACKEND=x11
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
unset WAYLAND_DISPLAY
unset DBUS_SESSION_BUS_ADDRESS
unset SESSION_MANAGER

eval $(dbus-launch --sh-syntax)
export DBUS_SESSION_BUS_ADDRESS

xfsettingsd &
fcitx &
xfwm4 --compositor=off &
sleep 3
xfdesktop &
sleep 3

# xrdp 環境ではモニター名が異なるため、壁紙を明示的に設定
for prop in $(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep last-image); do
    xfconf-query -c xfce4-desktop -p "$prop" -s /usr/share/backgrounds/deep_ocean.png
done

# アプリケーションメニューのアイコンを脳アイコンに変更し、タイトルを非表示
xfconf-query -c xfce4-panel -p /plugins/plugin-1/button-icon -n -t string -s brain64x48
xfconf-query -c xfce4-panel -p /plugins/plugin-1/show-button-title -n -t bool -s false

# パネルアイコンのサイズを自動調整に設定
xfconf-query -c xfce4-panel -p /panels/panel-1/icon-size -n -t int -s 0

xfce4-panel &
sleep 2
xfce4-terminal &

wait
