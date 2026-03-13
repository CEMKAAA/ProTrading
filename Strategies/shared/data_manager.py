"""
Shared data management for MT5 price data with caching.
Parameterizable version used by all live strategies.
"""

import MetaTrader5 as mt5
import pandas as pd
from datetime import datetime

# Seconds per bar for each MT5 timeframe constant.
# Some tests monkeypatch a partial MetaTrader5 stub, so build this table
# defensively instead of assuming every timeframe constant exists.
_TIMEFRAME_NAME_TO_SECONDS = {
    "TIMEFRAME_M1": 60,
    "TIMEFRAME_M2": 120,
    "TIMEFRAME_M3": 180,
    "TIMEFRAME_M4": 240,
    "TIMEFRAME_M5": 300,
    "TIMEFRAME_M6": 360,
    "TIMEFRAME_M10": 600,
    "TIMEFRAME_M12": 720,
    "TIMEFRAME_M15": 900,
    "TIMEFRAME_M20": 1200,
    "TIMEFRAME_M30": 1800,
    "TIMEFRAME_H1": 3600,
    "TIMEFRAME_H2": 7200,
    "TIMEFRAME_H3": 10800,
    "TIMEFRAME_H4": 14400,
    "TIMEFRAME_H6": 21600,
    "TIMEFRAME_H8": 28800,
    "TIMEFRAME_H12": 43200,
    "TIMEFRAME_D1": 86400,
    "TIMEFRAME_W1": 604800,
    "TIMEFRAME_MN1": 2592000,
}
TIMEFRAME_SECONDS = {
    tf_value: seconds
    for tf_name, seconds in _TIMEFRAME_NAME_TO_SECONDS.items()
    for tf_value in [getattr(mt5, tf_name, None)]
    if tf_value is not None
}


class DataManager:
    """Handles MT5 data fetching, caching, and timezone conversions."""

    def __init__(self, symbol, broker_tz, ny_tz, timeframe=mt5.TIMEFRAME_M1,
                 cache_bars=5000, logger=None):
        """
        Args:
            symbol: Trading symbol (e.g., 'XAUUSD')
            broker_tz: Broker timezone (pytz)
            ny_tz: New York timezone (pytz)
            timeframe: MT5 timeframe constant
            cache_bars: Number of bars to cache
            logger: Logger instance
        """
        self.symbol = symbol
        self.broker_tz = broker_tz
        self.ny_tz = ny_tz
        self.timeframe = timeframe
        self.cache_bars = cache_bars
        self.data_cache = pd.DataFrame()
        self.logger = logger

    def _log(self, level, msg):
        if self.logger:
            getattr(self.logger, level)(msg)

    def get_data(self, bars=None, force_refresh=False):
        """
        Fetch price data with intelligent caching.

        Args:
            bars: Number of bars to retrieve (defaults to cache_bars)
            force_refresh: Force full data reload

        Returns:
            DataFrame with OHLCV data in NY timezone
        """
        if bars is None:
            bars = self.cache_bars

        if force_refresh:
            self.data_cache = pd.DataFrame()

        if not self.data_cache.empty and not force_refresh:
            return self._update_cache(bars)

        rates = mt5.copy_rates_from_pos(self.symbol, self.timeframe, 0, bars)
        if rates is None or len(rates) == 0:
            self._log('warning', f"No data received for {self.symbol}")
            return pd.DataFrame()

        df = self._convert_to_dataframe(rates)
        self.data_cache = df
        self._log('debug', f"Loaded {len(df)} bars | Last: {df.index[-1]}")
        return df

    def _update_cache(self, bars):
        """Update cache with new bars only."""
        last_time_unix = int(self.data_cache.index[-1].timestamp())
        current_tick = mt5.symbol_info_tick(self.symbol)

        if current_tick is None:
            self._log('warning', "No tick data available")
            return self.data_cache.tail(bars)

        current_unix = current_tick.time

        tf_seconds = TIMEFRAME_SECONDS.get(self.timeframe, 60)
        rates = mt5.copy_rates_range(
            self.symbol,
            self.timeframe,
            last_time_unix + tf_seconds,
            current_unix
        )

        if rates is not None and len(rates) > 0:
            new_df = self._convert_to_dataframe(rates)
            self.data_cache = pd.concat([self.data_cache, new_df]).drop_duplicates()
            self._log('debug', f"Cache updated: +{len(new_df)} bars")

        return self.data_cache.tail(bars)

    def _convert_to_dataframe(self, rates):
        """Convert MT5 rates to timezone-aware DataFrame."""
        df = pd.DataFrame(rates)
        df['time'] = pd.to_datetime(df['time'], unit='s')
        df['time'] = df['time'].dt.tz_localize(self.broker_tz)
        df['time'] = df['time'].dt.tz_convert(self.ny_tz)
        df.set_index('time', inplace=True)
        return df

    def get_session_data(self, start_time, end_time, date=None):
        """
        Get data for a specific session.

        Args:
            start_time: time object for session start
            end_time: time object for session end
            date: date object (defaults to today)

        Returns:
            DataFrame filtered to session
        """
        df = self.get_data()

        if date is None:
            date = df.index[-1].date()

        start = pd.Timestamp.combine(date, start_time).tz_localize(self.ny_tz)
        end = pd.Timestamp.combine(date, end_time).tz_localize(self.ny_tz)

        return df[(df.index >= start) & (df.index < end)]

    def clear_cache(self):
        """Clear data cache (use on new day)."""
        self.data_cache = pd.DataFrame()
        self._log('debug', "Data cache cleared")
