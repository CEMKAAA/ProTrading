"""
Dukascopy Data Service
Manages background Dukascopy data download tasks with progress tracking.
Downloads tick data from Dukascopy's free binary feed and aggregates to M1 candles.
"""

import logging
import uuid
import lzma
import time
import threading
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional

import requests
import urllib3
import pandas as pd
import numpy as np

# Dukascopy uses self-signed SSL certificate
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

logger = logging.getLogger(__name__)

# In-memory task store for progress tracking
_dukascopy_tasks: Dict[str, Dict] = {}
_tasks_lock = threading.Lock()

# CSV output directory (same as other data services)
CSV_DATA_DIR = Path(__file__).resolve().parent.parent.parent / "data" / "historical"

# Dukascopy data feed base URL
BASE_URL = "https://datafeed.dukascopy.com/datafeed"

# Point values for converting integer prices to decimals
POINT_VALUES = {
    "XAUUSD": 1000,      # Gold: 3 decimal places
    "XAGUSD": 100000,    # Silver: 5 decimal places
    "EURUSD": 100000,    # EUR/USD: 5 decimal places
    "GBPUSD": 100000,
    "USDJPY": 1000,      # JPY pairs: 3 decimal places
    "USDCHF": 100000,
    "USA500IDXUSD": 1000,    # S&P 500 index: 3 decimal places
    "USATECHIDXUSD": 1000,   # NASDAQ 100 index: 3 decimal places
}

# Map our internal symbol names to Dukascopy feed names
DUKASCOPY_SYMBOL_MAP = {
    "US500": "USA500IDXUSD",
    "NAS100": "USATECHIDXUSD",
}


class DukascopyDataService:
    """Service for managing Dukascopy data download tasks."""

    @staticmethod
    def start_download(
        symbol: str,
        start_date: str,
        end_date: str,
    ) -> str:
        """
        Start a background Dukascopy data download task.
        Always downloads M1 data (tick → M1 aggregation).
        Returns task_id for progress polling.
        """
        task_id = str(uuid.uuid4())[:8]

        with _tasks_lock:
            _dukascopy_tasks[task_id] = {
                "task_id": task_id,
                "status": "pending",
                "progress": 0.0,
                "message": "Starting...",
                "symbol": symbol,
                "timeframe": "M1",
                "start_date": start_date,
                "end_date": end_date,
                "started_at": datetime.utcnow().isoformat(),
                "completed_at": None,
                "result": None,
                "error": None,
            }

        # Launch background thread
        thread = threading.Thread(
            target=DukascopyDataService._download_task,
            args=(task_id, symbol, start_date, end_date),
            daemon=True,
        )
        thread.start()

        return task_id

    @staticmethod
    def get_task_status(task_id: str) -> Optional[Dict]:
        """Get current status of a download task."""
        with _tasks_lock:
            task = _dukascopy_tasks.get(task_id)
            if task:
                return dict(task)  # Return a copy
        return None

    @staticmethod
    def _update_task(task_id: str, **kwargs):
        """Update task fields thread-safely."""
        with _tasks_lock:
            if task_id in _dukascopy_tasks:
                _dukascopy_tasks[task_id].update(kwargs)

    @staticmethod
    def _download_hour_ticks(
        symbol: str,
        year: int,
        month: int,
        day: int,
        hour: int,
        session: requests.Session,
        point_value: int,
    ) -> Optional[pd.DataFrame]:
        """Download and parse one hour of tick data from Dukascopy.
        Returns a DataFrame with ask/bid/mid/spread columns, or None."""
        # Dukascopy uses 0-based months (January = 00)
        url = f"{BASE_URL}/{symbol}/{year}/{month - 1:02d}/{day:02d}/{hour:02d}h_ticks.bi5"

        try:
            resp = session.get(url, timeout=15)
            if resp.status_code == 404:
                return None
            resp.raise_for_status()

            if len(resp.content) == 0:
                return None

            try:
                data = lzma.decompress(resp.content)
            except lzma.LZMAError:
                return None

            if len(data) == 0:
                return None

            tick_size = 20
            num_ticks = len(data) // tick_size
            if num_ticks == 0:
                return None

            # Vectorized parsing via numpy (10-100x faster than per-tick loop)
            usable = num_ticks * tick_size
            arr = np.frombuffer(data[:usable], dtype=np.dtype('>i4,>i4,>i4,>f4,>f4'))
            ms_offsets = arr['f0'].astype(np.int64)
            ask_prices = arr['f1'].astype(np.float64) / point_value
            bid_prices = arr['f2'].astype(np.float64) / point_value
            ask_vols = arr['f3'].astype(np.float64)
            bid_vols = arr['f4'].astype(np.float64)

            base_ts = np.datetime64(f'{year:04d}-{month:02d}-{day:02d}T{hour:02d}:00:00', 'ms')
            timestamps = base_ts + ms_offsets.astype('timedelta64[ms]')

            df = pd.DataFrame({
                'ask': ask_prices,
                'bid': bid_prices,
                'ask_vol': ask_vols,
                'bid_vol': bid_vols,
            }, index=pd.DatetimeIndex(timestamps))
            df['mid'] = (df['ask'] + df['bid']) * 0.5
            df['spread'] = df['ask'] - df['bid']
            return df

        except requests.exceptions.RequestException:
            return None
        except Exception:
            return None

    @staticmethod
    def _day_ticks_to_m1_candles(tick_dfs: List[pd.DataFrame]) -> pd.DataFrame:
        """Aggregate hourly tick DataFrames into M1 OHLCV candles using mid price."""
        if not tick_dfs:
            return pd.DataFrame()

        combined = pd.concat(tick_dfs)
        candles = combined['mid'].resample('1min').agg(
            open='first', high='max', low='min', close='last',
        ).dropna()
        candles['volume'] = combined['ask_vol'].resample('1min').sum()
        candles['spread'] = combined['spread'].resample('1min').mean()

        return candles

    @staticmethod
    def _download_task(
        task_id: str,
        symbol: str,
        start_date_str: str,
        end_date_str: str,
    ):
        """Background task that downloads tick data from Dukascopy and saves as M1 CSV."""
        try:
            DukascopyDataService._update_task(
                task_id, status="running", progress=1.0,
                message="Connecting to Dukascopy..."
            )

            start_date = datetime.strptime(start_date_str, "%Y-%m-%d")
            end_date = datetime.strptime(end_date_str, "%Y-%m-%d")

            # Map internal symbol to Dukascopy feed symbol
            feed_symbol = DUKASCOPY_SYMBOL_MAP.get(symbol, symbol)
            point_value = POINT_VALUES.get(feed_symbol, 100000)

            # Setup session
            session = requests.Session()
            session.verify = False
            session.headers.update({
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
            })

            # Count total weekdays for progress
            total_days = 0
            d = start_date
            while d <= end_date:
                if d.weekday() < 5:
                    total_days += 1
                d += timedelta(days=1)

            if total_days == 0:
                raise ValueError("No trading days in selected range")

            DukascopyDataService._update_task(
                task_id, progress=2.0,
                message=f"Downloading {total_days} trading days of {symbol} M1 data..."
            )

            all_candles = []
            current_date = start_date
            day_count = 0
            bars_total = 0

            while current_date <= end_date:
                if current_date.weekday() < 5:  # Mon-Fri
                    # Download all 24 hours for this day
                    hour_dfs = []
                    for hour in range(24):
                        tick_df = DukascopyDataService._download_hour_ticks(
                            feed_symbol, current_date.year, current_date.month,
                            current_date.day, hour, session, point_value
                        )
                        if tick_df is not None:
                            hour_dfs.append(tick_df)

                    day_candles = DukascopyDataService._day_ticks_to_m1_candles(hour_dfs)
                    if not day_candles.empty:
                        all_candles.append(day_candles)
                        bars_total += len(day_candles)

                    day_count += 1
                    # Scale progress from 2% to 95%
                    pct = 2.0 + (day_count / total_days) * 93.0

                    if day_count % 5 == 0:
                        DukascopyDataService._update_task(
                            task_id, progress=round(pct, 1),
                            message=(
                                f"Day {day_count}/{total_days} | "
                                f"{current_date.strftime('%Y-%m-%d')} | "
                                f"{bars_total:,} bars"
                            )
                        )

                    # Rate limiting
                    time.sleep(0.05)

                current_date += timedelta(days=1)

            if not all_candles:
                raise ValueError(
                    "No data downloaded. Check: VPN is enabled (Dukascopy may be blocked in your region), "
                    "symbol is valid, date range has trading days."
                )

            DukascopyDataService._update_task(
                task_id, progress=96.0,
                message="Merging and saving CSV file..."
            )

            # Combine all candles
            combined = pd.concat(all_candles)
            combined = combined[~combined.index.duplicated(keep='first')]
            combined = combined.sort_index()

            # Save as MT5-compatible CSV
            CSV_DATA_DIR.mkdir(parents=True, exist_ok=True)

            actual_start = combined.index.min().strftime("%Y%m%d")
            actual_end = combined.index.max().strftime("%Y%m%d")
            filename = f"{symbol}_M1_{actual_start}_{actual_end}_dukascopy.csv"
            csv_path = CSV_DATA_DIR / filename

            # Write MT5-compatible tab-separated format
            # Determine decimal precision based on symbol
            price_decimals = 5  # Default for forex
            if symbol in ("XAUUSD", "XAGUSD") or "IDX" in feed_symbol:
                price_decimals = 3  # Gold, Silver, Indices (USA500IDXUSD, USTECH100IDXUSD)
            elif "JPY" in symbol:
                price_decimals = 3  # JPY pairs

            # Vectorized CSV writing (avoids slow per-row Python loop)
            out = combined.copy()
            out.insert(0, 'Date', out.index.strftime('%Y.%m.%d'))
            out.insert(1, 'Time', out.index.strftime('%H:%M'))
            spread_mult = 10 ** price_decimals
            out['Spread'] = (out['spread'] * spread_mult).round().astype(int)
            out['Tickvolume'] = out['volume'].fillna(0).astype(int)
            out['Volume'] = 0
            out = out.rename(columns={
                'open': 'Open', 'high': 'High', 'low': 'Low', 'close': 'Close'
            })
            out = out[['Date', 'Time', 'Open', 'High', 'Low', 'Close',
                        'Tickvolume', 'Volume', 'Spread']]
            out.to_csv(csv_path, sep='\t', index=False,
                       float_format=f'%.{price_decimals}f')

            trading_days = combined.index.normalize().nunique()
            size_mb = round(csv_path.stat().st_size / (1024 * 1024), 2)

            result = {
                "filename": filename,
                "bars": len(combined),
                "start_date": combined.index.min().strftime('%Y-%m-%d'),
                "end_date": combined.index.max().strftime('%Y-%m-%d'),
                "trading_days": trading_days,
                "size_mb": size_mb,
            }

            DukascopyDataService._update_task(
                task_id,
                status="completed",
                progress=100.0,
                message=f"Done! {len(combined):,} bars saved to {filename}",
                result=result,
                completed_at=datetime.utcnow().isoformat(),
            )

            logger.info(f"Dukascopy download task {task_id} completed: {len(combined):,} bars → {filename}")

        except Exception as e:
            logger.error(f"Dukascopy download task {task_id} failed: {e}", exc_info=True)
            DukascopyDataService._update_task(
                task_id,
                status="error",
                message=str(e),
                error=str(e),
                completed_at=datetime.utcnow().isoformat(),
            )

    @staticmethod
    def test_connection(symbol: str = "XAUUSD") -> Dict:
        """Test connectivity to Dukascopy data feed."""
        try:
            session = requests.Session()
            session.verify = False
            session.headers.update({
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
            })

            # Map internal symbol to Dukascopy feed symbol
            feed_symbol = DUKASCOPY_SYMBOL_MAP.get(symbol, symbol)
            # Try downloading a known date with data
            test_url = f"{BASE_URL}/{feed_symbol}/2024/00/02/10h_ticks.bi5"
            resp = session.get(test_url, timeout=10)

            if resp.status_code == 200 and len(resp.content) > 0:
                return {
                    "connected": True,
                    "message": f"Connected! Got {len(resp.content)} bytes from test URL",
                    "symbol": symbol,
                }
            else:
                return {
                    "connected": False,
                    "error": (
                        f"Status {resp.status_code}, {len(resp.content)} bytes. "
                        "Dukascopy may be blocked in your region. Try using a VPN."
                    ),
                }
        except requests.exceptions.ConnectTimeout:
            return {
                "connected": False,
                "error": "Connection timeout. Dukascopy may be blocked in your region. Try using a VPN.",
            }
        except requests.exceptions.ConnectionError as e:
            return {
                "connected": False,
                "error": f"Connection error: {str(e)[:100]}. Try using a VPN.",
            }
        except Exception as e:
            return {
                "connected": False,
                "error": str(e),
            }
