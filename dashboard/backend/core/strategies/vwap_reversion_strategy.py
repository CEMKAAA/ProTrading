"""
VWAP Mean Reversion Strategy.

VWAP acts as institutional equilibrium.  When price deviates
significantly from VWAP, institutional execution algorithms pull it
back.  This strategy trades that mean reversion.

Core concept:
  - VWAP resets each trading day (cumulative Typical-Price * Volume /
    cumulative Volume).
  - Standard-deviation bands around VWAP quantify how extreme the
    deviation is.
  - Entry is triggered when price breaches the outer band with RSI
    confirmation, *only* in ranging markets (ADX < threshold).

Entry Rules:
  Long:
    1. Close <= VWAP - entry_sigma * sigma
    2. RSI(14) < 35  (oversold)
    3. ADX(14) < max_adx  (ranging market)
    4. Bullish reversal candle (close > open, hammer, or bullish pin bar)
  Short:
    1. Close >= VWAP + entry_sigma * sigma
    2. RSI(14) > 65  (overbought)
    3. ADX(14) < max_adx
    4. Bearish reversal candle (close < open, shooting star, or bearish pin bar)

Stop Loss:
  - Long:  VWAP - sl_sigma * sigma  (clamped to min/max SL)
  - Short: VWAP + sl_sigma * sigma  (clamped to min/max SL)

Take Profit:
  - Primary target: VWAP itself (the mean).
  - Minimum 2:1 R:R enforced; if VWAP is too close, TP = entry +/- 2 * SL distance.

Early Exit:
  1. Mean reversion complete: price within 0.2 sigma of VWAP while profitable.
  2. Counter-trend: ADX rises above 35 (market turned trending).
  3. Time decay: > 30 bars held with < 0.5R profit.
"""

import logging
from datetime import datetime
from typing import Optional, Dict, Any

import numpy as np
import pandas as pd

from .base import BacktestStrategy, DayContext, TradeSetup

logger = logging.getLogger(__name__)


class VWAPReversionStrategy(BacktestStrategy):
    """
    VWAP Mean Reversion Strategy.

    Trades mean reversion when price deviates beyond configurable
    standard-deviation bands around the session VWAP, confirmed by RSI
    extremes and an ADX ranging-market filter.
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
        """Calculate ATR for the day.  No directional bias -- mean
        reversion is direction-agnostic."""
        ctx = DayContext(date=date)

        if intraday_df is not None and len(intraday_df) >= 14:
            ctx.atr = self._calculate_atr(intraday_df, 14)

        # Mean reversion is direction-agnostic.
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
        """Scan for a VWAP band-breach entry with RSI + ADX confirmation."""

        # ---- config ------------------------------------------------
        vwap_std_period = self.config.get("vwap_std_period", 20)
        rsi_period = self.config.get("rsi_period", 14)
        adx_period = self.config.get("adx_period", 14)
        max_adx = self.config.get("max_adx", 30)
        entry_sigma = self.config.get("entry_sigma", 2.0)
        sl_sigma = self.config.get("sl_sigma", 3.0)
        min_rr = self.config.get("min_rr", 2.0)
        min_sl = self.config.get("min_sl_usd", 1.0)
        max_sl = self.config.get("max_sl_usd", 15.0)

        # Need enough bars for indicators
        min_bars = max(vwap_std_period, rsi_period, adx_period) + 10
        if len(df) < min_bars:
            return None

        # ---- VWAP (daily reset) ------------------------------------
        vwap, sigma = self._compute_vwap_and_sigma(df, bar, vwap_std_period)
        if vwap is None or sigma is None or sigma <= 0:
            return None

        # ---- RSI ---------------------------------------------------
        rsi = self._calculate_rsi(df["close"], rsi_period)
        current_rsi = rsi.iloc[-1] if len(rsi) > 0 and not pd.isna(rsi.iloc[-1]) else 50.0

        # ---- ADX ---------------------------------------------------
        adx_val = self._calculate_adx(df, adx_period)
        if adx_val >= max_adx:
            return None  # trending market -- skip

        # ---- Band levels -------------------------------------------
        upper_entry_band = vwap + entry_sigma * sigma
        lower_entry_band = vwap - entry_sigma * sigma
        upper_sl_band = vwap + sl_sigma * sigma
        lower_sl_band = vwap - sl_sigma * sigma

        current_close = bar["close"]
        entry = bar["open"]  # enter on next bar open (this bar open)

        # ---- LONG SETUP --------------------------------------------
        if current_close <= lower_entry_band and current_rsi < 35:
            if not self._is_bullish_reversal(df):
                return None

            sl_raw = lower_sl_band
            sl_distance = abs(entry - sl_raw)
            sl_distance = max(min_sl, min(max_sl, sl_distance))
            sl = entry - sl_distance

            # Primary target: VWAP
            tp = vwap
            # Enforce minimum R:R
            if abs(tp - entry) < sl_distance * min_rr:
                tp = entry + sl_distance * min_rr

            confidence = self._calc_confidence(current_close, vwap, sigma, current_rsi, adx_val)

            return TradeSetup(
                direction="BUY",
                entry_price=entry,
                stop_loss=sl,
                take_profit=tp,
                setup_type="VWAP Mean Reversion (Long)",
                confidence=confidence,
                metadata={
                    "vwap": float(vwap),
                    "sigma": float(sigma),
                    "deviation_sigma": float((current_close - vwap) / sigma),
                    "rsi": float(current_rsi),
                    "adx": float(adx_val),
                    "upper_entry_band": float(upper_entry_band),
                    "lower_entry_band": float(lower_entry_band),
                },
            )

        # ---- SHORT SETUP -------------------------------------------
        if current_close >= upper_entry_band and current_rsi > 65:
            if not self._is_bearish_reversal(df):
                return None

            sl_raw = upper_sl_band
            sl_distance = abs(sl_raw - entry)
            sl_distance = max(min_sl, min(max_sl, sl_distance))
            sl = entry + sl_distance

            # Primary target: VWAP
            tp = vwap
            # Enforce minimum R:R
            if abs(entry - tp) < sl_distance * min_rr:
                tp = entry - sl_distance * min_rr

            confidence = self._calc_confidence(current_close, vwap, sigma, current_rsi, adx_val)

            return TradeSetup(
                direction="SELL",
                entry_price=entry,
                stop_loss=sl,
                take_profit=tp,
                setup_type="VWAP Mean Reversion (Short)",
                confidence=confidence,
                metadata={
                    "vwap": float(vwap),
                    "sigma": float(sigma),
                    "deviation_sigma": float((current_close - vwap) / sigma),
                    "rsi": float(current_rsi),
                    "adx": float(adx_val),
                    "upper_entry_band": float(upper_entry_band),
                    "lower_entry_band": float(lower_entry_band),
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
        """Adaptive exits for VWAP mean-reversion trades."""

        vwap_std_period = self.config.get("vwap_std_period", 20)
        adx_period = self.config.get("adx_period", 14)

        if len(df) < vwap_std_period + 5:
            return None

        # Recompute VWAP and sigma for the current bar
        vwap, sigma = self._compute_vwap_and_sigma(df, bar, vwap_std_period)
        if vwap is None or sigma is None or sigma <= 0:
            return None

        current_close = bar["close"]
        initial_risk = abs(position.entry_price - position.stop_loss)
        if initial_risk <= 0:
            return None

        is_long = position.direction == "BUY"

        # 1. Mean reversion complete: price within 0.2 sigma of VWAP + profitable
        distance_sigma = abs(current_close - vwap) / sigma
        if distance_sigma < 0.2:
            if is_long and current_close > position.entry_price:
                return "Mean Reversion Complete (VWAP reached)"
            if not is_long and current_close < position.entry_price:
                return "Mean Reversion Complete (VWAP reached)"

        # 2. Counter-trend: ADX surged above 35 -- market became trending
        adx_val = self._calculate_adx(df, adx_period)
        if adx_val > 35:
            return "Counter-Trend Exit (ADX > 35, trending market)"

        # 3. Time decay: held > 30 bars with < 0.5R profit
        if hasattr(position, "entry_time") and bar.name is not None:
            bars_held = len(df[df.index >= position.entry_time])
            if bars_held > 30:
                if is_long:
                    pnl_r = (current_close - position.entry_price) / initial_risk
                else:
                    pnl_r = (position.entry_price - current_close) / initial_risk
                if pnl_r < 0.5:
                    return "Time Decay (30+ bars, <0.5R)"

        return None

    def get_required_lookback_bars(self) -> int:
        """Needs enough history for robust VWAP band computation."""
        return 200

    def get_required_daily_lookback_days(self) -> int:
        """Minimal daily data needed; intraday VWAP is the focus."""
        return 10

    # ------------------------------------------------------------------
    # VWAP computation helpers
    # ------------------------------------------------------------------

    def _compute_vwap_and_sigma(
        self,
        df: pd.DataFrame,
        bar: pd.Series,
        std_period: int,
    ) -> tuple:
        """Compute session VWAP and rolling standard deviation of
        (close - VWAP) for the current bar's trading day.

        VWAP resets at each day boundary.  If volume data is missing or
        all-zero, falls back to an equal-weight typical-price average.

        Returns:
            (vwap, sigma) or (None, None) if insufficient data.
        """
        # Determine today's date from the current bar
        bar_date = self._bar_date(bar)

        # Extract today's bars from df
        today_mask = df.index.normalize() == pd.Timestamp(bar_date)
        today_df = df.loc[today_mask]

        if today_df is None or len(today_df) < 5:
            return None, None

        typical_price = (today_df["high"] + today_df["low"] + today_df["close"]) / 3.0

        # Determine volume column
        volume = self._get_volume_series(today_df)

        if volume is not None and volume.sum() > 0:
            cum_tp_vol = (typical_price * volume).cumsum()
            cum_vol = volume.cumsum()
            vwap_series = cum_tp_vol / cum_vol
        else:
            # Fallback: equal-weight cumulative typical-price average
            vwap_series = typical_price.expanding().mean()

        current_vwap = vwap_series.iloc[-1]
        if pd.isna(current_vwap):
            return None, None

        # Rolling standard deviation of (close - VWAP)
        deviation = today_df["close"] - vwap_series
        if len(deviation) >= std_period:
            sigma = deviation.rolling(std_period).std().iloc[-1]
        else:
            # Not enough bars for a full window -- use what we have
            sigma = deviation.std()

        if pd.isna(sigma) or sigma <= 0:
            return None, None

        return float(current_vwap), float(sigma)

    @staticmethod
    def _get_volume_series(df: pd.DataFrame) -> Optional[pd.Series]:
        """Return the best available volume column, or None."""
        for col in ("tick_volume", "volume", "real_volume"):
            if col in df.columns:
                series = df[col]
                if series.sum() > 0:
                    return series
        return None

    @staticmethod
    def _bar_date(bar: pd.Series):
        """Extract the date from a bar (works with DatetimeIndex or
        'time' column)."""
        if hasattr(bar.name, "date"):
            return bar.name.date()
        if "time" in bar.index:
            ts = bar["time"]
            if hasattr(ts, "date"):
                return ts.date()
        return None

    # ------------------------------------------------------------------
    # Confidence scoring
    # ------------------------------------------------------------------

    @staticmethod
    def _calc_confidence(
        close: float,
        vwap: float,
        sigma: float,
        rsi: float,
        adx: float,
    ) -> float:
        """Heuristic confidence 0-100 based on how extreme the deviation,
        RSI, and low ADX are."""
        # Deviation score: farther from VWAP = higher confidence
        dev_score = min(40, abs(close - vwap) / sigma * 15)
        # RSI score: more extreme RSI = higher confidence
        rsi_score = min(30, abs(rsi - 50) / 50 * 30)
        # ADX score: lower ADX = higher confidence (better for mean reversion)
        adx_score = min(30, max(0, (30 - adx) / 30 * 30))
        return min(100, int(dev_score + rsi_score + adx_score))

    # ------------------------------------------------------------------
    # Candle-pattern helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _is_bullish_reversal(df: pd.DataFrame) -> bool:
        """Detect bullish reversal: close flip, hammer, or bullish pin bar."""
        if len(df) < 2:
            return False
        c = df.iloc[-1]
        p = df.iloc[-2]

        # 1. Close flip (current close > previous close)
        if c["close"] > p["close"]:
            return True

        body = abs(c["close"] - c["open"])
        full_range = c["high"] - c["low"]
        if full_range < 0.01:
            return False

        lower_wick = min(c["open"], c["close"]) - c["low"]
        upper_wick = c["high"] - max(c["open"], c["close"])

        # 2. Hammer: long lower wick, small upper wick
        if lower_wick > full_range * 0.6 and upper_wick < full_range * 0.15:
            return True

        # 3. Bullish pin bar: lower wick > 2x body
        if lower_wick > body * 2 and upper_wick < body * 0.5:
            return True

        return False

    @staticmethod
    def _is_bearish_reversal(df: pd.DataFrame) -> bool:
        """Detect bearish reversal: close flip, shooting star, or bearish pin bar."""
        if len(df) < 2:
            return False
        c = df.iloc[-1]
        p = df.iloc[-2]

        # 1. Close flip
        if c["close"] < p["close"]:
            return True

        body = abs(c["close"] - c["open"])
        full_range = c["high"] - c["low"]
        if full_range < 0.01:
            return False

        upper_wick = c["high"] - max(c["open"], c["close"])
        lower_wick = min(c["open"], c["close"]) - c["low"]

        # 2. Shooting star: long upper wick, small lower wick
        if upper_wick > full_range * 0.6 and lower_wick < full_range * 0.15:
            return True

        # 3. Bearish pin bar: upper wick > 2x body
        if upper_wick > body * 2 and lower_wick < body * 0.5:
            return True

        return False

    # ------------------------------------------------------------------
    # Standard indicator helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _calculate_rsi(close: pd.Series, period: int) -> pd.Series:
        """Calculate RSI using Wilder's smoothing (EMA-based)."""
        delta = close.diff()
        gain = delta.where(delta > 0, 0.0)
        loss = (-delta).where(delta < 0, 0.0)
        avg_gain = gain.ewm(alpha=1.0 / period, adjust=False).mean()
        avg_loss = loss.ewm(alpha=1.0 / period, adjust=False).mean()
        rs = avg_gain / avg_loss
        rsi = 100 - (100 / (1 + rs))
        return rsi

    @staticmethod
    def _calculate_adx(df: pd.DataFrame, period: int) -> float:
        """Average Directional Index (Wilder's smoothing)."""
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
