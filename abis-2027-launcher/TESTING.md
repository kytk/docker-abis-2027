# ランチャーのテストチェックリスト

実施済みの自動チェックには `[auto]` を付けている。これらは Linux 上で macOS 専用の
コマンドをスタブに置き換えて実行したもので、確認できているのはロジックと構文であり、
実際のダイアログではない。それ以外はすべて実機での確認が必要。

## 確認済み [auto]

- 6 つの `.ps1` ファイルがすべてパースできる（PowerShell 7 のパーサー）。
- バージョンの埋め込み（`release_common.sh`、Linux 上）: `VERSION.txt` は ASCII
  （Windows 版は CRLF）、`README.txt` は UTF-8（Windows 版は BOM + CRLF）で
  プレースホルダーが埋まっている。macOS 版・Windows 版のランチャーとも、タイトルに
  バージョンが表示され、`VERSION.txt` がない場合は `dev` と表示される。
- Node.js 上での `docker_settings.js`: get、set、undo（元と同じ JSON に戻る）、
  他のキーやネストしたキーが保持されること、不正な値は拒否されファイルが変更されない
  こと。`osascript` / `docker` / `pgrep` / `sysctl` / `open` をスタブにした
  `configure_docker.sh`（JSON は実際に編集）: 変更、元に戻す、キャンセル、
  設定ファイルなし、Rosetta 有効、Virtualization framework オフ（Rosetta には
  触れない）、Lin4Neuro 起動中（拒否）、Docker 未起動（再起動しない）。
  `0_Check_Environment` が設定の行を出力すること。
- スタブにした `gh` / `curl` に対する `publish_release.sh`: 新規リリース、
  リリースが既に存在する（拒否）、`--replace`、プロンプトでのキャンセル、
  アーカイブ間でバージョンが異なる（拒否）。
- `.wslconfig` の編集（`common.ps1` の `Set-WslConfig` / `Restore-WslConfig` /
  `Read-WslConfig` を Linux 上の PowerShell 7 で実行）: 新規作成とその取り消し
  （ファイルが削除される）。`[boot]`、`[experimental]`、コメントアウトされたキー、
  空白入りの `memory = 4GB`、重複した `memory=` 行を含む既存ファイル - 他の行は
  保持され、重複はまとめられ、2 回目の実行では何も変わらず、元に戻すとバイト単位で
  復元される。`[wsl2]` のない UTF-16 のファイルは読み込まれ、BOM なし UTF-8 で
  書き直される。
- macOS のスクリプトはすべて、macOS 標準の **bash 3.2** でパースできる。
- すべての `.sh` で `shellcheck` の指摘なし。
- `.bat` は Shift-JIS + CRLF、`.ps1` は BOM 付き UTF-8、`.command` と `.sh` は
  BOM なし UTF-8 で実行ビットが立っている。
- macOS のスクリプトを実行したとき日本語メッセージが正しく表示される
  （Linux 上で UTF-8 で確認。Windows のコードページについては後述）。
- 実イメージでの起動フロー: コンテナが起動し、HEALTHCHECK をポーリングし、
  公開ポートで noVNC が応答し、共有フォルダが双方から読み書きできる
  （`uid 1000` が `brain` と一致）。
- 再接続: コンテナが既に動いている場合は何も作り直さず、ブラウザを開き直す。
- 停止フロー: コンテナを停止・削除し、その後 Docker を終了するか尋ねる。
- 何も動いていないときの停止: その旨を表示して正常終了する。
- 環境チェック: レポートは色コードなしのプレーン ASCII で書かれる。Docker VM の
  CPU / メモリ / ディスクとイメージの有無を検出する。
- パスのチェック: 非 ASCII（例: `E:\脳画像\share`）とクラウドフォルダ
  （`OneDrive`、`Dropbox` など）を検出する。単に "box" を含むだけのフォルダ名
  （`Inbox`、`Sandbox`、`VirtualBox`）は検出しない。

## 実機で確認済み（2026-09-23）

- **Windows**: `0_Check_Environment`（エンコーディング修正後の `[WSL2]` セクション、
  エンジン停止時に Docker Desktop を起動する動作を含む）と起動 / 停止フローが
  意図どおり動く。日本語も正しく表示される。
- **macOS（Intel）**: 同上（`.command` ランチャー経由）。
- NTFS の外付けドライブ上の共有フォルダ: コンテナ**内で** `git clone`、`git pull`、
  `git status` がすべて動くので、2025 年の回避策（git 用に別途 WSL を入れる）は
  不要になった。

以下はまだ確認が必要な項目。配布用 zip、Apple Silicon、あるいは意図的に壊した
条件が必要なもの。

## Windows - 実機が必要

- [ ] 外付け SSD について `Get-Volume` が **NTFS** と報告し、exFAT のドライブは
      再フォーマットを促すメッセージで拒否される。
- [ ] `FolderBrowserDialog` が STA エラーなしで開く（PowerShell 5.1）。
- [ ] 空白を含むパス（例: `E:\MRI Data\share`）が正しくマウントされる。
- [ ] Edge が `--app` モード（タブバーなし）で開く。
- [ ] `3_Stop_Lin4Neuro` から Docker Desktop を終了すると WSL2 VM が実際に止まる
      （`wsl -l -v` で `docker-desktop` が Stopped と表示される）。現在はまず
      `docker desktop stop`（Docker Desktop 4.37 以降）を試すので、インストール
      されているバージョンにこのコマンドがあることを確認する。
- [ ] RAM 8 GB または 12 GB、`.wslconfig` なしの PC での `4_Configure_WSL`:
      memory 4 -> 4 / 6 -> 6 GB、swap 2 -> 8 / 3 -> 8 GB を提案し、ファイルを
      書き込み、WSL と Docker Desktop を再起動し、その後 `docker info` が約 4 / 6 GB
      と報告する。`0_Check_Environment` は RAM についてだけ警告し、Docker の
      メモリについては警告しない。もう一度実行すると元に戻す選択肢だけが出て、
      元に戻すとファイルが削除される。
- [ ] 他の設定（例: `[boot] systemd=true`、`networkingMode=mirrored`）を含む既存の
      `.wslconfig` で同じことをする: それらの設定は残り、元に戻すと
      `.wslconfig.abis-backup` からバイト単位で復元される。
- [ ] デフォルト設定の 16 GB の PC: memory は 8 GB のまま、swap 4 -> 8 GB。
      32 GB: 16 -> 24 GB。64 GB: memory は 32 GB のまま、swap 16 GB も維持され、
      変更は提案されない。
- [ ] Lin4Neuro 起動中は `4_Configure_WSL` が拒否し、`3_Stop_Lin4Neuro` を案内する。
      Ubuntu の WSL ディストリビューションを開いている場合は再起動の警告が出て、
      そのディストリビューションが停止される。
- [ ] Docker Desktop が起動していなかったときの `4_Configure_WSL`: WSL はシャット
      ダウンされ、Docker Desktop は起動**されない**。
- [ ] Hyper-V バックエンド（Windows Pro、"Use WSL 2 based engine" オフ）:
      スクリプトは Settings -> Resources -> Advanced を案内し、何も変更しない。
- [ ] Windows PowerShell 5.1 での `0_Check_Environment` の `[WSL2]` セクション:
      ディストリビューション名が正しく比較される（Docker 起動中は
      `docker-desktop (running)`）。以前は 5.1 で `wsl -l -q` の出力先頭の BOM が
      残っていた。ディストリビューションが 1 つもない場合は、文字化けした
      メッセージではなく `none installed` と表示される。
- [ ] `INSTALL_windows.md` の PowerShell ワンライナーをクリーンな PC の Windows
      PowerShell 5.1 に貼り付けると、`%USERPROFILE%\abis-2027-launcher-windows` が
      作成されてエクスプローラーで開く。5 つの `.bat` がダブルクリックで
      **SmartScreen や「ファイルを開く - セキュリティの警告」が出ずに**実行できる。
      Windows 10 と Windows 11 で確認し、手元にあれば Smart App Control を有効に
      した Windows 11 でも確認する。
- [ ] インストールされたファイルに対して
      `Get-Item ...\0_Check_Environment.bat -Stream *` を実行すると `:$DATA` だけが
      表示され、`Zone.Identifier` がない。
- [ ] ワンライナーをもう一度実行するとランチャーが上書きされ、
      `abis_check_result.txt` は残る。
- [ ] URL が誤っている場合、ワンライナーは curl のエラーを表示し、エクスプローラーを
      開か**ない**。
- [ ] ユーザー名に日本語や空白を含む場合でも、ワンライナーと `.bat` が動く。
- [ ] 代替手順: ブラウザでダウンロードした zip も「ブロックの解除」をすれば動く。
- [ ] `abis-2027-launcher-windows.zip` をエクスプローラーの「すべて展開」で展開すると、
      5 つの `.bat` と `lib` を含む `abis-2027-launcher-windows` フォルダが 1 つだけ
      でき、その中に同名のフォルダが二重に**できない**。
- [ ] `.bat` のウィンドウタイトルに日本語が正しく表示される（Shift-JIS + CP932）。
- [ ] コンソールのコードページが 932 でない環境（例: 英語版 Windows）で確認する -
      `.bat` の文字が化ける場合、影響するのは代替メッセージだけだが、wiki に
      記載しておく。

## リリース用スクリプト - Mac と実リポジトリが必要

- [ ] `./make_release.sh` で両方のアーカイブが作られ、それぞれの `VERSION.txt` に
      同じバージョンが入っている。公開後、同じ日に 2 回目を実行すると `.2` が付く。
- [ ] ランチャーのフォルダに未コミットの変更があると、ビルド前に確認を求める。
- [ ] `./publish_release.sh` で `kytk/abis-web-2027` に `launcher-<version>` が作られ、
      `releases/latest/download/...` の 2 つの URL が新しいファイルを返す
      （スクリプトが sha256 を確認する）。

## macOS - 実機が必要

- [ ] `INSTALL_macos.md` のワンライナーをクリーンな Mac のターミナルに貼り付けると、
      `~/abis-2027-launcher-macos` が作成されて Finder で開く。5 つの `.command` が
      ダブルクリックで **Gatekeeper の確認なしに**実行できる（macOS 15 Sequoia 以降）。
- [ ] ワンライナーをもう一度実行するとランチャーが上書きされ、
      `abis_check_result.txt` は残る。
- [ ] 代替手順: Safari でダウンロードし Finder で展開した tar.gz はブロックされ、
      `INSTALL_macos.md` にある `xattr -dr com.apple.quarantine` の行を実行すると
      動く。
- [ ] `/Volumes/...` 以下の外付けドライブ上のフォルダが中身ごとマウントされる
      （Docker Desktop のファイル共有）。
- [ ] Apple Silicon: イメージがエミュレーションで動く。
      "Use Rosetta for x86_64/amd64 emulation" の有無で速度を記録する。
- [ ] ダウンロード中ずっと `caffeinate` で Mac がスリープしない。
- [ ] Chrome または Edge が `--app` モードで開く。どちらも入っていない場合は
      Safari で普通に URL が開く。
- [x] `osascript -l JavaScript lib/docker_settings.js get "<settings-store.json>"`
      で値が表示される（2026-10-13、実機の Mac: MemoryMiB=8192、SwapMiB=1024、
      UseVirtualizationFrameworkRosetta=true で、ファイルの内容と一致）。
      実機での書き込み（`set`）は `4_Configure_Docker` 経由でまだ確認が必要。
- [ ] Rosetta オフ・メモリがデフォルトの Apple Silicon Mac での
      `4_Configure_Docker`: memory / swap / Rosetta の変更を提案し、Docker Desktop
      を終了して書き込み、再起動する。Settings -> Resources と General に新しい値が
      表示され、`docker info` がそのメモリを報告し、`0_Check_Environment` が警告
      しなくなる。もう一度実行すると元に戻す選択肢だけが出て、実行後は GUI に
      元の値が表示される。
- [ ] `SwapMiB=4096` が受け付けられる（スライダーの最大値と想定）。8 GB の Mac で
      `MemoryMiB=8192` が受け付けられる。
- [ ] Intel Mac: Rosetta の行は出ず、memory / swap のみ。
- [ ] Lin4Neuro 起動中は `4_Configure_Docker` が拒否する。
- [ ] 変更後に起動した Docker Desktop が編集したキーをリセットしない
      （つまり、起動時に本当に `settings-store.json` を読んでいる）。
- [ ] `3_Stop_Lin4Neuro` で「Docker Desktop を終了: はい」を選ぶと Docker Desktop が
      終了し（`docker desktop stop`、だめなら
      `osascript -e 'quit app id "com.docker.docker"'` にフォールバック）、
      「まだ動いています」ではなく「終了しました」と表示される。

## 両プラットフォーム共通

- [ ] `2_Start_Lin4Neuro` を続けて 2 回実行する: 2 回目は 2 つ目のコンテナを作らず
      再接続する。
- [ ] 外部からコンテナを削除（`docker rm -f abis`）してから再び起動する:
      残骸が片付けられる。
- [ ] ポート 6080 を別のプログラムで使用中にして起動する: エラーダイアログに
      そのポートが示される。
- [ ] 外付けドライブを選んだ後に取り外す: 空の共有フォルダができるのではなく、
      失敗がはっきり報告される。
- [ ] デスクトップ内でのチュートリアル全体のスモークテスト: FSLeyes、Freeview、
      AlizaMS、SPM25、CONN、短い `recon-all -autorecon1`。
- [ ] イメージが既にあり Docker Hub 側も変わっていない状態で `1_Download_Image`:
      pull が実行され、結果は「イメージは最新版です」となり、削除の提案は出ない。
- [ ] 同じタグで再ビルドしたイメージを push してから `1_Download_Image` を実行する:
      変更されたレイヤーだけがダウンロードされ、前のビルドを削除するか尋ねられる。
      1 回目は断り（`<none>` のイメージが残る）、次に承諾する（`docker images` に
      表示されなくなる）。
- [ ] 同じことを `2_Start_Lin4Neuro` 起動中に行う: 前のビルドの削除は失敗し、
      先に Lin4Neuro を停止するようメッセージが出る。
- [ ] ネットワークなし・イメージありの状態で `1_Download_Image`: メッセージは
      「更新は確認できませんでしたが、イメージは〜にあります」、終了コードは 0 で、`2_Start_Lin4Neuro` は
      引き続き動く。
- [ ] Docker Desktop をちょうど 8 GB に設定する: `0_Check_Environment` は
      「7.9 GB」（または VM が報告する値）と表示し、メモリについて警告**しない**。
      7 GB ではまだ警告する。
