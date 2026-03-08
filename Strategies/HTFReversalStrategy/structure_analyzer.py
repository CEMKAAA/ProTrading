"""
Structure Analyzer - Consolidation and Breakout Detection
Analyzes H4 and smaller timeframes for consolidative structure
"""

import pandas as pd
import numpy as np
from typing import Optional, Dict, Tuple, List
from dataclasses import dataclass
from .logger import logger
from .config import (
    CONSOLIDATION_LOOKBACK, MIN_CONSOLIDATION_BARS,
    MAX_CONSOLIDATION_RANGE_USD, MIN_CONSOLIDATION_RANGE_USD,
    BREAKOUT_THRESHOLD_PERCENT, SPIKE_VOLUME_MULTIPLIER
)


@dataclass
class Consolidation:
    """Represents a consolidation pattern"""
    high: float
    low: float
    range_size: float
    start_time: pd.Timestamp
    end_time: pd.Timestamp
    bar_count: int
    is_valid: bool


@dataclass
class Breakout:
    """Represents a breakout from consolidation"""
    direction: str  # 'bullish' or 'bearish'
    breakout_price: float
    consolidation_high: float
    consolidation_low: float
    spike_bar: pd.Series
    is_valid: bool
    is_false_breakout: bool = False


class StructureAnalyzer:
    """
    Analyzes price structure for consolidation patterns and breakouts.
    Used to identify potential reversal setups at key levels.
    """

    def __init__(self, data_manager):
        self.data_manager = data_manager
        self.current_consolidation: Optional[Consolidation] = None
        self.recent_breakouts: List[Breakout] = []

    def detect_consolidation(
        self,
        df: pd.DataFrame = None,
        lookback: int = None
    ) -> Optional[Consolidation]:
        """
        Detect consolidation pattern in H4 data.

        Consolidation = price trading in a tight range with
        similar highs and lows over multiple bars.

        Args:
            df: Optional DataFrame (uses H4 if None)
            lookback: Number of bars to analyze

        Returns:
            Consolidation object or None
        """
        if df is None:
            df = self.data_manager.get_h4_data()

        if df.empty:
            return None

        lookback = lookback or CONSOLIDATION_LOOKBACK
        recent = df.tail(lookback)

        if len(recent) < MIN_CONSOLIDATION_BARS:
            return None

        # Calculate range
        range_high = recent['high'].max()
        range_low = recent['low'].min()
        range_size = range_high - range_low

        # Check if range is within consolidation bounds
        if range_size > MAX_CONSOLIDATION_RANGE_USD:
            return None

        if range_size < MIN_CONSOLIDATION_RANGE_USD:
            return None

        # Count how many bars are within this range
        bars_in_range = len(recent[
            (recent['high'] <= range_high) &
            (recent['low'] >= range_low)
        ])

        is_valid = bars_in_range >= MIN_CONSOLIDATION_BARS

        consolidation = Consolidation(
            high=range_high,
            low=range_low,
            range_size=range_size,
            start_time=recent.index[0],
            end_time=recent.index[-1],
            bar_count=bars_in_range,
            is_valid=is_valid
        )

        if is_valid:
            self.current_consolidation = consolidation
            logger.info(
                f"Consolidation detected: ${range_low:.2f} - ${range_high:.2f} "
                f"(range: ${range_size:.2f}, bars: {bars_in_range})"
            )

        return consolidation

    def detect_breakout(
        self,
        consolidation: Consolidation = None,
        df: pd.DataFrame = None
    ) -> Optional[Breakout]:
        """
        Detect breakout from consolidation.

        Breakout = price closing outside the consolidation range
        with a strong move (spike).

        Args:
            consolidation: Consolidation to check (uses current if None)
            df: Optional DataFrame

        Returns:
            Breakout object or None
        """
        consolidation = consolidation or self.current_consolidation

        if consolidation is None or not consolidation.is_valid:
            return None

        if df is None:
            df = self.data_manager.get_h4_data()

        if df.empty:
            return None

        # Get latest bar
        latest = df.iloc[-1]

        # Calculate breakout threshold
        threshold = consolidation.range_size * (BREAKOUT_THRESHOLD_PERCENT / 100)

        breakout = None

        # Bullish breakout
        if latest.close > (consolidation.high + threshold):
            breakout = Breakout(
                direction='bullish',
                breakout_price=latest.close,
                consolidation_high=consolidation.high,
                consolidation_low=consolidation.low,
                spike_bar=latest,
                is_valid=True
            )

        # Bearish breakout
        elif latest.close < (consolidation.low - threshold):
            breakout = Breakout(
                direction='bearish',
                breakout_price=latest.close,
                consolidation_high=consolidation.high,
                consolidation_low=consolidation.low,
                spike_bar=latest,
                is_valid=True
            )

        if breakout:
            # Check if it's a spike (strong move)
            if self._is_valid_spike(df, breakout.direction):
                self.recent_breakouts.append(breakout)
                logger.info(
                    f"Breakout detected: {breakout.direction.upper()} "
                    f"@ ${breakout.breakout_price:.2f}"
                )
            else:
                breakout.is_valid = False

        return breakout

    def _is_valid_spike(self, df: pd.DataFrame, direction: str) -> bool:
        """
        Check if the breakout is a valid spike.

        Valid spike = larger than average range and/or
        higher volume than average.
        """
        if len(df) < 10:
            return True  # Not enough data to validate

        recent = df.tail(20)
        latest = df.iloc[-1]

        # Calculate average range
        avg_range = (recent['high'] - recent['low']).mean()
        latest_range = latest.high - latest.low

        # Spike should be larger than average
        is_large_range = latest_range > avg_range

        # Check body direction matches breakout direction
        body = latest.close - latest.open
        body_matches = (
            (direction == 'bullish' and body > 0) or
            (direction == 'bearish' and body < 0)
        )

        # Check volume if available
        has_high_volume = True
        if 'tick_volume' in df.columns:
            avg_volume = recent['tick_volume'].mean()
            has_high_volume = latest.tick_volume > (avg_volume * SPIKE_VOLUME_MULTIPLIER)

        return is_large_range and body_matches

    def detect_false_breakout(
        self,
        breakout: Breakout,
        df: pd.DataFrame = None
    ) -> bool:
        """
        Check if a breakout has failed (false breakout).

        False breakout = price returned back into the consolidation range.

        Args:
            breakout: The Breakout to check
            df: Optional DataFrame

        Returns:
            True if false breakout detected
        """
        if df is None:
            df = self.data_manager.get_h4_data()

        if df.empty:
            return False

        latest = df.iloc[-1]

        # Check if price is back inside the range
        if breakout.direction == 'bullish':
            # False bullish breakout: price closes back below the high
            if latest.close < breakout.consolidation_high:
                breakout.is_false_breakout = True
                logger.info(
                    f"False breakout detected: price returned to "
                    f"${latest.close:.2f} (below ${breakout.consolidation_high:.2f})"
                )
                return True

        elif breakout.direction == 'bearish':
            # False bearish breakout: price closes back above the low
            if latest.close > breakout.consolidation_low:
                breakout.is_false_breakout = True
                logger.info(
                    f"False breakout detected: price returned to "
                    f"${latest.close:.2f} (above ${breakout.consolidation_low:.2f})"
                )
                return True

        return False

    def get_structure_bias(self, df: pd.DataFrame = None) -> str:
        """
        Determine overall structure bias based on recent price action.

        Returns:
            'bullish', 'bearish', or 'neutral'
        """
        if df is None:
            df = self.data_manager.get_h4_data()

        if len(df) < 20:
            return 'neutral'

        recent = df.tail(20)

        # Calculate trend using closes
        first_close = recent.iloc[0].close
        last_close = recent.iloc[-1].close
        change_percent = ((last_close - first_close) / first_close) * 100

        # Check higher highs/lower lows
        highs = recent['high'].values
        lows = recent['low'].values

        higher_highs = sum(1 for i in range(1, len(highs)) if highs[i] > highs[i-1])
        lower_lows = sum(1 for i in range(1, len(lows)) if lows[i] < lows[i-1])

        # Determine bias
        if change_percent > 0.5 and higher_highs > lower_lows:
            return 'bullish'
        elif change_percent < -0.5 and lower_lows > higher_highs:
            return 'bearish'
        else:
            return 'neutral'

    def analyze_for_reversal(
        self,
        key_level_price: float,
        key_level_type: str
    ) -> Dict:
        """
        Analyze structure for potential reversal at a key level.

        Args:
            key_level_price: Price of the key level
            key_level_type: 'high' or 'low'

        Returns:
            Dict with analysis results
        """
        df = self.data_manager.get_h4_data()
        current_price = df.iloc[-1].close if not df.empty else None

        result = {
            'has_consolidation': False,
            'has_breakout': False,
            'is_false_breakout': False,
            'reversal_ready': False,
            'suggested_direction': None,
            'consolidation': None,
            'breakout': None,
        }

        if current_price is None:
            return result

        # Check distance from key level
        distance = abs(current_price - key_level_price)
        if distance > 10.0:  # Too far from level
            return result

        # Detect consolidation
        consolidation = self.detect_consolidation()
        if consolidation and consolidation.is_valid:
            result['has_consolidation'] = True
            result['consolidation'] = consolidation

            # Detect breakout
            breakout = self.detect_breakout(consolidation)
            if breakout and breakout.is_valid:
                result['has_breakout'] = True
                result['breakout'] = breakout

                # Check for false breakout (reversal signal)
                if self.detect_false_breakout(breakout):
                    result['is_false_breakout'] = True

                    # Reversal direction is opposite of breakout
                    if breakout.direction == 'bullish':
                        result['suggested_direction'] = 'bearish'
                    else:
                        result['suggested_direction'] = 'bullish'

                    result['reversal_ready'] = True

        return result
