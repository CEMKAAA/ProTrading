"""
ORB Backtest Strategy - Opening Range Breakout with ICT concepts.

Extracts the ORB-specific signal detection logic from BacktestEngine into a
reusable BacktestStrategy class.  The engine still handles position management,
cost simulation, and metrics; this class only owns:

  - Bias calculation (direction + strength scoring)
  - FVG (Fair Value Gap) detection
  - Displacement validation
  - Order Block detection
  - Trade setup generation
"""

import logging
from datetime import datetime
from typing import Optional, Dict, Any, Tuple

import numpy as np
import pandas as pd

from .base import BacktestStrategy, DayContext, TradeSetup

logger = logging.getLogger(__name__)


class ORBBacktestStrategy(BacktestStrategy):
    """
    Opening Range Breakout strategy using ICT concepts.

    Detects FVG + Order Block setups after ORB breakout with bias confirmation.
    Receives its config dict from optimal_parameters + preset overrides
    (see strategy_registry.py).
    """

    # ------------------------------------------------------------------
    # BacktestStrategy interface
    # ------------------------------------------------------------------

    def initialize_day(
        self,
        date: datetime,
        daily_df: Optional[pd.DataFrame],
        intraday_df: pd.DataFrame,
    ) -> DayContext:
        """
        Set up the day context.

        ATR is calculated here; bias/strength are deferred to ``calculate_bias``
        because they depend on ORB levels that the engine calculates *after*
        this method returns.
        """
        ctx = DayContext(date=date)

        # ATR for slippage and bias strength normalisation
        atr = 1.0
        if intraday_df is not None and len(intraday_df) >= 14:
            atr = self._calculate_atr(intraday_df, 14)
        ctx.atr = atr

        # Bias will be set later via calculate_bias() once ORB levels exist
        ctx.bias = "neutral"
        ctx.bias_strength = 0

        return ctx

    def calculate_bias(
        self, ctx: DayContext, current_price: float
    ) -> DayContext:
        """
        Calculate bias direction and strength *after* the engine has populated
        session levels (ORB, Asian, PD, London) inside ``ctx.levels``.

        Called by the engine once per day right after ORB levels are known.
        """
        bias, strength = self._calculate_bias_strength(
            current_price, ctx.atr, ctx.levels
        )
        ctx.bias = bias
        ctx.bias_strength = strength
        return ctx

    def find_setup(
        self,
        bar: pd.Series,
        df: pd.DataFrame,
        day_context: DayContext,
        current_bar_index: int,
    ) -> Optional[TradeSetup]:
        """
        Look for an ORB breakout setup with FVG confirmation.

        Signal detection uses the *previous* bar (``df.iloc[-2]``) to confirm
        the pattern.  Entry will happen at the current bar's open (the engine
        handles that).
        """
        if len(df) < 10:
            return None

        bias = day_context.bias
        bias_strength = day_context.bias_strength
        orb_high = day_context.levels.get("orb_high")
        orb_low = day_context.levels.get("orb_low")

        if bias == "neutral":
            return None

        # Require minimum bias strength
        min_strength = self.config.get("bias_min_strength", 30)
        if bias_strength < min_strength:
            return None

        # Cap maximum bias strength — very high scores often mean the move
        # is already overextended and likely to reverse (data-driven finding).
        max_strength = self.config.get("max_bias_strength", 100)
        if bias_strength > max_strength:
            return None

        # Direction filter: "both", "long_only", or "short_only"
        allowed_dir = self.config.get("allowed_directions", "both")
        if allowed_dir == "long_only" and bias != "bullish":
            return None
        elif allowed_dir == "short_only" and bias != "bearish":
            return None

        if orb_high is None or orb_low is None:
            return None

        # Volatility-aware ORB quality filter. Very small ORBs are noisy,
        # very large ORBs are often exhausted by the time breakouts print.
        # Use daily ATR (ADR) for normalization since ORB spans 15 minutes;
        # M1 ATR would give disproportionately high ratios.
        daily_atr = day_context.levels.get('daily_atr', 0)
        if daily_atr > 0:
            atr = daily_atr
            # Daily ATR bounds: ORB is typically 5-60% of daily range
            min_ratio = self.config.get("min_orb_range_daily", 0.05)
            max_ratio = self.config.get("max_orb_range_daily", 0.60)
        else:
            atr = max(day_context.atr, 0.01)
            min_ratio = self.config.get("min_orb_range_atr", 0.5)
            max_ratio = self.config.get("max_orb_range_atr", 3.0)
        orb_range = abs(orb_high - orb_low)
        orb_range_atr = orb_range / atr
        if orb_range_atr < min_ratio or orb_range_atr > max_ratio:
            return None

        # Use previous bar's close for signal detection (pattern confirmed)
        signal_bar = df.iloc[-2]
        signal_close = signal_bar["close"]

        # --- Breakout quality filters ---
        # Filter 1: Breakout distance — close must be meaningfully beyond ORB,
        # not just barely clipping the level (common in false breakouts).
        min_bo_dist = float(self.config.get("min_breakout_distance_atr", 0.0))
        if min_bo_dist > 0 and atr > 0:
            if bias == "bullish" and signal_close > orb_high:
                if (signal_close - orb_high) / atr < min_bo_dist:
                    return None
            elif bias == "bearish" and signal_close < orb_low:
                if (orb_low - signal_close) / atr < min_bo_dist:
                    return None

        # Filter 2: Breakout candle body — dojis and tiny-body candles near
        # ORB boundary indicate indecision, not conviction.
        min_bo_body = float(self.config.get("min_breakout_body_atr", 0.0))
        if min_bo_body > 0 and atr > 0:
            body = abs(signal_bar["close"] - signal_bar["open"])
            if body / atr < min_bo_body:
                return None

        # FVG-optional threshold: when bias is very strong and breakout shows
        # displacement, enter even without a 3-candle FVG.  The ORB breakout
        # level itself acts as the SL anchor.
        fvg_optional_threshold = self.config.get("fvg_optional_threshold", None)

        # --- Bullish setup ---
        if bias == "bullish" and signal_close > orb_high:
            fvg = self._find_fvg(df, "bullish")
            if fvg:
                # Filter 3: FVG size relative to daily ATR —
                # tiny FVGs on big-ATR days are noise.
                min_fvg_atr = float(self.config.get("min_fvg_size_atr", 0.0))
                if min_fvg_atr > 0 and atr > 0:
                    if fvg["size"] / atr < min_fvg_atr:
                        fvg = None  # Demote: too small, try FVG-optional path

            if fvg:
                ob = self._find_order_block(df, "bullish")

                # Filter 4: Require OB confluence (FVG + OB = double confirmation)
                if self.config.get("require_ob_confluence", False) and not ob:
                    return None

                # ORB+imbalance model: stop anchored to imbalance boundary.
                sl = fvg["bottom"]
                entry = bar["open"]
                if sl >= entry:
                    return None
                sl_distance = entry - sl
                if not self._passes_spread_efficiency(sl_distance):
                    return None
                rr_ratio = self._plan_rr(sl_distance, bias_strength)
                tp = entry + (sl_distance * rr_ratio)
                return TradeSetup(
                    direction="BUY",
                    entry_price=entry,
                    stop_loss=sl,
                    take_profit=tp,
                    setup_type="Bullish ORB Breakout + 3-Candle Imbalance",
                    confidence=bias_strength,
                    metadata={
                        "fvg": fvg,
                        "ob": None,
                        "rr_plan": rr_ratio,
                        "allow_sub2_rr": rr_ratio < 2.0,
                        "skip_out_of_bounds_sl": True,
                        "bias_strength": bias_strength,
                    },
                )

            # --- FVG-optional path: strong bias + displacement on breakout bar ---
            if (fvg_optional_threshold is not None
                    and bias_strength >= fvg_optional_threshold
                    and self._has_displacement(df, signal_bar, "bullish")):
                entry = bar["open"]
                # SL: just below ORB high (breakout level) with small buffer
                sl_buffer = atr * float(self.config.get("fvg_optional_sl_buffer", 0.15))
                sl = orb_high - sl_buffer
                if sl >= entry:
                    return None
                sl_distance = entry - sl
                if not self._passes_spread_efficiency(sl_distance):
                    return None
                rr_ratio = self._plan_rr(sl_distance, bias_strength)
                tp = entry + (sl_distance * rr_ratio)
                return TradeSetup(
                    direction="BUY",
                    entry_price=entry,
                    stop_loss=sl,
                    take_profit=tp,
                    setup_type="Bullish ORB Breakout + Displacement (No FVG)",
                    confidence=bias_strength,
                    metadata={
                        "fvg": None,
                        "ob": None,
                        "rr_plan": rr_ratio,
                        "allow_sub2_rr": rr_ratio < 2.0,
                        "skip_out_of_bounds_sl": True,
                        "bias_strength": bias_strength,
                        "fvg_optional": True,
                    },
                )

        # --- Bearish setup ---
        elif bias == "bearish" and signal_close < orb_low:
            fvg = self._find_fvg(df, "bearish")
            if fvg:
                # Filter 3: FVG size relative to daily ATR
                min_fvg_atr = float(self.config.get("min_fvg_size_atr", 0.0))
                if min_fvg_atr > 0 and atr > 0:
                    if fvg["size"] / atr < min_fvg_atr:
                        fvg = None  # Demote: too small, try FVG-optional path

            if fvg:
                ob = self._find_order_block(df, "bearish")

                # Filter 4: Require OB confluence
                if self.config.get("require_ob_confluence", False) and not ob:
                    return None

                # ORB+imbalance model: stop anchored to imbalance boundary.
                sl = fvg["top"]
                entry = bar["open"]
                if sl <= entry:
                    return None
                sl_distance = sl - entry
                if not self._passes_spread_efficiency(sl_distance):
                    return None
                rr_ratio = self._plan_rr(sl_distance, bias_strength)
                tp = entry - (sl_distance * rr_ratio)
                return TradeSetup(
                    direction="SELL",
                    entry_price=entry,
                    stop_loss=sl,
                    take_profit=tp,
                    setup_type="Bearish ORB Breakout + 3-Candle Imbalance",
                    confidence=bias_strength,
                    metadata={
                        "fvg": fvg,
                        "ob": None,
                        "rr_plan": rr_ratio,
                        "allow_sub2_rr": rr_ratio < 2.0,
                        "skip_out_of_bounds_sl": True,
                        "bias_strength": bias_strength,
                    },
                )

            # --- FVG-optional path: strong bias + displacement on breakout bar ---
            if (fvg_optional_threshold is not None
                    and bias_strength >= fvg_optional_threshold
                    and self._has_displacement(df, signal_bar, "bearish")):
                entry = bar["open"]
                # SL: just above ORB low (breakout level) with small buffer
                sl_buffer = atr * float(self.config.get("fvg_optional_sl_buffer", 0.15))
                sl = orb_low + sl_buffer
                if sl <= entry:
                    return None
                sl_distance = sl - entry
                if not self._passes_spread_efficiency(sl_distance):
                    return None
                rr_ratio = self._plan_rr(sl_distance, bias_strength)
                tp = entry - (sl_distance * rr_ratio)
                return TradeSetup(
                    direction="SELL",
                    entry_price=entry,
                    stop_loss=sl,
                    take_profit=tp,
                    setup_type="Bearish ORB Breakout + Displacement (No FVG)",
                    confidence=bias_strength,
                    metadata={
                        "fvg": None,
                        "ob": None,
                        "rr_plan": rr_ratio,
                        "allow_sub2_rr": rr_ratio < 2.0,
                        "skip_out_of_bounds_sl": True,
                        "bias_strength": bias_strength,
                        "fvg_optional": True,
                    },
                )

        return None

    def get_required_lookback_bars(self) -> int:
        """Strategy needs enough bars for FVG + displacement scanning."""
        return max(100, self.config.get("fvg_lookback", 50) + 10)

    # ------------------------------------------------------------------
    # ICT pattern-detection helpers (private)
    # ------------------------------------------------------------------

    @staticmethod
    def _calculate_atr(df: pd.DataFrame, period: int) -> float:
        """Simple ATR from a DataFrame."""
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
    # Bias strength scoring  (mirrors engine._calculate_bias_strength)
    # ------------------------------------------------------------------

    @staticmethod
    def _calculate_bias_strength(
        current_price: float,
        atr: float,
        levels: Dict[str, float],
    ) -> Tuple[str, int]:
        """
        Calculate bias direction and strength score (0-100).

        Matches the live bot's ``calculate_bias_strength`` logic exactly.
        """
        if atr <= 0:
            atr = 1.0

        orb_high = levels.get("orb_high")
        orb_low = levels.get("orb_low")
        asian_high = levels.get("asian_high")
        asian_low = levels.get("asian_low")
        pd_high = levels.get("pd_high")
        pd_low = levels.get("pd_low")
        london_high = levels.get("london_high")
        london_low = levels.get("london_low")

        bullish_score = 0
        bearish_score = 0

        # ORB Bias (30 pts max)
        if orb_high is not None and orb_low is not None:
            if current_price > orb_high:
                extension = (current_price - orb_high) / atr
                bullish_score += min(30, int(15 + extension * 15))
            elif current_price < orb_low:
                extension = (orb_low - current_price) / atr
                bearish_score += min(30, int(15 + extension * 15))

        # Asian Session Bias (25 pts max)
        if asian_high is not None and asian_low is not None:
            if current_price > asian_high:
                extension = (current_price - asian_high) / atr
                bullish_score += min(25, int(12 + extension * 13))
            elif current_price < asian_low:
                extension = (asian_low - current_price) / atr
                bearish_score += min(25, int(12 + extension * 13))

        # Previous Day Bias (25 pts max)
        if pd_high is not None and pd_low is not None:
            if current_price > pd_high:
                extension = (current_price - pd_high) / atr
                bullish_score += min(25, int(12 + extension * 13))
            elif current_price < pd_low:
                extension = (pd_low - current_price) / atr
                bearish_score += min(25, int(12 + extension * 13))

        # London session confluence (20 pts max)
        if london_high is not None and london_low is not None:
            london_mid = (london_high + london_low) / 2
            if current_price > london_high:
                bullish_score += 15
            elif current_price > london_mid:
                bullish_score += 8
            elif current_price < london_low:
                bearish_score += 15
            elif current_price < london_mid:
                bearish_score += 8

        if bullish_score > bearish_score:
            return "bullish", min(100, bullish_score)
        elif bearish_score > bullish_score:
            return "bearish", min(100, bearish_score)
        else:
            return "neutral", 0

    # ------------------------------------------------------------------
    # FVG detection  (mirrors engine._find_fvg)
    # ------------------------------------------------------------------

    def _find_fvg(
        self, df: pd.DataFrame, direction: str
    ) -> Optional[Dict[str, Any]]:
        """
        Find most-recent 3-candle FVG (imbalance) scanning backwards.

        Scans the last ``fvg_scan_window`` 3-candle groups (default 25) to
        find the freshest valid FVG.  The previous implementation only checked
        the very last group, which on M1 data meant each FVG had a single
        1-minute chance to be detected.
        """
        if len(df) < 4:
            return None

        min_gap = self.config.get("min_fvg_gap", 0.30)
        max_window = max(3, int(self.config.get("fvg_lookback", 50)))
        scan_window = min(
            max_window,
            int(self.config.get("fvg_scan_window", 25)),
            len(df) - 3,
        )
        require_unfilled = bool(self.config.get("require_unfilled_fvg", True))

        # Scan backwards: offset 0 = most recent completed group
        for offset in range(scan_window):
            # c3 is the third candle of the group (last in the trio)
            c3_idx = len(df) - 2 - offset
            if c3_idx < 2:
                break
            c1 = df.iloc[c3_idx - 2]
            c2 = df.iloc[c3_idx - 1]  # displacement candle
            c3 = df.iloc[c3_idx]

            # Truncate df to end at c3 so _has_displacement measures
            # the baseline from bars *before* the trio (no future data).
            df_truncated = df.iloc[: c3_idx + 1]

            if direction == "bullish":
                gap = c3["low"] - c1["high"]
                if gap > min_gap and self._has_displacement(
                    df_truncated, c2, "bullish"
                ):
                    if require_unfilled:
                        bars_after = df.iloc[c3_idx + 1 : -1]
                        if not bars_after.empty and bars_after["low"].min() < c1["high"]:
                            continue
                    return {
                        "type": "bullish_fvg",
                        "top": c3["low"],
                        "bottom": c1["high"],
                        "size": gap,
                        "time": c2.name,
                    }
            else:
                gap = c1["low"] - c3["high"]
                if gap > min_gap and self._has_displacement(
                    df_truncated, c2, "bearish"
                ):
                    if require_unfilled:
                        bars_after = df.iloc[c3_idx + 1 : -1]
                        if not bars_after.empty and bars_after["high"].max() > c1["low"]:
                            continue
                    return {
                        "type": "bearish_fvg",
                        "top": c1["low"],
                        "bottom": c3["high"],
                        "size": gap,
                        "time": c2.name,
                    }

        return None

    def _plan_rr(self, sl_distance: float, bias_strength: int) -> float:
        """
        Dynamic R:R planning with a hard floor.

        - Tight structural stops can target higher R.
        - Wider stops still require >= min_rr_target so expectancy isn't
          dominated by cost drag.
        """
        rr_threshold = float(self.config.get("gold_rr_threshold", 3.0))
        tight_rr = float(self.config.get("rr_tight_sl_target", 3.0))
        wide_rr = float(self.config.get("rr_wide_sl_target", 2.0))
        min_rr = float(self.config.get("min_rr_target", 2.0))
        strong_bias_threshold = int(self.config.get("bias_strong_threshold", 70))
        strong_bias_bonus = float(self.config.get("rr_bias_bonus", 0.0))

        rr = tight_rr if sl_distance < rr_threshold else wide_rr
        if bias_strength >= strong_bias_threshold:
            rr += strong_bias_bonus
        return max(min_rr, rr)

    def _passes_spread_efficiency(self, sl_distance: float) -> bool:
        """
        Filter out setups where configured max spread is too large relative to SL.
        """
        max_ratio = float(self.config.get("max_spread_to_sl_ratio", 0.0))
        if max_ratio <= 0 or sl_distance <= 0:
            return True
        est_spread = float(self.config.get("max_spread_usd", 0.40))
        ratio = est_spread / sl_distance
        return ratio <= max_ratio

    # ------------------------------------------------------------------
    # Displacement validation  (mirrors engine._has_displacement)
    # ------------------------------------------------------------------

    def _has_displacement(
        self, df: pd.DataFrame, candle: pd.Series, direction: str
    ) -> bool:
        """Check if *candle* shows strong displacement."""
        lookback = self.config.get("displacement_lookback", 20)
        if len(df) < lookback + 3:
            return False

        recent = df.iloc[-lookback - 3 : -3]
        recent_bodies = (recent["close"] - recent["open"]).abs()
        percentile = self.config.get("displacement_percentile", 75)
        threshold = recent_bodies.quantile(percentile / 100.0)

        if direction == "bullish":
            body = candle["close"] - candle["open"]
            if body <= 0:
                return False
            opposing_wick = candle["high"] - candle["close"]
        else:
            body = candle["open"] - candle["close"]
            if body <= 0:
                return False
            opposing_wick = candle["close"] - candle["low"]

        max_wick_ratio = self.config.get("max_opposing_wick_ratio", 0.5)
        strong_body = body >= threshold
        small_wick = opposing_wick < (body * max_wick_ratio)

        return strong_body and small_wick

    # ------------------------------------------------------------------
    # Order Block detection  (mirrors engine._find_order_block)
    # ------------------------------------------------------------------

    def _find_order_block(
        self, df: pd.DataFrame, direction: str
    ) -> Optional[Dict[str, Any]]:
        """
        Find Order Block pattern matching the live bot logic exactly.

        - Bullish OB = last *bearish* candle before bullish impulse
        - Bearish OB = last *bullish* candle before bearish impulse
        """
        ob_lookback = min(self.config.get("ob_lookback", 100), len(df) - 2)
        if ob_lookback < 5:
            return None

        scan_range = df.iloc[-ob_lookback:-2]
        validation_bars = self.config.get("ob_validation_bars", 3)
        min_body_pct = self.config.get("ob_min_body_percent", 60)

        for i in range(len(scan_range) - validation_bars - 1, -1, -1):
            candle = scan_range.iloc[i]
            candle_range = candle["high"] - candle["low"]

            if candle_range < 0.10:
                continue

            validation_candles = scan_range.iloc[i + 1 : i + 1 + validation_bars]
            if len(validation_candles) < validation_bars:
                continue

            if direction == "bullish":
                # Bullish OB: bearish candle (open > close)
                is_bearish_candle = candle["open"] > candle["close"]
                if not is_bearish_candle:
                    continue

                body = candle["open"] - candle["close"]
                body_percent = (body / candle_range) * 100
                if body_percent < min_body_pct:
                    continue

                impulse_up = (
                    validation_candles["close"].iloc[-1] > candle["high"]
                    and validation_candles["low"].min() > candle["low"]
                )
                not_violated = df.iloc[-10:]["low"].min() > candle["low"]

                if impulse_up and not_violated:
                    return {
                        "type": "bullish_ob",
                        "high": candle["high"],
                        "low": candle["low"],
                        "body_pct": body_percent,
                        "time": candle.name,
                    }

            else:  # bearish
                # Bearish OB: bullish candle (close > open)
                is_bullish_candle = candle["close"] > candle["open"]
                if not is_bullish_candle:
                    continue

                body = candle["close"] - candle["open"]
                body_percent = (body / candle_range) * 100
                if body_percent < min_body_pct:
                    continue

                impulse_down = (
                    validation_candles["close"].iloc[-1] < candle["low"]
                    and validation_candles["high"].max() < candle["high"]
                )
                not_violated = df.iloc[-10:]["high"].max() < candle["high"]

                if impulse_down and not_violated:
                    return {
                        "type": "bearish_ob",
                        "high": candle["high"],
                        "low": candle["low"],
                        "body_pct": body_percent,
                        "time": candle.name,
                    }

        return None
