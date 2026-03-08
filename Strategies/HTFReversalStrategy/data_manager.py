"""
Multi-Timeframe Data Manager for HTF Reversal Strategy
Handles data fetching for Monthly, Weekly, Daily, H4, and H1 timeframes
"""

import MetaTrader5 as mt5
import pandas as pd
from datetime import datetime, timedelta
import pytz
from typing import Dict, Optional
from .logger import logger
from .config import (
    HTF_TIMEFRAMES, EXECUTION_TIMEFRAME, ENTRY_TIMEFRAME,
    DATA_CACHE_BARS, SWING_LOOKBACK_MONTHLY, SWING_LOOKBACK_WEEKLY, SWING_LOOKBACK_DAILY
)


class MultiTimeframeDataManager:
    """
    Manages price data across multiple timeframes.
    Provides caching and efficient data updates.
    """

    def __init__(self, symbol: str, broker_tz, ny_tz):
        self.symbol = symbol
        self.broker_tz = broker_tz
        self.ny_tz = ny_tz

        # Data caches for each timeframe
        self.cache: Dict[str, pd.DataFrame] = {
            "monthly": pd.DataFrame(),
            "weekly": pd.DataFrame(),
            "daily": pd.DataFrame(),
            "h4": pd.DataFrame(),
            "h1": pd.DataFrame(),
        }

        self.last_update: Dict[str, datetime] = {}

    def get_data(self, timeframe: str, bars: int = None) -> pd.DataFrame:
        """
        Get price data for specified timeframe.

        Args:
            timeframe: 'monthly', 'weekly', 'daily', 'h4', or 'h1'
            bars: Number of bars to retrieve (uses default if None)

        Returns:
            DataFrame with OHLCV data
        """
        if bars is None:
            bars = self._get_default_bars(timeframe)

        mt5_tf = self._get_mt5_timeframe(timeframe)

        # Check cache validity
        if self._is_cache_valid(timeframe):
            return self.cache[timeframe].tail(bars)

        # Fetch fresh data
        rates = mt5.copy_rates_from_pos(self.symbol, mt5_tf, 0, bars)

        if rates is None or len(rates) == 0:
            logger.warning(f"No data for {self.symbol} on {timeframe}")
            return pd.DataFrame()

        df = self._convert_to_dataframe(rates)
        self.cache[timeframe] = df
        self.last_update[timeframe] = datetime.now()

        logger.debug(f"Loaded {len(df)} bars for {timeframe}")
        return df

    def get_monthly_data(self, bars: int = None) -> pd.DataFrame:
        """Get monthly data for key level detection"""
        return self.get_data("monthly", bars or SWING_LOOKBACK_MONTHLY)

    def get_weekly_data(self, bars: int = None) -> pd.DataFrame:
        """Get weekly data for key level detection"""
        return self.get_data("weekly", bars or SWING_LOOKBACK_WEEKLY)

    def get_daily_data(self, bars: int = None) -> pd.DataFrame:
        """Get daily data for key level detection"""
        return self.get_data("daily", bars or SWING_LOOKBACK_DAILY)

    def get_h4_data(self, bars: int = DATA_CACHE_BARS) -> pd.DataFrame:
        """Get H4 data for consolidation analysis"""
        return self.get_data("h4", bars)

    def get_h1_data(self, bars: int = DATA_CACHE_BARS) -> pd.DataFrame:
        """Get H1 data for entry timing"""
        return self.get_data("h1", bars)

    def _get_mt5_timeframe(self, timeframe: str) -> int:
        """Convert string timeframe to MT5 constant"""
        tf_map = {
            "monthly": mt5.TIMEFRAME_MN1,
            "weekly": mt5.TIMEFRAME_W1,
            "daily": mt5.TIMEFRAME_D1,
            "h4": mt5.TIMEFRAME_H4,
            "h1": mt5.TIMEFRAME_H1,
        }
        return tf_map.get(timeframe, mt5.TIMEFRAME_H4)

    def _get_default_bars(self, timeframe: str) -> int:
        """Get default number of bars for each timeframe"""
        defaults = {
            "monthly": SWING_LOOKBACK_MONTHLY,
            "weekly": SWING_LOOKBACK_WEEKLY,
            "daily": SWING_LOOKBACK_DAILY,
            "h4": 500,
            "h1": 1000,
        }
        return defaults.get(timeframe, 500)

    def _is_cache_valid(self, timeframe: str) -> bool:
        """
        Check if cached data is still valid.
        Cache validity depends on timeframe.
        """
        if self.cache[timeframe].empty:
            return False

        if timeframe not in self.last_update:
            return False

        age = (datetime.now() - self.last_update[timeframe]).total_seconds()

        # Cache expiry times in seconds
        expiry = {
            "monthly": 3600,   # 1 hour
            "weekly": 3600,    # 1 hour
            "daily": 1800,     # 30 minutes
            "h4": 900,         # 15 minutes
            "h1": 300,         # 5 minutes
        }

        return age < expiry.get(timeframe, 300)

    def _convert_to_dataframe(self, rates) -> pd.DataFrame:
        """Convert MT5 rates to timezone-aware DataFrame"""
        df = pd.DataFrame(rates)
        df['time'] = pd.to_datetime(df['time'], unit='s')
        df['time'] = df['time'].dt.tz_localize(self.broker_tz)
        df['time'] = df['time'].dt.tz_convert(self.ny_tz)
        df.set_index('time', inplace=True)
        return df

    def clear_cache(self, timeframe: str = None):
        """Clear cache for specified timeframe or all if None"""
        if timeframe:
            self.cache[timeframe] = pd.DataFrame()
            if timeframe in self.last_update:
                del self.last_update[timeframe]
        else:
            for tf in self.cache:
                self.cache[tf] = pd.DataFrame()
            self.last_update.clear()

        logger.debug(f"Cache cleared: {timeframe or 'all'}")

    def get_current_price(self) -> Optional[float]:
        """Get current bid price"""
        tick = mt5.symbol_info_tick(self.symbol)
        return tick.bid if tick else None

    def get_spread(self) -> Optional[float]:
        """Get current spread"""
        tick = mt5.symbol_info_tick(self.symbol)
        return (tick.ask - tick.bid) if tick else None
