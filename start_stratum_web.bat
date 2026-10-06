@echo off
setlocal
title Stratum Web Launcher
echo.
echo ============================================================
echo   Stratum Web Dashboard
echo   Website:   http://127.0.0.1:4310/
echo   Dashboard: http://127.0.0.1:4310/studio
echo   Links become available when the server is ready.
echo   Keep this window open. Press Ctrl+C to stop the server.
echo ============================================================
echo.
where node >nul 2>nul
if errorlevel 1 (
    echo ERROR: Node.js 22.13 or newer must be installed and available in PATH.
    pause
    exit /b 1
)
pushd "%~dp0web-mvp"
if errorlevel 1 (
    echo ERROR: The web-mvp directory could not be opened.
    pause
    exit /b 1
)
node scripts/start-local.mjs %*
set "RESULT=%ERRORLEVEL%"
popd
if not "%RESULT%"=="0" pause
exit /b %RESULT%
