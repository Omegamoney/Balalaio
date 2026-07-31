@echo off
setlocal
title Balalaio Updater

echo Updating Balalaio...
echo Lovely and Steamodded will be left unchanged.
echo.

rem Forward installer options such as -GamePath, -ModsPath, and -NoPrompt.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -SkipDependencies %*
set "BALALAIO_EXIT=%ERRORLEVEL%"

echo.
if not "%BALALAIO_EXIT%"=="0" (
    echo Update failed. Review the message above.
) else (
    echo Balalaio was updated successfully.
)
echo.
pause
exit /b %BALALAIO_EXIT%
