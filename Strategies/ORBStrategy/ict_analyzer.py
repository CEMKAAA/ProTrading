"""
ICT (Inner Circle Trader) Concept Implementation
- Fair Value Gaps (FVG)
- Order Blocks (OB)
- Liquidity Detection & Sweeps
"""

import pandas as pd
import numpy as np
from .logger import logger
from .config import (
    MIN_FVG_GAP, FVG_LOOKBACK, FVG_SCAN_WINDOW,
    DISPLACEMENT_PERCENTILE, DISPLACEMENT_LOOKBACK, MAX_OPPOSING_WICK_RATIO,
    OB_LOOKBACK, OB_MIN_BODY_PERCENT, OB_VALIDATION_BARS,
    LIQUIDITY_WICK_RATIO, SWEEP_TOLERANCE_USD
)


class ICTAnalyzer:
    """Advanced ICT pattern recognition"""

    @staticmethod
    def find_fvg(df, direction='bullish'):
        """
        Detect Fair Value Gap (3-candle imbalance) with backward scan.

        Bullish FVG: Gap between c1.high and c3.low (c2 jumps up)
        Bearish FVG: Gap between c1.low and c3.high (c2 drops down)

        Args:
            df: DataFrame with OHLC data
            direction: 'bullish' or 'bearish'

        Returns:
            dict with FVG info or None
        """
        if len(df) < 4:
            return None

        max_window = max(3, min(FVG_LOOKBACK, len(df) - 3))
        scan_window = min(max_window, FVG_SCAN_WINDOW)

        # offset=0 means the most recent completed 3-candle group
        for offset in range(scan_window):
            c3_idx = len(df) - 2 - offset
            if c3_idx < 2:
                break
            c1 = df.iloc[c3_idx - 2]
            c2 = df.iloc[c3_idx - 1]
            c3 = df.iloc[c3_idx]
            sub_df = df.iloc[: c3_idx + 1]

            if direction == 'bullish':
                gap = c3.low - c1.high
                if gap > MIN_FVG_GAP and ICTAnalyzer._has_displacement(sub_df, c2, 'bullish'):
                    # Skip stale/filled FVGs.
                    bars_after = df.iloc[c3_idx + 1:-1]
                    if not bars_after.empty and bars_after['low'].min() < c1.high:
                        continue
                    return {
                        'type': 'bullish_fvg',
                        'top': c3.low,
                        'bottom': c1.high,
                        'size': gap,
                        'time': c2.name,
                        'entry_zone': (c1.high, c3.low)
                    }

            elif direction == 'bearish':
                gap = c1.low - c3.high
                if gap > MIN_FVG_GAP and ICTAnalyzer._has_displacement(sub_df, c2, 'bearish'):
                    # Skip stale/filled FVGs.
                    bars_after = df.iloc[c3_idx + 1:-1]
                    if not bars_after.empty and bars_after['high'].max() > c1.low:
                        continue
                    return {
                        'type': 'bearish_fvg',
                        'top': c1.low,
                        'bottom': c3.high,
                        'size': gap,
                        'time': c2.name,
                        'entry_zone': (c3.high, c1.low)
                    }

        return None

    @staticmethod
    def _has_displacement(df, candle, direction):
        """
        Check if candle shows strong displacement

        Criteria:
        - Body size exceeds percentile threshold
        - Minimal opposing wick

        Args:
            df: Full dataframe for context
            candle: Specific candle to check
            direction: 'bullish' or 'bearish'

        Returns:
            bool
        """
        # Get recent body sizes for comparison
        recent = df.iloc[-DISPLACEMENT_LOOKBACK-3:-3]
        if len(recent) < 5:
            return False

        recent_bodies = (recent['close'] - recent['open']).abs()
        threshold = recent_bodies.quantile(DISPLACEMENT_PERCENTILE / 100.0)

        if direction == 'bullish':
            body = candle.close - candle.open
            if body <= 0:
                return False
            opposing_wick = candle.high - candle.close

        else:  # bearish
            body = candle.open - candle.close
            if body <= 0:
                return False
            opposing_wick = candle.close - candle.low

        # Check criteria
        strong_body = body >= threshold
        small_wick = opposing_wick < (body * MAX_OPPOSING_WICK_RATIO)

        return strong_body and small_wick

    @staticmethod
    def find_order_block(df, direction='bullish'):
        """
        Identify the last order block

        Order Block = Last down-candle before strong up-move (bullish)
                      Last up-candle before strong down-move (bearish)

        Criteria:
        - Strong body (>60% of range)
        - Followed by impulse move in opposite direction
        - Not yet violated

        Args:
            df: DataFrame with OHLC data
            direction: 'bullish' or 'bearish'

        Returns:
            dict with OB info or None
        """
        if len(df) < OB_LOOKBACK:
            return None

        scan_range = df.iloc[-OB_LOOKBACK:-2]  # Exclude last 2 candles

        for i in range(len(scan_range) - OB_VALIDATION_BARS - 1, -1, -1):
            candle = scan_range.iloc[i]
            candle_range = candle.high - candle.low

            if candle_range < 0.10:  # Skip tiny candles
                continue

            if direction == 'bullish':
                # Last bearish candle before bullish impulse
                body = candle.open - candle.close
                if body <= 0:
                    continue

                body_percent = (body / candle_range) * 100
                if body_percent < OB_MIN_BODY_PERCENT:
                    continue

                # Check next bars for bullish impulse
                next_bars = scan_range.iloc[i+1:i+1+OB_VALIDATION_BARS]
                if len(next_bars) < OB_VALIDATION_BARS:
                    continue

                bullish_impulse = (next_bars['close'] > candle.high).sum() >= 2
                not_violated = df.iloc[-10:]['low'].min() > candle.low

                if bullish_impulse and not_violated:
                    return {
                        'type': 'bullish_ob',
                        'high': candle.high,
                        'low': candle.low,
                        'body_pct': body_percent,
                        'time': candle.name,
                        'entry_zone': (candle.low, candle.close)
                    }

            elif direction == 'bearish':
                # Last bullish candle before bearish impulse
                body = candle.close - candle.open
                if body <= 0:
                    continue

                body_percent = (body / candle_range) * 100
                if body_percent < OB_MIN_BODY_PERCENT:
                    continue

                next_bars = scan_range.iloc[i+1:i+1+OB_VALIDATION_BARS]
                if len(next_bars) < OB_VALIDATION_BARS:
                    continue

                bearish_impulse = (next_bars['close'] < candle.low).sum() >= 2
                not_violated = df.iloc[-10:]['high'].max() < candle.high

                if bearish_impulse and not_violated:
                    return {
                        'type': 'bearish_ob',
                        'high': candle.high,
                        'low': candle.low,
                        'body_pct': body_percent,
                        'time': candle.name,
                        'entry_zone': (candle.close, candle.high)
                    }

        return None

    @staticmethod
    def detect_liquidity_sweep(df, level_price, level_type='high'):
        """
        Check if price swept a liquidity level (high/low)

        Sweep = Price pushed beyond level then reversed quickly

        Args:
            df: DataFrame with recent data
            level_price: The high/low being tested
            level_type: 'high' or 'low'

        Returns:
            bool
        """
        if len(df) < 5:
            return False

        recent = df.iloc[-5:]

        if level_type == 'high':
            # Bullish sweep: wick above level, close below
            swept = False
            for _, candle in recent.iterrows():
                if candle.high > (level_price + SWEEP_TOLERANCE_USD):
                    if candle.close < level_price:
                        body = abs(candle.close - candle.open)
                        upper_wick = candle.high - max(candle.open, candle.close)
                        if upper_wick > (body * LIQUIDITY_WICK_RATIO):
                            swept = True
                            break
            return swept

        else:  # low
            # Bearish sweep: wick below level, close above
            swept = False
            for _, candle in recent.iterrows():
                if candle.low < (level_price - SWEEP_TOLERANCE_USD):
                    if candle.close > level_price:
                        body = abs(candle.close - candle.open)
                        lower_wick = min(candle.open, candle.close) - candle.low
                        if lower_wick > (body * LIQUIDITY_WICK_RATIO):
                            swept = True
                            break
            return swept

    @staticmethod
    def find_liquidity_levels(df, lookback=50):
        """
        Identify recent swing highs/lows as liquidity pools

        Args:
            df: DataFrame with OHLC data
            lookback: Bars to scan

        Returns:
            dict with 'highs' and 'lows' lists
        """
        if len(df) < lookback:
            return {'highs': [], 'lows': []}

        scan = df.iloc[-lookback:]

        # Find swing highs (local maxima)
        highs = []
        for i in range(2, len(scan) - 2):
            if (scan.iloc[i].high > scan.iloc[i-1].high and
                scan.iloc[i].high > scan.iloc[i-2].high and
                scan.iloc[i].high > scan.iloc[i+1].high and
                scan.iloc[i].high > scan.iloc[i+2].high):
                highs.append(scan.iloc[i].high)

        # Find swing lows (local minima)
        lows = []
        for i in range(2, len(scan) - 2):
            if (scan.iloc[i].low < scan.iloc[i-1].low and
                scan.iloc[i].low < scan.iloc[i-2].low and
                scan.iloc[i].low < scan.iloc[i+1].low and
                scan.iloc[i].low < scan.iloc[i+2].low):
                lows.append(scan.iloc[i].low)

        return {
            'highs': sorted(highs, reverse=True)[:3],  # Top 3
            'lows': sorted(lows)[:3]                    # Bottom 3
        }
