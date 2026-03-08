"""MACD + EMA Trend Strategy."""

import logging
from datetime import datetime
from typing import Optional, Dict, Any

import numpy as np
import pandas as pd

from .base import BacktestStrategy, DayContext, TradeSetup

logger = logging.getLogger(__name__)


class MACDEMAStrategy(BacktestStrategy):
    """
    MACD + EMA Trend-Following Strategy.

    Trades in the direction of EMA alignment when MACD confirms momentum shift.

    Entry Rules:
        1. Trend Filter: EMA 9 > EMA 21 > EMA 50 (bullish) or reverse (bearish)
        2. MACD Signal: MACD line crosses above/below signal line
        3. MACD Histogram: Must be increasing in direction of trade
        4. Entry at next bar open after crossover
        5. Stop Loss below/above EMA 50, clamped to config min/max SL
        6. Take Profit at configurable R:R ratio (default 2.5x)

    Exit Rules (via should_close_early):
        - EMA 9 crosses below EMA 21 (opposing cross = trend weakening)
        - MACD histogram turns against position for 3 consecutive bars
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
        ctx = DayContext(date=date)

        if intraday_df is not None and len(intraday_df) >= 14:
            ctx.atr = self._calculate_atr(intraday_df, 14)

        # Determine trend from EMA alignment
        ema_slow_period = self.config.get("ema_slow", 50)
        if intraday_df is not None and len(intraday_df) >= ema_slow_period:
            ema_fast = intraday_df["close"].ewm(
                span=self.config.get("ema_fast", 9), adjust=False
            ).mean()
            ema_mid = intraday_df["close"].ewm(
                span=self.config.get("ema_mid", 21), adjust=False
            ).mean()
            ema_slow = intraday_df["close"].ewm(
                span=ema_slow_period, adjust=False
            ).mean()

            last_fast = ema_fast.iloc[-1]
            last_mid = ema_mid.iloc[-1]
            last_slow = ema_slow.iloc[-1]

            if last_fast > last_mid > last_slow:
                ctx.bias = "bullish"
                ctx.bias_strength = 70
            elif last_fast < last_mid < last_slow:
                ctx.bias = "bearish"
                ctx.bias_strength = 70
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
        ema_fast_period = self.config.get("ema_fast", 9)
        ema_mid_period = self.config.get("ema_mid", 21)
        ema_slow_period = self.config.get("ema_slow", 50)
        macd_fast = self.config.get("macd_fast", 12)
        macd_slow_period = self.config.get("macd_slow", 26)
        macd_signal_period = self.config.get("macd_signal", 9)

        min_bars = max(ema_slow_period, macd_slow_period + macd_signal_period) + 5
        if len(df) < min_bars:
            return None

        # ADX filter: skip if trend is too weak
        min_adx = self.config.get("min_adx", 25)
        if min_adx > 0 and len(df) >= 20:
            adx_val = self._calculate_adx(df, self.config.get("adx_period", 14))
            if adx_val < min_adx:
                return None

        # Calculate EMAs on the full df available
        close = df["close"]
        ema_f = close.ewm(span=ema_fast_period, adjust=False).mean()
        ema_m = close.ewm(span=ema_mid_period, adjust=False).mean()
        ema_s = close.ewm(span=ema_slow_period, adjust=False).mean()

        # Check EMA alignment at current bar
        ef = ema_f.iloc[-1]
        em = ema_m.iloc[-1]
        es = ema_s.iloc[-1]

        bullish_trend = ef > em > es
        bearish_trend = ef < em < es

        if not bullish_trend and not bearish_trend:
            return None

        # Minimum EMA separation filter: avoid choppy conditions where
        # EMAs are barely separated and likely to flip
        min_sep_pct = self.config.get("min_ema_separation_pct", 0.15)
        price = bar["close"]
        if price > 0 and min_sep_pct > 0:
            ema_spread = abs(ef - es) / price * 100
            if ema_spread < min_sep_pct:
                return None

        # Calculate MACD
        ema_macd_fast = close.ewm(span=macd_fast, adjust=False).mean()
        ema_macd_slow = close.ewm(span=macd_slow_period, adjust=False).mean()
        macd_line = ema_macd_fast - ema_macd_slow
        signal_line = macd_line.ewm(span=macd_signal_period, adjust=False).mean()
        histogram = macd_line - signal_line

        # Need at least 3 bars for crossover detection
        if len(macd_line) < 3:
            return None

        macd_prev2 = macd_line.iloc[-3]
        signal_prev2 = signal_line.iloc[-3]
        macd_prev = macd_line.iloc[-2]
        signal_prev = signal_line.iloc[-2]

        hist_curr = histogram.iloc[-1]
        hist_prev = histogram.iloc[-2]

        # Check histogram confirmation bars
        confirm_bars = self.config.get("histogram_confirmation_bars", 2)
        if len(histogram) < confirm_bars + 1:
            return None

        if bullish_trend:
            # Bullish crossover: MACD crossed above signal on previous bar
            crossover = macd_prev2 <= signal_prev2 and macd_prev > signal_prev
            if not crossover:
                return None

            # Optional regime filter: require MACD above zero line for longs.
            if self.config.get("require_macd_above_zero", True) and macd_prev <= 0:
                return None

            # Histogram should be increasing for confirm_bars
            hist_increasing = all(
                histogram.iloc[-i] > histogram.iloc[-i - 1]
                for i in range(1, min(confirm_bars + 1, len(histogram)))
            )
            if not hist_increasing:
                return None

            # SL below EMA 50 with ATR buffer
            atr_buffer = day_context.atr * self.config.get("sl_atr_buffer", 0.3)
            sl_raw = es - atr_buffer

            # Clamp SL distance
            entry = bar["open"]
            sl_distance = abs(entry - sl_raw)
            min_sl = self.config.get("min_sl_usd", 1.0)
            max_sl = self.config.get("max_sl_usd", 15.0)
            sl_distance = max(min_sl, min(max_sl, sl_distance))
            sl = entry - sl_distance

            rr = self.config.get("rr_ratio", 2.5)
            tp = entry + sl_distance * rr

            return TradeSetup(
                direction="BUY",
                entry_price=entry,
                stop_loss=sl,
                take_profit=tp,
                setup_type="MACD Bullish Cross + EMA Alignment",
                confidence=day_context.bias_strength,
                metadata={
                    "ema_fast": float(ef),
                    "ema_mid": float(em),
                    "ema_slow": float(es),
                    "macd": float(macd_prev),
                    "signal": float(signal_prev),
                    "histogram": float(hist_curr),
                },
            )

        elif bearish_trend:
            # Bearish crossover: MACD crossed below signal on previous bar
            crossover = macd_prev2 >= signal_prev2 and macd_prev < signal_prev
            if not crossover:
                return None

            # Optional regime filter: require MACD below zero line for shorts.
            if self.config.get("require_macd_below_zero", True) and macd_prev >= 0:
                return None

            # Histogram should be decreasing for confirm_bars
            hist_decreasing = all(
                histogram.iloc[-i] < histogram.iloc[-i - 1]
                for i in range(1, min(confirm_bars + 1, len(histogram)))
            )
            if not hist_decreasing:
                return None

            # SL above EMA 50 with ATR buffer
            atr_buffer = day_context.atr * self.config.get("sl_atr_buffer", 0.3)
            sl_raw = es + atr_buffer

            entry = bar["open"]
            sl_distance = abs(sl_raw - entry)
            min_sl = self.config.get("min_sl_usd", 1.0)
            max_sl = self.config.get("max_sl_usd", 15.0)
            sl_distance = max(min_sl, min(max_sl, sl_distance))
            sl = entry + sl_distance

            rr = self.config.get("rr_ratio", 2.5)
            tp = entry - sl_distance * rr

            return TradeSetup(
                direction="SELL",
                entry_price=entry,
                stop_loss=sl,
                take_profit=tp,
                setup_type="MACD Bearish Cross + EMA Alignment",
                confidence=day_context.bias_strength,
                metadata={
                    "ema_fast": float(ef),
                    "ema_mid": float(em),
                    "ema_slow": float(es),
                    "macd": float(macd_prev),
                    "signal": float(signal_prev),
                    "histogram": float(hist_curr),
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
        """Close if EMA 9 crosses EMA 21 against position or histogram reverses."""
        ema_fast_period = self.config.get("ema_fast", 9)
        ema_mid_period = self.config.get("ema_mid", 21)

        if len(df) < ema_mid_period + 2:
            return None

        close = df["close"]
        ema_f = close.ewm(span=ema_fast_period, adjust=False).mean()
        ema_m = close.ewm(span=ema_mid_period, adjust=False).mean()

        is_long = position.direction == "BUY"

        # Exit 1: EMA fast crosses mid against position direction
        ef_prev = ema_f.iloc[-2]
        em_prev = ema_m.iloc[-2]
        ef_curr = ema_f.iloc[-1]
        em_curr = ema_m.iloc[-1]

        if is_long and ef_prev >= em_prev and ef_curr < em_curr:
            return "EMA Cross Against (Bearish)"
        if not is_long and ef_prev <= em_prev and ef_curr > em_curr:
            return "EMA Cross Against (Bullish)"

        # Exit 2: MACD histogram reverses for 3 consecutive bars
        macd_fast = self.config.get("macd_fast", 12)
        macd_slow_period = self.config.get("macd_slow", 26)
        macd_signal_period = self.config.get("macd_signal", 9)

        if len(df) >= macd_slow_period + macd_signal_period + 4:
            ema_mf = close.ewm(span=macd_fast, adjust=False).mean()
            ema_ms = close.ewm(span=macd_slow_period, adjust=False).mean()
            macd_line = ema_mf - ema_ms
            histogram = macd_line - macd_line.ewm(span=macd_signal_period, adjust=False).mean()

            if len(histogram) >= 4:
                h1 = histogram.iloc[-1]
                h2 = histogram.iloc[-2]
                h3 = histogram.iloc[-3]
                h4 = histogram.iloc[-4]

                if is_long and h1 < h2 < h3 < h4:
                    return "MACD Histogram Fading (3 bars)"
                if not is_long and h1 > h2 > h3 > h4:
                    return "MACD Histogram Fading (3 bars)"

        return None

    def get_required_lookback_bars(self) -> int:
        """Strategy needs enough bars for MACD + EMA computation."""
        ema_slow = self.config.get("ema_slow", 50)
        macd_slow = self.config.get("macd_slow", 26)
        macd_signal = self.config.get("macd_signal", 9)
        return max(60, ema_slow + 10, macd_slow + macd_signal + 10)

    def get_required_daily_lookback_days(self) -> int:
        """Trend strategy benefits from some daily context."""
        return 30

    # ------------------------------------------------------------------
    # Helpers
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
