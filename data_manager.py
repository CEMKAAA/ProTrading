"""
Data management for MT5 price data with caching
"""

import MetaTrader5 as mt5
import pandas as pd
from datetime import datetime
import pytz
from logger import logger
from config import TIMEFRAME, DATA_CACHE_BARS


class DataManager:
    """Handles MT5 data fetching, caching, and timezone conversions"""
    
    def __init__(self, symbol, broker_tz, ny_tz):
        self.symbol = symbol
        self.broker_tz = broker_tz
        self.ny_tz = ny_tz
        self.data_cache = pd.DataFrame()
        
    def get_data(self, bars=DATA_CACHE_BARS, force_refresh=False):
        """
        Fetch price data with intelligent caching
        
        Args:
            bars: Number of bars to retrieve
            force_refresh: Force full data reload
            
        Returns:
            DataFrame with OHLCV data in NY timezone
        """
        if force_refresh:
            self.data_cache = pd.DataFrame()
        
        # Update cache incrementally if possible
        if not self.data_cache.empty and not force_refresh:
            return self._update_cache(bars)
        
        # Full fetch
        rates = mt5.copy_rates_from_pos(self.symbol, TIMEFRAME, 0, bars)
        if rates is None or len(rates) == 0:
            logger.warning(f"No data received for {self.symbol}")
            return pd.DataFrame()
        
        df = self._convert_to_dataframe(rates)
        self.data_cache = df
        logger.debug(f"Loaded {len(df)} bars | Last: {df.index[-1]}")
        return df
    
    def _update_cache(self, bars):
        """Update cache with new bars only"""
        last_time_unix = int(self.data_cache.index[-1].timestamp())
        current_tick = mt5.symbol_info_tick(self.symbol)
        
        if current_tick is None:
            logger.warning("No tick data available")
            return self.data_cache.tail(bars)
        
        current_unix = current_tick.time
        
        # Fetch only new bars
        rates = mt5.copy_rates_range(
            self.symbol, 
            TIMEFRAME, 
            last_time_unix + 60, 
            current_unix
        )
        
        if rates is not None and len(rates) > 0:
            new_df = self._convert_to_dataframe(rates)
            self.data_cache = pd.concat([self.data_cache, new_df]).drop_duplicates()
            logger.debug(f"Cache updated: +{len(new_df)} bars")
        
        return self.data_cache.tail(bars)
    
    def _convert_to_dataframe(self, rates):
        """Convert MT5 rates to timezone-aware DataFrame"""
        df = pd.DataFrame(rates)
        df['time'] = pd.to_datetime(df['time'], unit='s')
        df['time'] = df['time'].dt.tz_localize(self.broker_tz)
        df['time'] = df['time'].dt.tz_convert(self.ny_tz)
        df.set_index('time', inplace=True)
        return df
    
    def get_session_data(self, start_time, end_time, date=None):
        """
        Get data for a specific session
        
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
        """Clear data cache (use on new day)"""
        self.data_cache = pd.DataFrame()
        logger.debug("Data cache cleared")
