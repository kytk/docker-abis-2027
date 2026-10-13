# WSL2 / xrdp 版の開発メモ

Windows 向けの WSL2 + xrdp 配布は **experimental**。2027 年の本番は Windows も
Docker Desktop + noVNC を使う（起動時のフリーズが理由。`../LOG.md` 参照）。

受講者向けの手順は `install-for-users.md`、ビルドは `build-wsl2.sh`
（リポジトリのルートをコンテキストにするため、スクリプト自身がルートへ移動する）。

## 技術的制約

- `xfce4-session` / `dbus-run-session` は WSL2 + xorgxrdp で SIGSEGV する
  → `startwm.sh` で XFCE コンポーネントを個別に起動する
- `xfwm4 --compositor=off`（xorgxrdp はコンポジター非対応）
- `GDK_BACKEND=x11` + `unset WAYLAND_DISPLAY`（WSLg Wayland の干渉を防ぐ）
- 日本語入力は fcitx4 + Mozc（fcitx5 は不安定）

## setup.bat

- エンコーディング: Shift-JIS + CRLF
- ファイルシステムチェックは PowerShell の `Get-Volume`（`wmic` は非推奨のため廃止）
- 編集するときは UTF-8 に変換して作業し、`nkf -s -Lw` で戻す
