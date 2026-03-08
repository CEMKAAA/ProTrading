"""
HTF (Higher Timeframe) Analyzer
Detects key levels from Monthly, Weekly, and Daily timeframes
"""

import pandas as pd
import numpy as np
from typing import List, Dict, Optional, Tuple
from dataclasses import dataclass
from .logger import logger
from .config import (
    LEVEL_PROXIMITY_USD, LEVEL_TOUCH_TOLERANCE,
    SWING_LOOKBACK_MONTHLY, SWING_LOOKBACK_WEEKLY, SWING_LOOKBACK_DAILY
)


@dataclass
class KeyLevel:
    """Represents a significant price level"""
    price: float
    level_type: str  # 'high' or 'low'
    timeframe: str   # 'monthly', 'weekly', 'daily'
    strength: int    # Number of times tested
    timestamp: pd.Timestamp
    broken: bool = False


class HTFAnalyzer:
    """
    Analyzes higher timeframes to identify key support/resistance levels.
    Marks local highs and lows on Monthly, Weekly, and Daily charts.
    """

    def __init__(self, data_manager):
        self.data_manager = data_manager
        self.key_levels: List[KeyLevel] = []
        self.broken_levels: List[KeyLevel] = []

    def analyze_all_timeframes(self) -> List[KeyLevel]:
        """
        Analyze Monthly, Weekly, and Daily charts for key levels.

        Returns:
            List of KeyLevel objects sorted by price
        """
        self.key_levels.clear()

        # Get data for each timeframe
        monthly_df = self.data_manager.get_monthly_data()
        weekly_df = self.data_manager.get_weekly_data()
        daily_df = self.data_manager.get_daily_data()

        # Find swing points on each timeframe
        if not monthly_df.empty:
            self._find_swing_points(monthly_df, "monthly")

        if not weekly_df.empty:
            self._find_swing_points(weekly_df, "weekly")

        if not daily_df.empty:
            self._find_swing_points(daily_df, "daily")

        # Merge nearby levels and calculate strength
        self._merge_nearby_levels()

        # Sort by price
        self.key_levels.sort(key=lambda x: x.price)

        logger.info(f"Found {len(self.key_levels)} key levels across HTF")
        return self.key_levels

    def _find_swing_points(self, df: pd.DataFrame, timeframe: str):
        """
        Find swing highs and lows in the data.

        Uses a 5-bar pattern: middle bar must be highest/lowest
        of 5 consecutive bars (2 before, pivot, 2 after)
        """
        if len(df) < 5:
            return

        # Find swing highs
        for i in range(2, len(df) - 2):
            candle = df.iloc[i]

            # Swing high: higher than 2 bars before and after
            is_swing_high = (
                candle.high > df.iloc[i-1].high and
                candle.high > df.iloc[i-2].high and
                candle.high > df.iloc[i+1].high and
                candle.high > df.iloc[i+2].high
            )

            if is_swing_high:
                self.key_levels.append(KeyLevel(
                    price=candle.high,
                    level_type='high',
                    timeframe=timeframe,
                    strength=1,
                    timestamp=candle.name
                ))

            # Swing low: lower than 2 bars before and after
            is_swing_low = (
                candle.low < df.iloc[i-1].low and
                candle.low < df.iloc[i-2].low and
                candle.low < df.iloc[i+1].low and
                candle.low < df.iloc[i+2].low
            )

            if is_swing_low:
                self.key_levels.append(KeyLevel(
                    price=candle.low,
                    level_type='low',
                    timeframe=timeframe,
                    strength=1,
                    timestamp=candle.name
                ))

    def _merge_nearby_levels(self, tolerance: float = 5.0):
        """
        Merge levels that are close together.
        Increases strength for confluent levels.
        """
        if not self.key_levels:
            return

        # Sort by price
        self.key_levels.sort(key=lambda x: x.price)

        merged = []
        current_group = [self.key_levels[0]]

        for level in self.key_levels[1:]:
            # Check if within tolerance of current group
            group_avg = sum(l.price for l in current_group) / len(current_group)

            if abs(level.price - group_avg) <= tolerance:
                current_group.append(level)
            else:
                # Create merged level from current group
                merged.append(self._create_merged_level(current_group))
                current_group = [level]

        # Don't forget last group
        if current_group:
            merged.append(self._create_merged_level(current_group))

        self.key_levels = merged

    def _create_merged_level(self, group: List[KeyLevel]) -> KeyLevel:
        """Create a single level from a group of nearby levels"""
        avg_price = sum(l.price for l in group) / len(group)

        # Determine type priority: monthly > weekly > daily
        timeframe_priority = {'monthly': 3, 'weekly': 2, 'daily': 1}
        best_tf = max(group, key=lambda x: timeframe_priority.get(x.timeframe, 0))

        # Strength = count of levels + bonus for HTF confluence
        strength = len(group)
        if any(l.timeframe == 'monthly' for l in group):
            strength += 2
        if any(l.timeframe == 'weekly' for l in group):
            strength += 1

        return KeyLevel(
            price=round(avg_price, 2),
            level_type=group[0].level_type,
            timeframe=best_tf.timeframe,
            strength=strength,
            timestamp=best_tf.timestamp
        )

    def get_nearest_level(self, current_price: float) -> Optional[KeyLevel]:
        """
        Find the nearest key level to current price.

        Returns:
            Nearest KeyLevel or None if no levels exist
        """
        if not self.key_levels:
            return None

        nearest = min(self.key_levels, key=lambda x: abs(x.price - current_price))
        return nearest

    def get_levels_in_range(
        self,
        current_price: float,
        range_usd: float = 20.0
    ) -> List[KeyLevel]:
        """
        Get all key levels within a price range.

        Args:
            current_price: Current market price
            range_usd: Range above and below current price

        Returns:
            List of KeyLevel objects within range
        """
        return [
            level for level in self.key_levels
            if abs(level.price - current_price) <= range_usd
        ]

    def is_at_key_level(
        self,
        current_price: float,
        tolerance: float = None
    ) -> Tuple[bool, Optional[KeyLevel]]:
        """
        Check if price is at a key level.

        Args:
            current_price: Current market price
            tolerance: Max distance from level (default from config)

        Returns:
            Tuple of (is_at_level, KeyLevel or None)
        """
        tolerance = tolerance or LEVEL_PROXIMITY_USD

        for level in self.key_levels:
            if abs(current_price - level.price) <= tolerance:
                return True, level

        return False, None

    def check_level_break(
        self,
        level: KeyLevel,
        current_price: float,
        tolerance: float = None
    ) -> bool:
        """
        Check if a level has been broken.

        Args:
            level: The KeyLevel to check
            current_price: Current market price
            tolerance: Break tolerance (default from config)

        Returns:
            True if level is broken
        """
        tolerance = tolerance or LEVEL_TOUCH_TOLERANCE

        if level.level_type == 'high':
            # High is broken if price closes above it
            return current_price > (level.price + tolerance)
        else:
            # Low is broken if price closes below it
            return current_price < (level.price - tolerance)

    def get_broken_sr_levels(self) -> List[KeyLevel]:
        """Get list of recently broken support/resistance levels for TP targets"""
        return [l for l in self.broken_levels if not l.broken]

    def mark_level_broken(self, level: KeyLevel):
        """Mark a level as broken and move to broken_levels list"""
        level.broken = True
        if level not in self.broken_levels:
            self.broken_levels.append(level)
        if level in self.key_levels:
            self.key_levels.remove(level)

        logger.info(f"Level broken: {level.level_type} @ {level.price:.2f} ({level.timeframe})")

    def get_potential_reversal_zones(
        self,
        current_price: float,
        direction: str = 'both'
    ) -> List[Dict]:
        """
        Get zones where reversals are most likely.

        Args:
            current_price: Current market price
            direction: 'bullish', 'bearish', or 'both'

        Returns:
            List of potential reversal zones with metadata
        """
        zones = []

        for level in self.key_levels:
            distance = abs(current_price - level.price)

            # Skip levels that are too far
            if distance > 30.0:
                continue

            zone = {
                'price': level.price,
                'level_type': level.level_type,
                'timeframe': level.timeframe,
                'strength': level.strength,
                'distance': distance,
                'reversal_direction': 'bullish' if level.level_type == 'low' else 'bearish'
            }

            # Filter by direction
            if direction == 'both':
                zones.append(zone)
            elif direction == zone['reversal_direction']:
                zones.append(zone)

        # Sort by distance
        zones.sort(key=lambda x: x['distance'])

        return zones

    def log_levels(self):
        """Log all current key levels"""
        logger.info("=" * 50)
        logger.info("KEY LEVELS:")
        for level in self.key_levels:
            logger.info(
                f"  {level.timeframe.upper()} {level.level_type}: "
                f"${level.price:.2f} (strength: {level.strength})"
            )
        logger.info("=" * 50)
