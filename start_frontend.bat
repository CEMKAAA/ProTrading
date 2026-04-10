@echo off
title ProTrading Frontend Launcher
echo ==========================================
echo   ProTrading Frontend - Starting...
echo ==========================================
echo.

where python >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Python is not installed or not in PATH.
    pause
    exit /b 1
)

cd /d "%~dp0"

if not exist "dashboard\frontend\app.py" (
    echo ERROR: Frontend entry file not found: dashboard\frontend\app.py
    pause
    exit /b 1
)

echo Frontend will run on: http://127.0.0.1:5000
echo.
cd /d "%~dp0dashboard\frontend"
python app.py
