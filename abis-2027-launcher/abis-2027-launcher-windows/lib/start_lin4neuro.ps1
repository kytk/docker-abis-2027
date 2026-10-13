# start_lin4neuro.ps1 - Start the ABiS Lin4Neuro container and open it in a browser.
# A fresh container is created each time (--rm); all work must be saved in the
# share folder, which is chosen again on every start.
#
# Encoding: UTF-8 WITH BOM (see the note in common.ps1).

. (Join-Path $PSScriptRoot 'common.ps1')

Write-Title 'ABiS Lin4Neuro - 起動'

# ---------------------------------------------------------------------------
# [1] Docker engine
# ---------------------------------------------------------------------------
Write-Step 'Docker を確認しています...'
if (-not (Confirm-DockerReady)) {
    Exit-WithPause -Message 'Docker の準備ができていません。上のメッセージをご確認ください。' -Code 1
}

# ---------------------------------------------------------------------------
# [2] Container image
# ---------------------------------------------------------------------------
# Deliberately no pull here: a silent 20 GB download would leave the
# participant staring at a frozen window. Downloading is a separate, explicit
# step (1_Download_Image).
Write-Step "イメージ $($Script:ImageName) を確認しています..."
if (-not (Test-ImageExists)) {
    Show-Dialog -Icon 'Warning' -Message @"
チュートリアル用のイメージがまだこのパソコンにありません:

  $($Script:ImageName)

先に「1_Download_Image」を実行してください。
ダウンロード量は $($Script:ImageSizeText)、所要時間は $($Script:ImageTimeText) です。
"@ | Out-Null
    Exit-WithPause -Message 'イメージが見つかりません。' -Code 1
}
Write-Ok 'イメージを確認しました。'

# ---------------------------------------------------------------------------
# [3] Existing container
# ---------------------------------------------------------------------------
$state = Get-ContainerState

if ($state -eq 'running') {
    # Already up - most likely the participant double-clicked twice because
    # startup felt slow. Do not create anything, just reconnect.
    Write-Ok 'Lin4Neuro はすでに起動しています。接続し直します。'
    Write-Info '別の共有フォルダを使いたい場合は、先に「3_Stop_Lin4Neuro」を実行してください。'
    if (-not (Wait-ForHealthy)) {
        Show-ContainerLog
        Exit-WithPause -Message 'デスクトップが応答しません。「3_Stop_Lin4Neuro」を実行してから起動し直してください。' -Code 1
    }
    Open-Lin4Neuro
    Exit-WithPause -Code 0
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
# on each run. This also catches a disconnected external drive here, rather
# than producing a container with an empty share folder.
Write-Step '共有フォルダを選んでください...'
Write-Info '残しておきたいものは、すべてこのフォルダの中に保存してください。'

$sharePath = $null
while (-not $sharePath) {
    $selected = Select-ShareFolder
    if (-not $selected) {
        Exit-WithPause -Message 'キャンセルしました。Lin4Neuro は起動していません。' -Code 0
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
Write-Step 'Lin4Neuro を起動しています...'

$dockerArgs = @(
    'run', '-d', '--rm',
    '--name', $Script:ContainerName,
    '--platform', 'linux/amd64',
    '--shm-size', $Script:ShmSize,
    '-v', "$($dockerSharePath):$($Script:ContainerShare)",
    '-p', "127.0.0.1:$($Script:HostPort):$($Script:ContainerPort)",
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
Lin4Neuro を起動できませんでした。

よくある原因:
  - ポート $($Script:HostPort) を別のプログラムが使っている
  - ディスクの空き容量が足りない
  - 外付けドライブが取り外されている

詳しい内容は、このダイアログの後ろのコンソールウィンドウに表示されています。
"@ | Out-Null
    Exit-WithPause -Message 'docker run に失敗しました。' -Code 1
}
Write-Ok 'コンテナを起動しました。'

# ---------------------------------------------------------------------------
# [6] Wait until the desktop is ready
# ---------------------------------------------------------------------------
if (-not (Wait-ForHealthy)) {
    Show-ContainerLog
    Show-Dialog -Icon 'Error' -Message @"
Lin4Neuro のデスクトップが $($Script:ContainerReadyTimeout) 秒以内に起動しませんでした。

コンソールウィンドウにコンテナのログ (最後の 50 行) を表示しています。
その内容をチュートリアルのチャットに貼り付けてください。
"@ | Out-Null
    Exit-WithPause -Message '起動がタイムアウトしました。' -Code 1
}

# ---------------------------------------------------------------------------
# [7] Open the browser
# ---------------------------------------------------------------------------
Open-Lin4Neuro

Write-Host ''
Write-Ok 'Lin4Neuro の準備ができました。'
Write-Info ("共有フォルダは Lin4Neuro の中では {0} です。" -f $Script:ContainerShare)
Write-Warn '作業したファイルは必ず共有フォルダの中に保存してください。'
Write-Warn 'ブラウザを閉じても Lin4Neuro は止まりません。終了するときは「3_Stop_Lin4Neuro」を実行してください。'
Exit-WithPause -Code 0
