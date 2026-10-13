# common.ps1 - Shared settings and helper functions for the ABiS Lin4Neuro launcher.
# Dot-sourced by the other scripts in this folder; not meant to be run on its own.
#
# Target: Windows PowerShell 5.1 (the version that ships with Windows 10/11).
#
# Encoding: this file MUST be saved as UTF-8 WITH BOM. Windows PowerShell 5.1
# reads a .ps1 without a BOM using the system ANSI code page (CP932 on a
# Japanese Windows), which would turn every Japanese message into mojibake.
# Comments and identifiers stay in English; only the text shown to the
# participant is Japanese.
#
# Note: $ErrorActionPreference is deliberately left at 'Continue'. With 'Stop',
# any text a native command writes to stderr (docker does this routinely) would
# terminate the script, so every docker call is checked with $LASTEXITCODE.

# =============================================================================
# CONFIGURATION - review this section before distributing to participants
# =============================================================================

# Container image. A FIXED tag (not "latest") so that every participant runs
# byte-for-byte the same environment for the whole season.
$Script:ImageRepo = 'kytk/abis-2027'
$Script:ImageTag  = '26.12'
$Script:ImageName = '{0}:{1}' -f $Script:ImageRepo, $Script:ImageTag

# Shown in the download confirmation dialog. The size is the compressed
# download (measured: 18.3 GB), not the ~38 GB the image occupies on disk.
$Script:ImageSizeText = '約 20 GB'
$Script:ImageTimeText = '40〜60 分'

# Disk space the image needs once unpacked, plus room to work in.
$Script:ImageDiskGB = 38

# Container settings
$Script:ContainerName  = 'abis'
$Script:ContainerShare = '/home/brain/share'   # mount point inside the container
# The container always serves noVNC on 6080 (EXPOSE 6080 in the image); only
# the port on this computer can be changed, e.g. if 6080 is already taken.
$Script:ContainerPort  = 6080
$Script:HostPort       = 6080
$Script:ShmSize        = '2g'                  # the 64MB default is too small for FSL/FreeSurfer

# noVNC. The query parameters skip the settings gear, the Connect button and
# the password prompt, so the desktop appears immediately.
# 127.0.0.1 rather than localhost: localhost can resolve to ::1, which does not
# reach a port published on 127.0.0.1.
$Script:VncPassword = 'lin4neuro'
$Script:VncUrl      = 'http://127.0.0.1:{0}/vnc.html?resize=scale&autoconnect=1&password={1}' -f $Script:HostPort, $Script:VncPassword

# Minimum requirements checked by 0_Check_Environment. The memory assigned to
# the Docker VM is checked against MinDockerMemoryGB, or against
# Get-WslMemoryTargetGB below where that is lower (RAM under 16 GB).
$Script:MinFreeDiskGB     = 100   # free space on the system drive
$Script:MinDockerMemoryGB = 8     # enough for the tutorial; more is not needed
$Script:MinDockerDiskGB   = 60    # space available inside the Docker VM

# Timeouts (seconds)
$Script:DockerStartTimeout    = 180   # Docker Desktop can be slow on first launch
$Script:ContainerReadyTimeout = 180   # until the image reports HEALTHCHECK "healthy"

# Open noVNC in a borderless app window instead of a normal browser tab.
# A normal tab can be closed by accident with Ctrl+W, which hides the session
# view mid-analysis. Set to $false to use the default browser instead.
$Script:OpenInAppMode = $true

# Launcher version, from the VERSION.txt that make_release.sh puts next to the
# .bat files. Absent when the scripts are run from the repository.
$Script:LauncherVersion = 'dev'
try {
    $versionFile = Join-Path (Split-Path -Parent $PSScriptRoot) 'VERSION.txt'
    $versionLine = Select-String -LiteralPath $versionFile -Pattern '^version:\s*(\S+)' -ErrorAction Stop | Select-Object -First 1
    if ($versionLine) { $Script:LauncherVersion = $versionLine.Matches[0].Groups[1].Value }
} catch { }

# =============================================================================
# Console output helpers
# =============================================================================

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Message) Write-Host "    $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "    $Message" -ForegroundColor Yellow }
function Write-Fail { param([string]$Message) Write-Host "    $Message" -ForegroundColor Red }
function Write-Info { param([string]$Message) Write-Host "    $Message" }

function Write-Title {
    param([string]$Title)
    Write-Host ''
    Write-Host "  $Title  " -ForegroundColor White -NoNewline
    Write-Host "(launcher $($Script:LauncherVersion))" -ForegroundColor DarkGray
    Write-Host '  --------------------------------' -ForegroundColor DarkGray
    Write-Host ''
}

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
    Write-Host 'なにかキーを押すとこのウィンドウを閉じます...' -ForegroundColor DarkGray
    try {
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    } catch {
        # Not an interactive console (e.g. run from an IDE) - just return.
        Start-Sleep -Seconds 3
    }
    exit $Code
}

# =============================================================================
# Unit helpers
# =============================================================================

# Bytes -> whole GB, rounded to the nearest one (0.5 always rounds up, unlike
# [math]::Round's default). Used for every comparison against a minimum
# requirement, so that 7.9 GB counts as 8 GB: Docker reports the memory of
# its VM minus the VM's own overhead.
function ConvertTo-RoundedGB {
    param([Parameter(Mandatory)][double]$Bytes)
    return [int][math]::Round($Bytes / 1GB, 0, [System.MidpointRounding]::AwayFromZero)
}

# Bytes -> GB with one decimal, for display only.
function ConvertTo-GBText {
    param([Parameter(Mandatory)][double]$Bytes)
    return ('{0:0.0}' -f ($Bytes / 1GB))
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

# Ask the participant to pick the "share" folder.
# Returns the selected path, or $null if the dialog was cancelled.
function Select-ShareFolder {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description         = '共有フォルダ (share) を選んでください。'
    $dialog.ShowNewFolderButton = $true

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }
    return $null
}

# =============================================================================
# Docker helpers
# =============================================================================

# Is the docker CLI available? Docker Desktop puts it on PATH, but a broken
# PATH is common enough that the standard install location is tried as well.
function Initialize-DockerCli {
    if (Get-Command docker -ErrorAction SilentlyContinue) { return $true }

    $candidates = @(
        (Join-Path $env:ProgramFiles 'Docker\Docker\resources\bin'),
        (Join-Path $env:LOCALAPPDATA 'Docker\Docker\resources\bin')
    )
    foreach ($dir in $candidates) {
        if ($dir -and (Test-Path (Join-Path $dir 'docker.exe'))) {
            $env:Path = "$dir;$env:Path"
            return $true
        }
    }
    return $false
}

function Test-DockerInstalled {
    return (Initialize-DockerCli)
}

# Is the Docker engine actually answering? Docker Desktop's process can be
# running long before the engine is ready, so the server version is queried.
function Test-DockerRunning {
    if (-not (Test-DockerInstalled)) { return $false }
    docker info --format '{{.ServerVersion}}' 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

# Locate Docker Desktop.exe in the usual install locations.
function Get-DockerDesktopPath {
    $candidates = @(
        (Join-Path $env:ProgramFiles        'Docker\Docker\Docker Desktop.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Docker\Docker\Docker Desktop.exe'),
        (Join-Path $env:LOCALAPPDATA        'Docker\Docker Desktop.exe')
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
        Write-Ok 'Docker は起動しています。'
        return $true
    }

    if (-not (Test-DockerInstalled)) {
        Show-Dialog -Icon 'Error' -Message @"
Docker Desktop がインストールされていないようです。

チュートリアルの Wiki に従って Docker Desktop をインストールしてから、
もう一度このスクリプトを実行してください。
"@ | Out-Null
        return $false
    }

    $exe = Get-DockerDesktopPath
    if (-not $exe) {
        Show-Dialog -Icon 'Error' -Message @"
Docker Desktop はインストールされていますが、場所を自動で特定できませんでした。

Docker Desktop を手動で起動し、"Engine running" と表示されるまで待ってから、
もう一度このスクリプトを実行してください。
"@ | Out-Null
        return $false
    }

    Write-Step "Docker Desktop を起動しています (最大 $($Script:DockerStartTimeout) 秒かかります)..."
    Start-Process -FilePath $exe | Out-Null

    # Poll rather than sleeping a fixed amount: startup time varies a lot.
    $deadline = (Get-Date).AddSeconds($Script:DockerStartTimeout)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 3
        if (Test-DockerRunning) {
            Write-Host ''
            Write-Ok 'Docker は起動しています。'
            return $true
        }
        Write-Host '.' -NoNewline
    }
    Write-Host ''

    # A timeout usually means Docker Desktop is waiting for user input
    # (licence agreement, WSL2 update prompt, sign-in screen).
    Show-Dialog -Icon 'Warning' -Message @"
Docker Desktop が $($Script:DockerStartTimeout) 秒以内に起動しませんでした。

Docker Desktop の画面を開き、操作待ちになっていないか確認してください
(使用許諾への同意、WSL の更新、サインインなど)。
"Engine running" と表示されたら、もう一度このスクリプトを実行してください。
"@ | Out-Null
    return $false
}

# Is the expected image present locally?
function Test-ImageExists {
    docker image inspect $Script:ImageName 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

# Image ID of the local copy, or '' if there is none. Comparing the ID before
# and after a pull tells "a newer build was downloaded" from "the local copy
# was already current", without parsing docker's (localised) output.
function Get-ImageId {
    $id = docker image inspect $Script:ImageName --format '{{.Id}}' 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $id) { return '' }
    return ($id | Select-Object -First 1).Trim()
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
    Write-Step '前回のコンテナが残っているので削除します...'
    docker rm -f $Script:ContainerName 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Ok '削除しました。' } else { Write-Warn '削除するものはありませんでした。' }
}

# Quit Docker Desktop. Returns $true if it was asked to stop.
# "docker desktop stop" (Docker Desktop 4.37+) shuts down the app and its WSL
# virtual machine cleanly and waits until it is done. Docker Desktop usually
# sits in the tray with no main window, so CloseMainWindow() below fails and
# the processes are killed, which leaves the VM (vmmem) holding its memory -
# so the process loop is only a fallback for older versions.
function Stop-DockerDesktop {
    if (Test-DockerInstalled) {
        docker desktop stop 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { return $true }
    }
    $stopped = $false
    foreach ($name in @('Docker Desktop', 'com.docker.backend', 'com.docker.build')) {
        $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
        if ($procs) {
            foreach ($p in $procs) {
                if (-not $p.CloseMainWindow()) { $p | Stop-Process -Force -ErrorAction SilentlyContinue }
                $stopped = $true
            }
        }
    }
    return $stopped
}

# Does the running engine use the WSL 2 backend? $true / $false, or $null when
# the engine is not answering. The WSL 2 kernel is "...-microsoft-standard-WSL2";
# the Hyper-V backend runs a "...-linuxkit" kernel.
function Test-DockerUsesWsl {
    if (-not (Test-DockerInstalled)) { return $null }
    $kernel = docker info --format '{{.KernelVersion}}' 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $kernel) { return $null }
    return ("$kernel" -match 'microsoft|WSL2')
}

# =============================================================================
# WSL 2 virtual machine settings (%USERPROFILE%\.wslconfig)
# =============================================================================
# With the WSL 2 backend - the default, and the only one on Windows Home -
# Docker Desktop has no memory or CPU settings of its own: its engine runs in
# the WSL 2 utility VM, which is sized by the [wsl2] section of .wslconfig.
# Defaults when a key is absent: memory = 50 % of RAM, swap = 25 % of RAM,
# processors = all. The file applies to every WSL distribution, and a change
# takes effect only after "wsl --shutdown".

$Script:WslConfigPath   = Join-Path $env:USERPROFILE '.wslconfig'
# The participant's own file, saved before the first change so that it can be
# put back exactly. Absent if there was no .wslconfig to begin with.
$Script:WslConfigBackup = Join-Path $env:USERPROFILE '.wslconfig.abis-backup'
# Written into [wsl2]; its presence means "changed by 4_Configure_WSL".
$Script:WslConfigMarker = '# Set by the ABiS Lin4Neuro launcher (4_Configure_WSL). Run it again to undo.'
$Script:WslReservedGB   = 8   # left to Windows and the browser (RAM >= 16 GB)
$Script:WslMaxMemoryGB  = 32  # no more than this, however much RAM there is
$Script:WslSwapGB       = 8   # lets an 8 GB machine survive a memory peak

# Installed RAM in whole GB (rounded), or $null.
function Get-InstalledRamGB {
    try {
        return (ConvertTo-RoundedGB (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory)
    } catch {
        return $null
    }
}

# Memory to give the WSL VM. Below the recommended 16 GB, half of the RAM
# (the WSL default) so that Windows stays usable; the swap file absorbs peaks.
# From 16 GB, everything but WslReservedGB, at most WslMaxMemoryGB.
#   8 -> 4, 12 -> 6, 16 -> 8, 32 -> 24, 40 and above -> 32
function Get-WslMemoryTargetGB {
    param([Parameter(Mandatory)][int]$RamGB)
    if ($RamGB -lt 16) {
        return [int][math]::Floor($RamGB / 2)
    }
    return [math]::Min($Script:WslMaxMemoryGB, $RamGB - $Script:WslReservedGB)
}

# "12GB", "8192MB", "1.5 GB" -> bytes, or $null if the text is not a size.
function ConvertFrom-WslSize {
    param([string]$Text)
    if (-not ($Text -match '^\s*(\d+(?:\.\d+)?)\s*([KMGT]?)B?\s*$')) { return $null }
    $n = [double]$Matches[1]
    switch ($Matches[2].ToUpper()) {
        'K'     { return $n * 1KB }
        'M'     { return $n * 1MB }
        'G'     { return $n * 1GB }
        'T'     { return $n * 1TB }
        default { return $n }
    }
}

# The [wsl2] keys of .wslconfig as a hashtable with lower-case keys.
# ReadAllLines honours a BOM, so a file saved as UTF-16 by Notepad is read too.
function Read-WslConfig {
    $result = @{}
    if (-not (Test-Path -LiteralPath $Script:WslConfigPath)) { return $result }
    $section = ''
    foreach ($line in [System.IO.File]::ReadAllLines($Script:WslConfigPath)) {
        $t = $line.Trim()
        if ($t -match '^\[(.+)\]$') { $section = $Matches[1].Trim().ToLower(); continue }
        if ($section -ne 'wsl2' -or $t -match '^[#;]') { continue }
        if ($t -match '^([^=]+)=(.*)$') {
            $result[$Matches[1].Trim().ToLower()] = ($Matches[2] -replace '[#;].*$', '').Trim()
        }
    }
    return $result
}

function Test-WslConfigManaged {
    if (-not (Test-Path -LiteralPath $Script:WslConfigPath)) { return $false }
    return ([System.IO.File]::ReadAllLines($Script:WslConfigPath) -contains $Script:WslConfigMarker)
}

# Set memory and swap in [wsl2], leaving every other line of the file as it
# was. Creates the file or the section if needed.
function Set-WslConfig {
    param(
        [Parameter(Mandatory)][int]$MemoryGB,
        [Parameter(Mandatory)][int]$SwapGB
    )
    $lines = New-Object System.Collections.ArrayList
    if (Test-Path -LiteralPath $Script:WslConfigPath) {
        # Back up the participant's own file, once: a second run must not
        # replace the original with a file this script already changed.
        if (-not (Test-WslConfigManaged) -and -not (Test-Path -LiteralPath $Script:WslConfigBackup)) {
            Copy-Item -LiteralPath $Script:WslConfigPath -Destination $Script:WslConfigBackup -ErrorAction Stop
        }
        foreach ($l in [System.IO.File]::ReadAllLines($Script:WslConfigPath)) { [void]$lines.Add($l) }
    }

    $values = [ordered]@{ memory = "$($MemoryGB)GB"; swap = "$($SwapGB)GB" }

    # Find the [wsl2] section, or append one.
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -match '^\[\s*wsl2\s*\]$') { $start = $i; break }
    }
    if ($start -lt 0) {
        if ($lines.Count -gt 0 -and "$($lines[$lines.Count - 1])".Trim()) { [void]$lines.Add('') }
        [void]$lines.Add('[wsl2]')
        $start = $lines.Count - 1
    }
    $end = $lines.Count
    for ($i = $start + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -match '^\[') { $end = $i; break }
    }

    # Replace keys that are already there. Walking backwards keeps the last
    # occurrence and drops earlier duplicates without upsetting the indices.
    $done = @{}
    for ($i = $end - 1; $i -gt $start; $i--) {
        if ($lines[$i] -match '^\s*([A-Za-z]+)\s*=') {
            $key = $Matches[1].ToLower()
            if ($values.Contains($key)) {
                if ($done[$key]) {
                    $lines.RemoveAt($i)
                } else {
                    $lines[$i] = '{0}={1}' -f $key, $values[$key]
                    $done[$key] = $true
                }
            }
        }
    }

    # Marker and missing keys go directly under the section header.
    $pos = $lines.IndexOf($Script:WslConfigMarker)
    if ($pos -lt 0) {
        $lines.Insert($start + 1, $Script:WslConfigMarker)
        $pos = $start + 1
    }
    $pos++
    foreach ($key in $values.Keys) {
        if (-not $done[$key]) {
            $lines.Insert($pos, ('{0}={1}' -f $key, $values[$key]))
            $pos++
        }
    }

    # UTF-8 without BOM. PowerShell 5.1's Out-File / Set-Content would write
    # UTF-16 or ANSI, and WSL cannot read a UTF-16 .wslconfig.
    [System.IO.File]::WriteAllLines($Script:WslConfigPath, [string[]]$lines.ToArray(), (New-Object System.Text.UTF8Encoding($false)))
}

# Undo Set-WslConfig: put the participant's original file back, or remove the
# file if there was none before.
function Restore-WslConfig {
    if (Test-Path -LiteralPath $Script:WslConfigBackup) {
        Copy-Item -LiteralPath $Script:WslConfigBackup -Destination $Script:WslConfigPath -Force -ErrorAction Stop
        Remove-Item -LiteralPath $Script:WslConfigBackup -Force -ErrorAction SilentlyContinue
    } else {
        Remove-Item -LiteralPath $Script:WslConfigPath -Force -ErrorAction Stop
    }
}

# =============================================================================
# Share folder validation
# =============================================================================

# Convert a Windows path to the forward-slash form docker prefers.
function ConvertTo-DockerPath {
    param([Parameter(Mandatory)][string]$Path)
    return ($Path -replace '\\', '/')
}

# Check the selected folder for the problems that are known to cause trouble.
# Returns $true if it is safe to continue.
function Test-ShareFolder {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Show-Dialog -Icon 'Error' -Message "選んだフォルダが見つかりません:`n`n$Path" | Out-Null
        return $false
    }

    # --- File system must be NTFS ---------------------------------------
    # exFAT cannot store POSIX ownership, so everything is mounted as root and
    # the "brain" user inside the container cannot write to it.
    try {
        $driveLetter = (Get-Item -LiteralPath $Path).PSDrive.Name
        if ($driveLetter -and $driveLetter.Length -eq 1) {
            $volume = Get-Volume -DriveLetter $driveLetter -ErrorAction Stop
            if ($volume.FileSystem -and $volume.FileSystem -ne 'NTFS') {
                Show-Dialog -Icon 'Error' -Message @"
選んだドライブは $($volume.FileSystem) 形式ですが、NTFS 形式が必要です。

$($volume.FileSystem) は Linux のファイル所有者情報を保存できないため、
チュートリアルのソフトウェアが共有フォルダに書き込めません。

ドライブの中身をバックアップしてから NTFS で再フォーマットし、
もう一度お試しください。詳しくはチュートリアルの Wiki をご覧ください。

選んだフォルダ: $Path
"@ | Out-Null
                return $false
            }
        }
    } catch {
        # Network drives and some USB enclosures are not reported by Get-Volume.
        Write-Warn 'このドライブのファイルシステム形式を判定できませんでした。処理を続けます。'
    }

    # --- Non-ASCII characters --------------------------------------------
    # Mixed encodings between Windows, the Docker VM and the container are a
    # reliable source of hard-to-diagnose failures.
    if ($Path -match '[^\x20-\x7E]') {
        $answer = Show-Dialog -Buttons 'YesNo' -Icon 'Warning' -Message @"
選んだパスに日本語などの文字が含まれています:

$Path

コンテナの中で問題が起きることがあります。半角の英数字・ハイフン・
アンダースコアだけのパスを強くおすすめします。

このまま続けますか?
"@
        if ($answer -ne 'Yes') { return $false }
    }

    # --- Cloud-synced folders --------------------------------------------
    # Sync clients will try to upload every intermediate file that FreeSurfer
    # and FSL produce, which is slow at best and corrupting at worst.
    # Box Drive is matched as a whole path component ("C:\Users\<name>\Box"):
    # a bare 'Box' with the case-insensitive -match also hit Inbox, Sandbox,
    # VirtualBox and the like.
    if ($Path -match 'OneDrive|Dropbox|Google Drive|iCloud|\\Box( Sync)?(\\|$)') {
        $answer = Show-Dialog -Buttons 'YesNo' -Icon 'Warning' -Message @"
選んだフォルダはクラウド同期フォルダの中にあるようです:

$Path

解析では大量の中間ファイルが作られます。これらが同期されると
パソコンが非常に遅くなり、結果が壊れることもあります。

内蔵ディスクか外付けドライブのフォルダを選び直してください。

このまま続けますか?
"@
        if ($answer -ne 'Yes') { return $false }
    }

    # --- Write test -------------------------------------------------------
    $probe = Join-Path $Path '.abis_write_test'
    try {
        New-Item -Path $probe -ItemType File -Force -ErrorAction Stop | Out-Null
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
    } catch {
        Show-Dialog -Icon 'Error' -Message @"
選んだフォルダに書き込めません:

$Path

外付けドライブの場合、読み取り専用でマウントされている可能性があります。
安全に取り外してから接続し直してみてください。
"@ | Out-Null
        return $false
    }

    Write-Ok "共有フォルダ: $Path"
    return $true
}

# =============================================================================
# Container readiness and browser
# =============================================================================

# Wait until the container reports "healthy". The image ships a HEALTHCHECK
# that passes once the window manager is running AND noVNC serves its page, so
# there is no need to guess a fixed waiting time or to poll the port directly.
function Wait-ForHealthy {
    Write-Step 'Lin4Neuro のデスクトップが起動するのを待っています...'
    $deadline = (Get-Date).AddSeconds($Script:ContainerReadyTimeout)

    while ((Get-Date) -lt $deadline) {
        $status = docker inspect --format '{{.State.Health.Status}}' $Script:ContainerName 2>$null
        if ($LASTEXITCODE -ne 0) {
            # The container disappeared - it died during start-up.
            Write-Host ''
            Write-Fail 'コンテナが予期せず停止しました。'
            return $false
        }
        $status = "$status".Trim()
        if ($status -eq 'healthy') {
            Write-Host ''
            Write-Ok 'デスクトップの準備ができました。'
            return $true
        }
        if ($status -eq 'unhealthy') {
            Write-Host ''
            Write-Fail 'デスクトップを起動できませんでした (コンテナの状態が unhealthy です)。'
            return $false
        }
        Write-Host '.' -NoNewline
        Start-Sleep -Seconds 2
    }

    Write-Host ''
    return $false
}

# Open noVNC. App mode gives a window with no tab bar, so Ctrl+W cannot close
# the session by accident.
function Open-Lin4Neuro {
    Write-Step 'ブラウザで Lin4Neuro を開いています...'

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
                Write-Ok '専用ウィンドウで開きました。'
                return
            }
        }
        Write-Warn 'Edge / Chrome が見つかりませんでした。既定のブラウザで開きます。'
    }

    Start-Process $Script:VncUrl
    Write-Ok '既定のブラウザで開きました。'
}

# Show the tail of the container log. Used when start-up fails, so the
# participant has something concrete to paste into the support chat.
function Show-ContainerLog {
    Write-Host ''
    Write-Step 'コンテナのログ (最後の 50 行):'
    Write-Host '--------------------------------------------------------------'
    docker logs --tail 50 $Script:ContainerName 2>&1 | ForEach-Object { Write-Host $_ }
    Write-Host '--------------------------------------------------------------'
}
