# stop_lin4neuro.ps1 - Stop the ABiS Lin4Neuro container.
# The container was started with --rm, so stopping it also removes it. Anything
# that was not saved in the share folder is gone afterwards.
#
# Encoding: UTF-8 WITH BOM (see the note in common.ps1).

. (Join-Path $PSScriptRoot 'common.ps1')

Write-Title 'ABiS Lin4Neuro - 終了'

# ---------------------------------------------------------------------------
# [1] Docker engine
# ---------------------------------------------------------------------------
if (-not (Test-DockerInstalled)) {
    Exit-WithPause -Message 'Docker Desktop がインストールされていないため、終了する対象はありません。' -Code 0
}
if (-not (Test-DockerRunning)) {
    Exit-WithPause -Message 'Docker が起動していないため、Lin4Neuro も動いていません。' -Code 0
}

# ---------------------------------------------------------------------------
# [2] Stop the container
# ---------------------------------------------------------------------------
$state = Get-ContainerState

if (-not $state) {
    Write-Ok 'Lin4Neuro は起動していません。'
} elseif ($state -eq 'running') {
    $answer = Show-Dialog -Buttons 'YesNo' -Icon 'Question' -Message @"
Lin4Neuro を終了しますか?

共有フォルダ以外に置いたファイルは失われます。
"@
    if ($answer -ne 'Yes') {
        Exit-WithPause -Message 'キャンセルしました。Lin4Neuro は起動したままです。' -Code 0
    }

    Write-Step 'Lin4Neuro を終了しています (最大 20 秒かかります)...'
    docker stop -t 20 $Script:ContainerName 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Warn '通常の終了に失敗したため、コンテナを強制的に削除します。'
        docker rm -f $Script:ContainerName 2>$null | Out-Null
    }

    if (Get-ContainerState) {
        Remove-LeftoverContainer
    }
    Write-Ok 'Lin4Neuro を終了しました。'
} else {
    Write-Warn "前回のコンテナが残っています (状態: $state)。"
    Remove-LeftoverContainer
}

# ---------------------------------------------------------------------------
# [3] Offer to quit Docker Desktop
# ---------------------------------------------------------------------------
# Docker Desktop keeps a virtual machine running in the background and holds
# on to several GB of memory, which is worth reclaiming after a session.
$answer = Show-Dialog -Buttons 'YesNo' -Icon 'Question' -Message @"
Docker Desktop も終了しますか?

Docker は Lin4Neuro を止めた後も仮想マシンを動かし続けており、
数 GB のメモリを使っています。

すぐにまた Lin4Neuro を起動する場合は「いいえ」を選んでください。
"@

if ($answer -eq 'Yes') {
    Write-Step 'Docker Desktop を終了しています...'
    # Stop-DockerDesktop (common.ps1) tries "docker desktop stop" first.
    if (Stop-DockerDesktop) {
        Write-Ok 'Docker Desktop を終了しています。'
    } else {
        Write-Warn 'Docker Desktop は起動していないようです。'
    }
} else {
    Write-Info 'Docker Desktop は起動したままです。'
}

Write-Host ''
Write-Ok '完了しました。共有フォルダの中のファイルはそのまま残っています。'
Exit-WithPause -Code 0
