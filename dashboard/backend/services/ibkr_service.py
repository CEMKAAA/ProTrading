"""
IBKR Data Service
Manages background IBKR data download tasks with progress tracking.
"""

import logging
import uuid
import threading
from datetime import datetime
from pathlib import Path
from typing import Dict, Optional

import pandas as pd

logger = logging.getLogger(__name__)

# In-memory task store for progress tracking
_ibkr_tasks: Dict[str, Dict] = {}
_tasks_lock = threading.Lock()

# CSV output directory (same as data_provider.py)
CSV_DATA_DIR = Path(__file__).parent.parent.parent / "data" / "historical"


class IBKRDataService:
    """Service for managing IBKR data download tasks."""

    @staticmethod
    def start_download(
        symbol: str,
        timeframe: str,
        start_date: str,
        end_date: str,
        port: int = 7497,
    ) -> str:
        """
        Start a background IBKR data download task.
        Returns task_id for progress polling.
        """
        task_id = str(uuid.uuid4())[:8]

        with _tasks_lock:
            _ibkr_tasks[task_id] = {
                "task_id": task_id,
                "status": "pending",
                "progress": 0.0,
                "message": "Starting...",
                "symbol": symbol,
                "timeframe": timeframe,
                "start_date": start_date,
                "end_date": end_date,
                "port": port,
                "started_at": datetime.utcnow().isoformat(),
                "completed_at": None,
                "result": None,
                "error": None,
            }

        # Launch background thread
        thread = threading.Thread(
            target=IBKRDataService._download_task,
            args=(task_id, symbol, timeframe, start_date, end_date, port),
            daemon=True,
        )
        thread.start()

        return task_id

    @staticmethod
    def get_task_status(task_id: str) -> Optional[Dict]:
        """Get current status of a download task."""
        with _tasks_lock:
            task = _ibkr_tasks.get(task_id)
            if task:
                return dict(task)  # Return a copy
        return None

    @staticmethod
    def _update_task(task_id: str, **kwargs):
        """Update task fields thread-safely."""
        with _tasks_lock:
            if task_id in _ibkr_tasks:
                _ibkr_tasks[task_id].update(kwargs)

    @staticmethod
    def _download_task(
        task_id: str,
        symbol: str,
        timeframe: str,
        start_date_str: str,
        end_date_str: str,
        port: int,
    ):
        """Background task that downloads data from IBKR and saves as CSV."""
        from ..core.ibkr_data_provider import IBKRDataProvider

        provider = None

        try:
            IBKRDataService._update_task(task_id, status="running", progress=1.0,
                                         message="Connecting to TWS...")

            # Parse dates
            start_date = datetime.strptime(start_date_str, "%Y-%m-%d")
            end_date = datetime.strptime(end_date_str, "%Y-%m-%d").replace(
                hour=23, minute=59, second=59
            )

            # Connect
            provider = IBKRDataProvider()
            provider.connect(port=port, client_id=99)

            IBKRDataService._update_task(task_id, progress=3.0,
                                         message="Connected. Resolving contract...")

            # Progress callback
            def on_progress(pct: float, msg: str):
                # Scale from 3-97%
                scaled = 3.0 + (pct / 100.0) * 94.0
                IBKRDataService._update_task(task_id, progress=scaled, message=msg)

            # Fetch data
            df = provider.fetch_historical_data(
                symbol=symbol,
                timeframe=timeframe,
                start_date=start_date,
                end_date=end_date,
                progress_callback=on_progress,
            )

            IBKRDataService._update_task(task_id, progress=97.0,
                                         message="Saving CSV file...")

            # Save as tab-separated CSV (same format as MT5 download)
            CSV_DATA_DIR.mkdir(parents=True, exist_ok=True)

            actual_start = df.index.min().strftime("%Y%m%d")
            actual_end = df.index.max().strftime("%Y%m%d")
            filename = f"{symbol}_{timeframe}_{actual_start}_{actual_end}_ibkr.csv"
            csv_path = CSV_DATA_DIR / filename

            csv_df = pd.DataFrame({
                'Date': df.index.strftime('%Y.%m.%d'),
                'Time': df.index.strftime('%H:%M'),
                'Open': df['open'],
                'High': df['high'],
                'Low': df['low'],
                'Close': df['close'],
                'Tickvolume': df['volume'],
                'Volume': df['real_volume'],
                'Spread': df['spread'],
            })

            csv_df.to_csv(str(csv_path), sep='\t', index=False)

            trading_days = df.index.normalize().nunique()

            result = {
                "filename": filename,
                "bars": len(df),
                "start_date": df.index.min().strftime('%Y-%m-%d'),
                "end_date": df.index.max().strftime('%Y-%m-%d'),
                "trading_days": trading_days,
                "size_mb": round(csv_path.stat().st_size / (1024 * 1024), 2),
            }

            IBKRDataService._update_task(
                task_id,
                status="completed",
                progress=100.0,
                message=f"Done! {len(df):,} bars saved to {filename}",
                result=result,
                completed_at=datetime.utcnow().isoformat(),
            )

            logger.info(f"IBKR download task {task_id} completed: {len(df)} bars → {filename}")

        except Exception as e:
            logger.error(f"IBKR download task {task_id} failed: {e}", exc_info=True)
            IBKRDataService._update_task(
                task_id,
                status="error",
                message=str(e),
                error=str(e),
                completed_at=datetime.utcnow().isoformat(),
            )

        finally:
            if provider:
                try:
                    provider.disconnect()
                except Exception:
                    pass

    @staticmethod
    def test_connection(port: int = 7497) -> Dict:
        """Test TWS connectivity."""
        from ..core.ibkr_data_provider import IBKRDataProvider
        provider = IBKRDataProvider()
        return provider.test_connection(port=port)
