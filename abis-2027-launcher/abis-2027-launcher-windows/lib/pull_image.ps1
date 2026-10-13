# pull_image.ps1 - Download the tutorial image, or update an existing copy.
# Run before the course, and again whenever a new build is announced.
#
# Encoding: UTF-8 WITH BOM (see the note in common.ps1).

. (Join-Path $PSScriptRoot 'common.ps1')

Write-Title 'ABiS Lin4Neuro - イメージのダウンロード・更新'

# ---------------------------------------------------------------------------
# [1] Docker engine
# ---------------------------------------------------------------------------
Write-Step 'Docker を確認しています...'
if (-not (Confirm-DockerReady)) {
    Exit-WithPause -Message 'Docker の準備ができていません。上のメッセージをご確認ください。' -Code 1
}

# ---------------------------------------------------------------------------
# [2] Confirm - a first download is long and large, an update usually is not
# ---------------------------------------------------------------------------
# The tag stays 26.12 for the whole season, but the image behind it is rebuilt
# when something has to be fixed. So an existing local copy is not necessarily
# current: always ask Docker Hub, and let it transfer only the layers that
# actually changed. The ID taken here is compared with the one after the pull.
$beforeId = Get-ImageId

if ($beforeId) {
    $answer = Show-Dialog -Buttons 'YesNo' -Icon 'Question' -Message @"
チュートリアル用のイメージはすでにこのパソコンにあります:

  $($Script:ImageName)

更新されていないかを確認します。最新版であれば、すぐに終わります。
更新されていた場合は、変わった部分だけをダウンロードします
(内容によっては時間がかかることがあります)。

確認しますか?
"@
} else {
    $answer = Show-Dialog -Buttons 'YesNo' -Icon 'Question' -Message @"
これからチュートリアル環境をダウンロードします。

  イメージ       : $($Script:ImageName)
  ダウンロード量 : $($Script:ImageSizeText)
  所要時間       : 高速な回線で $($Script:ImageTimeText)
  ディスク使用量 : 展開後 約 $($Script:ImageDiskGB) GB

有線または安定した Wi-Fi でつなぎ、電源アダプタを接続したまま、
スリープしないようにしてください。途中で中断しても、このスクリプトを
もう一度実行すれば続きから再開できます。

ダウンロードを始めますか?
"@
}
if ($answer -ne 'Yes') {
    Exit-WithPause -Message 'キャンセルしました。' -Code 0
}

# ---------------------------------------------------------------------------
# [3] Pull
# ---------------------------------------------------------------------------
if ($beforeId) {
    Write-Step "$($Script:ImageName) の更新を確認しています..."
} else {
    Write-Step "$($Script:ImageName) をダウンロードしています..."
}
Write-Info '進行状況は下に表示されます。このウィンドウは裏に回しても構いません。'
Write-Host ''

$started = Get-Date

# --platform is passed explicitly so that the amd64 image is fetched even on
# an arm64 Windows machine, where Docker would otherwise look for arm64.
docker pull --platform linux/amd64 $Script:ImageName

if ($LASTEXITCODE -ne 0) {
    Write-Host ''

    # With a usable copy already on this computer, a failed update check is not
    # a fatal error - most often it just means there is no network right now.
    # Saying so, and letting the participant start the tutorial, matters more
    # than the update.
    if ($beforeId) {
        Show-Dialog -Icon 'Warning' -Message @"
更新を確認できませんでした。

ネットワークにつながっていないか、Docker Hub につながらないようです。
すでにあるイメージはそのまま使えます。「2_Start_Lin4Neuro」で
起動してください。
"@ | Out-Null
        Exit-WithPause -Message '更新は確認できませんでしたが、イメージはこのパソコンにあります。' -Code 0
    }

    Show-Dialog -Icon 'Error' -Message @"
ダウンロードが完了しませんでした。

よくある原因:
  - ネットワークが切断された
  - Docker の仮想ディスクの空き容量が足りない
    (Docker Desktop -> Settings -> Resources -> Virtual disk limit)

このスクリプトをもう一度実行すれば、中断したところから再開します。
"@ | Out-Null
    Exit-WithPause -Message 'docker pull に失敗しました。' -Code 1
}

# ---------------------------------------------------------------------------
# [4] Verify
# ---------------------------------------------------------------------------
Write-Host ''
Write-Step 'イメージを確認しています...'
$afterId = Get-ImageId
if (-not $afterId) {
    Exit-WithPause -Message 'ダウンロード後もイメージが見つかりません。講師にご連絡ください。' -Code 1
}

# Nothing changed: the local copy was already the build on Docker Hub.
if ($beforeId -eq $afterId) {
    Write-Ok 'イメージは最新版です。ダウンロードするものはありませんでした。'
    Show-Dialog -Message @"
チュートリアル用のイメージは最新版でした。

「2_Start_Lin4Neuro」で起動してください。
"@ | Out-Null
    Exit-WithPause -Code 0
}

$elapsed = (Get-Date) - $started
$size    = docker image inspect $Script:ImageName --format '{{.Size}}' 2>$null
$sizeGB  = if ($LASTEXITCODE -eq 0 -and $size) { [math]::Round([double]$size / 1GB, 1) } else { $null }

Write-Ok 'イメージの準備ができました。'
if ($sizeGB) { Write-Info ("ディスク使用量 : {0} GB" -f $sizeGB) }
Write-Info ("所要時間       : {0:hh\:mm\:ss}" -f $elapsed)

# ---------------------------------------------------------------------------
# [5] Clean up the build that was replaced
# ---------------------------------------------------------------------------
# An updated image leaves the previous build behind, untagged and still taking
# its full size on disk. Nothing uses it any more, and ~38 GB is more than most
# participants can spare, so offer to remove it here. "docker image rm" without
# -f refuses while a container is still using it, which is the behaviour we
# want.
if ($beforeId) {
    $answer = Show-Dialog -Buttons 'YesNo' -Icon 'Question' -Message @"
イメージを新しい版に更新しました。

前の版がディスクに残っています (約 $($Script:ImageDiskGB) GB)。
これから使うのは新しい版だけなので、削除して構いません。

前の版を削除しますか?
"@
    if ($answer -eq 'Yes') {
        Write-Step '前の版を削除しています...'
        docker image rm $beforeId 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Ok '削除しました。'
        } else {
            Write-Warn '削除できませんでした。Lin4Neuro が起動中かもしれません。'
            Write-Info '「3_Stop_Lin4Neuro」で終了してから、Docker Desktop の Images 画面で'
            Write-Info '<none> と表示されているイメージを削除してください。'
        }
    } else {
        Write-Info '前の版は Docker Desktop の Images 画面 (<none> の行) から削除できます。'
    }
}

Show-Dialog -Message @"
チュートリアル環境の準備ができました。

「2_Start_Lin4Neuro」で Lin4Neuro を起動してください。
チュートリアルの期間中にイメージが更新されることがあります。
ときどきこの「1_Download_Image」を実行して、確認してください。
"@ | Out-Null

Exit-WithPause -Message 'ダウンロードが完了しました。' -Code 0
