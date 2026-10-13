# check_environment.ps1 - Collect a diagnostic report about this computer.
# Writes abis_check_result.txt next to the launcher scripts so that the
# participant can paste or attach it in the tutorial chat.
#
# Encoding: UTF-8 WITH BOM (see the note in common.ps1).

. (Join-Path $PSScriptRoot 'common.ps1')

$reportPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'abis_check_result.txt'
$lines      = New-Object System.Collections.ArrayList
$problems   = New-Object System.Collections.ArrayList
$warnings   = New-Object System.Collections.ArrayList

function Add-Line {
    param([string]$Text = '')
    [void]$lines.Add($Text)
    Write-Host $Text
}
function Add-Problem { param([string]$Text) [void]$problems.Add($Text) }
function Add-Warning { param([string]$Text) [void]$warnings.Add($Text) }

Write-Title 'ABiS Lin4Neuro - 動作環境チェック'

Add-Line 'ABiS Lin4Neuro 動作環境チェック'
Add-Line ("作成日時: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Add-Line ("ランチャーの版: {0}" -f $Script:LauncherVersion)
Add-Line ("必要なイメージ: {0}" -f $Script:ImageName)
Add-Line ''

# ---------------------------------------------------------------------------
# Windows
# ---------------------------------------------------------------------------
Add-Line '[Windows]'
try {
    $os  = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $cs  = Get-CimInstance Win32_ComputerSystem  -ErrorAction Stop
    # Windows reports the installed RAM minus what the hardware reserves, so
    # a 16 GB machine can show 15.8 GB. Display the exact figure, compare the
    # rounded one.
    $ramText = ConvertTo-GBText $cs.TotalPhysicalMemory
    Add-Line ("  エディション : {0}" -f $os.Caption)
    Add-Line ("  バージョン   : {0} (build {1})" -f $os.Version, $os.BuildNumber)
    Add-Line ("  アーキテクチャ : {0}" -f $env:PROCESSOR_ARCHITECTURE)
    Add-Line ("  CPU コア数   : {0}" -f $env:NUMBER_OF_PROCESSORS)
    Add-Line ("  メモリ       : {0} GB" -f $ramText)
    if ((ConvertTo-RoundedGB $cs.TotalPhysicalMemory) -lt 16) {
        Add-Warning "このパソコンのメモリは $ramText GB です。16 GB 以上を推奨します。"
    }
} catch {
    Add-Line '  (システム情報を取得できませんでした)'
}
Add-Line ("  PowerShell   : {0}" -f $PSVersionTable.PSVersion.ToString())
Add-Line ''

# ---------------------------------------------------------------------------
# Disk space on the system drive
# ---------------------------------------------------------------------------
Add-Line '[ディスク空き容量]'
try {
    $sysDrive = ($env:SystemDrive).TrimEnd(':')
    $vol = Get-Volume -DriveLetter $sysDrive -ErrorAction Stop
    $freeGB = [math]::Round($vol.SizeRemaining / 1GB, 1)
    Add-Line ("  {0} ドライブ  : 空き {1} GB / 全体 {2} GB" -f $sysDrive, $freeGB, [math]::Round($vol.Size / 1GB, 1))
    if ($freeGB -lt $Script:MinFreeDiskGB) {
        Add-Problem ("{0} ドライブの空きが {1} GB しかありません。{2} GB 以上必要です (イメージだけで約 {3} GB 使います)。" -f $sysDrive, $freeGB, $Script:MinFreeDiskGB, $Script:ImageDiskGB)
    }
} catch {
    Add-Line '  (ディスク情報を取得できませんでした)'
}
Add-Line ''

# ---------------------------------------------------------------------------
# WSL2
# ---------------------------------------------------------------------------
# wsl.exe writes its output as UTF-16LE. PowerShell decodes the output of a
# native command with [Console]::OutputEncoding, which is the OEM code page
# (CP932 on a Japanese Windows), so the Japanese parts of the output arrive as
# mojibake ("WSL バージョン" -> "WSL ﾐ0ｼ0ｸ0ｧ0ﾝ0") unless the encoding is
# switched for the duration of the call.
function Invoke-WslText {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $previous = $null
    try { $previous = [Console]::OutputEncoding } catch { }

    $text = ''
    try {
        try { [Console]::OutputEncoding = [System.Text.Encoding]::Unicode } catch { }
        $text = (& wsl @Arguments 2>$null | Out-String)
        # A failing wsl.exe (e.g. "wsl -l -q" with no distribution installed)
        # prints a localised message on stdout; it must not be taken for data.
        if ($LASTEXITCODE -ne 0) { $text = '' }
    } catch {
        $text = ''
    } finally {
        if ($previous) { try { [Console]::OutputEncoding = $previous } catch { } }
    }

    # A recent WSL honours WSL_UTF8=1 and then writes UTF-8 instead; reading
    # that as UTF-16 produces CJK noise with no ASCII in it, so try again.
    if ($text -and ($text -notmatch '[A-Za-z0-9]')) {
        try {
            try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
            $text = (& wsl @Arguments 2>$null | Out-String)
            if ($LASTEXITCODE -ne 0) { $text = '' }
        } catch {
            $text = ''
        } finally {
            if ($previous) { try { [Console]::OutputEncoding = $previous } catch { } }
        }
    }

    # Strip any stray NUL from a mis-decoded UTF-16 stream, and the BOM that
    # wsl.exe puts in front of its output - a leading U+FEFF is invisible but
    # would make the distribution names fail to compare.
    # The BOM is matched with the regex escape '﻿': the string escape
    # "`u{FEFF}" exists only in PowerShell 6+, and 5.1 reads it as the literal
    # text "u{FEFF}", so the BOM was never removed.
    return (($text -replace "`0", '') -replace '﻿', '').Trim()
}

# This section is printed in ENGLISH on purpose. wsl.exe localises its output
# ("WSL バージョン: ..."), and that Japanese text arrives mis-decoded on a
# Japanese Windows (see the note on Invoke-WslText above). Only ASCII values
# are shown here - version numbers and distribution names - so the section is
# readable whatever the console code page is.
Add-Line '[WSL2]'
if (Get-Command wsl -ErrorAction SilentlyContinue) {
    # "wsl --version" prints one localised label per line, each ending in a
    # version number; the first two lines are the WSL version and the kernel
    # version. Only the numbers are taken, so the labels never matter.
    $versionText = Invoke-WslText @('--version')
    $versions = @([regex]::Matches($versionText, '\d+(\.\d+){2,3}') | ForEach-Object { $_.Value })
    if ($versions.Count -ge 1) {
        Add-Line ("  WSL version    : {0}" -f $versions[0])
        if ($versions.Count -ge 2) {
            Add-Line ("  Kernel version : {0}" -f $versions[1])
        }
    } else {
        Add-Line '  WSL version    : not reported (an older WSL build)'
    }

    # "wsl -l -q" lists the names only - no header and no localised state
    # column - and distribution names are ASCII.
    $installed = Invoke-WslText @('-l', '-q')
    $running   = Invoke-WslText @('-l', '--running', '-q')
    if ($installed) {
        $runningList = @($running -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        Add-Line '  Distributions  :'
        foreach ($line in ($installed -split "`r?`n")) {
            $name = $line.Trim()
            if ($name) {
                $state = if ($runningList -contains $name) { 'running' } else { 'stopped' }
                Add-Line ("    {0} ({1})" -f $name, $state)
            }
        }
    } else {
        Add-Line '  Distributions  : none installed'
    }

    # .wslconfig sizes the VM Docker runs in (WSL 2 backend). Values are ASCII.
    $wslConfig = Read-WslConfig
    if (-not (Test-Path -LiteralPath $Script:WslConfigPath)) {
        Add-Line '  .wslconfig     : none (defaults: memory = 50% of RAM, swap = 25% of RAM)'
    } else {
        $setBy = if (Test-WslConfigManaged) { ' (set by 4_Configure_WSL)' } else { '' }
        $wslParts = foreach ($key in @('memory', 'swap', 'processors')) {
            if ($wslConfig[$key]) { '{0}={1}' -f $key, $wslConfig[$key] } else { '{0}=default' -f $key }
        }
        Add-Line ("  .wslconfig     : {0}{1}" -f ($wslParts -join ', '), $setBy)
    }
} else {
    Add-Line '  wsl command not found'
    Add-Warning 'WSL が見つかりませんでした。通常は Docker Desktop が自動でインストールして使用します。'
}
Add-Line ''

# ---------------------------------------------------------------------------
# Docker Desktop
# ---------------------------------------------------------------------------
Add-Line '[Docker]'
if (-not (Test-DockerInstalled)) {
    Add-Line '  docker コマンド: 見つかりません'
    Add-Problem 'Docker Desktop がインストールされていない (または PATH にない) ようです。先にインストールしてください。'
} else {
    $clientVersion = (docker --version 2>$null | Out-String).Trim()
    Add-Line ("  クライアント : {0}" -f $clientVersion)

    # Offer to start Docker Desktop from here. Without a running engine the
    # rest of this section (VM memory, VM disk, whether the image is present)
    # cannot be measured at all, so a report that stops at "not running" tells
    # a tutor almost nothing.
    $dockerWasStarted = $false
    if (-not (Test-DockerRunning)) {
        Write-Host ''
        $answer = Show-Dialog -Buttons 'YesNo' -Icon 'Question' -Message @"
Docker が起動していません。

チェックを最後まで行うには Docker Desktop を起動する必要があります。
いま起動しますか? (最大 $($Script:DockerStartTimeout) 秒かかります)
"@
        if ($answer -eq 'Yes') {
            $dockerWasStarted = Confirm-DockerReady
        } else {
            Write-Warn 'Docker Desktop を起動せずにチェックを続けます。'
        }
    }

    if (-not (Test-DockerRunning)) {
        Add-Line '  エンジン     : 起動していません'
        Add-Problem 'Docker エンジンが起動していません。Docker Desktop を起動してから、もう一度このチェックを実行してください。'
    } else {
        if ($dockerWasStarted) {
            Add-Line '  (このチェックのために Docker Desktop を起動しました)'
        }
        $info = docker info --format '{{.ServerVersion}}|{{.NCPU}}|{{.MemTotal}}|{{.OperatingSystem}}|{{.DockerRootDir}}' 2>$null
        if ($LASTEXITCODE -eq 0 -and $info) {
            $parts = "$info".Trim() -split '\|'
            # Docker subtracts the VM's own overhead from the memory it was
            # given, so 8 GB assigned is reported as 7.9 GB. Show the exact
            # figure, but compare the rounded one - otherwise a correctly
            # configured machine is told to raise a setting already at 8 GB.
            $memText = ConvertTo-GBText $parts[2]
            Add-Line ("  エンジン     : {0}" -f $parts[0])
            Add-Line ("  バックエンド : {0}" -f $parts[3])
            Add-Line ("  仮想マシンの CPU    : {0}" -f $parts[1])
            Add-Line ("  仮想マシンのメモリ  : {0} GB" -f $memText)
            Add-Line ("  データ保存先 : {0}" -f $parts[4])
            # Compared with what 4_Configure_WSL would set on this PC, so that a
            # PC under 16 GB, already warned about above, is not sent to a
            # script that has nothing to raise.
            $ramGB     = Get-InstalledRamGB
            $memTarget = if ($ramGB) { Get-WslMemoryTargetGB -RamGB $ramGB } else { 0 }
            if ((ConvertTo-RoundedGB $parts[2]) -lt $memTarget) {
                # With the WSL 2 backend Docker Desktop's Settings -> Resources
                # has no memory slider; the VM is sized by .wslconfig instead.
                if ((Test-DockerUsesWsl) -eq $false) {
                    Add-Warning ("Docker に割り当てられたメモリが {0} GB しかありません。Docker Desktop の Settings -> Resources -> Advanced で {1} GB 以上に増やしてください。" -f $memText, $memTarget)
                } else {
                    Add-Warning ("Docker に割り当てられたメモリが {0} GB しかありません。「4_Configure_WSL」を実行すると増やせます。" -f $memText)
                }
            }
            if ([int]$parts[1] -lt 4) {
                Add-Warning ("Docker に割り当てられた CPU が {0}個しかありません。4 個以上にすると解析がかなり速くなります。" -f $parts[1])
            }
        }

        # Space inside the Docker VM. This is what actually limits "docker pull",
        # and on Windows it is not the same as the free space on C:.
        Add-Line ''
        Add-Line '  Docker が使えるディスク容量 (Docker の仮想マシン内):'
        $df = docker run --rm --platform linux/amd64 alpine df -P /  2>$null
        if ($LASTEXITCODE -eq 0 -and $df) {
            $dfLine = ($df -split "`r?`n" | Select-Object -Last 1).Trim()
            $cols   = $dfLine -split '\s+'
            if ($cols.Count -ge 4) {
                $availGB = [math]::Round([double]$cols[3] / 1MB, 1)   # df -P reports 1K blocks
                $sizeGB  = [math]::Round([double]$cols[1] / 1MB, 1)
                Add-Line ("    空き {0} GB / 全体 {1} GB" -f $availGB, $sizeGB)
                if ($availGB -lt $Script:MinDockerDiskGB) {
                    Add-Problem ("Docker が使える空き容量が {0} GB しかありません。イメージに約 {1} GB 必要です。Docker Desktop の Settings -> Resources で仮想ディスクの上限を増やすか、'docker system prune -a' で空けてください。" -f $availGB, $Script:ImageDiskGB)
                }
            }
        } else {
            Add-Line '    (測定できませんでした。ネットワークに接続していないか、Docker が小さなテスト用イメージを取得できません)'
            Add-Warning 'Docker が使えるディスク容量を測定できませんでした。ネットワーク接続を確認してください。'
        }

        # Is the tutorial image already here?
        Add-Line ''
        if (Test-ImageExists) {
            $size = docker image inspect $Script:ImageName --format '{{.Size}}' 2>$null
            if ($LASTEXITCODE -eq 0 -and $size) {
                Add-Line ("  チュートリアル用イメージ: ダウンロード済み (ディスク上 {0} GB)" -f [math]::Round([double]$size / 1GB, 1))
            } else {
                Add-Line '  チュートリアル用イメージ: ダウンロード済み'
            }
            Add-Line '                            更新の有無は「1_Download_Image」で確認できます。'
        } else {
            Add-Line ("  チュートリアル用イメージ: 未ダウンロード ({0})" -f $Script:ImageName)
            Add-Line '                            準備ができたら「1_Download_Image」を実行してください。'
        }
    }
}
Add-Line ''

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Add-Line '[判定]'
if ($problems.Count -eq 0 -and $warnings.Count -eq 0) {
    Add-Line '  OK - このパソコンは必要な条件を満たしています。'
} else {
    foreach ($p in $problems) { Add-Line ("  【要対応】{0}" -f $p) }
    foreach ($w in $warnings) { Add-Line ("  【注意】{0}" -f $w) }
}
Add-Line ''

# The report is written as UTF-8 with BOM (what PowerShell 5.1's "UTF8" means),
# so that Notepad and chat clients show the Japanese text correctly.
try {
    $lines | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Host ''
    Write-Ok "結果を保存しました: $reportPath"
} catch {
    Write-Warn "結果ファイルを保存できませんでした: $reportPath"
}

if ($problems.Count -gt 0) {
    Show-Dialog -Icon 'Warning' -Message @"
動作環境チェックで $($problems.Count) 件の問題が見つかりました。

コンソールウィンドウの内容をご確認ください。判断に迷う場合は
abis_check_result.txt をチュートリアルのサポートに送ってください。
"@ | Out-Null
    Exit-WithPause -Code 1
} elseif ($warnings.Count -gt 0) {
    Exit-WithPause -Message 'チェックが終わりました (注意事項があります)。上の内容をご確認ください。' -Code 0
} else {
    Show-Dialog -Message @"
このパソコンは必要な条件を満たしています。

次の手順: 「1_Download_Image」を実行して、チュートリアル環境を
ダウンロードしてください ($($Script:ImageSizeText)、$($Script:ImageTimeText))。
"@ | Out-Null
    Exit-WithPause -Message 'チェックが終わりました。' -Code 0
}
