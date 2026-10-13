@echo off
REM 1_Download_Image.bat - Double-click launcher for the ABiS Lin4Neuro tutorial environment.
REM Runs lib\pull_image.ps1; -ExecutionPolicy Bypass applies to this process only and
REM does not change any system setting.
REM
REM Encoding: this file must be Shift-JIS (CP932) with CRLF, so that the
REM Japanese text below is readable in the console (chcp 932 is the default
REM on a Japanese Windows). The .ps1 files are UTF-8 with BOM instead.

title ABiS Lin4Neuro - イメージのダウンロード・更新

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0lib\pull_image.ps1"

REM The PowerShell script pauses on its own. This pause is only reached when
REM PowerShell itself could not be started (errorlevel 9009 = command not found).
if errorlevel 9009 (
    echo.
    echo PowerShell を起動できませんでした。
    echo 講師にご連絡ください。
    pause
)
