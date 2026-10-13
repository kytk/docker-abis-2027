# ABiS Lin4Neuro 起動ラッパー設計ディスカッション記録

Docker + noVNC で提供している Lin4Neuro コンテナ（ABiS チュートリアル用）について、初心者向けのラッパーを検討した記録です。

---

## 1. 出発点

- Docker で Linux GUI（XFCE + noVNC）が立ち上がるコンテナを作成済み
- 講師本人は問題なく使えるが、初心者には Docker Desktop の操作が負担
- Python などでラッパー GUI を作る案を検討
- MRI 解析のため共有フォルダは必須

### 前提条件（ヒアリング結果）

| 項目 | 内容 |
|---|---|
| GUI 表示方式 | noVNC（ブラウザ） |
| 対象 OS | Windows / macOS / Linux |
| 配布範囲 | 講習会・研究室の受講者限定 |
| 開催形態 | 完全オンライン。事前準備を完了した人のみ当日リンクが表示される |

---

## 2. 議論の要点

### 2.1 ラッパーで消せるもの・消せないもの

- **消せない**: Docker Desktop のインストール、WSL2 有効化、初回 image pull（約30GB）
- **消せる**: 長い `docker run`、パス指定、ポート、ブラウザ起動、停止・後片付け、状態確認

→ ラッパーは「インストーラ」ではなく「ランチャー＋診断ツール」と位置づける。

### 2.2 Python GUI にしない理由

- Python で作ると「Python を入れる」という新しいハードルが生まれる
- PyInstaller で固めても、Windows SmartScreen / macOS Gatekeeper・公証の問題が残る
- noVNC なので画面表示はブラウザ任せ。ラッパーの仕事は薄い
- **結論**: スクリプト（Windows: `.bat` + `.ps1` / macOS: `.command`）で十分。GUI にこだわる理由はなく、目的は「受講者が簡単にできること」

### 2.3 オンライン開催で効くもの

- 対面と違い画面を覗けないため、**診断情報の出力**が有効
- 事前スクリプトの関門を「環境が要件を満たすか」の確認に格上げできる

---

## 3. 既存 Wiki（2026年版）のレビューで見つかった問題

| # | 問題 | 詳細 |
|---|---|---|
| 1 | マウント先が OS で不一致 | Windows `/root/share`、macOS `/home/brain/share` |
| 2 | macOS で `shm-size` が効いていない | Docker Desktop の Environment variables 欄に `shm-size` / `platform` を入れていたが、これらは環境変数ではなく `docker run` のフラグ。GUI には該当項目がない |
| 3 | ポートが全インターフェースに公開 | `-p 6080:6080` + 公開パスワードで、同一 LAN から接続可能 |
| 4 | 3ヶ月同一コンテナを使う設計の脆さ | bind mount はコンテナ生成時に焼き付く。Windows の外付け SSD のドライブレターが変わると壊れる |
| 5 | `.DS_Store` 対策 | `DSDontWriteNetworkStores` はネットワークボリューム専用のキー（macOS は exFAT で問題なしを確認済み） |
| 6 | `latest` タグ | シーズン途中の更新で受講者間の環境が割れうる |

### 3.1 マウント先問題の原因と解決

- Windows で **exFAT** の外付けドライブを使うと、`brain` ユーザーで共有できず `/root/share` にする必要があった
- exFAT は POSIX の所有者・パーミッションを保存できないため、と考えられる
- **Windows では NTFS にすれば `/home/brain/share` で動作することを確認済み**
- macOS は exFAT でも問題なし
- **NTFS 化により `--privileged` も不要になることを確認済み**
  - `--privileged` は「外付けディスクアクセスのため」ではなく、exFAT のパーミッション問題への対症療法だった

---

## 4. 決定事項

| 項目 | 変更前 | 変更後 |
|---|---|---|
| マウント先 | Win `/root/share` / mac `/home/brain/share` | `/home/brain/share` に統一 |
| フォーマット | 指定なし | Windows は NTFS 必須、macOS は exFAT 可 |
| `--privileged` | Windows のみ付与 | 不要 |
| ポート | `6080:6080` | `127.0.0.1:6080:6080` |
| `shm-size` | macOS では未適用 | CLI 統一で全 OS に適用 |
| タグ | `latest` | 配布前に固定し、以降変更しない（`kytk/abis-2027` 系） |
| コンテナ運用 | 3ヶ月同じコンテナを start/stop | `--rm` で毎回使い捨て |
| 共有フォルダ選択 | 手入力 | 起動のたびにダイアログで選択 |
| noVNC 接続 | 歯車→Scaling 設定→Connect→パスワード | クエリパラメータで自動接続 |

### 4.1 `--rm` を採用できた理由

- 各回の事前準備でコンテナ内へのインストールはしていない
- `git clone` も外付け（share）側で行っている
- → コンテナ内に固有の状態がほぼなく、使い捨てにできる
- 副次効果: ドライブレター変更・マウント先変更・「SSD を接続してから再開」の注意がすべて不要になる

> 注意: `docker start` 方式のままなら「毎回ダイアログ」は選択が無視されるため不適切。`--rm` にしたことで毎回選択が正しい設計になった。

### 4.2 noVNC の自動接続 URL（動作確認済み）

```
http://127.0.0.1:6080/vnc.html?resize=scale&autoconnect=1&password=lin4neuro
```

`localhost` ではなく `127.0.0.1` を使う（IPv6 の `::1` に解決されると、127.0.0.1 バインドのポートに繋がらない場合があるため）。

### 4.3 全 OS 共通の起動コマンド

```bash
docker run -d --rm --name abis --shm-size 2g \
  -v "<ホスト側のshareパス>:/home/brain/share" \
  -p 127.0.0.1:6080:6080 \
  kytk/abis-2027:<固定タグ>
```

OS 間で異なるのはホスト側パスの表記のみ。

---

## 5. スクリプト構成

### 5.1 3つの操作

| ファイル | 頻度 | 内容 |
|---|---|---|
| `1_Download_Image` | 1回のみ | Docker Desktop 起動 → 確認ダイアログ（約30GB / 40-50分）→ `docker pull`（ターミナルに進捗表示） |
| `2_Start_Lin4Neuro` | 毎回 | Docker 確認 → image 確認 → フォルダ選択 → `docker run --rm` → 起動待ち → ブラウザ |
| `3_Stop_Lin4Neuro` | 毎回 | `docker stop abis`（`--rm` により自動削除） |

- 起動と停止は別ファイルにする（「もう一度押したら止まった」事故を防ぐ）
- 日本語はエンコーディングでバグりやすいので、ファイル名・メッセージはすべて英語

### 5.2 ファイル配置（Windows）

```
ABiS_Lin4Neuro/
├── 1_Download_Image.bat
├── 2_Start_Lin4Neuro.bat
├── 3_Stop_Lin4Neuro.bat
└── lib/
    ├── common.ps1
    ├── pull_image.ps1
    ├── start_lin4neuro.ps1
    └── stop_lin4neuro.ps1
```

- `.ps1` はダブルクリックで実行されない（既定はメモ帳）ため、`.bat` から `powershell -ExecutionPolicy Bypass -File` で呼ぶ
- `-ExecutionPolicy Bypass` はそのプロセス限りで、システム設定は変更しない
- ZIP 配布時は Mark of the Web 対策として「展開前にプロパティ→許可する」を Wiki に記載
- macOS は `.command` 拡張子 + `chmod +x`。初回は右クリック→開くで Gatekeeper を回避

### 5.3 起動フロー

```
[1] docker が動いているか
      ↓ NG → Docker Desktop を起動し、docker info が通るまでポーリング（最大180秒）
[2] 期待タグの image があるか
      ↓ NG → 「1_Download_Image を先に実行してください」で終了
[3] 同名コンテナの状態は？
      ├ 起動中     → [6] へ（二度押し対策：何もせず開くだけ）
      └ 停止/残骸   → docker rm して [4] へ
[4] share フォルダを選択（ダイアログ）＋検証
      ・NTFS か（Windows のみ）
      ・非 ASCII 文字を含まないか
      ・クラウド同期フォルダ配下でないか
      ・書き込めるか
      ↓ キャンセル → 終了 / 検証 NG → 選び直し
[5] docker run --rm
[6] /vnc.html が 200 を返すまでポーリング（最大120秒）＋ 5秒待機
      ↓ タイムアウト → docker logs --tail 50 を表示
[7] ブラウザを開く（Edge/Chrome の --app モード、なければ既定ブラウザ）
```

`--app` モードはタブバーのない独立ウィンドウになり、Ctrl+W でセッション画面を誤って閉じる事故を防ぐ。

### 5.4 状態表

| 状態 | 起動スクリプトの動作 |
|---|---|
| Docker 未起動 | Docker Desktop を起動して待機 |
| image なし | 案内して終了 |
| コンテナ起動中 | ブラウザを開くのみ |
| コンテナ停止・残骸 | 削除して新規作成 |
| コンテナなし | フォルダ選択 → 新規作成 |

### 5.5 OS 差分

| | Windows (.ps1) | macOS (.command) |
|---|---|---|
| フォルダ選択 | FolderBrowserDialog | `osascript -e 'choose folder'` |
| ブラウザ起動 | `Start-Process` | `open` |
| メッセージ表示 | MessageBox | `osascript -e 'display dialog'` |
| 待機処理 | `Invoke-WebRequest` | `curl -s -o /dev/null -w %{http_code}` |

---

## 6. 進捗と残作業

### 作成済み（Windows）

- `lib/common.ps1` — 設定と共通関数
- `lib/start_lin4neuro.ps1` — 起動スクリプト本体
- `2_Start_Lin4Neuro.bat` — ダブルクリック用ラッパー

### Windows 実機で確認が必要な点

1. `Get-Volume` が外付け SSD で正しく NTFS を返すか
2. `FolderBrowserDialog` が STA エラーなく開くか
3. `-v "E:/share:/home/brain/share"`（フォワードスラッシュ形式）を Docker が受け付けるか

### 未着手

- `1_Download_Image`（Windows / macOS）
- `3_Stop_Lin4Neuro`（Windows / macOS）
- macOS 版 `.command` 一式
- 診断レポート出力スクリプト（余裕があれば）
- Wiki（2027年版）改訂
- `common.ps1` の `$ImageTag` を実際の固定タグに差し替え

### スケジュール

- 2026年12月: 準備期間
- 2027年1月・2月: 本番

---

## 付録: 作成したスクリプト

### `2_Start_Lin4Neuro.bat`

```bat
@echo off
REM 2_Start_Lin4Neuro.bat - Double-click launcher for the ABiS Lin4Neuro container.
REM Runs lib\start_lin4neuro.ps1; -ExecutionPolicy Bypass applies to this process only.

title ABiS Lin4Neuro - Start

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0lib\start_lin4neuro.ps1"

REM Only pause if PowerShell itself could not be launched; the script pauses on its own.
if errorlevel 9009 (
    echo.
    echo PowerShell could not be started.
    pause
)
```

### `lib/common.ps1`

```powershell
# common.ps1 - Shared settings and helper functions for the ABiS Lin4Neuro launcher.
# Dot-sourced by the other scripts in this folder; not meant to be run on its own.

# =============================================================================
# CONFIGURATION - review this section before distributing to participants
# =============================================================================

# Container image. Use a FIXED tag (not "latest") so that every participant
# runs byte-for-byte the same environment for the whole season.
$Script:ImageRepo = 'kytk/abis-2027'
$Script:ImageTag  = '2026.12'
$Script:ImageName = '{0}:{1}' -f $Script:ImageRepo, $Script:ImageTag

# Approximate download size, shown in the confirmation dialog.
$Script:ImageSizeText = 'about 30 GB'
$Script:ImageTimeText = '40-50 minutes'

# Container settings
$Script:ContainerName  = 'abis'
$Script:ContainerShare = '/home/brain/share'   # mount point inside the container
$Script:HostPort       = 6080
$Script:ShmSize        = '2g'                  # default 64MB is too small for FSL/FreeSurfer

# noVNC. Query parameters skip the settings gear, the Connect button and the
# password prompt, so the desktop appears immediately.
$Script:VncPassword  = 'lin4neuro'
$Script:VncUrl       = 'http://127.0.0.1:{0}/vnc.html?resize=scale&autoconnect=1&password={1}' -f $Script:HostPort, $Script:VncPassword
$Script:VncProbeUrl  = 'http://127.0.0.1:{0}/vnc.html' -f $Script:HostPort

# Timeouts (seconds)
$Script:DockerStartTimeout = 180   # Docker Desktop can be slow on first launch
$Script:VncReadyTimeout    = 120   # Xvfb + x11vnc + xfce4-session startup
$Script:PostReadyWait      = 5     # grace period after the port answers

# Open noVNC in a borderless app window instead of a normal browser tab.
# A normal tab can be closed by accident with Ctrl+W, which kills the session
# view mid-analysis. Set to $false to use the default browser instead.
$Script:OpenInAppMode = $true

# =============================================================================
# Console output helpers
# =============================================================================

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Message) Write-Host "    $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "    $Message" -ForegroundColor Yellow }
function Write-Fail { param([string]$Message) Write-Host "    $Message" -ForegroundColor Red }

# Print a message and wait for a key press, so the console window does not
# vanish before the participant can read what went wrong.
function Exit-WithPause {
    param(
        [string]$Message = '',
        [int]$Code = 0
    )
    if ($Message) {
        if ($Code -eq 0) { Write-Ok $Message } else { Write-Fail $Message }
    }
    Write-Host ''
    Write-Host 'Press any key to close this window...' -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit $Code
}

# =============================================================================
# GUI dialog helpers (Windows Forms)
# =============================================================================

Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type -AssemblyName System.Drawing        | Out-Null

# Show a message box. Returns 'Yes', 'No' or 'OK'.
function Show-Dialog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Title = 'ABiS Lin4Neuro',
        [ValidateSet('OK', 'YesNo')][string]$Buttons = 'OK',
        [ValidateSet('Info', 'Warning', 'Error', 'Question')][string]$Icon = 'Info'
    )

    $btn = switch ($Buttons) {
        'YesNo' { [System.Windows.Forms.MessageBoxButtons]::YesNo }
        default { [System.Windows.Forms.MessageBoxButtons]::OK }
    }
    $ico = switch ($Icon) {
        'Warning'  { [System.Windows.Forms.MessageBoxIcon]::Warning }
        'Error'    { [System.Windows.Forms.MessageBoxIcon]::Error }
        'Question' { [System.Windows.Forms.MessageBoxIcon]::Question }
        default    { [System.Windows.Forms.MessageBoxIcon]::Information }
    }

    return [System.Windows.Forms.MessageBox]::Show($Message, $Title, $btn, $ico).ToString()
}

# Ask the participant to pick the "share" folder on their external SSD.
# Returns the selected path, or $null if the dialog was cancelled.
function Select-ShareFolder {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description  = 'Select the "share" folder on your external SSD.'
    $dialog.ShowNewFolderButton = $false

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }
    return $null
}

# =============================================================================
# Docker helpers
# =============================================================================

# Is the docker CLI on PATH? (Docker Desktop may simply not be installed.)
function Test-DockerInstalled {
    return [bool](Get-Command docker -ErrorAction SilentlyContinue)
}

# Is the Docker engine actually answering? Docker Desktop's process can be
# running long before the engine is ready, so we query the server version.
function Test-DockerRunning {
    if (-not (Test-DockerInstalled)) { return $false }
    try {
        docker info --format '{{.ServerVersion}}' 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

# Locate Docker Desktop.exe in the usual install locations.
function Get-DockerDesktopPath {
    $candidates = @(
        (Join-Path $env:ProgramFiles      'Docker\Docker\Docker Desktop.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Docker\Docker\Docker Desktop.exe'),
        (Join-Path $env:LOCALAPPDATA      'Docker\Docker Desktop.exe')
    )
    foreach ($path in $candidates) {
        if ($path -and (Test-Path $path)) { return $path }
    }
    return $null
}

# Make sure the Docker engine is up: start Docker Desktop if needed and poll
# until it answers. Returns $true on success.
function Confirm-DockerReady {
    if (Test-DockerRunning) {
        Write-Ok 'Docker is running.'
        return $true
    }

    if (-not (Test-DockerInstalled)) {
        Show-Dialog -Message @"
Docker Desktop does not seem to be installed.

Please follow the tutorial wiki to install Docker Desktop first,
then run this script again.
"@ -Icon 'Error' | Out-Null
        return $false
    }

    $exe = Get-DockerDesktopPath
    if (-not $exe) {
        Show-Dialog -Message @"
Docker Desktop is installed but could not be located automatically.

Please start Docker Desktop by hand, wait until it says "Engine running",
then run this script again.
"@ -Icon 'Error' | Out-Null
        return $false
    }

    Write-Step "Starting Docker Desktop (this can take up to $($Script:DockerStartTimeout) seconds)..."
    Start-Process -FilePath $exe | Out-Null

    # Poll rather than sleeping a fixed amount: startup time varies a lot.
    $deadline = (Get-Date).AddSeconds($Script:DockerStartTimeout)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 3
        if (Test-DockerRunning) {
            Write-Ok 'Docker is running.'
            return $true
        }
        Write-Host '.' -NoNewline
    }
    Write-Host ''

    # A timeout usually means Docker Desktop is waiting for user input
    # (licence agreement, WSL2 update prompt, sign-in screen).
    Show-Dialog -Message @"
Docker Desktop did not finish starting within $($Script:DockerStartTimeout) seconds.

Please open the Docker Desktop window and check whether it is waiting for
something (licence agreement, WSL update, sign-in). Once it shows
"Engine running", run this script again.
"@ -Icon 'Warning' | Out-Null
    return $false
}

# Is the expected image present locally?
function Test-ImageExists {
    docker image inspect $Script:ImageName 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

# Container state: 'running', 'exited'/'created' (a leftover), or '' (none).
function Get-ContainerState {
    $state = docker ps -a --filter "name=^$($Script:ContainerName)$" --format '{{.State}}' 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $state) { return '' }
    return ($state | Select-Object -First 1).Trim()
}

# Remove a stopped container. Needed even with --rm, because a container that
# died abnormally can survive and then block "docker run --name abis".
function Remove-LeftoverContainer {
    Write-Step 'Removing a leftover container from a previous session...'
    docker rm -f $Script:ContainerName 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Ok 'Removed.' } else { Write-Warn 'Nothing to remove.' }
}

# =============================================================================
# Share folder validation
# =============================================================================

# Convert a Windows path to the forward-slash form docker prefers.
function ConvertTo-DockerPath {
    param([Parameter(Mandatory)][string]$Path)
    return ($Path -replace '\\', '/')
}

# Check the selected folder for the problems we know cause trouble.
# Returns $true if it is safe to continue.
function Test-ShareFolder {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Show-Dialog -Message "The selected folder no longer exists:`n`n$Path" -Icon 'Error' | Out-Null
        return $false
    }

    # --- File system must be NTFS ---------------------------------------
    # exFAT cannot store POSIX ownership, so everything is mounted as root
    # and the "brain" user inside the container cannot write to it.
    try {
        $driveLetter = (Get-Item -LiteralPath $Path).PSDrive.Name
        if ($driveLetter -and $driveLetter.Length -eq 1) {
            $volume = Get-Volume -DriveLetter $driveLetter -ErrorAction Stop
            if ($volume.FileSystem -and $volume.FileSystem -ne 'NTFS') {
                Show-Dialog -Message @"
The selected drive is formatted as $($volume.FileSystem), but NTFS is required.

On $($volume.FileSystem) the tutorial software cannot write into the share folder,
because that file system cannot store Linux file ownership.

Please back up the contents of the drive, reformat it as NTFS, and try again.
See the tutorial wiki for details.

Selected folder: $Path
"@ -Icon 'Error' | Out-Null
                return $false
            }
        }
    } catch {
        # Network drives and some USB enclosures are not reported by Get-Volume.
        Write-Warn 'Could not determine the file system of this drive; continuing.'
    }

    # --- Non-ASCII characters --------------------------------------------
    # Mixed encodings between Windows, the Docker VM and the container are a
    # reliable source of hard-to-diagnose failures.
    if ($Path -match '[^\x20-\x7E]') {
        $answer = Show-Dialog -Buttons 'YesNo' -Icon 'Warning' -Message @"
The selected path contains non-ASCII characters:

$Path

This often causes problems inside the container. A path made only of
ASCII letters, digits, hyphens and underscores is strongly recommended.

Continue anyway?
"@
        if ($answer -ne 'Yes') { return $false }
    }

    # --- Cloud-synced folders --------------------------------------------
    # Sync clients will try to upload every intermediate file that FreeSurfer
    # and FSL produce, which is slow at best and corrupting at worst.
    if ($Path -match 'OneDrive|Dropbox|Google Drive|iCloud|Box Sync') {
        $answer = Show-Dialog -Buttons 'YesNo' -Icon 'Warning' -Message @"
The selected folder looks like it is inside a cloud-synced folder:

$Path

Analysis produces a very large number of intermediate files. Syncing them
will slow your machine down badly and may corrupt results.

Please choose a folder on a local or external drive instead.

Continue anyway?
"@
        if ($answer -ne 'Yes') { return $false }
    }

    # --- Write test -------------------------------------------------------
    $probe = Join-Path $Path '.abis_write_test'
    try {
        New-Item -Path $probe -ItemType File -Force -ErrorAction Stop | Out-Null
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
    } catch {
        Show-Dialog -Message @"
The selected folder is not writable:

$Path

If this is an external drive, it may have been mounted read-only. Try
safely ejecting and reconnecting it.
"@ -Icon 'Error' | Out-Null
        return $false
    }

    Write-Ok "Share folder: $Path"
    return $true
}

# =============================================================================
# noVNC readiness and browser
# =============================================================================

# Poll until noVNC answers. The port opens as soon as websockify listens, but
# Xvfb, x11vnc and xfce4-session are still starting behind it - connecting too
# early shows a grey or broken desktop. Hence the extra grace period.
function Wait-ForVnc {
    Write-Step 'Waiting for the Lin4Neuro desktop to start...'
    $deadline = (Get-Date).AddSeconds($Script:VncReadyTimeout)

    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -Uri $Script:VncProbeUrl -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
            if ($response.StatusCode -eq 200) {
                Write-Host ''
                Write-Ok "Desktop is up. Waiting $($Script:PostReadyWait) more seconds for the session to settle..."
                Start-Sleep -Seconds $Script:PostReadyWait
                return $true
            }
        } catch {
            # Not ready yet - this is the normal case while starting up.
        }
        Write-Host '.' -NoNewline
        Start-Sleep -Seconds 2
    }

    Write-Host ''
    return $false
}

# Open noVNC. App mode gives a window with no tab bar, so Ctrl+W cannot
# close the session by accident.
function Open-Lin4Neuro {
    Write-Step 'Opening Lin4Neuro in your browser...'

    if ($Script:OpenInAppMode) {
        $browsers = @(
            (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
            (Join-Path $env:ProgramFiles         'Microsoft\Edge\Application\msedge.exe'),
            (Join-Path $env:ProgramFiles         'Google\Chrome\Application\chrome.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe')
        )
        foreach ($browser in $browsers) {
            if ($browser -and (Test-Path $browser)) {
                Start-Process -FilePath $browser -ArgumentList "--app=$($Script:VncUrl)"
                Write-Ok 'Opened in a dedicated window.'
                return
            }
        }
        Write-Warn 'Edge/Chrome not found; falling back to the default browser.'
    }

    Start-Process $Script:VncUrl
    Write-Ok 'Opened in your default browser.'
}

# Show the tail of the container log. Used when startup times out, so the
# participant has something concrete to paste into the support chat.
function Show-ContainerLog {
    Write-Host ''
    Write-Step "Last 50 lines of the container log:"
    Write-Host '--------------------------------------------------------------'
    docker logs --tail 50 $Script:ContainerName 2>&1 | ForEach-Object { Write-Host $_ }
    Write-Host '--------------------------------------------------------------'
}
```

### `lib/start_lin4neuro.ps1`

```powershell
# start_lin4neuro.ps1 - Start the ABiS Lin4Neuro container and open it in a browser.
# Creates a fresh container each time (--rm); all work must be saved in the share folder.

$ErrorActionPreference = 'Stop'

# Load shared settings and helpers from the same folder as this script.
. (Join-Path $PSScriptRoot 'common.ps1')

Write-Host ''
Write-Host '  ABiS Lin4Neuro - Start' -ForegroundColor White
Write-Host '  ----------------------' -ForegroundColor DarkGray
Write-Host ''

# ---------------------------------------------------------------------------
# [1] Docker engine
# ---------------------------------------------------------------------------
Write-Step 'Checking Docker...'
if (-not (Confirm-DockerReady)) {
    Exit-WithPause -Message 'Docker is not ready. Please see the message above.' -Code 1
}

# ---------------------------------------------------------------------------
# [2] Container image
# ---------------------------------------------------------------------------
# Deliberately do NOT pull here. A silent 30 GB download would leave the
# participant staring at a frozen window for 40 minutes. Downloading is a
# separate, explicit step (1_Download_Image).
Write-Step "Checking for the image $($Script:ImageName)..."
if (-not (Test-ImageExists)) {
    Show-Dialog -Icon 'Warning' -Message @"
The tutorial image is not on this computer yet:

  $($Script:ImageName)

Please run "1_Download_Image" first. The download is $($Script:ImageSizeText)
and takes about $($Script:ImageTimeText).
"@ | Out-Null
    Exit-WithPause -Message 'Image not found.' -Code 1
}
Write-Ok 'Image found.'

# ---------------------------------------------------------------------------
# [3] Existing container
# ---------------------------------------------------------------------------
$state = Get-ContainerState

if ($state -eq 'running') {
    # Already up - most likely the participant double-clicked twice because
    # startup felt slow. Do not create anything, just reconnect.
    Write-Ok 'The container is already running. Reconnecting.'
    if (-not (Wait-ForVnc)) {
        Show-ContainerLog
        Exit-WithPause -Message 'The desktop did not respond. Try "3_Stop_Lin4Neuro" and start again.' -Code 1
    }
    Open-Lin4Neuro
    Exit-WithPause -Message 'Done.' -Code 0
}

if ($state) {
    # A stopped container with our name exists. With --rm this should not
    # happen, but an abnormal exit can leave one behind - and it would block
    # "docker run --name abis" with a name conflict.
    Remove-LeftoverContainer
}

# ---------------------------------------------------------------------------
# [4] Choose the share folder
# ---------------------------------------------------------------------------
# Asked every time: the container is disposable, so the mount is decided fresh
# on each run. This also means a disconnected SSD is caught here rather than
# producing a container with an empty share folder.
Write-Step 'Please select your share folder...'

$sharePath = $null
while (-not $sharePath) {
    $selected = Select-ShareFolder
    if (-not $selected) {
        Exit-WithPause -Message 'Cancelled. Nothing was started.' -Code 0
    }
    if (Test-ShareFolder -Path $selected) {
        $sharePath = $selected
    }
    # Otherwise loop and let them choose again.
}

$dockerSharePath = ConvertTo-DockerPath -Path $sharePath

# ---------------------------------------------------------------------------
# [5] Start the container
# ---------------------------------------------------------------------------
Write-Step 'Starting the container...'

$dockerArgs = @(
    'run', '-d', '--rm',
    '--name', $Script:ContainerName,
    '--shm-size', $Script:ShmSize,
    '-v', "$($dockerSharePath):$($Script:ContainerShare)",
    '-p', "127.0.0.1:$($Script:HostPort):$($Script:HostPort)",
    $Script:ImageName
)

# Show the command so participants can see exactly what is being run, and
# reproduce it by hand later if they want to.
Write-Host ''
Write-Host "    docker $($dockerArgs -join ' ')" -ForegroundColor DarkGray
Write-Host ''

& docker @dockerArgs | Out-Null

if ($LASTEXITCODE -ne 0) {
    Show-Dialog -Icon 'Error' -Message @"
The container failed to start.

The most common causes are:
  - port $($Script:HostPort) is already used by another program
  - not enough disk space
  - the external SSD was disconnected

Details are shown in the console window behind this dialog.
"@ | Out-Null
    Exit-WithPause -Message 'docker run failed.' -Code 1
}
Write-Ok 'Container started.'

# ---------------------------------------------------------------------------
# [6] Wait until noVNC is serving
# ---------------------------------------------------------------------------
if (-not (Wait-ForVnc)) {
    Show-ContainerLog
    Show-Dialog -Icon 'Error' -Message @"
The Lin4Neuro desktop did not start within $($Script:VncReadyTimeout) seconds.

The console window shows the last 50 lines of the container log.
Please copy that text into the tutorial chat so a tutor can help.
"@ | Out-Null
    Exit-WithPause -Message 'Startup timed out.' -Code 1
}

# ---------------------------------------------------------------------------
# [7] Open the browser
# ---------------------------------------------------------------------------
Open-Lin4Neuro

Write-Host ''
Write-Ok 'Lin4Neuro is ready.'
Write-Warn 'Remember: save all your work inside the share folder.'
Write-Warn 'Closing the browser does NOT stop the container - use "3_Stop_Lin4Neuro".'
Exit-WithPause -Code 0
```
