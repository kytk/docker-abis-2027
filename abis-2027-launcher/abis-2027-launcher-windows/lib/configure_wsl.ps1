# configure_wsl.ps1 - Show, set or undo the memory of the WSL 2 VM that runs Docker.
# With the WSL 2 backend, Docker Desktop has no memory setting of its own; the
# VM is sized by %USERPROFILE%\.wslconfig (see the WSL section of common.ps1).
# This script sets memory and swap there, keeps a backup of the participant's
# own file, and restarts WSL so that the change takes effect.
#
# Encoding: UTF-8 WITH BOM (see the note in common.ps1).

. (Join-Path $PSScriptRoot 'common.ps1')

Write-Title 'ABiS Lin4Neuro - WSL のメモリ設定'

# ---------------------------------------------------------------------------
# [1] Preconditions
# ---------------------------------------------------------------------------
if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    Exit-WithPause -Message 'WSL が見つかりません。先に Docker Desktop をインストールしてください。' -Code 1
}

$ramGB = Get-InstalledRamGB
if (-not $ramGB) {
    Exit-WithPause -Message 'このパソコンのメモリ容量を取得できませんでした。講師にご連絡ください。' -Code 1
}

# With the Hyper-V backend .wslconfig has no effect on Docker; its memory is
# set in Docker Desktop's own Settings -> Resources instead. The backend can
# only be told while the engine runs, so an engine that is down is assumed to
# be WSL 2 (the default, and the only choice on Windows Home).
$dockerWasRunning = Test-DockerRunning
if ($dockerWasRunning -and (Test-DockerUsesWsl) -eq $false) {
    Show-Dialog -Icon 'Info' -Message @"
この Docker Desktop は WSL 2 ではなく Hyper-V で動いています。

この場合、メモリは Docker Desktop の画面で設定します:
Settings -> Resources -> Advanced -> Memory を $(Get-WslMemoryTargetGB -RamGB $ramGB) GB 以上にして、
Apply & restart を押してください。
"@ | Out-Null
    Exit-WithPause -Message '変更はしていません。' -Code 0
}

# Restarting WSL would cut off a running tutorial session.
if ($dockerWasRunning -and (Get-ContainerState) -eq 'running') {
    Show-Dialog -Icon 'Warning' -Message @"
Lin4Neuro が起動中です。

設定を反映するために WSL を再起動すると、Lin4Neuro も止まります。
先に「3_Stop_Lin4Neuro」で終了してから、もう一度実行してください。
"@ | Out-Null
    Exit-WithPause -Message '変更はしていません。' -Code 0
}

# ---------------------------------------------------------------------------
# [2] Current state
# ---------------------------------------------------------------------------
$config    = Read-WslConfig
$managed   = Test-WslConfigManaged
$targetMem = Get-WslMemoryTargetGB -RamGB $ramGB

function Format-WslValue {
    param([string]$Key, [string]$DefaultText)
    if ($config.ContainsKey($Key) -and $config[$Key]) { return $config[$Key] }
    return "未設定 (既定: $DefaultText)"
}

Write-Step '現在の設定'
Write-Info ("搭載メモリ : {0} GB" -f $ramGB)
if (Test-Path -LiteralPath $Script:WslConfigPath) {
    Write-Info ("設定ファイル: {0}" -f $Script:WslConfigPath)
} else {
    Write-Info ("設定ファイル: なし ({0})" -f $Script:WslConfigPath)
}
Write-Info ("  memory     : {0}" -f (Format-WslValue 'memory'     ("搭載メモリの半分 = 約 {0} GB" -f [math]::Floor($ramGB / 2))))
Write-Info ("  swap       : {0}" -f (Format-WslValue 'swap'       ("搭載メモリの 1/4 = 約 {0} GB" -f [math]::Floor($ramGB / 4))))
Write-Info ("  processors : {0}" -f (Format-WslValue 'processors' 'すべての CPU'))
if ($managed) { Write-Info '(このランチャーで変更した設定です)' }
Write-Host ''

# ---------------------------------------------------------------------------
# [3] Decide what to do
# ---------------------------------------------------------------------------
$changed = $false

if ($managed) {
    # Already changed by this script: the only action offered is to undo it.
    $answer = Show-Dialog -Buttons 'YesNo' -Icon 'Question' -Message @"
WSL のメモリ設定は、以前このスクリプトで変更しています。

  memory = $($config['memory'])
  swap   = $($config['swap'])

元の設定に戻しますか?
(チュートリアル中は、このままにしておいてください)
"@
    if ($answer -ne 'Yes') {
        Exit-WithPause -Message '変更はしていません。' -Code 0
    }
    try {
        Restore-WslConfig
        Write-Ok '元の設定に戻しました。'
        $changed = $true
    } catch {
        Exit-WithPause -Message ("元に戻せませんでした: {0}" -f $_.Exception.Message) -Code 1
    }
} else {
    # The current values: those in the file, or the WSL defaults (memory half
    # the RAM, swap a quarter). An unreadable value is treated as "too small"
    # so that it is offered for replacement rather than silently kept.
    $currentBytes = if ($config['memory']) { ConvertFrom-WslSize $config['memory'] } else { $ramGB * 1GB / 2 }
    $currentGB    = if ($currentBytes) { ConvertTo-RoundedGB $currentBytes } else { 0 }
    $swapBytes    = if ($config['swap']) { ConvertFrom-WslSize $config['swap'] } else { $ramGB * 1GB / 4 }
    $swapGB       = if ($swapBytes) { ConvertTo-RoundedGB $swapBytes } else { 0 }

    # Under 16 GB the memory target is the WSL default, but the swap still
    # has to be raised. Neither value is ever lowered.
    if ($currentGB -ge $targetMem -and $swapGB -ge $Script:WslSwapGB) {
        Show-Dialog -Message @"
WSL のメモリは $currentGB GB、スワップは $swapGB GB で、変更の必要はありません。
"@ | Out-Null
        Exit-WithPause -Message '変更の必要はありません。' -Code 0
    }
    $newMem  = [math]::Max($currentGB, $targetMem)
    $newSwap = [math]::Max($swapGB, $Script:WslSwapGB)

    $answer = Show-Dialog -Buttons 'YesNo' -Icon 'Question' -Message @"
Docker (WSL) のメモリ設定を変更します。

  memory : $currentGB GB  ->  $newMem GB
  swap   : $swapGB GB  ->  $newSwap GB

設定ファイル $($Script:WslConfigPath) を書き換えます。
ほかの設定はそのまま残し、元のファイルは .wslconfig.abis-backup に
保存します。このスクリプトをもう一度実行すると元に戻せます。
変更しますか?
"@
    if ($answer -ne 'Yes') {
        Exit-WithPause -Message 'キャンセルしました。変更はしていません。' -Code 0
    }
    try {
        Set-WslConfig -MemoryGB $newMem -SwapGB $newSwap
        Write-Ok ("設定を書き換えました: memory={0}GB, swap={1}GB" -f $newMem, $newSwap)
        $changed = $true
    } catch {
        Exit-WithPause -Message ("設定ファイルを書き換えられませんでした: {0}" -f $_.Exception.Message) -Code 1
    }
}

# ---------------------------------------------------------------------------
# [4] Restart WSL so that the change takes effect
# ---------------------------------------------------------------------------
if ($changed) {
    $answer = Show-Dialog -Buttons 'YesNo' -Icon 'Warning' -Message @"
設定を反映するには WSL の再起動が必要です。

Docker Desktop と、ほかに起動している WSL (Ubuntu など) も
いったん終了します。WSL の中で作業中のものがあれば先に保存してください。

いま再起動しますか?
(「いいえ」を選んだ場合は、パソコンを再起動すると反映されます)
"@
    if ($answer -ne 'Yes') {
        Exit-WithPause -Message '設定は保存しました。パソコンを再起動すると反映されます。' -Code 0
    }

    Write-Step 'Docker Desktop を終了しています...'
    if (Stop-DockerDesktop) {
        # The fallback in Stop-DockerDesktop returns before the processes are
        # gone; give them a moment so they do not restart the VM.
        Start-Sleep -Seconds 5
    }

    Write-Step 'WSL を再起動しています...'
    & wsl --shutdown 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Exit-WithPause -Message '設定は保存しましたが、WSL を停止できませんでした。パソコンを再起動すると反映されます。' -Code 1
    }
    # Microsoft's guidance: wait about 8 seconds after the VM stops before
    # starting it again, or the old configuration can still be in use.
    Start-Sleep -Seconds 8
    Write-Ok 'WSL を停止しました。'

    if ($dockerWasRunning) {
        Write-Step 'Docker Desktop を起動し直しています...'
        if (-not (Confirm-DockerReady)) {
            Exit-WithPause -Message '設定は保存しました。Docker Desktop を手動で起動してください。' -Code 1
        }
        $memBytes = docker info --format '{{.MemTotal}}' 2>$null
        if ($LASTEXITCODE -eq 0 -and $memBytes) {
            Write-Ok ("Docker が使えるメモリ: {0} GB" -f (ConvertTo-GBText ([double]"$memBytes".Trim())))
        }
    } else {
        Write-Info 'Docker Desktop を次に起動したときから新しい設定が使われます。'
    }
}

Write-Host ''
Exit-WithPause -Message '完了しました。' -Code 0
