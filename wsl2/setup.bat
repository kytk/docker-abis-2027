@echo off
chcp 932 > nul
setlocal

SET DISTRO_NAME=Lin4Neuro
SET TAR_FILE=%~dp0abis-2027-wsl2.tar.gz

REM ============================================================
REM 前提条件の確認
REM ============================================================

REM WSL2 が利用可能か確認
wsl --status >nul 2>&1
if errorlevel 1 (
    echo [エラー] WSL2 がインストールされていません。
    echo 管理者権限の PowerShell で以下を実行してください:
    echo   wsl --install
    pause
    exit /b 1
)

REM tar.gz ファイルの存在確認
if not exist "%TAR_FILE%" (
    echo [エラー] %TAR_FILE% が見つかりません。
    echo setup.bat と abis-2027-wsl2.tar.gz を同じフォルダに配置してください。
    pause
    exit /b 1
)

REM ============================================================
REM インストール先の決定
REM ============================================================

REM デフォルトはバッチファイルと同じドライブ
SET INSTALL_DIR=%~d0\Lin4Neuro

REM ファイルシステムの確認（NTFS を推奨）
SET DRIVE_LETTER=%~d0
SET DRIVE_LETTER=%DRIVE_LETTER:~0,1%
SET FileSystem=
for /f "usebackq tokens=*" %%i in (`powershell -NoProfile -Command "(Get-Volume -DriveLetter '%DRIVE_LETTER%' -ErrorAction SilentlyContinue).FileSystemType"`) do set FileSystem=%%i
if not defined FileSystem (
    echo [情報] ドライブ %~d0 のファイルシステムを確認できませんでした。
    echo そのまま続行します。
) else if /i not "%FileSystem%"=="NTFS" (
    echo [警告] このドライブは %FileSystem% でフォーマットされています。
    echo NTFS でないドライブでは問題が発生する可能性があります。
    echo NTFS でフォーマットされたドライブの使用を強く推奨します。
    echo.
    set /p CONTINUE="続行しますか？ (y/N): "
    if /i not "%CONTINUE%"=="y" (
        echo インストールを中止しました。
        pause
        exit /b 1
    )
)

REM 既存のディストリビューションの確認
wsl -l -q 2>nul | find /i "%DISTRO_NAME%" >nul 2>&1
if not errorlevel 1 (
    echo [警告] %DISTRO_NAME% は既にインストールされています。
    echo 再インストールするには、先に以下を実行してください:
    echo   wsl --unregister %DISTRO_NAME%
    pause
    exit /b 1
)

REM ============================================================
REM インストール実行
REM ============================================================

echo.
echo ============================================
echo  Lin4Neuro WSL2 環境インストール
echo ============================================
echo  インストール元: %TAR_FILE%
echo  インストール先: %INSTALL_DIR%
echo.

wsl --import %DISTRO_NAME% "%INSTALL_DIR%" "%TAR_FILE%"

if errorlevel 1 (
    echo.
    echo [エラー] インストールに失敗しました。
    pause
    exit /b 1
)

echo.
echo ============================================
echo  インストール完了
echo ============================================
echo.
echo  以下の手順で使用を開始できます:
echo.
echo  1. WSL2 を起動:
echo       wsl -d %DISTRO_NAME%
echo.
echo  2. xrdp を起動:
echo       start-xrdp.sh
echo.
echo  3. Windows のリモートデスクトップで接続:
echo       アドレス: localhost:3390
echo       ユーザー名: brain
echo       パスワード: lin4neuro
echo.
pause
