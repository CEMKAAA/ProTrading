"""
Shared session level detection for live trading strategies.
Identifies Asian, London, and Previous Day high/low levels.
"""

from datetime import time, timedelta
import pandas as pd

try:
    from dashboard.backend.core.timezone_config import (
        ASIAN_SESSION, LONDON_SESSION,
    )
    ASIAN_START = ASIAN_SESSION.start
    ASIAN_END = ASIAN_SESSION.end
    LONDON_START = LONDON_SESSION.start
    LONDON_END = LONDON_SESSION.end
except ImportError:
    # Fallback when running outside the dashboard package context
    ASIAN_START = time(20, 0)
    ASIAN_END = time(2, 0)
    LONDON_START = time(3, 0)
    LONDON_END = time(12, 0)


class SessionLevelDetector:
    """Detects session-based support/resistance levels."""

    def __init__(self, data_manager, ny_tz):
        """
        Args:
            data_manager: DataManager instance for fetching price data
            ny_tz: New York timezone (pytz)
        """
        self.data_manager = data_manager
        self.ny_tz = ny_tz

    def get_session_levels(self, date):
        """
        Get all session levels for a given trading date.

        Args:
            date: Trading date

        Returns:
            dict with keys: asian_high, asian_low, london_high, london_low,
                           pd_high, pd_low (values may be None)
        """
        levels = {}

        # Asian session (previous day 20:00 to today 02:00)
        asian_data = self._get_session_data(date, ASIAN_START, ASIAN_END,
                                            cross_midnight=True)
        if asian_data is not None and not asian_data.empty:
            levels['asian_high'] = float(asian_data['high'].max())
            levels['asian_low'] = float(asian_data['low'].min())

        # London session (today 03:00 to 12:00)
        london_data = self._get_session_data(date, LONDON_START, LONDON_END)
        if london_data is not None and not london_data.empty:
            levels['london_high'] = float(london_data['high'].max())
            levels['london_low'] = float(london_data['low'].min())

        # Previous day levels
        pd_levels = self._get_previous_day_levels(date)
        levels.update(pd_levels)

        return levels

    def _get_session_data(self, date, start_time, end_time, cross_midnight=False):
        """
        Get price data for a session period.

        Args:
            date: Trading date
            start_time: Session start time
            end_time: Session end time
            cross_midnight: True if session crosses midnight

        Returns:
            DataFrame or None
        """
        df = self.data_manager.get_data()
        if df.empty:
            return None

        if cross_midnight:
            prev_date = date - timedelta(days=1)
            # Skip weekends
            while prev_date.weekday() >= 5:
                prev_date -= timedelta(days=1)
            start = pd.Timestamp.combine(prev_date, start_time).tz_localize(self.ny_tz)
            end = pd.Timestamp.combine(date, end_time).tz_localize(self.ny_tz)
        else:
            start = pd.Timestamp.combine(date, start_time).tz_localize(self.ny_tz)
            end = pd.Timestamp.combine(date, end_time).tz_localize(self.ny_tz)

        return df[(df.index >= start) & (df.index < end)]

    def _get_previous_day_levels(self, date):
        """
        Get previous trading day high/low.

        Args:
            date: Current trading date

        Returns:
            dict with pd_high, pd_low (may be empty)
        """
        prev_date = date - timedelta(days=1)
        # Skip weekends
        while prev_date.weekday() >= 5:
            prev_date -= timedelta(days=1)

        df = self.data_manager.get_data()
        if df.empty:
            return {}

        day_data = df[df.index.date == prev_date]
        if day_data.empty:
            return {}

        return {
            'pd_high': float(day_data['high'].max()),
            'pd_low': float(day_data['low'].min()),
        }
