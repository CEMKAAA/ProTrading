"""
Advanced ICT Pattern Analyzer
Dynamic thresholds, cached calculations, and liquidity sweep detection
"""

import pandas as pd
import numpy as np
from datetime import datetime
from typing import Optional, Dict, List, Any, Tuple
from dataclasses import dataclass, field

from .logger import logger
from .config import get_config


@dataclass
class FairValueGap:
    """Fair Value Gap data"""
    index: int
    direction: str  # 'bullish' or 'bearish'
    top: float
    bottom: float
    size: float
    formation_time: datetime
    is_filled: bool = False
    strength: float = 0.0  # 0-100 strength score


@dataclass
class OrderBlock:
    """Order Block data"""
    index: int
    direction: str  # 'bullish' or 'bearish'
    high: float
    low: float
    body_percent: float
    formation_time: datetime
    is_mitigated: bool = False
    touches: int = 0


@dataclass
class LiquidityLevel:
    """Liquidity level data"""
    price: float
    level_type: str  # 'high', 'low', 'equal_highs', 'equal_lows'
    strength: int  # Number of touches
    formation_time: datetime
    swept: bool = False


@dataclass
class ICTCache:
    """Cache for ICT calculations"""
    last_bar_index: int = -1
    fvgs: List[FairValueGap] = field(default_factory=list)
    order_blocks: List[OrderBlock] = field(default_factory=list)
    liquidity_levels: List[LiquidityLevel] = field(default_factory=list)
    atr: float = 0.0
    displacement_threshold: float = 0.0


class AdvancedICTAnalyzer:
    """
    Advanced ICT pattern detection with:
    - Dynamic thresholds based on ATR
    - Cached calculations for performance
    - Liquidity sweep detection
    - Pattern strength scoring
    - Correct Order Block logic (OB is opposite candle before impulse)
    """

    def __init__(self, symbol: str):
        self.symbol = symbol
        self._cache = ICTCache()
        self._last_cache_bar = -1

    def reset_cache(self):
        """Reset all cached ICT data (call on new day)"""
        self._cache = ICTCache()
        self._last_cache_bar = -1
        logger.info("ICT analyzer cache reset")

    def analyze(
        self,
        df: pd.DataFrame,
        force_refresh: bool = False
    ) -> Dict[str, Any]:
        """
        Run full ICT analysis on price data.

        Args:
            df: DataFrame with OHLCV data
            force_refresh: Force recalculation even if cached

        Returns:
            Dict with all ICT analysis results
        """
        if df is None or len(df) < 100:
            return {"error": "Insufficient data", "atr": 1.0}

        cfg = get_config()
        current_bar = len(df) - 1

        # Check if we need to refresh cache
        bars_since_cache = current_bar - self._cache.last_bar_index
        needs_refresh = (
            force_refresh or
            bars_since_cache >= cfg.ob_cache_ttl_bars or
            self._cache.last_bar_index < 0
        )

        if needs_refresh:
            self._update_cache(df)

        # Get current values
        current_price = df.iloc[-1].close
        atr = self._cache.atr

        # Find active (non-filled/mitigated) patterns
        active_fvgs = [f for f in self._cache.fvgs if not f.is_filled]
        active_obs = [o for o in self._cache.order_blocks if not o.is_mitigated]

        # Check for liquidity sweeps
        sweeps = self._detect_sweeps(df, current_price)

        # Find nearest relevant patterns
        nearest_bullish_fvg = self._find_nearest_fvg(active_fvgs, current_price, 'bullish')
        nearest_bearish_fvg = self._find_nearest_fvg(active_fvgs, current_price, 'bearish')
        nearest_bullish_ob = self._find_nearest_ob(active_obs, current_price, 'bullish')
        nearest_bearish_ob = self._find_nearest_ob(active_obs, current_price, 'bearish')

        return {
            "atr": atr,
            "displacement_threshold": self._cache.displacement_threshold,
            "fvgs": active_fvgs,
            "order_blocks": active_obs,
            "liquidity_levels": self._cache.liquidity_levels,
            "sweeps": sweeps,
            "nearest_bullish_fvg": nearest_bullish_fvg,
            "nearest_bearish_fvg": nearest_bearish_fvg,
            "nearest_bullish_ob": nearest_bullish_ob,
            "nearest_bearish_ob": nearest_bearish_ob,
            "current_price": current_price,
        }

    def _update_cache(self, df: pd.DataFrame):
        """Update all cached ICT calculations"""
        cfg = get_config()

        # Calculate ATR for dynamic thresholds
        atr = self._calculate_atr(df)
        self._cache.atr = atr

        # Dynamic FVG threshold
        min_fvg = max(cfg.fvg_min_absolute, atr * cfg.fvg_atr_multiplier)

        # Calculate displacement threshold
        body_sizes = abs(df['close'] - df['open']).tail(cfg.displacement_lookback)
        self._cache.displacement_threshold = body_sizes.quantile(cfg.displacement_percentile / 100)

        # Find FVGs with dynamic threshold
        self._cache.fvgs = self._find_fvgs(df, min_fvg)

        # Find Order Blocks
        self._cache.order_blocks = self._find_order_blocks(df)

        # Find Liquidity Levels
        self._cache.liquidity_levels = self._find_liquidity_levels(df)

        # Update filled/mitigated status
        self._update_pattern_status(df)

        self._cache.last_bar_index = len(df) - 1

    def _calculate_atr(self, df: pd.DataFrame, period: int = 14) -> float:
        """Calculate Average True Range"""
        if len(df) < period + 1:
            return 1.0

        high = df['high']
        low = df['low']
        close = df['close']

        tr1 = high - low
        tr2 = abs(high - close.shift())
        tr3 = abs(low - close.shift())

        tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
        atr = tr.rolling(window=period).mean().iloc[-1]

        return float(atr) if not np.isnan(atr) else 1.0

    def _find_fvgs(self, df: pd.DataFrame, min_gap: float) -> List[FairValueGap]:
        """
        Find Fair Value Gaps with dynamic threshold.

        Args:
            df: Price data
            min_gap: Minimum gap size (dynamic based on ATR)

        Returns:
            List of FVG objects
        """
        cfg = get_config()
        fvgs = []
        lookback = min(cfg.fvg_lookback, len(df) - 3)

        for i in range(len(df) - lookback, len(df) - 2):
            if i < 2:
                continue

            candle1 = df.iloc[i - 2]
            candle2 = df.iloc[i - 1]
            candle3 = df.iloc[i]

            # Check for displacement (strong move)
            body_size = abs(candle2.close - candle2.open)
            if body_size < self._cache.displacement_threshold:
                continue

            # Check opposing wick ratio
            if candle2.close > candle2.open:  # Bullish
                opposing_wick = candle2.open - candle2.low
            else:  # Bearish
                opposing_wick = candle2.high - candle2.open

            if body_size > 0 and (opposing_wick / body_size) > cfg.max_opposing_wick_ratio:
                continue

            atr = self._cache.atr if self._cache.atr > 0 else 1.0

            # Bullish FVG: Gap between candle 1 high and candle 3 low
            if candle3.low > candle1.high:
                gap = candle3.low - candle1.high
                if gap >= min_gap:
                    strength = min(100, (gap / atr) * 50 + (body_size / atr) * 50)
                    fvgs.append(FairValueGap(
                        index=i,
                        direction='bullish',
                        top=candle3.low,
                        bottom=candle1.high,
                        size=gap,
                        formation_time=df.index[i] if hasattr(df.index[i], 'timestamp') else datetime.now(),
                        strength=strength
                    ))

            # Bearish FVG: Gap between candle 1 low and candle 3 high
            elif candle3.high < candle1.low:
                gap = candle1.low - candle3.high
                if gap >= min_gap:
                    strength = min(100, (gap / atr) * 50 + (body_size / atr) * 50)
                    fvgs.append(FairValueGap(
                        index=i,
                        direction='bearish',
                        top=candle1.low,
                        bottom=candle3.high,
                        size=gap,
                        formation_time=df.index[i] if hasattr(df.index[i], 'timestamp') else datetime.now(),
                        strength=strength
                    ))

        return fvgs

    def _find_order_blocks(self, df: pd.DataFrame) -> List[OrderBlock]:
        """
        Find Order Blocks with correct ICT logic.

        ICT Order Block Definition:
        - Bullish OB: Last BEARISH (down) candle before an impulsive BULLISH move
        - Bearish OB: Last BULLISH (up) candle before an impulsive BEARISH move

        The OB represents institutional orders hidden in the opposite-direction candle.

        Returns:
            List of OrderBlock objects
        """
        cfg = get_config()
        obs = []
        lookback = min(cfg.ob_lookback, len(df) - cfg.ob_validation_bars - 1)

        for i in range(len(df) - lookback, len(df) - cfg.ob_validation_bars):
            if i < 1:
                continue

            candle = df.iloc[i]
            body = abs(candle.close - candle.open)
            total_range = candle.high - candle.low

            if total_range == 0:
                continue

            body_percent = (body / total_range) * 100

            if body_percent < cfg.ob_min_body_percent:
                continue

            # Determine candle direction
            is_bearish_candle = candle.close < candle.open  # Down candle
            is_bullish_candle = candle.close > candle.open  # Up candle

            # Check validation candles for impulsive move
            validation_candles = df.iloc[i + 1:i + 1 + cfg.ob_validation_bars]

            if is_bearish_candle:
                # BEARISH CANDLE before BULLISH impulse = Bullish OB
                # Price should move UP impulsively after this down candle
                impulse_up = (
                    validation_candles['close'].iloc[-1] > candle.high and
                    validation_candles['low'].min() > candle.low
                )
                if impulse_up:
                    obs.append(OrderBlock(
                        index=i,
                        direction='bullish',  # It's a bullish OB (buy zone)
                        high=candle.high,
                        low=candle.low,
                        body_percent=body_percent,
                        formation_time=df.index[i] if hasattr(df.index[i], 'timestamp') else datetime.now()
                    ))

            elif is_bullish_candle:
                # BULLISH CANDLE before BEARISH impulse = Bearish OB
                # Price should move DOWN impulsively after this up candle
                impulse_down = (
                    validation_candles['close'].iloc[-1] < candle.low and
                    validation_candles['high'].max() < candle.high
                )
                if impulse_down:
                    obs.append(OrderBlock(
                        index=i,
                        direction='bearish',  # It's a bearish OB (sell zone)
                        high=candle.high,
                        low=candle.low,
                        body_percent=body_percent,
                        formation_time=df.index[i] if hasattr(df.index[i], 'timestamp') else datetime.now()
                    ))

        return obs

    def _find_liquidity_levels(self, df: pd.DataFrame) -> List[LiquidityLevel]:
        """
        Find liquidity levels (swing highs/lows, equal levels).
        With proper deduplication.

        Returns:
            List of LiquidityLevel objects
        """
        cfg = get_config()
        levels = []
        lookback = min(cfg.liquidity_lookback, len(df) - 5)
        tolerance = cfg.sweep_tolerance_usd

        # Find swing highs and lows
        for i in range(len(df) - lookback, len(df) - 2):
            if i < 2:
                continue

            # Swing High
            if (df.iloc[i].high > df.iloc[i - 1].high and
                df.iloc[i].high > df.iloc[i - 2].high and
                df.iloc[i].high > df.iloc[i + 1].high and
                df.iloc[i].high > df.iloc[i + 2].high):
                levels.append(LiquidityLevel(
                    price=df.iloc[i].high,
                    level_type='high',
                    strength=1,
                    formation_time=df.index[i] if hasattr(df.index[i], 'timestamp') else datetime.now()
                ))

            # Swing Low
            if (df.iloc[i].low < df.iloc[i - 1].low and
                df.iloc[i].low < df.iloc[i - 2].low and
                df.iloc[i].low < df.iloc[i + 1].low and
                df.iloc[i].low < df.iloc[i + 2].low):
                levels.append(LiquidityLevel(
                    price=df.iloc[i].low,
                    level_type='low',
                    strength=1,
                    formation_time=df.index[i] if hasattr(df.index[i], 'timestamp') else datetime.now()
                ))

        # Find equal highs/lows with proper deduplication
        highs = df['high'].tail(lookback).values
        lows = df['low'].tail(lookback).values

        # Track found equal levels to avoid duplicates
        found_equal_highs = set()
        found_equal_lows = set()

        # Equal highs - find clusters
        for i in range(len(highs)):
            if i in found_equal_highs:
                continue

            cluster = [i]
            for j in range(i + 3, len(highs)):
                if j in found_equal_highs:
                    continue
                if abs(highs[i] - highs[j]) < tolerance:
                    cluster.append(j)
                    found_equal_highs.add(j)

            if len(cluster) >= 2:
                found_equal_highs.add(i)
                avg_price = np.mean([highs[idx] for idx in cluster])
                levels.append(LiquidityLevel(
                    price=avg_price,
                    level_type='equal_highs',
                    strength=len(cluster),
                    formation_time=datetime.now()
                ))

        # Equal lows - find clusters
        for i in range(len(lows)):
            if i in found_equal_lows:
                continue

            cluster = [i]
            for j in range(i + 3, len(lows)):
                if j in found_equal_lows:
                    continue
                if abs(lows[i] - lows[j]) < tolerance:
                    cluster.append(j)
                    found_equal_lows.add(j)

            if len(cluster) >= 2:
                found_equal_lows.add(i)
                avg_price = np.mean([lows[idx] for idx in cluster])
                levels.append(LiquidityLevel(
                    price=avg_price,
                    level_type='equal_lows',
                    strength=len(cluster),
                    formation_time=datetime.now()
                ))

        return levels

    def _detect_sweeps(self, df: pd.DataFrame, current_price: float) -> List[Dict[str, Any]]:
        """
        Detect recent liquidity sweeps.

        Returns:
            List of sweep events
        """
        cfg = get_config()
        sweeps = []
        tolerance = cfg.sweep_tolerance_usd

        # Check last 5 candles for sweeps
        for level in self._cache.liquidity_levels:
            if level.swept:
                continue

            for i in range(-5, 0):
                candle = df.iloc[i]

                # Check if level was swept (exceeded then price reversed)
                if level.level_type in ['high', 'equal_highs']:
                    if candle.high > level.price + tolerance and candle.close < level.price:
                        sweeps.append({
                            "type": "sell_side_sweep",
                            "level": level.price,
                            "sweep_high": candle.high,
                            "close": candle.close,
                            "bar_index": len(df) + i
                        })
                        level.swept = True

                elif level.level_type in ['low', 'equal_lows']:
                    if candle.low < level.price - tolerance and candle.close > level.price:
                        sweeps.append({
                            "type": "buy_side_sweep",
                            "level": level.price,
                            "sweep_low": candle.low,
                            "close": candle.close,
                            "bar_index": len(df) + i
                        })
                        level.swept = True

        return sweeps

    def _update_pattern_status(self, df: pd.DataFrame):
        """Update filled/mitigated status of patterns"""
        # Check FVG fill status
        for fvg in self._cache.fvgs:
            if fvg.is_filled:
                continue

            # FVG is filled if price has traded through it
            if fvg.index < len(df):
                recent_prices = df.iloc[fvg.index:][['high', 'low']]
                if fvg.direction == 'bullish':
                    if recent_prices['low'].min() <= fvg.bottom:
                        fvg.is_filled = True
                else:
                    if recent_prices['high'].max() >= fvg.top:
                        fvg.is_filled = True

        # Check OB mitigation status
        for ob in self._cache.order_blocks:
            if ob.is_mitigated:
                continue

            if ob.index < len(df):
                recent_prices = df.iloc[ob.index:][['high', 'low']]
                if ob.direction == 'bullish':
                    # Bullish OB mitigated if price traded through it from above
                    if recent_prices['low'].min() < ob.low:
                        ob.is_mitigated = True
                else:
                    # Bearish OB mitigated if price traded through it from below
                    if recent_prices['high'].max() > ob.high:
                        ob.is_mitigated = True

    def _find_nearest_fvg(
        self,
        fvgs: List[FairValueGap],
        price: float,
        direction: str
    ) -> Optional[FairValueGap]:
        """Find nearest unfilled FVG in specified direction"""
        relevant = [f for f in fvgs if f.direction == direction and not f.is_filled]

        if not relevant:
            return None

        if direction == 'bullish':
            # Find FVG below current price
            below = [f for f in relevant if f.top < price]
            if below:
                return max(below, key=lambda f: f.top)
        else:
            # Find FVG above current price
            above = [f for f in relevant if f.bottom > price]
            if above:
                return min(above, key=lambda f: f.bottom)

        return None

    def _find_nearest_ob(
        self,
        obs: List[OrderBlock],
        price: float,
        direction: str
    ) -> Optional[OrderBlock]:
        """Find nearest unmitigated Order Block in specified direction"""
        relevant = [o for o in obs if o.direction == direction and not o.is_mitigated]

        if not relevant:
            return None

        if direction == 'bullish':
            # Find OB below current price
            below = [o for o in relevant if o.high < price]
            if below:
                return max(below, key=lambda o: o.high)
        else:
            # Find OB above current price
            above = [o for o in relevant if o.low > price]
            if above:
                return min(above, key=lambda o: o.low)

        return None

    def check_entry_conditions(
        self,
        df: pd.DataFrame,
        direction: str,
        entry_price: float,
        existing_analysis: Optional[Dict[str, Any]] = None
    ) -> Tuple[bool, Dict[str, Any]]:
        """
        Check if ICT conditions support an entry.

        Args:
            df: Price data
            direction: 'BUY' or 'SELL'
            entry_price: Proposed entry price
            existing_analysis: Pass existing analysis to avoid redundant calculation

        Returns:
            Tuple of (conditions_met, details)
        """
        # Use existing analysis if provided, otherwise run new analysis
        analysis = existing_analysis if existing_analysis else self.analyze(df)
        cfg = get_config()

        details = {
            "has_fvg": False,
            "has_ob": False,
            "has_sweep": False,
            "fvg_strength": 0,
            "total_score": 0,
        }

        score = 0
        atr = self._cache.atr if self._cache.atr > 0 else 1.0

        if direction == 'BUY':
            # Check for bullish FVG near entry
            if analysis.get('nearest_bullish_fvg'):
                fvg = analysis['nearest_bullish_fvg']
                if abs(entry_price - fvg.top) < atr:
                    details['has_fvg'] = True
                    details['fvg_strength'] = fvg.strength
                    score += 30

            # Check for bullish OB near entry
            if analysis.get('nearest_bullish_ob'):
                ob = analysis['nearest_bullish_ob']
                if abs(entry_price - ob.high) < atr:
                    details['has_ob'] = True
                    score += 25

            # Check for recent buy-side sweep (liquidity grab)
            if cfg.use_liquidity_sweeps:
                sweeps = analysis.get('sweeps', [])
                buy_sweeps = [s for s in sweeps if s['type'] == 'buy_side_sweep']
                if buy_sweeps:
                    details['has_sweep'] = True
                    score += 35

        else:  # SELL
            # Check for bearish FVG near entry
            if analysis.get('nearest_bearish_fvg'):
                fvg = analysis['nearest_bearish_fvg']
                if abs(entry_price - fvg.bottom) < atr:
                    details['has_fvg'] = True
                    details['fvg_strength'] = fvg.strength
                    score += 30

            # Check for bearish OB near entry
            if analysis.get('nearest_bearish_ob'):
                ob = analysis['nearest_bearish_ob']
                if abs(entry_price - ob.low) < atr:
                    details['has_ob'] = True
                    score += 25

            # Check for recent sell-side sweep
            if cfg.use_liquidity_sweeps:
                sweeps = analysis.get('sweeps', [])
                sell_sweeps = [s for s in sweeps if s['type'] == 'sell_side_sweep']
                if sell_sweeps:
                    details['has_sweep'] = True
                    score += 35

        details['total_score'] = score

        # ORB + imbalance model: FVG confirmation is mandatory.
        conditions_met = details['has_fvg']

        return conditions_met, details

    def get_optimal_sl(
        self,
        direction: str,
        entry_price: float,
        df: pd.DataFrame,
        existing_analysis: Optional[Dict[str, Any]] = None
    ) -> float:
        """
        Get optimal stop loss based on ICT structure.
        Returns STRUCTURAL SL level, not distance-based.

        Args:
            direction: 'BUY' or 'SELL'
            entry_price: Entry price
            df: Price data
            existing_analysis: Pass existing analysis to avoid redundant calculation

        Returns:
            Optimal stop loss price (structural level)
        """
        cfg = get_config()
        analysis = existing_analysis if existing_analysis else self.analyze(df)

        if direction == 'BUY':
            # Prefer structural SL anchored to bullish imbalance boundary.
            bullish_fvg = analysis.get('nearest_bullish_fvg')
            if bullish_fvg:
                fvg_sl = bullish_fvg.bottom - 0.05
                if entry_price - fvg_sl >= cfg.min_sl_usd:
                    return fvg_sl

            # Start with max SL distance as fallback
            sl = entry_price - cfg.max_sl_usd

            # Check for bullish OB to place SL below (structural)
            if analysis.get('nearest_bullish_ob'):
                ob = analysis['nearest_bullish_ob']
                ob_sl = ob.low - 0.20  # Small buffer below OB low
                if entry_price - ob_sl <= cfg.max_sl_usd:
                    sl = ob_sl

            # Check recent swing low (structural)
            recent_low = df['low'].tail(20).min()
            swing_sl = recent_low - 0.20
            if entry_price - swing_sl <= cfg.max_sl_usd and swing_sl < sl:
                sl = swing_sl

            # Ensure minimum SL distance
            if entry_price - sl < cfg.min_sl_usd:
                sl = entry_price - cfg.min_sl_usd

        else:  # SELL
            bearish_fvg = analysis.get('nearest_bearish_fvg')
            if bearish_fvg:
                fvg_sl = bearish_fvg.top + 0.05
                if fvg_sl - entry_price >= cfg.min_sl_usd:
                    return fvg_sl

            sl = entry_price + cfg.max_sl_usd

            if analysis.get('nearest_bearish_ob'):
                ob = analysis['nearest_bearish_ob']
                ob_sl = ob.high + 0.20  # Small buffer above OB high
                if ob_sl - entry_price <= cfg.max_sl_usd:
                    sl = ob_sl

            recent_high = df['high'].tail(20).max()
            swing_sl = recent_high + 0.20
            if swing_sl - entry_price <= cfg.max_sl_usd and swing_sl > sl:
                sl = swing_sl

            if sl - entry_price < cfg.min_sl_usd:
                sl = entry_price + cfg.min_sl_usd

        return sl
