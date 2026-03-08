"""
Advanced Session Analyzer
Adaptive ORB, bias strength scoring, and proper timezone handling with DST support
"""

import pandas as pd
import numpy as np
from datetime import datetime, time, timedelta, date
from typing import Optional, Dict, Any, Tuple
from dataclasses import dataclass

# Use zoneinfo for proper DST handling (Python 3.9+)
try:
    from zoneinfo import ZoneInfo
except ImportError:
    from backports.zoneinfo import ZoneInfo

from .logger import logger
from .config import get_config


@dataclass
class SessionBias:
    """Session bias with strength scoring"""
    direction: str  # 'bullish', 'bearish', 'neutral'
    strength: int  # 0-100
    reasons: list
    asian_bias: str
    london_bias: str
    orb_bias: str


@dataclass
class ORBData:
    """Opening Range Breakout data"""
    high: float
    low: float
    range_size: float
    is_valid: bool
    is_extended: bool
    extension_minutes: int
    breakout_direction: Optional[str]
    breakout_time: Optional[datetime]


@dataclass
class SessionData:
    """Complete session analysis data"""
    orb: ORBData
    asian_high: float
    asian_low: float
    asian_range: float
    previous_day_high: float
    previous_day_low: float
    bias: SessionBias
    is_trending: bool
    adr: float


class AdvancedSessionAnalyzer:
    """
    Advanced session analysis with:
    - Adaptive ORB window
    - Bias strength scoring (0-100)
    - Proper timezone detection with DST support
    - Multi-session confluence
    - Day-level caching for expensive calculations
    """

    def __init__(self, symbol: str):
        self.symbol = symbol
        self._broker_offset: Optional[int] = None
        self._ny_tz = ZoneInfo("America/New_York")
        self._utc_tz = ZoneInfo("UTC")

        # Day-level caching
        self._cache_date: Optional[date] = None
        self._cached_orb: Optional[ORBData] = None
        self._cached_asian: Optional[Tuple[float, float, float]] = None
        self._cached_pd: Optional[Tuple[float, float]] = None
        self._cached_adr: Optional[float] = None

        self._last_session_data: Optional[SessionData] = None

    def detect_broker_timezone(self, broker_time: datetime) -> int:
        """
        Detect broker's UTC offset by comparing with known UTC time.

        Args:
            broker_time: Timestamp from broker (tick.time)

        Returns:
            Hours offset from UTC
        """
        cfg = get_config()

        # If explicitly configured, use that
        if cfg.broker_utc_offset is not None:
            self._broker_offset = cfg.broker_utc_offset
            return self._broker_offset

        # Calculate offset from current UTC
        utc_now = datetime.now(self._utc_tz).replace(tzinfo=None)
        offset_seconds = (broker_time - utc_now).total_seconds()
        offset_hours = round(offset_seconds / 3600)

        # Sanity check: broker offset should be between -12 and +14
        if -12 <= offset_hours <= 14:
            self._broker_offset = offset_hours
        else:
            # Default to UTC+2 (common for forex brokers)
            logger.warning(f"Unusual broker offset detected: {offset_hours}h, defaulting to UTC+2")
            self._broker_offset = 2

        logger.info(f"Broker timezone detected: UTC{self._broker_offset:+d}")
        return self._broker_offset

    def broker_to_ny_time(self, broker_time: datetime) -> datetime:
        """
        Convert broker time to New York time with proper DST handling.

        Args:
            broker_time: Time in broker's timezone (naive datetime)

        Returns:
            Time in New York timezone (naive datetime for compatibility)
        """
        if self._broker_offset is None:
            self._broker_offset = 2  # Default assumption

        # Convert broker time to UTC first
        utc_time = broker_time - timedelta(hours=self._broker_offset)

        # Make it timezone-aware as UTC
        utc_aware = utc_time.replace(tzinfo=self._utc_tz)

        # Convert to NY time (automatically handles DST)
        ny_aware = utc_aware.astimezone(self._ny_tz)

        # Return naive datetime for compatibility with rest of code
        return ny_aware.replace(tzinfo=None)

    def utc_to_ny_time(self, utc_time: datetime) -> datetime:
        """
        Convert UTC time to New York time with proper DST handling.
        Use this for DataFrame candle timestamps (MT5 rates are UTC).

        Args:
            utc_time: Time in UTC (naive datetime from pd.to_datetime(unit='s'))

        Returns:
            Time in New York timezone (naive datetime for compatibility)
        """
        # Make it timezone-aware as UTC
        utc_aware = utc_time.replace(tzinfo=self._utc_tz)

        # Convert to NY time (automatically handles DST)
        ny_aware = utc_aware.astimezone(self._ny_tz)

        # Return naive datetime for compatibility with rest of code
        return ny_aware.replace(tzinfo=None)

    def convert_df_index_to_ny(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Convert entire DataFrame index from UTC to NY time in one vectorized operation.
        Much faster than calling utc_to_ny_time per candle.

        Args:
            df: DataFrame with UTC timestamps as index

        Returns:
            DataFrame with NY-time index
        """
        if df is None or len(df) == 0:
            return df

        # Convert index to UTC-aware, then to NY, then back to naive
        utc_index = df.index.tz_localize(self._utc_tz)
        ny_index = utc_index.tz_convert(self._ny_tz).tz_localize(None)
        df_copy = df.copy()
        df_copy.index = ny_index
        return df_copy

    def ny_to_broker_time(self, ny_time: datetime) -> datetime:
        """Convert NY time to broker time with DST handling"""
        if self._broker_offset is None:
            self._broker_offset = 2

        # Make NY time aware
        ny_aware = ny_time.replace(tzinfo=self._ny_tz)

        # Convert to UTC
        utc_aware = ny_aware.astimezone(self._utc_tz)

        # Apply broker offset
        broker_time = utc_aware.replace(tzinfo=None) + timedelta(hours=self._broker_offset)

        return broker_time

    def _invalidate_cache_if_new_day(self, ny_time: datetime):
        """Clear cached session data if it's a new day"""
        current_date = ny_time.date()
        if self._cache_date != current_date:
            self._cache_date = current_date
            self._cached_orb = None
            self._cached_asian = None
            self._cached_pd = None
            self._cached_adr = None
            logger.debug(f"Session cache invalidated for new day: {current_date}")

    def clear_daily_cache(self):
        """Explicitly clear all cached session data (call on new trading day)"""
        self._cache_date = None
        self._cached_orb = None
        self._cached_asian = None
        self._cached_pd = None
        self._cached_adr = None
        self._last_session_data = None
        logger.info("Session analyzer cache cleared")

    def calculate_orb(
        self,
        df: pd.DataFrame,
        broker_time: datetime,
        force_recalc: bool = False
    ) -> ORBData:
        """
        Calculate Opening Range Breakout with adaptive window.
        Cached per day - only breakout direction is updated on each call.

        Args:
            df: Price data with NY-time index (converted in _get_data)
            broker_time: Current broker time
            force_recalc: Force recalculation

        Returns:
            ORBData with ORB levels
        """
        cfg = get_config()
        ny_time = self.broker_to_ny_time(broker_time)

        # Check cache - ORB levels don't change intraday
        self._invalidate_cache_if_new_day(ny_time)

        # ORB is only valid after ORB window closes
        orb_end_time = time(cfg.orb_end_hour, cfg.orb_end_minute)
        orb_window_closed = ny_time.time() >= orb_end_time

        if self._cached_orb is not None and not force_recalc and orb_window_closed:
            # Just update breakout direction based on current price
            current_price = df.iloc[-1].close
            orb = self._cached_orb

            if orb.range_size >= cfg.orb_min_range_usd:
                if current_price > orb.high:
                    breakout_direction = 'bullish'
                elif current_price < orb.low:
                    breakout_direction = 'bearish'
                else:
                    breakout_direction = None
            else:
                breakout_direction = None

            return ORBData(
                high=orb.high, low=orb.low, range_size=orb.range_size,
                is_valid=orb.is_valid, is_extended=orb.is_extended,
                extension_minutes=orb.extension_minutes,
                breakout_direction=breakout_direction, breakout_time=orb.breakout_time
            )

        # Standard ORB window
        orb_start = time(cfg.orb_start_hour, cfg.orb_start_minute)
        orb_end = time(cfg.orb_end_hour, cfg.orb_end_minute)

        # Get today's date in NY
        today_ny = ny_time.date()

        # Find ORB candles - DataFrame index is already in NY time
        orb_candles = []
        for i in range(len(df) - 1, max(0, len(df) - 100), -1):
            candle_ny = df.index[i]

            # Handle edge case where index wasn't converted
            if isinstance(candle_ny, (int, float)):
                candle_ny = datetime.utcfromtimestamp(candle_ny)
                candle_ny = self.utc_to_ny_time(candle_ny)
            elif not isinstance(candle_ny, datetime):
                continue

            if candle_ny.date() != today_ny:
                break

            if orb_start <= candle_ny.time() < orb_end:
                orb_candles.append(df.iloc[i])

        if not orb_candles:
            return ORBData(
                high=0, low=0, range_size=0,
                is_valid=False, is_extended=False,
                extension_minutes=0,
                breakout_direction=None, breakout_time=None
            )

        orb_high = max(c.high for c in orb_candles)
        orb_low = min(c.low for c in orb_candles)
        orb_range = orb_high - orb_low

        # Check if we need to extend ORB (adaptive feature)
        is_extended = False
        extension_minutes = 0

        if cfg.use_adaptive_orb and orb_range < cfg.orb_extend_threshold_usd:
            # Calculate extended end time using timedelta to avoid overflow
            orb_end_dt = datetime.combine(today_ny, orb_end)
            extended_end_dt = orb_end_dt + timedelta(minutes=cfg.orb_max_extension_minutes)
            extended_end = extended_end_dt.time()
            original_range = orb_range

            for i in range(len(df) - 1, max(0, len(df) - 100), -1):
                candle_time = df.index[i]
                if isinstance(candle_time, (int, float)):
                    candle_time = datetime.utcfromtimestamp(candle_time)
                    candle_ny = self.utc_to_ny_time(candle_time)
                elif not isinstance(candle_time, datetime):
                    continue
                else:
                    # DataFrame index is already NY time.
                    candle_ny = candle_time

                if candle_ny.date() != today_ny:
                    break

                if orb_end <= candle_ny.time() < extended_end:
                    candle = df.iloc[i]
                    orb_high = max(orb_high, candle.high)
                    orb_low = min(orb_low, candle.low)

            new_range = orb_high - orb_low
            if new_range > orb_range:
                is_extended = True
                extension_minutes = cfg.orb_max_extension_minutes
                orb_range = new_range
                logger.info(f"ORB extended: range ${original_range:.2f} -> ${new_range:.2f}")

        # Check for breakout
        breakout_direction = None
        current_price = df.iloc[-1].close

        if orb_range >= cfg.orb_min_range_usd:
            if current_price > orb_high:
                breakout_direction = 'bullish'
            elif current_price < orb_low:
                breakout_direction = 'bearish'

        result = ORBData(
            high=orb_high,
            low=orb_low,
            range_size=orb_range,
            is_valid=orb_range >= cfg.orb_min_range_usd,
            is_extended=is_extended,
            extension_minutes=extension_minutes,
            breakout_direction=breakout_direction,
            breakout_time=None
        )

        # Cache if ORB window is closed
        if orb_window_closed:
            self._cached_orb = result

        return result

    def calculate_asian_range(
        self,
        df: pd.DataFrame,
        broker_time: datetime,
        force_recalc: bool = False
    ) -> Tuple[float, float, float]:
        """
        Calculate Asian session high/low. Cached per day.

        Args:
            df: Price data with NY-time index (converted in _get_data)

        Returns:
            Tuple of (asian_high, asian_low, range)
        """
        cfg = get_config()
        ny_time = self.broker_to_ny_time(broker_time)

        self._invalidate_cache_if_new_day(ny_time)

        # Return cached if available
        if self._cached_asian is not None and not force_recalc:
            return self._cached_asian

        asian_start = time(cfg.asian_start_hour, cfg.asian_start_minute)
        asian_end = time(cfg.asian_end_hour, cfg.asian_end_minute)

        # Asian session spans midnight, so we need yesterday's date for start
        today_ny = ny_time.date()
        yesterday_ny = today_ny - timedelta(days=1)

        # DataFrame index is already in NY time
        asian_candles = []
        for i in range(len(df) - 1, max(0, len(df) - 500), -1):
            candle_ny = df.index[i]

            # Handle edge case where index wasn't converted
            if isinstance(candle_ny, (int, float)):
                candle_ny = datetime.utcfromtimestamp(candle_ny)
                candle_ny = self.utc_to_ny_time(candle_ny)
            elif not isinstance(candle_ny, datetime):
                continue

            # Asian session: 8pm yesterday to 2am today
            if candle_ny.date() == yesterday_ny and candle_ny.time() >= asian_start:
                asian_candles.append(df.iloc[i])
            elif candle_ny.date() == today_ny and candle_ny.time() < asian_end:
                asian_candles.append(df.iloc[i])

            # Stop if we're before yesterday's Asian start
            if candle_ny.date() < yesterday_ny:
                break

        if not asian_candles:
            return 0, 0, 0

        asian_high = max(c.high for c in asian_candles)
        asian_low = min(c.low for c in asian_candles)

        result = (asian_high, asian_low, asian_high - asian_low)
        self._cached_asian = result

        return result

    def calculate_previous_day(
        self,
        df: pd.DataFrame,
        broker_time: datetime,
        force_recalc: bool = False
    ) -> Tuple[float, float]:
        """
        Calculate previous day's high/low. Cached per day.

        Args:
            df: Price data with NY-time index (converted in _get_data)

        Returns:
            Tuple of (pd_high, pd_low)
        """
        ny_time = self.broker_to_ny_time(broker_time)

        self._invalidate_cache_if_new_day(ny_time)

        if self._cached_pd is not None and not force_recalc:
            return self._cached_pd

        yesterday = ny_time.date() - timedelta(days=1)

        # DataFrame index is already in NY time
        pd_candles = []
        for i in range(len(df) - 1, max(0, len(df) - 2000), -1):
            candle_ny = df.index[i]

            # Handle edge case where index wasn't converted
            if isinstance(candle_ny, (int, float)):
                candle_ny = datetime.utcfromtimestamp(candle_ny)
                candle_ny = self.utc_to_ny_time(candle_ny)
            elif not isinstance(candle_ny, datetime):
                continue

            if candle_ny.date() == yesterday:
                pd_candles.append(df.iloc[i])
            elif candle_ny.date() < yesterday:
                break

        if not pd_candles:
            return 0, 0

        result = (max(c.high for c in pd_candles), min(c.low for c in pd_candles))
        self._cached_pd = result

        return result

    def calculate_bias_strength(
        self,
        current_price: float,
        orb: ORBData,
        asian_high: float,
        asian_low: float,
        pd_high: float,
        pd_low: float,
        atr: float
    ) -> SessionBias:
        """
        Calculate session bias with strength scoring (0-100).
        This runs on every tick as it depends on current price.
        """
        cfg = get_config()

        bullish_score = 0
        bearish_score = 0
        reasons = []

        # ORB Bias (30 points max)
        orb_bias = 'neutral'
        if orb.is_valid and atr > 0:
            if current_price > orb.high:
                orb_bias = 'bullish'
                extension = (current_price - orb.high) / atr
                bullish_score += min(30, int(15 + extension * 15))
                reasons.append(f"Above ORB high (+${current_price - orb.high:.2f})")
            elif current_price < orb.low:
                orb_bias = 'bearish'
                extension = (orb.low - current_price) / atr
                bearish_score += min(30, int(15 + extension * 15))
                reasons.append(f"Below ORB low (-${orb.low - current_price:.2f})")

        # Asian Session Bias (25 points max)
        asian_bias = 'neutral'
        if asian_high > 0 and asian_low > 0 and atr > 0:
            if current_price > asian_high:
                asian_bias = 'bullish'
                extension = (current_price - asian_high) / atr
                bullish_score += min(25, int(12 + extension * 13))
                reasons.append("Above Asian high")
            elif current_price < asian_low:
                asian_bias = 'bearish'
                extension = (asian_low - current_price) / atr
                bearish_score += min(25, int(12 + extension * 13))
                reasons.append("Below Asian low")

        # Previous Day Bias (25 points max)
        london_bias = 'neutral'
        if pd_high > 0 and pd_low > 0:
            if current_price > pd_high:
                london_bias = 'bullish'
                bullish_score += 25
                reasons.append("Above previous day high")
            elif current_price < pd_low:
                london_bias = 'bearish'
                bearish_score += 25
                reasons.append("Below previous day low")
            elif current_price > (pd_high + pd_low) / 2:
                bullish_score += 10
            else:
                bearish_score += 10

        # Determine overall bias
        if bullish_score > bearish_score + 10:
            direction = 'bullish'
            strength = min(100, bullish_score)
        elif bearish_score > bullish_score + 10:
            direction = 'bearish'
            strength = min(100, bearish_score)
        else:
            direction = 'neutral'
            strength = max(bullish_score, bearish_score)

        return SessionBias(
            direction=direction,
            strength=strength,
            reasons=reasons,
            asian_bias=asian_bias,
            london_bias=london_bias,
            orb_bias=orb_bias
        )

    def calculate_adr(self, df: pd.DataFrame, force_recalc: bool = False) -> float:
        """Calculate Average Daily Range. Cached per day."""
        cfg = get_config()

        if self._cached_adr is not None and not force_recalc:
            return self._cached_adr

        daily_ranges = []
        current_date = None
        day_high = 0
        day_low = float('inf')

        for i in range(len(df)):
            candle_time = df.index[i]
            if isinstance(candle_time, (int, float)):
                candle_date = datetime.utcfromtimestamp(candle_time).date()
            elif hasattr(candle_time, 'date'):
                candle_date = candle_time.date()
            else:
                continue

            if current_date != candle_date:
                if current_date is not None and day_high > 0:
                    daily_ranges.append(day_high - day_low)
                current_date = candle_date
                day_high = df.iloc[i].high
                day_low = df.iloc[i].low
            else:
                day_high = max(day_high, df.iloc[i].high)
                day_low = min(day_low, df.iloc[i].low)

        if len(daily_ranges) < cfg.adr_period:
            return 0

        result = float(np.mean(daily_ranges[-cfg.adr_period:]))
        self._cached_adr = result

        return result

    def is_trending(self, adr: float, df: pd.DataFrame) -> bool:
        """Check if market is trending based on ADR and MA."""
        cfg = get_config()

        if adr < cfg.min_adr_for_trend:
            return False

        if cfg.use_ma_confirmation and len(df) >= cfg.ma_period:
            ma = df['close'].tail(cfg.ma_period).mean()
            current_price = df.iloc[-1].close

            deviation = abs(current_price - ma) / ma
            if deviation < 0.002:
                return False

        return True

    def reset_daily_cache(self):
        """Reset all cached session data (call on new day)"""
        self._cache_date = None
        self._cached_orb = None
        self._cached_asian = None
        self._cached_pd = None
        self._cached_adr = None
        logger.info("Session analyzer cache reset")

    def analyze(
        self,
        df: pd.DataFrame,
        broker_time: datetime,
        atr: float
    ) -> SessionData:
        """
        Run complete session analysis with caching.
        Expensive calculations (ORB, Asian, PD, ADR) are cached per day.
        Only bias strength is recalculated on each call.
        """
        if self._broker_offset is None:
            self.detect_broker_timezone(broker_time)

        ny_time = self.broker_to_ny_time(broker_time)
        self._invalidate_cache_if_new_day(ny_time)

        # These are cached per day
        orb = self.calculate_orb(df, broker_time)
        asian_high, asian_low, asian_range = self.calculate_asian_range(df, broker_time)
        pd_high, pd_low = self.calculate_previous_day(df, broker_time)
        adr_value = self.calculate_adr(df)

        current_price = df.iloc[-1].close

        # Bias strength is calculated every time (depends on current price)
        bias = self.calculate_bias_strength(
            current_price, orb,
            asian_high, asian_low,
            pd_high, pd_low,
            atr if atr > 0 else 1.0
        )

        is_trending = self.is_trending(adr_value, df)

        self._last_session_data = SessionData(
            orb=orb,
            asian_high=asian_high,
            asian_low=asian_low,
            asian_range=asian_range,
            previous_day_high=pd_high,
            previous_day_low=pd_low,
            bias=bias,
            is_trending=is_trending,
            adr=adr_value
        )

        return self._last_session_data

    def is_in_trading_window(self, broker_time: datetime) -> Tuple[bool, str]:
        """
        Check if current time is within trading window.
        Includes Friday close logic.

        Returns:
            Tuple of (is_in_window, reason)
        """
        cfg = get_config()
        ny_time = self.broker_to_ny_time(broker_time)

        trade_start = time(cfg.trade_start_hour, cfg.trade_start_minute)
        trade_end = time(cfg.trade_end_hour, cfg.trade_end_minute)

        # Friday close logic - close positions by 3:30 PM NY on Friday
        if ny_time.weekday() == 4:  # Friday
            friday_close = time(15, 30)
            if ny_time.time() >= friday_close:
                return False, "Friday end of week - no new trades"

        # Weekend check
        if ny_time.weekday() >= 5:  # Saturday or Sunday
            return False, "Weekend - market closed"

        # Check for end-of-session close
        if cfg.close_positions_at_session_end:
            close_time = datetime.combine(
                ny_time.date(),
                trade_end
            ) - timedelta(minutes=cfg.session_end_close_minutes_before)

            if ny_time >= close_time:
                return False, "End of session approaching"

        if ny_time.time() < trade_start:
            return False, f"Before trading hours ({trade_start})"

        if ny_time.time() >= trade_end:
            return False, f"After trading hours ({trade_end})"

        return True, "In trading window"
