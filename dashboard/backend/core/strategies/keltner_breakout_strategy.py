"""
Keltner Channel Breakout Strategy.

Keltner Channels are volatility envelopes around an EMA.  When price closes
outside the bands it signals a volatility expansion -- a breakout with momentum.
Combined with the TTM Squeeze (Bollinger Bands inside Keltner = compressed
volatility about to explode), this captures high-probability directional moves.

Why this works for Gold:
  - Gold trends strongly once volatility compresses and then expands.
  - The Keltner / Bollinger squeeze is a reliable "coiled spring" detector.
  - ADX confirmation prevents false breakouts in choppy ranges.
  - EMA200 slope filter keeps trades aligned with the dominant trend.

Entry Rules:
  1. Squeeze Detection: BBands were inside KC (squeeze ON) and have now
     expanded outside (squeeze OFF = "fired") within the last N bars.
  2. Breakout: Price closes above (long) or below (short) the Keltner band.
  3. ADX(14) > min_adx -- confirmed trending environment.
  4. Momentum: ROC(12) positive and rising (long) or negative and falling (short).
  5. EMA200 slope filter: don't buy if EMA200 is falling, don't sell if rising.
  6. Stop Loss: Opposite Keltner band, clamped to min/max SL config.
  7. Take Profit: rr_ratio * SL distance (default 2.5x).

Exit Rules (via should_close_early):
  - Momentum reversal: ROC crosses zero against position direction.
  - KC re-entry: Price closes back inside the Keltner Channel bands.
  - Time decay: Held > 20 bars without reaching 1R profit.
"""

import logging
from datetime import datetime
from typing import Optional, Dict, Any

import numpy as np
import pandas as pd

from .base import BacktestStrategy, DayContext, TradeSetup

logger = logging.getLogger(__name__)


class KeltnerBreakoutStrategy(BacktestStrategy):
    """
    Keltner Channel Breakout Strategy with TTM Squeeze detection.

    Trades volatility expansions (squeeze fires) confirmed by ADX trend
    strength and ROC momentum, filtered by EMA200 slope for trend alignment.
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
        """Calculate ATR and determine daily trend bias from EMA200 direction."""
        ctx = DayContext(date=date)

        if intraday_df is not None and len(intraday_df) >= 14:
            ctx.atr = self._calculate_atr(intraday_df, 14)

        # Determine trend bias from EMA200 direction
        if intraday_df is not None and len(intraday_df) >= 220:
            ema200 = intraday_df["close"].ewm(span=200, adjust=False).mean()
            slope_bars = 20
            if len(ema200) > slope_bars:
                current_ema = ema200.iloc[-1]
                prev_ema = ema200.iloc[-1 - slope_bars]
                if not pd.isna(current_ema) and not pd.isna(prev_ema):
                    if current_ema > prev_ema:
                        ctx.bias = "bullish"
                        ctx.bias_strength = 60
                    elif current_ema < prev_ema:
                        ctx.bias = "bearish"
                        ctx.bias_strength = 60
                    else:
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
        Detect Keltner Channel breakout setups with TTM Squeeze confirmation.

        Requires: KC breakout + recent squeeze fire + ADX trend + ROC momentum
        + EMA200 slope alignment.
        """
        # ---- Config knobs ----
        kc_ema_period = self.config.get("kc_ema_period", 20)
        kc_atr_period = self.config.get("kc_atr_period", 10)
        kc_atr_mult = self.config.get("kc_atr_mult", 2.0)
        bb_period = self.config.get("bb_period", 20)
        bb_std = self.config.get("bb_std", 2.0)
        squeeze_lookback = self.config.get("squeeze_lookback", 5)
        roc_period = self.config.get("roc_period", 12)
        adx_period = self.config.get("adx_period", 14)
        min_adx = self.config.get("min_adx", 20)

        # Minimum bars needed for all indicators
        min_bars = max(kc_ema_period, kc_atr_period, bb_period, adx_period,
                       roc_period, 200) + squeeze_lookback + 10
        if len(df) < min_bars:
            return None

        close = df["close"]
        high = df["high"]
        low = df["low"]

        # ---- 1. Keltner Channels ----
        kc_middle = close.ewm(span=kc_ema_period, adjust=False).mean()
        kc_atr = self._calculate_atr_series(df, kc_atr_period)
        kc_upper = kc_middle + kc_atr_mult * kc_atr
        kc_lower = kc_middle - kc_atr_mult * kc_atr

        # ---- 2. Bollinger Bands ----
        bb_middle = close.rolling(bb_period).mean()
        bb_stddev = close.rolling(bb_period).std()
        bb_upper = bb_middle + bb_std * bb_stddev
        bb_lower = bb_middle - bb_std * bb_stddev

        # ---- 3. Squeeze Detection ----
        # Squeeze ON = BB inside KC (BB upper < KC upper AND BB lower > KC lower)
        squeeze_on = (bb_upper < kc_upper) & (bb_lower > kc_lower)

        # Squeeze fires when it transitions from ON to OFF
        squeeze_fire = squeeze_on.shift(1).fillna(False) & ~squeeze_on

        # Check if squeeze fired within the lookback window
        recent_squeeze_fired = squeeze_fire.iloc[-(squeeze_lookback + 1):].any()
        if not recent_squeeze_fired:
            return None

        # ---- 4. ADX filter ----
        adx_val = self._calculate_adx(df, adx_period)
        if adx_val < min_adx:
            return None

        # ---- 5. Momentum: Rate of Change ----
        roc = self._calculate_roc(close, roc_period)
        if len(roc) < 2 or pd.isna(roc.iloc[-1]) or pd.isna(roc.iloc[-2]):
            return None

        current_roc = roc.iloc[-1]
        prev_roc = roc.iloc[-2]

        # ---- 6. EMA200 slope for trend filter ----
        ema200 = close.ewm(span=200, adjust=False).mean()
        slope_bars = 20
        ema200_slope = self._ema_slope(ema200, slope_bars)

        # ---- Current indicator values ----
        current_close = close.iloc[-1]
        current_kc_upper = kc_upper.iloc[-1]
        current_kc_lower = kc_lower.iloc[-1]
        current_kc_middle = kc_middle.iloc[-1]

        if pd.isna(current_kc_upper) or pd.isna(current_kc_lower) or pd.isna(current_kc_middle):
            return None

        entry = bar["open"]
        atr_14 = day_context.atr if day_context.atr > 0 else self._calculate_atr(df, 14)

        # ========== LONG SETUP ==========
        # ROC must be positive (momentum in direction).  The "accelerating"
        # check (roc > prev_roc) is optional — requiring it filters out
        # valid breakouts where momentum is strong but decelerating slightly.
        require_roc_accel = self.config.get("require_roc_acceleration", False)
        if (current_close > current_kc_upper
                and current_roc > 0
                and (not require_roc_accel or current_roc > prev_roc)
                and ema200_slope != "falling"):

            # Stop loss: opposite (lower) Keltner band
            sl_raw = current_kc_lower
            sl_distance = abs(entry - sl_raw)

            # If bands are too wide, fall back to 2.0 * ATR(14)
            atr_sl = 2.0 * atr_14
            if sl_distance > atr_sl * 2.0:
                sl_distance = atr_sl

            # Clamp SL distance to config bounds
            min_sl = self.config.get("min_sl_usd", 3.0)
            max_sl = self.config.get("max_sl_usd", 15.0)
            sl_distance = max(min_sl, min(max_sl, sl_distance))
            sl = entry - sl_distance

            # Take profit
            rr = self.config.get("rr_ratio", 2.5)
            tp = entry + sl_distance * rr

            confidence = self._compute_confidence(adx_val, current_roc, squeeze_lookback,
                                                  squeeze_fire, day_context.bias)

            logger.debug(
                "Keltner Breakout LONG: close=%.2f > KC_upper=%.2f, "
                "ADX=%.1f, ROC=%.3f, squeeze_fired=True",
                current_close, current_kc_upper, adx_val, current_roc,
            )

            return TradeSetup(
                direction="BUY",
                entry_price=entry,
                stop_loss=sl,
                take_profit=tp,
                setup_type="Keltner Breakout (Long)",
                confidence=confidence,
                metadata={
                    "kc_upper": float(current_kc_upper),
                    "kc_lower": float(current_kc_lower),
                    "kc_middle": float(current_kc_middle),
                    "adx": float(adx_val),
                    "roc": float(current_roc),
                    "ema200_slope": ema200_slope,
                    "squeeze_bars_ago": int(self._bars_since_squeeze(squeeze_fire, squeeze_lookback)),
                    "bb_upper": float(bb_upper.iloc[-1]) if not pd.isna(bb_upper.iloc[-1]) else None,
                    "bb_lower": float(bb_lower.iloc[-1]) if not pd.isna(bb_lower.iloc[-1]) else None,
                    "scale_out": "50% at 1.5R, trail remainder",
                },
            )

        # ========== SHORT SETUP ==========
        if (current_close < current_kc_lower
                and current_roc < 0
                and (not require_roc_accel or current_roc < prev_roc)
                and ema200_slope != "rising"):

            # Stop loss: opposite (upper) Keltner band
            sl_raw = current_kc_upper
            sl_distance = abs(sl_raw - entry)

            # If bands are too wide, fall back to 2.0 * ATR(14)
            atr_sl = 2.0 * atr_14
            if sl_distance > atr_sl * 2.0:
                sl_distance = atr_sl

            # Clamp SL distance to config bounds
            min_sl = self.config.get("min_sl_usd", 3.0)
            max_sl = self.config.get("max_sl_usd", 15.0)
            sl_distance = max(min_sl, min(max_sl, sl_distance))
            sl = entry + sl_distance

            # Take profit
            rr = self.config.get("rr_ratio", 2.5)
            tp = entry - sl_distance * rr

            confidence = self._compute_confidence(adx_val, current_roc, squeeze_lookback,
                                                  squeeze_fire, day_context.bias)

            logger.debug(
                "Keltner Breakout SHORT: close=%.2f < KC_lower=%.2f, "
                "ADX=%.1f, ROC=%.3f, squeeze_fired=True",
                current_close, current_kc_lower, adx_val, current_roc,
            )

            return TradeSetup(
                direction="SELL",
                entry_price=entry,
                stop_loss=sl,
                take_profit=tp,
                setup_type="Keltner Breakout (Short)",
                confidence=confidence,
                metadata={
                    "kc_upper": float(current_kc_upper),
                    "kc_lower": float(current_kc_lower),
                    "kc_middle": float(current_kc_middle),
                    "adx": float(adx_val),
                    "roc": float(current_roc),
                    "ema200_slope": ema200_slope,
                    "squeeze_bars_ago": int(self._bars_since_squeeze(squeeze_fire, squeeze_lookback)),
                    "bb_upper": float(bb_upper.iloc[-1]) if not pd.isna(bb_upper.iloc[-1]) else None,
                    "bb_lower": float(bb_lower.iloc[-1]) if not pd.isna(bb_lower.iloc[-1]) else None,
                    "scale_out": "50% at 1.5R, trail remainder",
                },
            )

        return None

    def should_close_early(
        self,
        bar: pd.Series,
        df: pd.DataFrame,
        position: Any,
        day_context: DayContext,
    ) -> Optional[str]:
        """
        Custom exit logic for Keltner Breakout trades.

        Exits:
          1. Momentum reversal: ROC-12 crosses zero against position.
          2. KC re-entry: Price closes back inside the Keltner Channel bands.
          3. Time decay: Held > 20 bars without reaching 1R profit.
        """
        roc_period = self.config.get("roc_period", 12)
        kc_ema_period = self.config.get("kc_ema_period", 20)
        kc_atr_period = self.config.get("kc_atr_period", 10)
        kc_atr_mult = self.config.get("kc_atr_mult", 2.0)

        if len(df) < max(kc_ema_period, kc_atr_period, roc_period) + 5:
            return None

        close = df["close"]
        current_close = bar["close"]
        is_long = position.direction == "BUY"

        initial_risk = abs(position.entry_price - position.stop_loss)
        if initial_risk <= 0:
            return None

        # ---- 1. Momentum reversal: ROC crosses zero against position ----
        roc = self._calculate_roc(close, roc_period)
        if len(roc) >= 2 and not pd.isna(roc.iloc[-1]) and not pd.isna(roc.iloc[-2]):
            roc_curr = roc.iloc[-1]
            roc_prev = roc.iloc[-2]

            if is_long and roc_prev >= 0 and roc_curr < 0:
                return "Momentum Reversal (ROC Crossed Below Zero)"
            if not is_long and roc_prev <= 0 and roc_curr > 0:
                return "Momentum Reversal (ROC Crossed Above Zero)"

        # ---- 2. KC re-entry: price closes back to channel midline ----
        # Grace period: don't check for first N bars — breakout needs room
        kc_reentry_grace = self.config.get("kc_reentry_grace_bars", 3)
        bars_held = 0
        if hasattr(position, "entry_time") and bar.name is not None:
            bars_held = len(df[df.index >= position.entry_time])

        if bars_held >= kc_reentry_grace:
            kc_middle = close.ewm(span=kc_ema_period, adjust=False).mean()
            kc_atr = self._calculate_atr_series(df, kc_atr_period)
            kc_upper = kc_middle + kc_atr_mult * kc_atr
            kc_lower = kc_middle - kc_atr_mult * kc_atr

            current_kc_upper = kc_upper.iloc[-1]
            current_kc_lower = kc_lower.iloc[-1]
            current_kc_middle = kc_middle.iloc[-1]

            if not pd.isna(current_kc_upper) and not pd.isna(current_kc_lower):
                # Use kc_middle as the failure threshold, not the outer band.
                # Dipping slightly below the upper band is normal retracement;
                # falling to the channel midline means the breakout truly failed.
                if is_long and current_close < current_kc_middle:
                    return "KC Re-entry (Breakout Failed - Long)"
                if not is_long and current_close > current_kc_middle:
                    return "KC Re-entry (Breakout Failed - Short)"

        # ---- 3. Time decay: > 20 bars without reaching 1R profit ----
        if bars_held > 20:
            if is_long:
                pnl_r = (current_close - position.entry_price) / initial_risk
            else:
                pnl_r = (position.entry_price - current_close) / initial_risk

            if pnl_r < 1.0:
                return "Time Decay (Breakout Stalling)"

        return None

    def get_required_lookback_bars(self) -> int:
        """Needs EMA200 for trend filter plus indicator warm-up."""
        return 200

    def get_required_daily_lookback_days(self) -> int:
        """Daily data for broader context."""
        return 30

    # ------------------------------------------------------------------
    # Indicator helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _calculate_roc(close: pd.Series, period: int) -> pd.Series:
        """
        Rate of Change: (close - close[period]) / close[period] * 100.
        """
        shifted = close.shift(period)
        roc = (close - shifted) / shifted * 100
        return roc

    @staticmethod
    def _ema_slope(ema: pd.Series, slope_bars: int) -> str:
        """
        Determine EMA slope direction over the last *slope_bars* bars.

        Returns "rising", "falling", or "flat".
        """
        if len(ema) <= slope_bars:
            return "flat"
        current = ema.iloc[-1]
        prev = ema.iloc[-1 - slope_bars]
        if pd.isna(current) or pd.isna(prev) or prev == 0:
            return "flat"
        # Percentage-based threshold: 0.01% over slope_bars is a real trend
        # For Gold at $4000 this is ~$0.40 — sensitive enough to detect
        # intraday EMA200 direction without triggering on noise.
        pct_change = (current - prev) / abs(prev)
        threshold = 0.0001  # 0.01%
        if pct_change > threshold:
            return "rising"
        elif pct_change < -threshold:
            return "falling"
        return "flat"

    @staticmethod
    def _bars_since_squeeze(squeeze_fire: pd.Series, lookback: int) -> int:
        """
        Return the number of bars since the most recent squeeze fire
        within the lookback window.  Returns lookback + 1 if none found.
        """
        recent = squeeze_fire.iloc[-(lookback + 1):]
        for i in range(len(recent) - 1, -1, -1):
            if recent.iloc[i]:
                return len(recent) - 1 - i
        return lookback + 1

    @staticmethod
    def _compute_confidence(
        adx: float,
        roc: float,
        squeeze_lookback: int,
        squeeze_fire: pd.Series,
        bias: str,
    ) -> float:
        """
        Compute a 0-100 confidence score based on indicator agreement.

        Components:
          - ADX strength (0-35 points): higher ADX = stronger trend
          - ROC magnitude (0-25 points): stronger momentum = more confidence
          - Squeeze recency (0-20 points): more recent squeeze = better
          - Bias alignment (0-20 points): trade direction matching daily bias
        """
        # ADX component: scale 20-50 range to 0-35 points
        adx_score = min(35.0, max(0.0, (adx - 20) / 30.0 * 35.0))

        # ROC magnitude component: absolute ROC 0-2% maps to 0-25 points
        roc_score = min(25.0, abs(roc) / 2.0 * 25.0)

        # Squeeze recency: how recently did the squeeze fire
        recent = squeeze_fire.iloc[-(squeeze_lookback + 1):]
        bars_ago = squeeze_lookback + 1
        for i in range(len(recent) - 1, -1, -1):
            if recent.iloc[i]:
                bars_ago = len(recent) - 1 - i
                break
        squeeze_score = max(0.0, 20.0 - bars_ago * 4.0)

        # Bias alignment: if daily bias matches trade direction
        # (Long setup with bullish bias, or Short setup with bearish bias)
        # This is a rough bonus; the caller already filters by EMA200 slope
        bias_score = 10.0  # neutral default
        if bias == "bullish" and roc > 0:
            bias_score = 20.0
        elif bias == "bearish" and roc < 0:
            bias_score = 20.0
        elif bias == "neutral":
            bias_score = 10.0
        else:
            bias_score = 0.0  # counter-bias (shouldn't happen due to slope filter)

        total = adx_score + roc_score + squeeze_score + bias_score
        return min(100.0, max(0.0, round(total, 1)))

    @staticmethod
    def _calculate_atr(df: pd.DataFrame, period: int) -> float:
        """Calculate the current (latest) ATR value."""
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

    @staticmethod
    def _calculate_atr_series(df: pd.DataFrame, period: int) -> pd.Series:
        """Calculate ATR as a full Series (for Keltner band computation)."""
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
        return tr.rolling(period).mean()

    @staticmethod
    def _calculate_adx(df: pd.DataFrame, period: int) -> float:
        """Average Directional Index for trend strength measurement."""
        if len(df) < period + 5:
            return 0.0
        high = df["high"]
        low = df["low"]
        close = df["close"]

        plus_dm = high.diff()
        minus_dm = -low.diff()
        plus_dm = plus_dm.where((plus_dm > minus_dm) & (plus_dm > 0), 0.0)
        minus_dm = minus_dm.where((minus_dm > plus_dm) & (minus_dm > 0), 0.0)

        tr = pd.concat(
            [
                high - low,
                (high - close.shift(1)).abs(),
                (low - close.shift(1)).abs(),
            ],
            axis=1,
        ).max(axis=1)

        atr = tr.ewm(span=period, adjust=False).mean()
        plus_di = 100 * (plus_dm.ewm(span=period, adjust=False).mean() / atr)
        minus_di = 100 * (minus_dm.ewm(span=period, adjust=False).mean() / atr)

        di_sum = plus_di + minus_di
        di_sum = di_sum.replace(0, np.nan)
        dx = 100 * (plus_di - minus_di).abs() / di_sum
        adx = dx.ewm(span=period, adjust=False).mean()

        if len(adx) > 0 and not pd.isna(adx.iloc[-1]):
            return float(adx.iloc[-1])
        return 0.0
