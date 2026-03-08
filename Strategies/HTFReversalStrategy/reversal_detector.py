"""
Reversal Detector - Candle Patterns, Divergences, and Confluence
Identifies reversal signals for entry timing
"""

import pandas as pd
import numpy as np
from typing import List, Dict, Optional, Tuple
from dataclasses import dataclass
from enum import Enum
from .logger import logger
from .config import (
    DOJI_BODY_RATIO, HAMMER_WICK_RATIO, ENGULFING_OVERLAP_PERCENT,
    INSIDE_BAR_TOLERANCE, RSI_PERIOD, RSI_OVERBOUGHT, RSI_OVERSOLD,
    DIVERGENCE_LOOKBACK, TRENDLINE_MIN_TOUCHES, TRENDLINE_LOOKBACK
)


class PatternType(Enum):
    DOJI = "doji"
    HAMMER = "hammer"
    INVERTED_HAMMER = "inverted_hammer"
    ENGULFING_BULLISH = "engulfing_bullish"
    ENGULFING_BEARISH = "engulfing_bearish"
    MORNING_STAR = "morning_star"
    EVENING_STAR = "evening_star"
    INSIDE_BAR = "inside_bar"
    PIN_BAR_BULLISH = "pin_bar_bullish"
    PIN_BAR_BEARISH = "pin_bar_bearish"


@dataclass
class CandlePattern:
    """Represents a detected candle pattern"""
    pattern_type: PatternType
    direction: str  # 'bullish' or 'bearish'
    strength: float  # 0-1 confidence score
    timestamp: pd.Timestamp
    price: float


@dataclass
class Divergence:
    """Represents a price-indicator divergence"""
    divergence_type: str  # 'bullish' or 'bearish'
    indicator: str  # 'rsi', 'macd', etc.
    price_swing_1: float
    price_swing_2: float
    indicator_swing_1: float
    indicator_swing_2: float
    strength: float


@dataclass
class Confluence:
    """Represents stacked confluences for entry"""
    patterns: List[CandlePattern]
    divergences: List[Divergence]
    trendline_touch: bool
    key_level_distance: float
    total_score: float
    suggested_direction: str


class ReversalDetector:
    """
    Detects reversal signals using multiple methods:
    - Candle patterns (doji, hammer, engulfing, etc.)
    - RSI divergences
    - Trendline touches
    - Confluence stacking
    """

    def __init__(self, data_manager):
        self.data_manager = data_manager

    def detect_candle_patterns(
        self,
        df: pd.DataFrame = None,
        lookback: int = 5
    ) -> List[CandlePattern]:
        """
        Detect reversal candle patterns in recent bars.

        Args:
            df: Optional DataFrame
            lookback: Number of bars to scan

        Returns:
            List of detected CandlePattern objects
        """
        if df is None:
            df = self.data_manager.get_h1_data()

        if len(df) < lookback + 2:
            return []

        patterns = []
        recent = df.tail(lookback + 2)

        for i in range(2, len(recent)):
            candle = recent.iloc[i]
            prev_candle = recent.iloc[i - 1]
            prev_prev = recent.iloc[i - 2]

            # Calculate candle metrics
            body = candle.close - candle.open
            candle_range = candle.high - candle.low

            if candle_range < 0.01:
                continue

            body_ratio = abs(body) / candle_range
            upper_wick = candle.high - max(candle.open, candle.close)
            lower_wick = min(candle.open, candle.close) - candle.low

            # 1. Doji Pattern
            if body_ratio <= DOJI_BODY_RATIO:
                patterns.append(CandlePattern(
                    pattern_type=PatternType.DOJI,
                    direction='neutral',
                    strength=0.5,
                    timestamp=candle.name,
                    price=candle.close
                ))

            # 2. Hammer (Bullish reversal at lows)
            if (body > 0 and
                lower_wick >= abs(body) * HAMMER_WICK_RATIO and
                upper_wick < abs(body) * 0.3):
                patterns.append(CandlePattern(
                    pattern_type=PatternType.HAMMER,
                    direction='bullish',
                    strength=0.7,
                    timestamp=candle.name,
                    price=candle.close
                ))

            # 3. Inverted Hammer / Shooting Star (Bearish at highs)
            if (body < 0 and
                upper_wick >= abs(body) * HAMMER_WICK_RATIO and
                lower_wick < abs(body) * 0.3):
                patterns.append(CandlePattern(
                    pattern_type=PatternType.INVERTED_HAMMER,
                    direction='bearish',
                    strength=0.7,
                    timestamp=candle.name,
                    price=candle.close
                ))

            # 4. Bullish Engulfing
            prev_body = prev_candle.close - prev_candle.open
            if (prev_body < 0 and body > 0 and
                candle.close > prev_candle.open and
                candle.open < prev_candle.close):
                patterns.append(CandlePattern(
                    pattern_type=PatternType.ENGULFING_BULLISH,
                    direction='bullish',
                    strength=0.8,
                    timestamp=candle.name,
                    price=candle.close
                ))

            # 5. Bearish Engulfing
            if (prev_body > 0 and body < 0 and
                candle.close < prev_candle.open and
                candle.open > prev_candle.close):
                patterns.append(CandlePattern(
                    pattern_type=PatternType.ENGULFING_BEARISH,
                    direction='bearish',
                    strength=0.8,
                    timestamp=candle.name,
                    price=candle.close
                ))

            # 6. Pin Bar Bullish (long lower wick)
            if (lower_wick > candle_range * 0.6 and
                upper_wick < candle_range * 0.2):
                patterns.append(CandlePattern(
                    pattern_type=PatternType.PIN_BAR_BULLISH,
                    direction='bullish',
                    strength=0.75,
                    timestamp=candle.name,
                    price=candle.close
                ))

            # 7. Pin Bar Bearish (long upper wick)
            if (upper_wick > candle_range * 0.6 and
                lower_wick < candle_range * 0.2):
                patterns.append(CandlePattern(
                    pattern_type=PatternType.PIN_BAR_BEARISH,
                    direction='bearish',
                    strength=0.75,
                    timestamp=candle.name,
                    price=candle.close
                ))

            # 8. Inside Bar
            if (candle.high < prev_candle.high and
                candle.low > prev_candle.low):
                patterns.append(CandlePattern(
                    pattern_type=PatternType.INSIDE_BAR,
                    direction='neutral',
                    strength=0.5,
                    timestamp=candle.name,
                    price=candle.close
                ))

        return patterns

    def calculate_rsi(self, df: pd.DataFrame, period: int = None) -> pd.Series:
        """Calculate RSI indicator"""
        period = period or RSI_PERIOD

        delta = df['close'].diff()
        gain = (delta.where(delta > 0, 0)).rolling(window=period).mean()
        loss = (-delta.where(delta < 0, 0)).rolling(window=period).mean()

        rs = gain / loss
        rsi = 100 - (100 / (1 + rs))

        return rsi

    def detect_divergence(
        self,
        df: pd.DataFrame = None,
        lookback: int = None
    ) -> List[Divergence]:
        """
        Detect RSI divergences.

        Bullish divergence: Price makes lower low, RSI makes higher low
        Bearish divergence: Price makes higher high, RSI makes lower high

        Args:
            df: Optional DataFrame
            lookback: Number of bars to analyze

        Returns:
            List of detected Divergence objects
        """
        if df is None:
            df = self.data_manager.get_h4_data()

        lookback = lookback or DIVERGENCE_LOOKBACK

        if len(df) < lookback + RSI_PERIOD:
            return []

        divergences = []

        # Calculate RSI
        rsi = self.calculate_rsi(df)
        recent = df.tail(lookback)
        rsi_recent = rsi.tail(lookback)

        # Find swing points in price
        price_swings = self._find_swing_points(recent['close'].values)
        rsi_swings = self._find_swing_points(rsi_recent.values)

        if len(price_swings['lows']) >= 2 and len(rsi_swings['lows']) >= 2:
            # Check for bullish divergence
            price_low_1 = price_swings['lows'][-2]
            price_low_2 = price_swings['lows'][-1]
            rsi_low_1 = rsi_swings['lows'][-2]
            rsi_low_2 = rsi_swings['lows'][-1]

            # Bullish: price lower low, RSI higher low
            if price_low_2 < price_low_1 and rsi_low_2 > rsi_low_1:
                strength = (rsi_low_2 - rsi_low_1) / 10  # Normalize
                divergences.append(Divergence(
                    divergence_type='bullish',
                    indicator='rsi',
                    price_swing_1=price_low_1,
                    price_swing_2=price_low_2,
                    indicator_swing_1=rsi_low_1,
                    indicator_swing_2=rsi_low_2,
                    strength=min(1.0, strength)
                ))
                logger.info(f"Bullish RSI divergence detected (strength: {strength:.2f})")

        if len(price_swings['highs']) >= 2 and len(rsi_swings['highs']) >= 2:
            # Check for bearish divergence
            price_high_1 = price_swings['highs'][-2]
            price_high_2 = price_swings['highs'][-1]
            rsi_high_1 = rsi_swings['highs'][-2]
            rsi_high_2 = rsi_swings['highs'][-1]

            # Bearish: price higher high, RSI lower high
            if price_high_2 > price_high_1 and rsi_high_2 < rsi_high_1:
                strength = (rsi_high_1 - rsi_high_2) / 10  # Normalize
                divergences.append(Divergence(
                    divergence_type='bearish',
                    indicator='rsi',
                    price_swing_1=price_high_1,
                    price_swing_2=price_high_2,
                    indicator_swing_1=rsi_high_1,
                    indicator_swing_2=rsi_high_2,
                    strength=min(1.0, strength)
                ))
                logger.info(f"Bearish RSI divergence detected (strength: {strength:.2f})")

        return divergences

    def _find_swing_points(self, data: np.ndarray) -> Dict[str, List[float]]:
        """Find swing highs and lows in data"""
        highs = []
        lows = []

        for i in range(2, len(data) - 2):
            # Swing high
            if (data[i] > data[i-1] and data[i] > data[i-2] and
                data[i] > data[i+1] and data[i] > data[i+2]):
                highs.append(data[i])

            # Swing low
            if (data[i] < data[i-1] and data[i] < data[i-2] and
                data[i] < data[i+1] and data[i] < data[i+2]):
                lows.append(data[i])

        return {'highs': highs, 'lows': lows}

    def detect_trendline_touch(
        self,
        df: pd.DataFrame = None,
        direction: str = 'both'
    ) -> Optional[Dict]:
        """
        Detect if price is touching a trendline.

        Args:
            df: Optional DataFrame
            direction: 'bullish', 'bearish', or 'both'

        Returns:
            Dict with trendline info or None
        """
        if df is None:
            df = self.data_manager.get_h4_data()

        lookback = TRENDLINE_LOOKBACK
        if len(df) < lookback:
            return None

        recent = df.tail(lookback)
        current_price = recent.iloc[-1].close

        # Find swing lows for bullish trendline
        if direction in ['bullish', 'both']:
            lows = []
            for i in range(2, len(recent) - 2):
                if (recent.iloc[i].low < recent.iloc[i-1].low and
                    recent.iloc[i].low < recent.iloc[i-2].low and
                    recent.iloc[i].low < recent.iloc[i+1].low and
                    recent.iloc[i].low < recent.iloc[i+2].low):
                    lows.append((i, recent.iloc[i].low))

            if len(lows) >= TRENDLINE_MIN_TOUCHES:
                # Calculate trendline from lows
                x = np.array([l[0] for l in lows])
                y = np.array([l[1] for l in lows])
                slope, intercept = np.polyfit(x, y, 1)

                # Project to current bar
                current_idx = len(recent) - 1
                trendline_value = slope * current_idx + intercept

                # Check if price is near trendline
                if abs(current_price - trendline_value) < 2.0:
                    return {
                        'type': 'bullish',
                        'trendline_price': trendline_value,
                        'current_price': current_price,
                        'slope': slope,
                        'touches': len(lows)
                    }

        # Find swing highs for bearish trendline
        if direction in ['bearish', 'both']:
            highs = []
            for i in range(2, len(recent) - 2):
                if (recent.iloc[i].high > recent.iloc[i-1].high and
                    recent.iloc[i].high > recent.iloc[i-2].high and
                    recent.iloc[i].high > recent.iloc[i+1].high and
                    recent.iloc[i].high > recent.iloc[i+2].high):
                    highs.append((i, recent.iloc[i].high))

            if len(highs) >= TRENDLINE_MIN_TOUCHES:
                x = np.array([h[0] for h in highs])
                y = np.array([h[1] for h in highs])
                slope, intercept = np.polyfit(x, y, 1)

                current_idx = len(recent) - 1
                trendline_value = slope * current_idx + intercept

                if abs(current_price - trendline_value) < 2.0:
                    return {
                        'type': 'bearish',
                        'trendline_price': trendline_value,
                        'current_price': current_price,
                        'slope': slope,
                        'touches': len(highs)
                    }

        return None

    def analyze_confluence(
        self,
        key_level_price: float,
        suggested_direction: str
    ) -> Confluence:
        """
        Stack confluences to determine entry quality.

        Args:
            key_level_price: Price of the key HTF level
            suggested_direction: Expected reversal direction

        Returns:
            Confluence object with total score
        """
        df_h4 = self.data_manager.get_h4_data()
        df_h1 = self.data_manager.get_h1_data()

        current_price = df_h4.iloc[-1].close if not df_h4.empty else None

        # Detect signals
        patterns = self.detect_candle_patterns(df_h1)
        divergences = self.detect_divergence(df_h4)
        trendline = self.detect_trendline_touch(df_h4, suggested_direction)

        # Filter patterns by direction
        matching_patterns = [
            p for p in patterns
            if p.direction == suggested_direction or p.direction == 'neutral'
        ]

        # Filter divergences by direction
        matching_divergences = [
            d for d in divergences
            if d.divergence_type == suggested_direction
        ]

        # Calculate distance from key level
        level_distance = abs(current_price - key_level_price) if current_price else 999

        # Calculate total score
        score = 0.0

        # Pattern scores (max 3 points)
        for pattern in matching_patterns[:3]:
            score += pattern.strength

        # Divergence scores (max 2 points)
        for div in matching_divergences[:2]:
            score += div.strength

        # Trendline touch (1 point)
        trendline_touch = trendline is not None and trendline['type'] == suggested_direction
        if trendline_touch:
            score += 1.0

        # Level proximity bonus (max 1 point)
        if level_distance < 3.0:
            score += 1.0
        elif level_distance < 5.0:
            score += 0.5

        logger.info(
            f"Confluence analysis: {len(matching_patterns)} patterns, "
            f"{len(matching_divergences)} divergences, "
            f"trendline: {trendline_touch}, score: {score:.1f}"
        )

        return Confluence(
            patterns=matching_patterns,
            divergences=matching_divergences,
            trendline_touch=trendline_touch,
            key_level_distance=level_distance,
            total_score=score,
            suggested_direction=suggested_direction
        )

    def is_entry_valid(self, confluence: Confluence, min_score: float = 2.0) -> bool:
        """
        Determine if entry is valid based on confluence score.

        Args:
            confluence: Confluence object from analyze_confluence
            min_score: Minimum score required for entry

        Returns:
            True if entry is valid
        """
        return confluence.total_score >= min_score
