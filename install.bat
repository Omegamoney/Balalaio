@echo off
setlocal
title Balalaio Installer

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
set "BALALAIO_EXIT=%ERRORLEVEL%"

echo.
if not "%BALALAIO_EXIT%"=="0" (
    echo Installation failed. Review the message above.
) else (
    echo Installation finished successfully.
)
echo.
pause
exit /b %BALALAIO_EXIT%
