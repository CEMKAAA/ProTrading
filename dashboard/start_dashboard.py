#!/usr/bin/env python3
"""
ProTrading Dashboard - Startup Script
Run this script to start both backend and frontend servers
"""

import subprocess
import sys
import os
import time
import webbrowser
from pathlib import Path


def check_dependencies():
    """Check and install required dependencies"""
    print("Checking dependencies...")

    backend_deps = [
        'fastapi', 'uvicorn', 'sqlalchemy', 'aiosqlite',
        'pydantic', 'pandas', 'numpy', 'python-dateutil', 'openpyxl'
    ]

    frontend_deps = ['flask', 'requests']

    all_deps = backend_deps + frontend_deps

    for dep in all_deps:
        try:
            __import__(dep.replace('-', '_'))
        except ImportError:
            print(f"Installing {dep}...")
            subprocess.check_call([sys.executable, '-m', 'pip', 'install', '-q', dep])

    print("All dependencies installed!")


def start_backend(dashboard_dir):
    """Start the FastAPI backend server"""
    print("\nStarting Backend Server...")

    # Change to parent directory (ProTradingSystem)
    parent_dir = dashboard_dir.parent

    backend_process = subprocess.Popen(
        [sys.executable, '-m', 'uvicorn', 'dashboard.backend.main:app',
         '--reload', '--host', '0.0.0.0', '--port', '8000'],
        cwd=str(parent_dir),
        creationflags=subprocess.CREATE_NEW_CONSOLE if os.name == 'nt' else 0
    )

    return backend_process


def start_frontend(dashboard_dir):
    """Start the Flask frontend server"""
    print("Starting Frontend Server...")

    frontend_dir = dashboard_dir / 'frontend'

    frontend_process = subprocess.Popen(
        [sys.executable, 'app.py'],
        cwd=str(frontend_dir),
        creationflags=subprocess.CREATE_NEW_CONSOLE if os.name == 'nt' else 0
    )

    return frontend_process


def main():
    print("=" * 50)
    print("  ProTrading Dashboard - Startup")
    print("=" * 50)

    # Get the dashboard directory
    dashboard_dir = Path(__file__).parent.absolute()

    # Create data directory
    data_dir = dashboard_dir / 'data'
    data_dir.mkdir(exist_ok=True)

    # Check dependencies
    check_dependencies()

    # Start servers
    backend_proc = start_backend(dashboard_dir)
    time.sleep(3)  # Wait for backend to initialize

    frontend_proc = start_frontend(dashboard_dir)
    time.sleep(2)  # Wait for frontend to initialize

    print("\n" + "=" * 50)
    print("  Dashboard Started Successfully!")
    print("=" * 50)
    print("\n  Frontend:  http://localhost:5000")
    print("  Backend:   http://localhost:8000")
    print("  API Docs:  http://localhost:8000/docs")
    print("\n  Press Ctrl+C to stop the servers...")

    # Open browser
    time.sleep(1)
    webbrowser.open('http://localhost:5000')

    # Keep running until interrupted
    try:
        while True:
            time.sleep(1)
            # Check if processes are still running
            if backend_proc.poll() is not None:
                print("\nBackend server stopped unexpectedly!")
                break
            if frontend_proc.poll() is not None:
                print("\nFrontend server stopped unexpectedly!")
                break
    except KeyboardInterrupt:
        print("\n\nShutting down servers...")
        backend_proc.terminate()
        frontend_proc.terminate()
        print("Servers stopped.")


if __name__ == '__main__':
    main()
