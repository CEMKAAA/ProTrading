"""
Bollinger Band Squeeze Breakout Strategy.

Volatility is mean-reverting.  Periods of low volatility (squeeze /
compression) are reliably followed by high volatility (expansion).  When
Bollinger BandWidth drops to a multi-bar low, the market is coiling;
the subsequent breakout -- confirmed by a linear-regression momentum
oscillator and a volume spike -- offers a high-probability entry.

Entry Rules:
    1. Squeeze Detection: BandWidth at or within 5 % of its N-bar low.
    2. Breakout: Price closes beyond the upper (long) or lower (short)
       Bollinger Band.
    3. Momentum: Linear Regression Slope of close (12-bar) confirms
       direction and is accelerating.
    4. Volume: Bar volume > 1.3x 20-bar average (skipped if absent).
    5. EMA 200 Filter: Slope must not oppose the trade direction.

Exit Rules (should_close_early):
    1. Momentum Reversal: Momentum oscillator crosses zero against position.
    2. BandWidth Contraction: New squeeze forming after breakout (stalling).
    3. Time Decay: Held > 25 bars with < 0.5 R profit.
"""

import logging
from datetime import datetime
from typing import Optional, Dict, Any

import numpy as np
import pandas as pd

from .base import BacktestStrategy, DayContext, TradeSetup

logger = logging.getLogger(__name__)


class BBSqueezeStrategy(BacktestStrategy):
    """
    Bollinger Band Squeeze Breakout Strategy.

    Detects volatility compression via Bollinger BandWidth at multi-bar
    lows, then enters on a confirmed breakout with momentum and volume
    confirmation.
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
        """Calculate daily ATR and determine trend context from EMA 200."""
        ctx = DayContext(date=date)

        if intraday_df is not None and len(intraday_df) >= 14:
            ctx.atr = self._calculate_atr(intraday_df, 14)

        # EMA 200 direction for daily bias
        if intraday_df is not None and len(intraday_df) >= 220:
            ema200 = intraday_df["close"].ewm(span=200, adjust=False).mean()
            slope_bars = 20
            if len(ema200) > slope_bars:
                current_ema = ema200.iloc[-1]
                prev_ema = ema200.iloc[-1 - slope_bars]
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
        """Detect squeeze breakout setups."""
        # ---- Config ----
        bb_period = self.config.get("bb_period", 20)
        bb_std = self.config.get("bb_std", 2.0)
        bw_lookback = self.config.get("squeeze_bandwidth_lookback", 120)
        squeeze_lookback = self.config.get("squeeze_lookback", 5)
        momentum_period = self.config.get("momentum_period", 10)
        volume_spike_mult = self.config.get("volume_spike_mult", 1.3)
        min_rr = self.config.get("min_rr", 2.0)

        # Need enough bars for BandWidth rolling minimum + BB period
        min_bars = bw_lookback + bb_period + 5
        if len(df) < min_bars:
            return None

        close = df["close"]

        # ---- Bollinger Bands ----
        sma = close.rolling(bb_period).mean()
        std = close.rolling(bb_period).std(ddof=0)
        upper_band = sma + bb_std * std
        lower_band = sma - bb_std * std

        current_upper = upper_band.iloc[-1]
        current_lower = lower_band.iloc[-1]
        current_sma = sma.iloc[-1]

        if pd.isna(current_upper) or pd.isna(current_lower) or pd.isna(current_sma):
            return None

        # ---- BandWidth ----
        bandwidth = (upper_band - lower_band) / sma * 100
        bandwidth = bandwidth.replace([np.inf, -np.inf], np.nan)

        if pd.isna(bandwidth.iloc[-1]):
            return None

        # ---- Squeeze Detection ----
        # Squeeze is active when bandwidth is within 5% of its N-bar min
        bw_min = bandwidth.rolling(bw_lookback).min()

        # Check if squeeze was active within the last squeeze_lookback bars
        squeeze_was_recent = False
        for lookback_idx in range(1, squeeze_lookback + 1):
            idx = -1 - lookback_idx
            if abs(idx) > len(bandwidth) or abs(idx) > len(bw_min):
                break
            bw_val = bandwidth.iloc[idx]
            bw_min_val = bw_min.iloc[idx]
            if pd.isna(bw_val) or pd.isna(bw_min_val) or bw_min_val <= 0:
                continue
            if bw_val <= bw_min_val * 1.05:
                squeeze_was_recent = True
                break

        if not squeeze_was_recent:
            return None

        # ---- Momentum Oscillator (Linear Regression Slope) ----
        if len(close) < momentum_period + 2:
            return None

        current_momentum = self._linreg_slope(close, momentum_period, offset=0)
        prev_momentum = self._linreg_slope(close, momentum_period, offset=1)

        if current_momentum is None or prev_momentum is None:
            return None

        # ---- Volume Confirmation ----
        volume_col = self._get_volume_column(df)
        volume_ok = True  # default: pass if no volume data
        if volume_col is not None:
            vol_series = df[volume_col]
            if len(vol_series) >= 21:
                avg_vol = vol_series.iloc[-21:-1].mean()
                current_vol = vol_series.iloc[-1]
                if avg_vol > 0:
                    volume_ok = current_vol > avg_vol * volume_spike_mult
                # If avg_vol == 0, skip volume filter

        # ---- EMA 200 Slope ----
        ema200_slope_bars = 20
        ema200 = close.ewm(span=200, adjust=False).mean()
        if len(ema200) > ema200_slope_bars:
            ema200_current = ema200.iloc[-1]
            ema200_prev = ema200.iloc[-1 - ema200_slope_bars]
            ema200_rising = ema200_current > ema200_prev
            ema200_falling = ema200_current < ema200_prev
        else:
            ema200_rising = False
            ema200_falling = False

        # ---- ATR for SL fallback ----
        atr = day_context.atr
        if atr <= 0:
            atr = self._calculate_atr(df, 14)
        if atr <= 0:
            return None

        entry = bar["open"]
        current_close = bar["close"]
        current_bw = float(bandwidth.iloc[-1])

        # =================================================================
        # LONG SETUP
        # =================================================================
        if (
            current_close > current_upper
            and current_momentum > 0
            and current_momentum > prev_momentum
            and volume_ok
            and not ema200_falling
        ):
            # Stop loss at middle BB (SMA 20)
            sl_raw = current_sma
            sl_distance = abs(entry - sl_raw)

            # If middle band is too close, use 1.5 ATR
            if sl_distance < atr:
                sl_distance = 1.5 * atr
                sl_raw = entry - sl_distance

            # Clamp SL
            min_sl = self.config.get("min_sl_usd", 1.0)
            max_sl = self.config.get("max_sl_usd", 15.0)
            sl_distance = max(min_sl, min(max_sl, sl_distance))
            sl = entry - sl_distance

            # Take profit: 2x the BandWidth at breakout
            band_spread = abs(current_upper - current_lower)
            tp_distance = band_spread * 2.0

            # Enforce minimum R:R
            if tp_distance < sl_distance * min_rr:
                tp_distance = sl_distance * min_rr

            tp = entry + tp_distance

            confidence = self._compute_confidence(
                current_bw, bw_min.iloc[-1], current_momentum, volume_ok,
            )

            return TradeSetup(
                direction="BUY",
                entry_price=entry,
                stop_loss=sl,
                take_profit=tp,
                setup_type="BB Squeeze Breakout (Long)",
                confidence=confidence,
                metadata={
                    "bb_upper": float(current_upper),
                    "bb_lower": float(current_lower),
                    "bb_sma": float(current_sma),
                    "bandwidth": current_bw,
                    "bandwidth_min": float(bw_min.iloc[-1]) if not pd.isna(bw_min.iloc[-1]) else None,
                    "momentum": float(current_momentum),
                    "momentum_prev": float(prev_momentum),
                    "volume_spike": volume_ok,
                    "band_spread": float(band_spread),
                },
            )

        # =================================================================
        # SHORT SETUP
        # =================================================================
        if (
            current_close < current_lower
            and current_momentum < 0
            and current_momentum < prev_momentum
            and volume_ok
            and not ema200_rising
        ):
            # Stop loss at middle BB (SMA 20)
            sl_raw = current_sma
            sl_distance = abs(sl_raw - entry)

            # If middle band is too close, use 1.5 ATR
            if sl_distance < atr:
                sl_distance = 1.5 * atr
                sl_raw = entry + sl_distance

            # Clamp SL
            min_sl = self.config.get("min_sl_usd", 1.0)
            max_sl = self.config.get("max_sl_usd", 15.0)
            sl_distance = max(min_sl, min(max_sl, sl_distance))
            sl = entry + sl_distance

            # Take profit: 2x the BandWidth at breakout
            band_spread = abs(current_upper - current_lower)
            tp_distance = band_spread * 2.0

            # Enforce minimum R:R
            if tp_distance < sl_distance * min_rr:
                tp_distance = sl_distance * min_rr

            tp = entry - tp_distance

            confidence = self._compute_confidence(
                current_bw, bw_min.iloc[-1], current_momentum, volume_ok,
            )

            return TradeSetup(
                direction="SELL",
                entry_price=entry,
                stop_loss=sl,
                take_profit=tp,
                setup_type="BB Squeeze Breakout (Short)",
                confidence=confidence,
                metadata={
                    "bb_upper": float(current_upper),
                    "bb_lower": float(current_lower),
                    "bb_sma": float(current_sma),
                    "bandwidth": current_bw,
                    "bandwidth_min": float(bw_min.iloc[-1]) if not pd.isna(bw_min.iloc[-1]) else None,
                    "momentum": float(current_momentum),
                    "momentum_prev": float(prev_momentum),
                    "volume_spike": volume_ok,
                    "band_spread": float(band_spread),
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
        Custom exit logic for BB Squeeze breakout trades.

        1. Momentum reversal: momentum oscillator crosses zero against position.
        2. BandWidth contraction: new squeeze forming (breakout stalling).
        3. Time decay: held > 25 bars with < 0.5 R profit.
        """
        momentum_period = self.config.get("momentum_period", 10)
        bb_period = self.config.get("bb_period", 20)
        bb_std = self.config.get("bb_std", 2.0)
        bw_lookback = self.config.get("squeeze_bandwidth_lookback", 120)

        close = df["close"]
        if len(close) < max(momentum_period + 2, bb_period + bw_lookback):
            return None

        is_long = position.direction == "BUY"
        current_close = bar["close"]
        initial_risk = abs(position.entry_price - position.stop_loss)
        if initial_risk <= 0:
            return None

        # --- 1. Momentum Reversal ---
        current_momentum = self._linreg_slope(close, momentum_period, offset=0)
        if current_momentum is not None:
            if is_long and current_momentum < 0:
                return "Momentum Reversal (Bearish)"
            if not is_long and current_momentum > 0:
                return "Momentum Reversal (Bullish)"

        # --- 2. BandWidth Contraction (new squeeze forming) ---
        sma = close.rolling(bb_period).mean()
        std = close.rolling(bb_period).std(ddof=0)
        upper_band = sma + bb_std * std
        lower_band = sma - bb_std * std
        bandwidth = (upper_band - lower_band) / sma * 100
        bandwidth = bandwidth.replace([np.inf, -np.inf], np.nan)

        if not pd.isna(bandwidth.iloc[-1]) and len(bandwidth) >= bw_lookback:
            bw_min = bandwidth.rolling(bw_lookback).min()
            if not pd.isna(bw_min.iloc[-1]) and bw_min.iloc[-1] > 0:
                if bandwidth.iloc[-1] <= bw_min.iloc[-1] * 1.05:
                    # Squeeze has re-formed after the breakout -- stalling
                    return "BandWidth Contraction (Squeeze Re-forming)"

        # --- 3. Time Decay ---
        if hasattr(position, "entry_time") and bar.name is not None:
            bars_held = len(df[df.index >= position.entry_time])
            if bars_held > 25:
                if is_long:
                    pnl_r = (current_close - position.entry_price) / initial_risk
                else:
                    pnl_r = (position.entry_price - current_close) / initial_risk
                if pnl_r < 0.5:
                    return "Time Decay (>25 bars, <0.5R)"

        return None

    def get_required_lookback_bars(self) -> int:
        """Strategy needs enough bars for EMA 200 and BandWidth rolling min."""
        bw_lookback = self.config.get("squeeze_bandwidth_lookback", 120)
        return max(220, bw_lookback + 20)

    def get_required_daily_lookback_days(self) -> int:
        """Moderate daily context for EMA 200 trend."""
        return 30

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _linreg_slope(
        series: pd.Series, period: int, offset: int = 0,
    ) -> Optional[float]:
        """
        Calculate the linear regression slope over the last *period* bars.

        Args:
            series: Price series (typically close).
            period: Number of bars for the regression window.
            offset: How many bars back from the end to anchor the window.
                    0 = most recent window, 1 = one bar earlier, etc.

        Returns:
            Slope (float) or None if not enough data.
        """
        end_idx = len(series) - offset
        start_idx = end_idx - period
        if start_idx < 0 or end_idx <= 0:
            return None

        window = series.iloc[start_idx:end_idx].values
        if len(window) < period:
            return None

        # Check for NaN
        if np.any(np.isnan(window)):
            return None

        x = np.arange(period, dtype=np.float64)
        try:
            slope = np.polyfit(x, window, 1)[0]
        except (np.linalg.LinAlgError, ValueError):
            return None

        return float(slope)

    @staticmethod
    def _get_volume_column(df: pd.DataFrame) -> Optional[str]:
        """
        Return the name of the usable volume column, or None.

        Prefers 'tick_volume' over 'volume'.  Returns None if the column
        is entirely zero or absent.
        """
        for col in ("tick_volume", "volume"):
            if col in df.columns:
                if df[col].sum() > 0:
                    return col
        return None

    @staticmethod
    def _compute_confidence(
        bandwidth: float,
        bandwidth_min: float,
        momentum: float,
        volume_ok: bool,
    ) -> float:
        """
        Heuristic confidence score (0-100) based on squeeze tightness,
        momentum strength, and volume confirmation.
        """
        score = 40.0  # base: squeeze + breakout already confirmed

        # Tighter squeeze = higher confidence
        if bandwidth_min is not None and not np.isnan(bandwidth_min) and bandwidth_min > 0:
            squeeze_ratio = bandwidth / bandwidth_min
            # squeeze_ratio close to 1.0 means very tight squeeze just fired
            if squeeze_ratio <= 1.02:
                score += 20.0
            elif squeeze_ratio <= 1.05:
                score += 10.0

        # Stronger momentum = higher confidence
        abs_mom = abs(momentum) if momentum is not None else 0
        if abs_mom > 1.0:
            score += 15.0
        elif abs_mom > 0.5:
            score += 10.0
        elif abs_mom > 0.1:
            score += 5.0

        # Volume spike present
        if volume_ok:
            score += 10.0

        return min(100.0, score)

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
