@echo off
setlocal
cd /d "%~dp0"

REM Change this before exposing the service to the internet.
if "%LICENSE_ADMIN_TOKEN%"=="" set "LICENSE_ADMIN_TOKEN=change-me-now"
if "%LICENSE_MANAGER_PORT%"=="" set "LICENSE_MANAGER_PORT=8765"

echo.
echo Starting EA License Manager...
echo URL: http://127.0.0.1:%LICENSE_MANAGER_PORT%
echo Admin token: %LICENSE_ADMIN_TOKEN%
echo.
echo If this will be used remotely, set LICENSE_ADMIN_TOKEN to a strong secret and put the app behind HTTPS.
echo.

python license_manager\app.py
pause
