"""Multi-Timeframe Confluence Zone Strategy.

Trades bounces at zones where 3+ technical levels converge within a tight
price band (1 ATR width).  Each confluence factor adds points to a score;
a minimum score of 60 (configurable) is required before a trade is taken.

Confluence Scoring System (0-100):
    - EMA 50 within zone:       +20
    - EMA 200 within zone:      +25
    - Session level (Asian/London/PD high or low) within zone: +15 each
    - Round number ($XX00 or $XX50) within zone: +15
    - RSI at extremes (>65 or <35): +10

Entry Rules:
    1. Zone Definition: Price area where 3+ levels converge within 1 ATR width
    2. Confluence Score: Must be >= 60 (at least 3 strong factors)
    3. Approach: Price must be moving toward the zone (not already past it)
    4. Trigger: Reversal candle pattern (pin bar, engulfing, hammer) at the zone
    5. Entry: Next bar open after trigger candle
    6. Stop Loss: Other side of the zone + 0.5 ATR buffer
    7. Take Profit: 2.5:1 R:R minimum
"""

import logging
from datetime import datetime
from typing import Optional, Dict, Any, List, Tuple

import numpy as np
import pandas as pd

from .base import BacktestStrategy, DayContext, TradeSetup

logger = logging.getLogger(__name__)


class ConfluenceZoneStrategy(BacktestStrategy):
    """
    Multi-Timeframe Confluence Zone Strategy.

    Trades bounces at zones where 3+ technical levels converge.
    """

    # ------------------------------------------------------------------
    # Day initialisation
    # ------------------------------------------------------------------

    def initialize_day(
        self,
        date: datetime,
        daily_df: Optional[pd.DataFrame],
        intraday_df: pd.DataFrame,
    ) -> DayContext:
        ctx = DayContext(date=date)
        if intraday_df is not None and len(intraday_df) >= 14:
            ctx.atr = self._calculate_atr(intraday_df, 14)
        return ctx

    # ------------------------------------------------------------------
    # Setup detection
    # ------------------------------------------------------------------

    def find_setup(
        self,
        bar: pd.Series,
        df: pd.DataFrame,
        day_context: DayContext,
        current_bar_index: int,
    ) -> Optional[TradeSetup]:
        # ---- Config values ----
        ema_slow: int = self.config.get("ema_slow", 50)
        ema_very_slow: int = self.config.get("ema_very_slow", 200)
        min_bars: int = ema_very_slow + 10

        if len(df) < min_bars:
            return None

        atr: float = day_context.atr
        if atr <= 0:
            atr = 1.0

        zone_width: float = self.config.get("zone_width_atr", 1.0) * atr
        min_score: int = self.config.get("min_confluence_score", 60)
        min_levels: int = self.config.get("min_levels_in_zone", 3)
        use_reversal: bool = self.config.get("use_reversal_candle_filter", True)
        rsi_period: int = self.config.get("rsi_period", 14)
        rsi_threshold: float = self.config.get("rsi_extreme_threshold", 35.0)
        sl_buffer_atr: float = self.config.get("sl_buffer_atr", 0.5)
        min_rr: float = self.config.get("min_rr_ratio", 2.5)

        current_price: float = float(df.iloc[-1]["close"])
        current_close: float = current_price

        # ---- Collect technical levels ----
        all_levels = self._collect_levels(df, day_context, ema_slow, ema_very_slow)

        if len(all_levels) < min_levels:
            return None

        # ---- Cluster levels into confluence zones ----
        zones = self._find_zones(all_levels, zone_width, min_levels)

        if not zones:
            return None

        # ---- Trend filter: prefer trades aligned with EMA200 ----
        close = df["close"]
        ema200 = close.ewm(span=200, adjust=False).mean()
        if len(ema200) >= 200 and not pd.isna(ema200.iloc[-1]):
            above_ema200 = current_close > ema200.iloc[-1]
        else:
            above_ema200 = None  # Can't determine, allow both directions

        # ---- RSI for extra scoring ----
        rsi_series = self._calculate_rsi(df["close"], rsi_period)
        current_rsi: float = (
            float(rsi_series.iloc[-1])
            if len(rsi_series) > 0 and not pd.isna(rsi_series.iloc[-1])
            else 50.0
        )

        # ---- Evaluate each zone ----
        for zone in zones:
            zone_center: float = zone["center"]
            zone_top: float = zone["top"]
            zone_bottom: float = zone["bottom"]
            score: int = zone["score"]

            # RSI bonus --------------------------------------------------
            if current_rsi > (100 - rsi_threshold):
                # Overbought -- bonus only if price is above zone (sell setup)
                if current_price > zone_center:
                    score += 10
            elif current_rsi < rsi_threshold:
                # Oversold -- bonus only if price is below zone (buy setup)
                if current_price < zone_center:
                    score += 10

            if score < min_score:
                continue

            # ---- Price position relative to zone ----
            price_above_zone: bool = current_price > zone_top
            price_below_zone: bool = current_price < zone_bottom
            price_at_zone: bool = zone_bottom <= current_price <= zone_top

            # Determine direction based on position relative to zone center
            zone_center_price: float = zone_center
            price_below_center: bool = current_close <= zone_center_price
            price_above_center: bool = current_close > zone_center_price

            entry: float = float(bar["open"])

            # === BULLISH: Price at lower part of zone (support bounce) ===
            if price_at_zone and price_below_center:
                # Only take if trend allows (above EMA200 or unknown)
                if above_ema200 is not None and not above_ema200:
                    continue

                # Reversal candle filter
                if use_reversal:
                    reversal = self._detect_reversal_candle(df, 'bullish')
                    if not reversal.get("detected"):
                        continue

                sl = zone_bottom - atr * sl_buffer_atr
                sl_distance = abs(entry - sl)

                # Clamp SL distance
                min_sl_cfg: float = self.config.get("min_sl_usd", 1.0)
                max_sl_cfg: float = self.config.get("max_sl_usd", 15.0)
                sl_distance = max(min_sl_cfg, min(max_sl_cfg, sl_distance))

                sl = entry - sl_distance
                tp = entry + sl_distance * min_rr

                return TradeSetup(
                    direction="BUY",
                    entry_price=entry,
                    stop_loss=sl,
                    take_profit=tp,
                    setup_type=f"Confluence Zone Bounce (Long, score={score})",
                    confidence=min(100.0, float(score)),
                    metadata={
                        "zone_center": zone_center,
                        "zone_top": zone_top,
                        "zone_bottom": zone_bottom,
                        "confluence_score": score,
                        "levels_in_zone": zone["count"],
                        "level_types": zone["types"],
                        "rsi": current_rsi,
                    },
                )

            # === BEARISH: Price at upper part of zone (resistance rejection) ===
            if price_at_zone and price_above_center:
                # Only take if trend allows (below EMA200 or unknown)
                if above_ema200 is not None and above_ema200:
                    continue

                # Reversal candle filter
                if use_reversal:
                    reversal = self._detect_reversal_candle(df, 'bearish')
                    if not reversal.get("detected"):
                        continue

                sl = zone_top + atr * sl_buffer_atr
                sl_distance = abs(sl - entry)

                min_sl_cfg = self.config.get("min_sl_usd", 1.0)
                max_sl_cfg = self.config.get("max_sl_usd", 15.0)
                sl_distance = max(min_sl_cfg, min(max_sl_cfg, sl_distance))

                sl = entry + sl_distance
                tp = entry - sl_distance * min_rr

                return TradeSetup(
                    direction="SELL",
                    entry_price=entry,
                    stop_loss=sl,
                    take_profit=tp,
                    setup_type=f"Confluence Zone Bounce (Short, score={score})",
                    confidence=min(100.0, float(score)),
                    metadata={
                        "zone_center": zone_center,
                        "zone_top": zone_top,
                        "zone_bottom": zone_bottom,
                        "confluence_score": score,
                        "levels_in_zone": zone["count"],
                        "level_types": zone["types"],
                        "rsi": current_rsi,
                    },
                )

        return None

    def should_close_early(self, bar, df, position, day_context):
        """Exit if price breaks through the confluence zone against the trade."""
        atr = day_context.atr or 1.0
        current_close = bar['close']

        # Get the zone info from position metadata
        meta = position.strategy_metadata or {}
        zone_top = meta.get('zone_top')
        zone_bottom = meta.get('zone_bottom')

        if zone_top is None or zone_bottom is None:
            return None

        initial_risk = abs(position.entry_price - position.stop_loss)
        if initial_risk <= 0:
            return None

        # Zone break: price closes beyond zone + 1 ATR buffer (invalidation)
        if position.direction == 'BUY' and current_close < zone_bottom - atr:
            return "Zone Support Broken"
        elif position.direction == 'SELL' and current_close > zone_top + atr:
            return "Zone Resistance Broken"

        # Time decay: if held > 30 bars and not profitable, exit
        if hasattr(position, 'entry_time') and bar.name is not None:
            bars_held = len(df[df.index >= position.entry_time])
            if bars_held > 30:
                if position.direction == 'BUY' and current_close <= position.entry_price:
                    return "Time Decay (Stale Long)"
                elif position.direction == 'SELL' and current_close >= position.entry_price:
                    return "Time Decay (Stale Short)"

        return None

    # ------------------------------------------------------------------
    # Level collection
    # ------------------------------------------------------------------

    def _collect_levels(
        self,
        df: pd.DataFrame,
        ctx: DayContext,
        ema_slow_period: int,
        ema_very_slow_period: int,
    ) -> List[Tuple[float, str, int]]:
        """Collect all technical levels with their weights.

        Returns:
            List of ``(price, type_label, weight)`` tuples.
        """
        levels: List[Tuple[float, str, int]] = []
        close = df["close"]

        # --- EMAs ---
        ema_50 = close.ewm(span=ema_slow_period, adjust=False).mean()
        ema_200 = close.ewm(span=ema_very_slow_period, adjust=False).mean()

        if not pd.isna(ema_50.iloc[-1]):
            levels.append((float(ema_50.iloc[-1]), "ema_50", 20))
        if not pd.isna(ema_200.iloc[-1]):
            levels.append((float(ema_200.iloc[-1]), "ema_200", 25))

        # --- Session levels from DayContext ---
        level_weights: Dict[str, int] = {
            "asian_high": 15,
            "asian_low": 15,
            "pd_high": 15,
            "pd_low": 15,
            "london_high": 15,
            "london_low": 15,
            "orb_high": 10,
            "orb_low": 10,
        }
        for name, weight in level_weights.items():
            val = ctx.levels.get(name)
            if val is not None:
                levels.append((float(val), name, weight))

        # --- Round numbers ($50 intervals for Gold) ---
        current_price = float(close.iloc[-1])
        interval: int = self.config.get("round_number_interval", 100)
        base = int(current_price / interval) * interval
        for rn in [base - interval, base, base + interval, base + 2 * interval]:
            levels.append((float(rn), f"round_{rn}", 15))

        return levels

    # ------------------------------------------------------------------
    # Zone clustering
    # ------------------------------------------------------------------

    def _find_zones(
        self,
        levels: List[Tuple[float, str, int]],
        zone_width: float,
        min_levels: int,
    ) -> List[Dict[str, Any]]:
        """Cluster nearby levels into confluence zones.

        Uses a sliding-window over price-sorted levels.  Overlapping zones
        are deduplicated by keeping the highest scoring one.
        """
        if not levels:
            return []

        sorted_levels = sorted(levels, key=lambda x: x[0])
        zones: List[Dict[str, Any]] = []

        for i in range(len(sorted_levels)):
            zone_levels = [sorted_levels[i]]
            zone_score = sorted_levels[i][2]
            zone_types = [sorted_levels[i][1]]

            for j in range(i + 1, len(sorted_levels)):
                if sorted_levels[j][0] - sorted_levels[i][0] <= zone_width:
                    zone_levels.append(sorted_levels[j])
                    zone_score += sorted_levels[j][2]
                    zone_types.append(sorted_levels[j][1])
                else:
                    break

            if len(zone_levels) >= min_levels:
                prices = [lev[0] for lev in zone_levels]
                zones.append(
                    {
                        "center": sum(prices) / len(prices),
                        "top": max(prices) + zone_width * 0.1,
                        "bottom": min(prices) - zone_width * 0.1,
                        "score": zone_score,
                        "count": len(zone_levels),
                        "types": zone_types,
                    }
                )

        # Deduplicate overlapping zones -- keep highest scoring
        if len(zones) > 1:
            zones.sort(key=lambda z: z["score"], reverse=True)
            filtered: List[Dict[str, Any]] = [zones[0]]
            for zone in zones[1:]:
                overlaps = any(
                    zone["bottom"] <= existing["top"]
                    and zone["top"] >= existing["bottom"]
                    for existing in filtered
                )
                if not overlaps:
                    filtered.append(zone)
            zones = filtered

        return zones

    # ------------------------------------------------------------------
    # Reversal candle detection
    # ------------------------------------------------------------------

    def _detect_reversal_candle(self, df: pd.DataFrame, direction: str = 'both') -> Dict[str, Any]:
        """Detect reversal candle patterns on the *previous confirmed* bar.

        Supported patterns: pin bar (bullish/bearish), engulfing, hammer,
        shooting star.

        Args:
            df: Price dataframe
            direction: 'bullish', 'bearish', or 'both' to filter pattern type
        """
        if len(df) < 3:
            return {"detected": False}

        c = df.iloc[-2]  # Previous bar (confirmed)
        p = df.iloc[-3]  # Bar before that

        body = abs(c["close"] - c["open"])
        full_range = c["high"] - c["low"]
        if full_range < 0.01:
            return {"detected": False}

        upper_wick = c["high"] - max(c["open"], c["close"])
        lower_wick = min(c["open"], c["close"]) - c["low"]

        # Pin bar: one wick > 2x body, other wick tiny
        if lower_wick > body * 2 and upper_wick < body * 0.5:
            if direction in ['bullish', 'both']:
                return {"detected": True, "type": "bullish_pin_bar"}
        if upper_wick > body * 2 and lower_wick < body * 0.5:
            if direction in ['bearish', 'both']:
                return {"detected": True, "type": "bearish_pin_bar"}

        # Engulfing: current body > 1.5x previous body + opposite color
        prev_body = abs(p["close"] - p["open"])
        if body > prev_body * 1.5:
            if c["close"] > c["open"] and p["close"] < p["open"]:
                if direction in ['bullish', 'both']:
                    return {"detected": True, "type": "bullish_engulfing"}
            if c["close"] < c["open"] and p["close"] > p["open"]:
                if direction in ['bearish', 'both']:
                    return {"detected": True, "type": "bearish_engulfing"}

        # Hammer (bullish) / Shooting Star (bearish)
        if lower_wick > full_range * 0.6 and upper_wick < full_range * 0.1:
            if direction in ['bullish', 'both']:
                return {"detected": True, "type": "hammer"}
        if upper_wick > full_range * 0.6 and lower_wick < full_range * 0.1:
            if direction in ['bearish', 'both']:
                return {"detected": True, "type": "shooting_star"}

        return {"detected": False}

    # ------------------------------------------------------------------
    # Technical helpers
    # ------------------------------------------------------------------

    def _calculate_rsi(self, close: pd.Series, period: int) -> pd.Series:
        """Calculate RSI (Relative Strength Index)."""
        delta = close.diff()
        gain = delta.where(delta > 0, 0.0)
        loss = (-delta).where(delta < 0, 0.0)
        avg_gain = gain.ewm(alpha=1.0 / period, adjust=False).mean()
        avg_loss = loss.ewm(alpha=1.0 / period, adjust=False).mean()
        rs = avg_gain / avg_loss
        return 100 - (100 / (1 + rs))

    def _calculate_atr(self, df: pd.DataFrame, period: int) -> float:
        """Calculate Average True Range."""
        if len(df) < period:
            return 1.0
        high = df["high"]
        low = df["low"]
        close = df["close"]
        tr = pd.concat(
            [
                high - low,
                (high - close.shift(1)).abs(),
                (low - close.shift(1)).abs(),
            ],
            axis=1,
        ).max(axis=1)
        atr = tr.rolling(period).mean()
        if len(atr) > 0 and not pd.isna(atr.iloc[-1]):
            return float(atr.iloc[-1])
        return 1.0

    # ------------------------------------------------------------------
    # Lookback requirements
    # ------------------------------------------------------------------

    def get_required_lookback_bars(self) -> int:
        return max(220, self.config.get("ema_very_slow", 200) + 20)

    def get_required_daily_lookback_days(self) -> int:
        return 30
