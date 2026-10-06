# Windows Local Launcher

Double-click `start_stratum_web.bat` in the workspace root. It starts the web
panel at http://127.0.0.1:4310/studio and the local control API at port 4321,
then opens the browser. Keep the BAT window open.

Press Ctrl+C in that window to stop the processes started by this launcher.
Already-running services are verified and reused, not killed on shutdown.
MT5, the installation companion and live trading are never started here.

Prerequisites: Node.js 22.13+ in PATH and installed web-mvp dependencies.
Use `start_stratum_web.bat --no-browser` to skip opening the browser.
Fixed startup logs are under `web-mvp/logs/`; no history directories are copied.
