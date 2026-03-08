"""
Historical Data Provider for Backtesting
Fetches and manages historical price data from MetaTrader 5 and CSV files.

Supports chunked fetching for long time spans (years of data).
Supports CSV import for extended historical data beyond broker limits.
"""

import MetaTrader5 as mt5
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from typing import Optional, Dict, Any, List, Tuple, Callable
from pathlib import Path
import pytz
import logging
import time
import os
import glob as glob_module

logger = logging.getLogger(__name__)


class HistoricalDataProvider:
    """
    Provides historical market data for backtesting.
    Handles MT5 connection, data fetching, and caching.

    Supports chunked fetching for intraday data to handle long time spans.
    """

    TIMEFRAME_MAP = {
        "M1": mt5.TIMEFRAME_M1,
        "M5": mt5.TIMEFRAME_M5,
        "M15": mt5.TIMEFRAME_M15,
        "M30": mt5.TIMEFRAME_M30,
        "H1": mt5.TIMEFRAME_H1,
        "H4": mt5.TIMEFRAME_H4,
        "D1": mt5.TIMEFRAME_D1,
        "W1": mt5.TIMEFRAME_W1,
        "MN1": mt5.TIMEFRAME_MN1,
    }

    # Chunk sizes for different timeframes (in days)
    CHUNK_SIZES = {
        "M1": 7,     # 1 week chunks for M1 (very granular)
        "M5": 14,    # 2 week chunks for M5
        "M15": 30,   # 1 month chunks for M15
        "M30": 60,   # 2 month chunks for M30
        "H1": 90,    # 3 month chunks for H1
        "H4": 180,   # 6 month chunks for H4
        "D1": 365,   # 1 year chunks for D1
        "W1": 730,   # 2 years for weekly
        "MN1": 1825, # 5 years for monthly
    }

    # CSV data directory (relative to project root)
    CSV_DATA_DIR = Path(__file__).parent.parent.parent / "data" / "historical"

    def __init__(self):
        self.ny_tz = pytz.timezone('America/New_York')
        self.utc_tz = pytz.UTC
        self._data_cache: Dict[str, pd.DataFrame] = {}
        self._negative_cache: set = set()  # Cache keys where data was unavailable
        self._mt5_initialized = False

    def initialize_mt5(self) -> bool:
        """Initialize MT5 connection"""
        if self._mt5_initialized:
            return True

        if not mt5.initialize():
            logger.error(f"MT5 initialization failed: {mt5.last_error()}")
            return False

        # Check if connected to a broker
        account_info = mt5.account_info()
        if account_info is None:
            logger.warning("MT5 initialized but not logged into any account. Please log in to MT5.")
        else:
            logger.info(f"MT5 connected to account: {account_info.login} ({account_info.server})")
            logger.info(f"   Balance: ${account_info.balance:.2f}, Equity: ${account_info.equity:.2f}")

        self._mt5_initialized = True
        logger.info("MT5 initialized successfully")
        return True

    def shutdown_mt5(self):
        """Shutdown MT5 connection"""
        if self._mt5_initialized:
            mt5.shutdown()
            self._mt5_initialized = False
            logger.info("MT5 shutdown complete")

    def get_historical_data(
        self,
        symbol: str,
        timeframe: str,
        start_date: datetime,
        end_date: datetime,
        use_cache: bool = True,
        progress_callback: Optional[Callable[[float, str], None]] = None,
        data_source: str = "auto",
        csv_files: Optional[List[str]] = None,
    ) -> Optional[pd.DataFrame]:
        """
        Fetch historical price data from CSV files and/or MT5.

        Strategy:
        1. Check for CSV data covering the requested range
        2. If CSV covers everything, use it (no MT5 needed)
        3. If CSV covers partial range, fetch remaining from MT5 and merge
        4. If no CSV, fetch entirely from MT5

        Args:
            symbol: Trading symbol (e.g., "XAUUSD")
            timeframe: Timeframe string (M1, M5, M15, etc.)
            start_date: Start datetime
            end_date: End datetime
            use_cache: Whether to use cached data
            progress_callback: Optional callback for progress updates (percent, message)
            data_source: "auto" (MT5+CSV), "csv_only" (imported files only)
            csv_files: Optional list of specific CSV filenames to use (None = auto-discover)

        Returns:
            DataFrame with OHLCV data or None if failed
        """
        csv_key = ",".join(sorted(csv_files)) if csv_files else "all"
        cache_key = f"{symbol}_{timeframe}_{start_date.date()}_{end_date.date()}_{data_source}_{csv_key}"

        if use_cache and cache_key in self._data_cache:
            logger.info(f"Using cached data for {cache_key}")
            return self._data_cache[cache_key]

        # Negative cache: skip repeated probes for known-unavailable data
        if use_cache and cache_key in self._negative_cache:
            logger.debug(f"Negative-cached (no data available): {cache_key}")
            return None

        logger.info(f"=" * 60)
        logger.info(f"FETCHING HISTORICAL DATA")
        logger.info(f"=" * 60)
        logger.info(f"Symbol: {symbol}, Timeframe: {timeframe}, Data Source: {data_source}")
        logger.info(f"Date Range: {start_date.strftime('%Y-%m-%d')} to {end_date.strftime('%Y-%m-%d')}")

        all_dataframes = []

        # Step 1: Try loading CSV data
        csv_df = self._load_csv_data(symbol, timeframe, start_date, end_date, csv_files=csv_files)

        # Step 1b: If no CSV for this timeframe, try resampling from M1
        resampled_from_m1 = False
        if (csv_df is None or csv_df.empty) and timeframe != "M1":
            logger.info(f"No {timeframe} CSV data found, attempting to resample from M1...")
            m1_df = self._load_csv_data(symbol, "M1", start_date, end_date, csv_files=None)
            if m1_df is not None and not m1_df.empty:
                csv_df = self._resample_data(m1_df, timeframe)
                if csv_df is not None and not csv_df.empty:
                    logger.info(f"Resampled M1 -> {timeframe}: {len(csv_df)} bars")
                    resampled_from_m1 = True

        if csv_df is not None and not csv_df.empty:
            logger.info(f"CSV data loaded: {len(csv_df)} bars ({csv_df.index.min()} to {csv_df.index.max()})")
            all_dataframes.append(csv_df)

            if progress_callback:
                progress_callback(5.0, f"CSV data loaded: {len(csv_df)} bars")

        # Step 2: Try MT5 for any gaps or additional data (skip if csv_only)
        # Also skip MT5 if we already resampled from M1 CSV (M1 is our most complete source)
        if data_source == "csv_only" or resampled_from_m1:
            if resampled_from_m1:
                logger.info(f"Using resampled M1 data — skipping redundant MT5 fetch for {timeframe}")
            else:
                logger.info("Data source: csv_only — skipping MT5 fetch")
        else:
            mt5_df = self._fetch_from_mt5(symbol, timeframe, start_date, end_date, progress_callback)
            if mt5_df is not None and not mt5_df.empty:
                logger.info(f"MT5 data loaded: {len(mt5_df)} bars ({mt5_df.index.min()} to {mt5_df.index.max()})")
                all_dataframes.append(mt5_df)

        # Step 3: Combine all data sources
        if not all_dataframes:
            logger.error("No data from CSV or MT5")
            self._log_data_fetch_diagnostics(symbol, start_date, end_date)
            # Negative-cache to avoid repeated expensive probes (WF/Phase01 loops)
            self._negative_cache.add(cache_key)
            return None

        if len(all_dataframes) == 1:
            df = all_dataframes[0]
        else:
            # Merge CSV + MT5, removing duplicates (prefer MT5 for recent data)
            df = pd.concat(all_dataframes)
            df = df[~df.index.duplicated(keep='last')]  # keep='last' = prefer MT5 (appended second)
            df = df.sort_index()
            logger.info(f"Merged data sources: {len(df)} total bars")

        # Filter to requested date range
        start_tz = self.ny_tz.localize(start_date) if start_date.tzinfo is None else start_date
        end_tz = self.ny_tz.localize(end_date) if end_date.tzinfo is None else end_date
        df = df[(df.index >= start_tz) & (df.index <= end_tz)]

        if df.empty:
            logger.error("No data in requested date range after filtering")
            self._negative_cache.add(cache_key)
            return None

        # Cache the data
        self._data_cache[cache_key] = df

        logger.info(f"=" * 60)
        logger.info(f"DATA FETCH COMPLETE: {len(df)} bars loaded")
        logger.info(f"Date range: {df.index.min()} to {df.index.max()}")
        logger.info(f"=" * 60)

        return df

    def _fetch_from_mt5(
        self,
        symbol: str,
        timeframe: str,
        start_date: datetime,
        end_date: datetime,
        progress_callback: Optional[Callable[[float, str], None]] = None
    ) -> Optional[pd.DataFrame]:
        """Fetch data from MT5 (original logic)."""
        if not self.initialize_mt5():
            logger.warning("MT5 not available, skipping MT5 data fetch")
            return None

        # Select symbol
        if not mt5.symbol_select(symbol, True):
            logger.warning(f"Failed to select symbol {symbol} in MT5")
            return None

        # Get timeframe constant
        mt5_timeframe = self.TIMEFRAME_MAP.get(timeframe)
        if mt5_timeframe is None:
            logger.error(f"Invalid timeframe: {timeframe}")
            return None

        # Calculate total days
        total_days = (end_date - start_date).days
        chunk_days = self.CHUNK_SIZES.get(timeframe, 30)

        # Safety cap: limit MT5 fetches to reasonable ranges
        MAX_MT5_DAYS = {
            "M1": 365,      # Max 1 year of M1 (huge data)
            "M5": 730,      # Max 2 years of M5
            "M15": 1095,    # Max 3 years
            "M30": 1825,    # Max 5 years
        }
        max_days = MAX_MT5_DAYS.get(timeframe, 3650)  # Default 10 years for H1+
        if total_days > max_days:
            logger.warning(f"MT5 fetch date range ({total_days} days) exceeds {max_days}-day limit for {timeframe}. Trimming.")
            from datetime import timedelta
            start_date = end_date - timedelta(days=max_days)
            total_days = max_days

        logger.info(f"MT5 fetch: {total_days} days, chunk size: {chunk_days} days")

        # Determine if we need chunking
        if total_days <= chunk_days:
            if progress_callback:
                progress_callback(5.0, "Fetching from MT5...")
            return self._fetch_single_chunk(symbol, mt5_timeframe, start_date, end_date)
        else:
            num_chunks = (total_days // chunk_days) + (1 if total_days % chunk_days > 0 else 0)
            logger.info(f"Fetching in {num_chunks} chunks ({chunk_days} days per chunk)...")
            return self._fetch_chunked_data(
                symbol, mt5_timeframe, timeframe, start_date, end_date,
                chunk_days, progress_callback
            )

    def _fetch_single_chunk(
        self,
        symbol: str,
        mt5_timeframe: int,
        start_date: datetime,
        end_date: datetime
    ) -> Optional[pd.DataFrame]:
        """Fetch data in a single request"""
        # Convert dates to UTC for MT5
        start_utc = self._to_utc(start_date)
        end_utc = self._to_utc(end_date)

        rates = mt5.copy_rates_range(symbol, mt5_timeframe, start_utc, end_utc)

        if rates is None or len(rates) == 0:
            return None

        return self._rates_to_dataframe(rates)

    def _fetch_chunked_data(
        self,
        symbol: str,
        mt5_timeframe: int,
        timeframe_str: str,
        start_date: datetime,
        end_date: datetime,
        chunk_days: int,
        progress_callback: Optional[Callable[[float, str], None]] = None
    ) -> Optional[pd.DataFrame]:
        """
        Fetch data in chunks for long time spans.
        Works backwards from end_date to start_date.
        """
        all_dataframes = []
        current_end = end_date
        total_days = (end_date - start_date).days
        fetched_days = 0
        chunk_num = 0
        consecutive_low_data_chunks = 0  # Track when we hit data boundary
        max_consecutive_low = 3  # Stop after 3 consecutive low-data chunks

        while current_end > start_date:
            chunk_num += 1
            chunk_start = max(start_date, current_end - timedelta(days=chunk_days))

            # Progress update
            fetched_days = (end_date - chunk_start).days
            progress_pct = min(5.0 + (fetched_days / total_days) * 20.0, 25.0)
            progress_msg = f"Fetching data: {fetched_days}/{total_days} days..."

            if progress_callback:
                progress_callback(progress_pct, progress_msg)

            logger.info(f"  Chunk {chunk_num}: {chunk_start.strftime('%Y-%m-%d')} to {current_end.strftime('%Y-%m-%d')}")

            # Fetch this chunk
            chunk_start_utc = self._to_utc(chunk_start)
            chunk_end_utc = self._to_utc(current_end)

            rates = mt5.copy_rates_range(symbol, mt5_timeframe, chunk_start_utc, chunk_end_utc)

            if rates is not None and len(rates) > 0:
                df_chunk = self._rates_to_dataframe(rates)
                all_dataframes.append(df_chunk)
                logger.info(f"    ✓ Got {len(rates)} bars")

                # Move to next chunk - use the oldest bar's time to avoid gaps
                if len(df_chunk) > 0:
                    oldest_bar_time = df_chunk.index.min().to_pydatetime().replace(tzinfo=None)

                    # Safety check: if we got very few bars (< 100), the broker might have
                    # limited data. Move to chunk_start to avoid infinite loops.
                    if len(rates) < 100:
                        consecutive_low_data_chunks += 1
                        logger.info(f"    ⚠ Limited data ({len(rates)} bars) - consecutive low: {consecutive_low_data_chunks}/{max_consecutive_low}")

                        if consecutive_low_data_chunks >= max_consecutive_low:
                            logger.warning(f"    ⛔ Reached historical data boundary at {chunk_start.strftime('%Y-%m-%d')}")
                            logger.warning(f"       The broker may not have data before this date.")
                            break  # Stop fetching - we've hit the limit of available data

                        # Move by full chunk size to ensure progress
                        current_end = chunk_start
                    else:
                        # Got good data, reset counter
                        consecutive_low_data_chunks = 0
                        # Normal case: use oldest bar time to avoid gaps
                        if oldest_bar_time < current_end - timedelta(hours=1):
                            current_end = oldest_bar_time
                        else:
                            # Oldest bar is too close to current_end, move by chunk size
                            current_end = chunk_start
                else:
                    current_end = chunk_start
            else:
                consecutive_low_data_chunks += 1
                logger.warning(f"    ⚠ No data for this chunk (consecutive: {consecutive_low_data_chunks}/{max_consecutive_low})")

                if consecutive_low_data_chunks >= max_consecutive_low:
                    logger.warning(f"    ⛔ Reached historical data boundary - no more data available before {chunk_start.strftime('%Y-%m-%d')}")
                    break

                # Move backwards by the full chunk to avoid getting stuck
                current_end = chunk_start

            # Small delay to avoid overwhelming MT5
            time.sleep(0.1)

        if not all_dataframes:
            return None

        # Combine all chunks
        df = pd.concat(all_dataframes)

        # Remove duplicates and sort
        df = df[~df.index.duplicated(keep='first')]
        df = df.sort_index()

        logger.info(f"  Combined {len(all_dataframes)} chunks: {len(df)} total bars")

        # Check if we got full date range or partial
        actual_start = df.index.min()
        actual_end = df.index.max()
        if actual_start > self.ny_tz.localize(start_date):
            logger.warning(f"  ⚠ PARTIAL DATA: Requested from {start_date.strftime('%Y-%m-%d')}, "
                          f"but only got data from {actual_start.strftime('%Y-%m-%d')}")
            logger.warning(f"    Your broker may have limited historical data available.")

        return df

    def _to_utc(self, dt: datetime) -> datetime:
        """Convert datetime to UTC for MT5"""
        if dt.tzinfo is not None:
            return dt.astimezone(self.utc_tz)
        else:
            return self.ny_tz.localize(dt).astimezone(self.utc_tz)

    def _rates_to_dataframe(self, rates) -> pd.DataFrame:
        """Convert MT5 rates to DataFrame"""
        df = pd.DataFrame(rates)
        df['time'] = pd.to_datetime(df['time'], unit='s')
        df['time'] = df['time'].dt.tz_localize('UTC').dt.tz_convert(self.ny_tz)
        df.set_index('time', inplace=True)

        # Rename columns for consistency
        df = df.rename(columns={
            'tick_volume': 'volume',
            'real_volume': 'real_volume'
        })

        return df

    def _log_symbol_diagnostics(self, symbol: str):
        """Log diagnostic info when symbol selection fails"""
        logger.error(f"Failed to select symbol {symbol}")

        # Check if account is logged in
        account = mt5.account_info()
        if account is None:
            logger.error("MT5 is not logged into any account! Please open MT5 and log in.")
            return

        # Check symbol info
        symbol_info = mt5.symbol_info(symbol)
        if symbol_info is None:
            logger.error(f"Symbol '{symbol}' not found! Check available symbols in MT5.")
            # Try to list similar symbols
            all_symbols = mt5.symbols_get()
            if all_symbols:
                gold_symbols = [s.name for s in all_symbols if 'XAU' in s.name or 'GOLD' in s.name.upper()]
                if gold_symbols:
                    logger.info(f"Available gold symbols: {gold_symbols[:10]}")
                else:
                    logger.info(f"First 10 symbols: {[s.name for s in all_symbols[:10]]}")

    def _log_data_fetch_diagnostics(self, symbol: str, start_date: datetime, end_date: datetime):
        """Log diagnostic info when data fetch fails"""
        error = mt5.last_error()
        logger.warning(f"No data received for {symbol} from {start_date} to {end_date}")
        logger.warning(f"MT5 last error: {error}")

        # Check if account is logged in
        account = mt5.account_info()
        if account is None:
            logger.error("MT5 is not logged into any account! Please open MT5 and log in.")
        else:
            symbol_info = mt5.symbol_info(symbol)
            if symbol_info is not None:
                logger.info(f"Symbol {symbol} exists, but no data for requested range")
                logger.info(f"Suggestion: Try a more recent date range or check MT5 history settings")

                # Try to get the latest available data point
                rates = mt5.copy_rates_from_pos(symbol, mt5.TIMEFRAME_M1, 0, 10)
                if rates is not None and len(rates) > 0:
                    latest_time = pd.to_datetime(rates[-1]['time'], unit='s')
                    logger.info(f"Latest available data: {latest_time}")

    def get_daily_data(
        self,
        symbol: str,
        start_date: datetime,
        end_date: datetime,
        data_source: str = "auto"
    ) -> Optional[pd.DataFrame]:
        """
        Fetch daily OHLCV data for trend analysis.
        """
        return self.get_historical_data(symbol, "D1", start_date, end_date, data_source=data_source)

    def calculate_adr(
        self,
        df_daily: pd.DataFrame,
        period: int = 5
    ) -> pd.Series:
        """
        Calculate Average Daily Range.

        Args:
            df_daily: Daily OHLCV DataFrame
            period: Number of days for average

        Returns:
            Series of ADR values
        """
        daily_range = df_daily['high'] - df_daily['low']
        return daily_range.rolling(window=period).mean()

    def get_session_data(
        self,
        df: pd.DataFrame,
        session_start: str,
        session_end: str,
        date: datetime
    ) -> pd.DataFrame:
        """
        Extract data for a specific trading session.

        Args:
            df: Full OHLCV DataFrame
            session_start: Start time as HH:MM string
            session_end: End time as HH:MM string
            date: Date to extract session for

        Returns:
            DataFrame filtered to session timeframe
        """
        start_hour, start_min = map(int, session_start.split(':'))
        end_hour, end_min = map(int, session_end.split(':'))

        start_dt = self.ny_tz.localize(
            datetime(date.year, date.month, date.day, start_hour, start_min)
        )
        end_dt = self.ny_tz.localize(
            datetime(date.year, date.month, date.day, end_hour, end_min)
        )

        # Handle overnight sessions (e.g., Asian session)
        if end_dt < start_dt:
            end_dt += timedelta(days=1)

        return df[(df.index >= start_dt) & (df.index < end_dt)]

    def get_previous_day_session(
        self,
        df: pd.DataFrame,
        date: datetime,
        session_start: str = "09:30",
        session_end: str = "16:00"
    ) -> Tuple[Optional[float], Optional[float]]:
        """
        Get previous day's session high and low.

        Returns:
            Tuple of (high, low) or (None, None) if no data
        """
        prev_date = date - timedelta(days=1)
        # Skip weekends
        while prev_date.weekday() >= 5:
            prev_date -= timedelta(days=1)

        session_data = self.get_session_data(df, session_start, session_end, prev_date)

        if session_data.empty:
            return None, None

        return session_data['high'].max(), session_data['low'].min()

    def get_asian_session(
        self,
        df: pd.DataFrame,
        date: datetime,
        asian_start: str = "20:00",
        asian_end: str = "02:00"
    ) -> Tuple[Optional[float], Optional[float]]:
        """
        Get Asian session high and low.
        Asian session spans from previous day 8pm to current day 2am NY time.

        For Monday, we skip back to Friday since there's no Sunday session data.

        Returns:
            Tuple of (high, low) or (None, None) if no data
        """
        prev_date = date - timedelta(days=1)

        # Skip weekends
        while prev_date.weekday() >= 5:
            prev_date -= timedelta(days=1)

        start_hour, start_min = map(int, asian_start.split(':'))
        end_hour, end_min = map(int, asian_end.split(':'))

        start_dt = self.ny_tz.localize(
            datetime(prev_date.year, prev_date.month, prev_date.day, start_hour, start_min)
        )

        if date.weekday() == 0:  # Monday
            end_date = prev_date + timedelta(days=1)
            end_dt = self.ny_tz.localize(
                datetime(end_date.year, end_date.month, end_date.day, end_hour, end_min)
            )
        else:
            end_dt = self.ny_tz.localize(
                datetime(date.year, date.month, date.day, end_hour, end_min)
            )

        session_data = df[(df.index >= start_dt) & (df.index < end_dt)]

        if session_data.empty:
            return None, None

        return session_data['high'].max(), session_data['low'].min()

    def get_london_session(
        self,
        df: pd.DataFrame,
        date: datetime,
        london_start: str = "03:00",
        london_end: str = "12:00"
    ) -> Tuple[Optional[float], Optional[float]]:
        """
        Get London session high and low.

        Returns:
            Tuple of (high, low) or (None, None) if no data
        """
        session_data = self.get_session_data(df, london_start, london_end, date)

        if session_data.empty:
            return None, None

        return session_data['high'].max(), session_data['low'].min()

    def get_orb_levels(
        self,
        df: pd.DataFrame,
        date: datetime,
        orb_start: str = "09:30",
        orb_end: str = "09:45"
    ) -> Tuple[Optional[float], Optional[float]]:
        """
        Get Opening Range Breakout high and low.

        Returns:
            Tuple of (high, low) or (None, None) if insufficient data
        """
        session_data = self.get_session_data(df, orb_start, orb_end, date)

        if session_data.empty or len(session_data) < 5:
            return None, None

        return session_data['high'].max(), session_data['low'].min()

    def calculate_atr(
        self,
        df: pd.DataFrame,
        period: int = 14
    ) -> pd.Series:
        """
        Calculate Average True Range.

        Args:
            df: OHLCV DataFrame
            period: ATR period

        Returns:
            Series of ATR values
        """
        high = df['high']
        low = df['low']
        close = df['close'].shift(1)

        tr1 = high - low
        tr2 = abs(high - close)
        tr3 = abs(low - close)

        tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)

        return tr.rolling(window=period).mean()

    def clear_cache(self):
        """Clear all cached data (positive and negative)"""
        self._data_cache.clear()
        self._negative_cache.clear()
        logger.info("Data cache cleared (positive + negative)")

    # ========================================================================
    # CSV Data Loading
    # ========================================================================

    def _load_csv_data(
        self,
        symbol: str,
        timeframe: str,
        start_date: datetime,
        end_date: datetime,
        csv_files: Optional[List[str]] = None,
    ) -> Optional[pd.DataFrame]:
        """
        Load historical data from CSV files in the data/historical/ directory.

        File naming convention: {SYMBOL}_{TIMEFRAME}*.csv
        Example: XAUUSD_M1_2024.csv, XAUUSD_M1_2024_jan_jun.csv

        Args:
            csv_files: If provided, load only these specific filenames.
                       If None, auto-discover all matching files.

        Supports multiple CSV formats:
        1. MT5 export (tab/comma separated): Date, Time, Open, High, Low, Close, Volume
        2. Generic: datetime, open, high, low, close, volume
        3. With headers auto-detected
        """
        csv_dir = self.CSV_DATA_DIR
        if not csv_dir.exists():
            return None

        # Find matching CSV files
        if csv_files:
            # Use specific files provided by user
            matched_files = []
            for fname in csv_files:
                # Security: reject path traversal attempts
                if '..' in fname or '/' in fname or '\\' in fname:
                    logger.warning(f"  Skipping invalid filename: {fname}")
                    continue
                fpath = csv_dir / fname
                if fpath.exists() and fpath.suffix == '.csv':
                    matched_files.append(fpath)
                else:
                    logger.warning(f"  CSV file not found: {fname}")
            if not matched_files:
                logger.warning(f"None of the specified CSV files were found: {csv_files}")
                return None
            logger.info(f"Using {len(matched_files)} user-selected CSV file(s)")
        else:
            # Auto-discover matching files
            matched_files = self._find_csv_files(symbol, timeframe)
            if not matched_files:
                return None
            logger.info(f"Found {len(matched_files)} CSV file(s) for {symbol}_{timeframe}")

        all_dfs = []
        for csv_path in matched_files:
            try:
                df = self._parse_csv_file(csv_path)
                if df is not None and not df.empty:
                    all_dfs.append(df)
                    logger.info(f"  Loaded {csv_path.name}: {len(df)} bars")
            except Exception as e:
                logger.warning(f"  Failed to parse {csv_path.name}: {e}")

        if not all_dfs:
            return None

        # Combine all CSV files
        combined = pd.concat(all_dfs)
        combined = combined[~combined.index.duplicated(keep='first')]
        combined = combined.sort_index()

        # Filter to requested date range
        start_tz = self.ny_tz.localize(start_date) if start_date.tzinfo is None else start_date
        end_tz = self.ny_tz.localize(end_date) if end_date.tzinfo is None else end_date
        filtered = combined[(combined.index >= start_tz) & (combined.index <= end_tz)]

        if filtered.empty:
            logger.info(f"  CSV data exists but none in requested range {start_date.date()} to {end_date.date()}")
            return None

        return filtered

    # ========================================================================
    # Timeframe Resampling (M1 -> higher timeframes)
    # ========================================================================

    RESAMPLE_RULES = {
        "M5": "5min",
        "M15": "15min",
        "M30": "30min",
        "H1": "1h",
        "H4": "4h",
        "D1": "1D",
    }

    def _resample_data(self, df_m1: pd.DataFrame, target_timeframe: str) -> Optional[pd.DataFrame]:
        """
        Resample M1 data to a higher timeframe (M5, M15, M30, H1, H4, D1).

        Args:
            df_m1: DataFrame with M1 OHLCV data (datetime index)
            target_timeframe: Target timeframe string (e.g. "M15", "H1")

        Returns:
            Resampled DataFrame or None if target timeframe is unsupported
        """
        rule = self.RESAMPLE_RULES.get(target_timeframe)
        if rule is None:
            logger.warning(f"Unsupported resample target: {target_timeframe}")
            return None

        logger.info(f"Resampling {len(df_m1)} M1 bars to {target_timeframe} (rule={rule})")

        resampled = df_m1.resample(rule).agg({
            'open': 'first',
            'high': 'max',
            'low': 'min',
            'close': 'last',
            'volume': 'sum',
        }).dropna(subset=['open'])

        # Copy optional columns if present
        if 'spread' in df_m1.columns:
            resampled['spread'] = df_m1['spread'].resample(rule).mean()
        if 'real_volume' in df_m1.columns:
            resampled['real_volume'] = df_m1['real_volume'].resample(rule).sum()
        if 'tick_volume' in df_m1.columns:
            resampled['tick_volume'] = df_m1['tick_volume'].resample(rule).sum()

        logger.info(f"Resampling complete: {len(resampled)} {target_timeframe} bars")
        return resampled

    def _find_csv_files(self, symbol: str, timeframe: str) -> List[Path]:
        """Find CSV files matching symbol and timeframe."""
        csv_dir = self.CSV_DATA_DIR
        if not csv_dir.exists():
            return []

        # Match patterns: XAUUSD_M1*.csv, xauusd_m1*.csv (case-insensitive)
        pattern = f"{symbol}_{timeframe}*.csv"
        files = list(csv_dir.glob(pattern))

        # Also try lowercase
        if not files:
            pattern_lower = f"{symbol.lower()}_{timeframe.lower()}*.csv"
            files = list(csv_dir.glob(pattern_lower))

        # Also try uppercase
        if not files:
            pattern_upper = f"{symbol.upper()}_{timeframe.upper()}*.csv"
            files = list(csv_dir.glob(pattern_upper))

        # Also match any file containing the symbol and timeframe
        if not files:
            all_csvs = list(csv_dir.glob("*.csv"))
            sym_lower = symbol.lower()
            tf_lower = timeframe.lower()
            files = [f for f in all_csvs
                     if sym_lower in f.name.lower() and tf_lower in f.name.lower()]

        return sorted(files)

    def _parse_csv_file(self, csv_path: Path) -> Optional[pd.DataFrame]:
        """
        Parse a CSV file with auto-detection of format.

        Supports:
        1. MT5 export: tab-separated, Date/Time/Open/High/Low/Close/TickVolume/Volume/Spread
        2. Generic with datetime column: datetime,open,high,low,close,volume
        3. Separate date+time columns: date,time,open,high,low,close,volume
        4. Unix timestamp: timestamp,open,high,low,close,volume
        """
        # Read first few lines to detect format
        with open(csv_path, 'r', encoding='utf-8-sig') as f:
            first_lines = [f.readline() for _ in range(5)]

        # Detect separator
        first_line = first_lines[0].strip()
        if '\t' in first_line:
            sep = '\t'
        elif ';' in first_line:
            sep = ';'
        else:
            sep = ','

        # Detect if first line is header
        has_header = any(keyword in first_line.lower()
                        for keyword in ['date', 'time', 'open', 'high', 'low', 'close', 'volume', 'timestamp'])

        # Read the CSV
        df = pd.read_csv(csv_path, sep=sep, header=0 if has_header else None, encoding='utf-8-sig')

        if df.empty:
            return None

        # Normalize column names
        if has_header:
            df.columns = [c.strip().lower().replace(' ', '_') for c in df.columns]
            return self._parse_csv_with_headers(df)
        else:
            return self._parse_csv_no_headers(df)

    def _parse_csv_with_headers(self, df: pd.DataFrame) -> Optional[pd.DataFrame]:
        """Parse CSV that has header row."""
        # Case 1: MT5 format with <DATE>, <TIME>, etc.
        # Clean angle bracket column names
        df.columns = [c.replace('<', '').replace('>', '') for c in df.columns]

        # Identify datetime columns
        datetime_col = None
        date_col = None
        time_col = None

        for col in df.columns:
            col_lower = col.lower()
            if col_lower in ('datetime', 'date_time', 'timestamp'):
                datetime_col = col
                break
            elif col_lower == 'date':
                date_col = col
            elif col_lower == 'time':
                time_col = col

        # Build datetime index
        if datetime_col:
            df['_datetime'] = pd.to_datetime(df[datetime_col], errors='coerce', utc=True)
        elif date_col and time_col:
            # Combine date + time columns
            date_str = df[date_col].astype(str).str.strip()
            time_str = df[time_col].astype(str).str.strip()
            combined = date_str + ' ' + time_str
            # Date+time without explicit timezone -> assume UTC for consistency.
            df['_datetime'] = pd.to_datetime(combined, format='mixed', dayfirst=False, errors='coerce', utc=True)
        elif date_col:
            df['_datetime'] = pd.to_datetime(df[date_col], errors='coerce', utc=True)
        else:
            # Try first column as datetime
            try:
                df['_datetime'] = pd.to_datetime(df.iloc[:, 0], errors='coerce', utc=True)
            except Exception:
                logger.error("Could not find datetime column in CSV")
                return None

        # Identify OHLCV columns
        col_map = {}
        for col in df.columns:
            col_lower = col.lower()
            if col_lower == 'open':
                col_map['open'] = col
            elif col_lower == 'high':
                col_map['high'] = col
            elif col_lower == 'low':
                col_map['low'] = col
            elif col_lower == 'close':
                col_map['close'] = col
            elif col_lower in ('volume', 'tick_volume', 'tickvolume', 'vol'):
                col_map['volume'] = col
            elif col_lower in ('spread',):
                col_map['spread'] = col

        if not all(k in col_map for k in ['open', 'high', 'low', 'close']):
            logger.error(f"CSV missing required OHLC columns. Found: {list(df.columns)}")
            return None

        # Build result DataFrame
        result = pd.DataFrame({
            'open': pd.to_numeric(df[col_map['open']], errors='coerce'),
            'high': pd.to_numeric(df[col_map['high']], errors='coerce'),
            'low': pd.to_numeric(df[col_map['low']], errors='coerce'),
            'close': pd.to_numeric(df[col_map['close']], errors='coerce'),
        })

        if 'volume' in col_map:
            result['volume'] = pd.to_numeric(df[col_map['volume']], errors='coerce').fillna(0).astype(int)
        else:
            result['volume'] = 0

        if 'spread' in col_map:
            result['spread'] = pd.to_numeric(df[col_map['spread']], errors='coerce').fillna(0)
        else:
            result['spread'] = 0

        result['real_volume'] = 0

        # Preserve all additional columns (strategy-specific features such as
        # earnings_event / iv_front / iv_back / iv30 / rv30 / volume30).
        used_cols = set(col_map.values())
        if datetime_col:
            used_cols.add(datetime_col)
        if date_col:
            used_cols.add(date_col)
        if time_col:
            used_cols.add(time_col)
        used_cols.add('_datetime')

        for col in df.columns:
            if col in used_cols:
                continue
            # Prefer numeric parsing when possible; otherwise keep as-is.
            parsed = pd.to_numeric(df[col], errors='coerce')
            if parsed.notna().sum() >= max(1, int(0.5 * len(df))):
                result[col] = parsed
            else:
                result[col] = df[col]

        # Set datetime index with NY timezone.
        # Use utc=True parsing above to safely handle mixed-offset timestamp strings.
        dt_index = pd.to_datetime(df['_datetime'], errors='coerce', utc=True)
        valid_dt = dt_index.notna()
        if valid_dt.sum() == 0:
            logger.error("CSV has no valid datetime rows after parsing")
            return None
        result = result.loc[valid_dt].copy()
        result.index = dt_index[valid_dt]
        result.index.name = 'time'

        # Convert to NY timezone for unified engine semantics.
        result.index = result.index.tz_convert(self.ny_tz)

        # Drop rows with NaN in OHLC
        result = result.dropna(subset=['open', 'high', 'low', 'close'])

        return result

    def _parse_csv_no_headers(self, df: pd.DataFrame) -> Optional[pd.DataFrame]:
        """Parse CSV without headers by detecting column layout."""
        num_cols = len(df.columns)

        if num_cols < 5:
            logger.error(f"CSV has only {num_cols} columns, need at least 5 (datetime, O, H, L, C)")
            return None

        # Try to detect if first column is date and second is time (MT5 format)
        # MT5 no-header: date, time, open, high, low, close, tickvolume, volume, spread
        first_val = str(df.iloc[0, 0])
        second_val = str(df.iloc[0, 1])

        try:
            # Check if second column looks like a time (HH:MM or HH:MM:SS)
            if ':' in second_val and len(second_val) <= 8:
                # Separate date + time columns
                date_str = df.iloc[:, 0].astype(str).str.strip()
                time_str = df.iloc[:, 1].astype(str).str.strip()
                dt_combined = date_str + ' ' + time_str
                dt_index = pd.to_datetime(dt_combined, format='mixed', dayfirst=False, errors='coerce', utc=True)
                ohlc_start = 2
            else:
                # Single datetime column
                dt_index = pd.to_datetime(df.iloc[:, 0], errors='coerce', utc=True)
                ohlc_start = 1
        except Exception:
            logger.error("Could not parse datetime from CSV first columns")
            return None

        # OHLC(V) columns
        result = pd.DataFrame({
            'open': pd.to_numeric(df.iloc[:, ohlc_start], errors='coerce'),
            'high': pd.to_numeric(df.iloc[:, ohlc_start + 1], errors='coerce'),
            'low': pd.to_numeric(df.iloc[:, ohlc_start + 2], errors='coerce'),
            'close': pd.to_numeric(df.iloc[:, ohlc_start + 3], errors='coerce'),
        })

        if num_cols > ohlc_start + 4:
            result['volume'] = pd.to_numeric(df.iloc[:, ohlc_start + 4], errors='coerce').fillna(0).astype(int)
        else:
            result['volume'] = 0

        if num_cols > ohlc_start + 6:
            result['spread'] = pd.to_numeric(df.iloc[:, ohlc_start + 6], errors='coerce').fillna(0)
        else:
            result['spread'] = 0

        result['real_volume'] = 0

        # Set datetime index
        valid_dt = pd.Series(dt_index).notna().to_numpy()
        if valid_dt.sum() == 0:
            logger.error("CSV has no valid datetime rows after parsing")
            return None
        result = result.loc[valid_dt].copy()
        result.index = dt_index[valid_dt]
        result.index.name = 'time'

        result.index = result.index.tz_convert(self.ny_tz)

        result = result.dropna(subset=['open', 'high', 'low', 'close'])

        return result

    def get_csv_data_info(self) -> List[Dict[str, Any]]:
        """
        List available CSV data files with their date ranges.
        Used by the data management API.
        """
        csv_dir = self.CSV_DATA_DIR
        if not csv_dir.exists():
            return []

        results = []
        for csv_path in sorted(csv_dir.glob("*.csv")):
            try:
                info = self._get_csv_file_info(csv_path)
                if info:
                    results.append(info)
            except Exception as e:
                results.append({
                    'filename': csv_path.name,
                    'size_mb': csv_path.stat().st_size / (1024 * 1024),
                    'error': str(e),
                })

        return results

    def _get_csv_file_info(self, csv_path: Path) -> Optional[Dict[str, Any]]:
        """Get info about a CSV file (date range, bar count, etc.) using a small sample."""
        stat = csv_path.stat()
        size_mb = stat.st_size / (1024 * 1024)

        # Parse symbol/timeframe from filename
        name_parts = csv_path.stem.upper().split('_')
        symbol = name_parts[0] if len(name_parts) >= 1 else 'UNKNOWN'
        timeframe = name_parts[1] if len(name_parts) >= 2 else 'UNKNOWN'

        # Quick read: first and last few rows to get date range
        try:
            df = self._parse_csv_file(csv_path)
            if df is None or df.empty:
                return {
                    'filename': csv_path.name,
                    'symbol': symbol,
                    'timeframe': timeframe,
                    'size_mb': round(size_mb, 2),
                    'bars': 0,
                    'error': 'Could not parse file',
                }

            return {
                'filename': csv_path.name,
                'symbol': symbol,
                'timeframe': timeframe,
                'size_mb': round(size_mb, 2),
                'bars': len(df),
                'start_date': str(df.index.min()),
                'end_date': str(df.index.max()),
                'trading_days': len(df.index.normalize().unique()),
            }
        except Exception as e:
            return {
                'filename': csv_path.name,
                'symbol': symbol,
                'timeframe': timeframe,
                'size_mb': round(size_mb, 2),
                'bars': 0,
                'error': str(e),
            }

    def delete_csv_file(self, filename: str) -> bool:
        """Delete a CSV data file."""
        csv_path = self.CSV_DATA_DIR / filename
        if csv_path.exists() and csv_path.suffix == '.csv':
            csv_path.unlink()
            logger.info(f"Deleted CSV file: {filename}")
            return True
        return False

    def get_symbol_info(self, symbol: str) -> Optional[Dict[str, Any]]:
        """
        Get symbol information from MT5.

        Returns:
            Dictionary with symbol info or None if failed
        """
        if not self.initialize_mt5():
            return None

        info = mt5.symbol_info(symbol)
        if info is None:
            return None

        return {
            'name': info.name,
            'point': info.point,
            'digits': info.digits,
            'spread': info.spread,
            'trade_tick_value': info.trade_tick_value,
            'trade_tick_size': info.trade_tick_size,
            'volume_min': info.volume_min,
            'volume_max': info.volume_max,
            'volume_step': info.volume_step,
            'trade_stops_level': info.trade_stops_level,
        }

    def get_trading_days(
        self,
        df: pd.DataFrame
    ) -> List[datetime]:
        """
        Get list of unique trading days from data.

        Returns:
            List of date objects
        """
        dates = df.index.date
        unique_dates = pd.unique(dates)
        return [datetime.combine(d, datetime.min.time()) for d in unique_dates]

    def validate_data_quality(
        self,
        df: pd.DataFrame,
        min_bars: int = 200
    ) -> Tuple[bool, str]:
        """
        Validate data quality for backtesting.

        Returns:
            Tuple of (is_valid, message)
        """
        if df is None or df.empty:
            return False, "No data available"

        if len(df) < min_bars:
            return False, f"Insufficient data: {len(df)} bars (minimum: {min_bars})"

        # Check for gaps - allow up to 7 days for weekends + holidays
        # (Christmas+New Year can produce 6+ day gaps in equity/index data)
        time_diffs = df.index.to_series().diff()
        max_gap = time_diffs.max()

        if max_gap > timedelta(days=7):
            return False, f"Data has excessive gaps: max gap = {max_gap}"

        # Log warning for gaps > 2 hours (but don't fail)
        if max_gap > timedelta(hours=2):
            logger.warning(f"Data has gaps up to {max_gap} (normal for market close periods)")

        # Check for NaN values
        nan_count = df[['open', 'high', 'low', 'close']].isna().sum().sum()
        if nan_count > 0:
            return False, f"Data contains {nan_count} NaN values"

        return True, "Data quality validated"
