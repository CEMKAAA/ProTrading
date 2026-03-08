"""
Session Liquidity Sweep Reversal Strategy.

Gold consistently sweeps retail stop-losses at obvious session levels
(Asian high/low, Previous Day high/low), then reverses.  This strategy
exploits that institutional behaviour.

Why this works for Gold:
  - Institutional traders hunt retail stops placed at Asian session H/L.
  - After the sweep, smart money enters in the opposite direction.
  - Gold's strong session-based behaviour makes this highly repeatable.
  - Best during NY session (9:30-12:00) when London overlap provides liquidity.

Entry Rules:
  1. Identify Liquidity Level: Asian H/L, Previous Day H/L, or round number.
  2. Detect Sweep: Price breaks the level by at least ``sweep_min_penetration_atr``
     multiples of ATR (wick through).
  3. Rejection: Within ``sweep_max_bars_to_reject`` bars of the sweep, price must
     close back on the opposite side of the level.
  4. Displacement: The rejection candle body must exceed the
     ``rejection_body_percentile``-th percentile of recent candle bodies.
  5. FVG Formation: A FVG forms in the reversal direction after the sweep
     (optional via ``require_fvg_after_sweep``).
  6. Entry: At the next bar open after the rejection is confirmed.
  7. Stop Loss: Beyond the sweep wick extreme + ``sl_buffer_atr`` * ATR.
  8. Take Profit: Opposite session level, or ``min_rr_ratio`` * risk,
     whichever yields the larger move.
"""

import logging
from datetime import datetime
from typing import Optional, Dict, Any, List

import numpy as np
import pandas as pd

from .base import BacktestStrategy, DayContext, TradeSetup

logger = logging.getLogger(__name__)


class LiquiditySweepStrategy(BacktestStrategy):
    """
    Session Liquidity Sweep Reversal Strategy.

    Exploits institutional stop-hunting at session levels with reversal
    entries confirmed by displacement and optional FVG.
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
        """Set up daily context with ATR."""
        ctx = DayContext(date=date)

        if intraday_df is not None and len(intraday_df) >= 14:
            ctx.atr = self._calculate_atr(intraday_df, 14)

        # Bias is not required for this strategy; sweeps are direction-agnostic.
        ctx.bias = "neutral"
        ctx.bias_strength = 0

        return ctx

    def find_setup(
        self,
        bar: pd.Series,
        df: pd.DataFrame,
        day_context: DayContext,
        current_bar_index: int,
    ) -> Optional[TradeSetup]:
        """
        Scan each bar for a completed sweep-rejection pattern at any
        tracked liquidity level.
        """
        if len(df) < 10:
            return None

        atr = day_context.atr
        if atr <= 0:
            atr = 1.0

        # ----- configurable knobs -----
        sweep_min_pen = self.config.get("sweep_min_penetration_atr", 0.3)
        max_bars_reject = self.config.get("sweep_max_bars_to_reject", 5)
        body_percentile = self.config.get("rejection_body_percentile", 60)
        require_fvg = self.config.get("require_fvg_after_sweep", True)
        min_rr = self.config.get("min_rr_ratio", 3.0)
        sl_buffer = self.config.get("sl_buffer_atr", 0.3)
        use_round_numbers = self.config.get("use_round_numbers", True)
        round_interval = self.config.get("round_number_interval", 50)

        # Build the set of liquidity levels to watch
        liquidity_levels = self._build_liquidity_levels(
            day_context, bar, use_round_numbers, round_interval
        )
        if not liquidity_levels:
            return None

        # Evaluate each level
        for level_info in liquidity_levels:
            setup = self._check_sweep(
                df=df,
                bar=bar,
                level=level_info["level"],
                direction=level_info["direction"],
                atr=atr,
                min_pen=sweep_min_pen,
                max_bars=max_bars_reject,
                body_pctl=body_percentile,
                require_fvg=require_fvg,
                min_rr=min_rr,
                sl_buffer=sl_buffer,
                ctx=day_context,
            )
            if setup is not None:
                setup.metadata["level_type"] = level_info["type"]
                return setup

        return None

    def should_close_early(self, bar, df, position, day_context):
        """Exit if sweep thesis is invalidated."""
        current_close = bar['close']
        atr = day_context.atr or 1.0

        meta = position.strategy_metadata or {}
        sweep_level = meta.get('sweep_level')

        if sweep_level is None:
            return None

        initial_risk = abs(position.entry_price - position.stop_loss)
        if initial_risk <= 0:
            return None

        # Sweep invalidation: price retakes the swept level decisively
        # (closes beyond it by > 0.5 ATR = the sweep was a real breakout, not a fake-out)
        if position.direction == 'BUY':
            # We went long after a bearish sweep (price swept below and reversed up)
            # Invalidation: price falls back below the swept level
            if current_close < sweep_level - atr * 0.5:
                return "Sweep Invalidated (Price Below Swept Level)"
        else:
            # We went short after a bullish sweep (price swept above and reversed down)
            # Invalidation: price rises back above the swept level
            if current_close > sweep_level + atr * 0.5:
                return "Sweep Invalidated (Price Above Swept Level)"

        # Momentum fade: if reversal loses steam (price stalls for many bars)
        if hasattr(position, 'entry_time') and bar.name is not None:
            bars_held = len(df[df.index >= position.entry_time])
            if bars_held > 25:
                pnl_r = 0
                if position.direction == 'BUY':
                    pnl_r = (current_close - position.entry_price) / initial_risk
                else:
                    pnl_r = (position.entry_price - current_close) / initial_risk
                # If held 25+ bars and less than 0.5R profit, momentum is dead
                if pnl_r < 0.5:
                    return "Momentum Fade (Stale Trade)"

        return None

    def get_required_lookback_bars(self) -> int:
        """Strategy needs enough history for body-percentile and FVG scans."""
        return 100

    # ------------------------------------------------------------------
    # Liquidity level construction
    # ------------------------------------------------------------------

    def _build_liquidity_levels(
        self,
        ctx: DayContext,
        bar: pd.Series,
        use_round: bool,
        interval: float,
    ) -> List[Dict[str, Any]]:
        """
        Assemble a list of liquidity levels to monitor.

        Each entry is ``{"level": float, "type": str, "direction": str}``
        where *direction* is the expected trade direction **after** the
        sweep (i.e. the reversal direction).
        """
        levels: List[Dict[str, Any]] = []

        # --- Session levels from DayContext.levels ---
        ah = ctx.levels.get("asian_high")
        al = ctx.levels.get("asian_low")
        ph = ctx.levels.get("pd_high")
        pl = ctx.levels.get("pd_low")
        lh = ctx.levels.get("london_high")
        ll = ctx.levels.get("london_low")

        if ah is not None:
            levels.append({"level": ah, "type": "asian_high", "direction": "SELL"})
        if al is not None:
            levels.append({"level": al, "type": "asian_low", "direction": "BUY"})
        if ph is not None:
            levels.append({"level": ph, "type": "pd_high", "direction": "SELL"})
        if pl is not None:
            levels.append({"level": pl, "type": "pd_low", "direction": "BUY"})
        # London session extremes — frequently swept during NY open
        if lh is not None:
            levels.append({"level": lh, "type": "london_high", "direction": "SELL"})
        if ll is not None:
            levels.append({"level": ll, "type": "london_low", "direction": "BUY"})

        # --- Round numbers near the current price ---
        if use_round:
            price = bar["close"]
            base = int(price / interval) * interval
            candidates = [
                base - interval,
                base,
                base + interval,
                base + 2 * interval,
            ]
            for rn in candidates:
                # Only consider round numbers within 2 % of price
                if abs(price - rn) < price * 0.02:
                    if rn > price:
                        levels.append(
                            {"level": rn, "type": f"round_{int(rn)}", "direction": "SELL"}
                        )
                    else:
                        levels.append(
                            {"level": rn, "type": f"round_{int(rn)}", "direction": "BUY"}
                        )

        return levels

    # ------------------------------------------------------------------
    # Core sweep-rejection detection
    # ------------------------------------------------------------------

    def _check_sweep(
        self,
        df: pd.DataFrame,
        bar: pd.Series,
        level: float,
        direction: str,
        atr: float,
        min_pen: float,
        max_bars: int,
        body_pctl: float,
        require_fvg: bool,
        min_rr: float,
        sl_buffer: float,
        ctx: DayContext,
    ) -> Optional[TradeSetup]:
        """
        Check whether a sweep + rejection has occurred at *level*.

        Parameters
        ----------
        direction : str
            Expected trade direction after the sweep (``"BUY"`` or ``"SELL"``).
        """
        if direction == "SELL":
            return self._check_bearish_sweep(
                df, bar, level, atr, min_pen, max_bars,
                body_pctl, require_fvg, min_rr, sl_buffer, ctx,
            )
        else:
            return self._check_bullish_sweep(
                df, bar, level, atr, min_pen, max_bars,
                body_pctl, require_fvg, min_rr, sl_buffer, ctx,
            )

    # ---------- Bearish sweep (price breaks above level, then reverses) ----------

    def _check_bearish_sweep(
        self,
        df: pd.DataFrame,
        bar: pd.Series,
        level: float,
        atr: float,
        min_pen: float,
        max_bars: int,
        body_pctl: float,
        require_fvg: bool,
        min_rr: float,
        sl_buffer: float,
        ctx: DayContext,
    ) -> Optional[TradeSetup]:
        """Detect a sweep above *level* followed by a bearish rejection."""
        lookback = min(max_bars + 2, len(df) - 1)
        recent = df.iloc[-lookback:]

        # 1) Find the most recent valid sweep + rejection sequence.
        sweep_bar_idx = None
        sweep_high = None
        rejection_bar = None
        for i in range(len(recent) - 1, -1, -1):
            bar_high = recent.iloc[i]["high"]
            if bar_high > level + atr * min_pen:
                for j in range(i, min(i + max_bars + 1, len(recent))):
                    if recent.iloc[j]["close"] < level:
                        sweep_bar_idx = i
                        sweep_high = bar_high
                        rejection_bar = recent.iloc[j]
                        break
                if rejection_bar is not None:
                    break

        if sweep_bar_idx is None or rejection_bar is None:
            return None

        # 3) Displacement: rejection candle body size check
        if not self._has_displacement_body(df, rejection_bar, body_pctl):
            return None

        # 4) Optional FVG confirmation
        if require_fvg:
            sweep_bar_timestamp = recent.iloc[sweep_bar_idx].name
            fvg = self._find_simple_fvg(df, "bearish", sweep_bar_timestamp)
            if fvg is None:
                return None

        # 5) Build the trade setup
        entry = bar["open"]
        sl = sweep_high + atr * sl_buffer
        sl_distance = abs(sl - entry)

        # Clamp SL distance
        min_sl_cfg = self.config.get("min_sl_usd", 1.0)
        max_sl_cfg = self.config.get("max_sl_usd", 15.0)
        sl_distance = max(min_sl_cfg, min(max_sl_cfg, sl_distance))
        sl = entry + sl_distance

        # TP: opposite session level or min R:R, whichever is further
        target_levels = [
            v for k, v in ctx.levels.items()
            if v is not None and v < entry and "low" in k
        ]
        tp_target = max(target_levels) if target_levels else None
        tp_rr = entry - sl_distance * min_rr

        if tp_target is not None:
            tp = min(tp_target, tp_rr)
        else:
            tp = tp_rr

        return TradeSetup(
            direction="SELL",
            entry_price=entry,
            stop_loss=sl,
            take_profit=tp,
            setup_type="Liquidity Sweep Reversal (Short)",
            confidence=75,
            metadata={
                "sweep_level": level,
                "sweep_high": sweep_high,
            },
        )

    # ---------- Bullish sweep (price breaks below level, then reverses) ----------

    def _check_bullish_sweep(
        self,
        df: pd.DataFrame,
        bar: pd.Series,
        level: float,
        atr: float,
        min_pen: float,
        max_bars: int,
        body_pctl: float,
        require_fvg: bool,
        min_rr: float,
        sl_buffer: float,
        ctx: DayContext,
    ) -> Optional[TradeSetup]:
        """Detect a sweep below *level* followed by a bullish rejection."""
        lookback = min(max_bars + 2, len(df) - 1)
        recent = df.iloc[-lookback:]

        # 1) Find the most recent valid sweep + rejection sequence.
        sweep_bar_idx = None
        sweep_low = None
        rejection_bar = None
        for i in range(len(recent) - 1, -1, -1):
            bar_low = recent.iloc[i]["low"]
            if bar_low < level - atr * min_pen:
                for j in range(i, min(i + max_bars + 1, len(recent))):
                    if recent.iloc[j]["close"] > level:
                        sweep_bar_idx = i
                        sweep_low = bar_low
                        rejection_bar = recent.iloc[j]
                        break
                if rejection_bar is not None:
                    break

        if sweep_bar_idx is None or rejection_bar is None:
            return None

        # 3) Displacement: rejection candle body size check
        if not self._has_displacement_body(df, rejection_bar, body_pctl):
            return None

        # 4) Optional FVG confirmation
        if require_fvg:
            sweep_bar_timestamp = recent.iloc[sweep_bar_idx].name
            fvg = self._find_simple_fvg(df, "bullish", sweep_bar_timestamp)
            if fvg is None:
                return None

        # 5) Build the trade setup
        entry = bar["open"]
        sl = sweep_low - atr * sl_buffer
        sl_distance = abs(entry - sl)

        # Clamp SL distance
        min_sl_cfg = self.config.get("min_sl_usd", 1.0)
        max_sl_cfg = self.config.get("max_sl_usd", 15.0)
        sl_distance = max(min_sl_cfg, min(max_sl_cfg, sl_distance))
        sl = entry - sl_distance

        # TP: opposite session level or min R:R, whichever is further
        target_levels = [
            v for k, v in ctx.levels.items()
            if v is not None and v > entry and "high" in k
        ]
        tp_target = min(target_levels) if target_levels else None
        tp_rr = entry + sl_distance * min_rr

        if tp_target is not None:
            tp = max(tp_target, tp_rr)
        else:
            tp = tp_rr

        return TradeSetup(
            direction="BUY",
            entry_price=entry,
            stop_loss=sl,
            take_profit=tp,
            setup_type="Liquidity Sweep Reversal (Long)",
            confidence=75,
            metadata={
                "sweep_level": level,
                "sweep_low": sweep_low,
            },
        )

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _has_displacement_body(
        df: pd.DataFrame, rejection_bar: pd.Series, body_pctl: float
    ) -> bool:
        """
        Check that the rejection candle's body is in the top
        *body_pctl* percentile of recent candle bodies.
        """
        bodies = (df["close"] - df["open"]).abs()
        if len(bodies) < 20:
            return True  # not enough data; skip the filter
        threshold = bodies.iloc[-20:].quantile(body_pctl / 100.0)
        rejection_body = abs(rejection_bar["close"] - rejection_bar["open"])
        return rejection_body >= threshold

    def _find_simple_fvg(
        self, df: pd.DataFrame, direction: str, sweep_timestamp=None
    ) -> Optional[Dict[str, Any]]:
        """
        Lightweight FVG detection for sweep confirmation.

        Scans the most recent bars (up to 8 back) for a three-candle gap
        pattern exceeding ``fvg_min_gap``.

        If sweep_timestamp is provided, ensures the FVG formed after the sweep.
        """
        if len(df) < 5:
            return None

        # Preferred key is min_fvg_gap (registry/builder). Keep legacy fallback.
        min_gap = self.config.get("min_fvg_gap", self.config.get("fvg_min_gap", 0.15))

        for offset in range(2, min(8, len(df) - 2)):
            c1 = df.iloc[-offset - 2]
            c3 = df.iloc[-offset]

            # Validate FVG timing: c1 (the oldest candle of the FVG pattern)
            # must be at or after the sweep bar — ensures entire FVG formed
            # as a result of the post-sweep reversal, not before it
            if sweep_timestamp is not None and c1.name is not None:
                if c1.name < sweep_timestamp:
                    continue  # This FVG started forming before the sweep; skip it

            if direction == "bullish":
                gap = c3["low"] - c1["high"]
                if gap > min_gap:
                    return {
                        "type": "bullish_fvg",
                        "top": c3["low"],
                        "bottom": c1["high"],
                    }
            else:
                gap = c1["low"] - c3["high"]
                if gap > min_gap:
                    return {
                        "type": "bearish_fvg",
                        "top": c1["low"],
                        "bottom": c3["high"],
                    }

        return None

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
