@echo off
title ProTrading Dashboard Launcher
echo ==========================================
echo   ProTrading Dashboard - Starting...
echo ==========================================
echo.

:: Check Python installation
where python >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Python is not installed or not in PATH
    echo Please install Python 3.11+ from https://python.org
    pause
    exit /b 1
)

:: Navigate to dashboard directory
cd /d "%~dp0"

:: Create data directory if it doesn't exist
if not exist "data" mkdir data

:: Install backend dependencies if needed
echo Checking backend dependencies...
pip install -q fastapi uvicorn sqlalchemy aiosqlite pydantic pandas numpy python-dateutil openpyxl

:: Install frontend dependencies if needed
echo Checking frontend dependencies...
pip install -q flask requests

echo.
echo ==========================================
echo   Starting Backend Server...
echo ==========================================
echo.

:: Start backend in a new window
start "ProTrading Backend" cmd /k "cd /d %~dp0 && python -m uvicorn dashboard.backend.main:app --reload --host 0.0.0.0 --port 8000"

:: Wait for backend to start
echo Waiting for backend to initialize...
timeout /t 5 /nobreak >nul

echo.
echo ==========================================
echo   Starting Frontend Server...
echo ==========================================
echo.

:: Start frontend in a new window
start "ProTrading Frontend" cmd /k "cd /d %~dp0\frontend && python app.py"

:: Wait for frontend to start
timeout /t 3 /nobreak >nul

echo.
echo ==========================================
echo   Dashboard Started Successfully!
echo ==========================================
echo.
echo   Frontend:  http://localhost:5000
echo   Backend:   http://localhost:8000
echo   API Docs:  http://localhost:8000/docs
echo.
echo   Press any key to open the dashboard...
pause >nul

:: Open browser
start http://localhost:5000

echo.
echo To stop the servers, close the Backend and Frontend windows.
echo.
pause
