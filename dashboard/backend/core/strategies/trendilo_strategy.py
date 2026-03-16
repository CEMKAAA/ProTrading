"""Trendilo Strategy.

Trendilo core:
1) Normalized momentum (% change over lookback)
2) ALMA smoothing of momentum
3) RMS envelope around smoothed momentum
4) Direction from envelope breakout

Confirmations:
- ADX (stoch) with VWMA line
- DI direction
- 300 ALMA and 300 T3 trend filter

Risk model:
- SL from ATR * multiplier
- TP from fixed R multiple
"""

from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, Optional, Tuple

import numpy as np
import pandas as pd

from .base import BacktestStrategy, DayContext, TradeSetup


class TrendiloStrategy(BacktestStrategy):
    """Trendilo momentum + confirmation strategy."""

    def initialize_day(
        self,
        date: datetime,
        daily_df: Optional[pd.DataFrame],
        intraday_df: pd.DataFrame,
    ) -> DayContext:
        ctx = DayContext(date=date)
        if intraday_df is not None and len(intraday_df) >= 20:
            ctx.atr = self._atr(intraday_df, int(self.config.get("atr_period", 14)))
            ind = self._compute_indicators(intraday_df)
            direction = str(ind.get("trendilo_direction") or "neutral")
            di_dir = str(ind.get("di_direction") or "neutral")
            adx_line = float(ind.get("adx_stoch_vwma") or 0.0)
            if direction == "bullish" and di_dir == "bullish":
                ctx.bias = "bullish"
            elif direction == "bearish" and di_dir == "bearish":
                ctx.bias = "bearish"
            else:
                ctx.bias = "neutral"
            # Keep confidence deterministic and bounded.
            ctx.bias_strength = int(max(0.0, min(100.0, adx_line)))
            ctx.levels.update(
                {
                    "trendilo_avpch": float(ind.get("trendilo_avpch") or 0.0),
                    "trendilo_rms": float(ind.get("trendilo_rms") or 0.0),
                    "alma300": float(ind.get("alma300") or 0.0),
                    "t3_300": float(ind.get("t3_300") or 0.0),
                    "adx_stoch_vwma": float(ind.get("adx_stoch_vwma") or 0.0),
                    "plus_di14": float(ind.get("plus_di14") or 0.0),
                    "minus_di14": float(ind.get("minus_di14") or 0.0),
                }
            )
        return ctx

    def find_setup(
        self,
        bar: pd.Series,
        df: pd.DataFrame,
        day_context: DayContext,
        current_bar_index: int,
    ) -> Optional[TradeSetup]:
        min_bars = int(self.get_required_lookback_bars())
        if df is None or len(df) < min_bars:
            return None

        ind = self._compute_indicators(df)
        direction = str(ind.get("trendilo_direction") or "neutral")
        prev_direction = str(ind.get("trendilo_prev_direction") or "neutral")
        close = float(df["close"].iloc[-1])
        entry = float(bar["open"])

        adx_line = float(ind.get("adx_stoch_vwma") or 0.0)
        adx_threshold = float(self.config.get("adx_threshold", 20.0))
        if adx_line < adx_threshold:
            return None

        use_di = bool(self.config.get("use_di_direction", True))
        plus_di = float(ind.get("plus_di14") or 0.0)
        minus_di = float(ind.get("minus_di14") or 0.0)
        di_bull_ok = (plus_di > minus_di) if use_di else True
        di_bear_ok = (minus_di > plus_di) if use_di else True

        alma300 = float(ind.get("alma300") or close)
        t3_300 = float(ind.get("t3_300") or close)
        trend_bull_ok = close > alma300 and close > t3_300
        trend_bear_ok = close < alma300 and close < t3_300

        require_flip = bool(self.config.get("require_direction_flip", False))
        long_signal = direction == "bullish" and di_bull_ok and trend_bull_ok
        short_signal = direction == "bearish" and di_bear_ok and trend_bear_ok
        if require_flip:
            long_signal = long_signal and prev_direction != "bullish"
            short_signal = short_signal and prev_direction != "bearish"
        if not long_signal and not short_signal:
            return None

        atr = self._atr(df, int(self.config.get("atr_period", 14)))
        atr_mult = float(self.config.get("atr_stop_mult", 1.8))
        sl_raw = max(atr * atr_mult, 1e-6)
        min_sl = float(self.config.get("min_sl_usd", 0.3))
        max_sl = float(self.config.get("max_sl_usd", 20.0))
        risk_distance = max(min_sl, min(max_sl, sl_raw))

        rr_ratio = float(self.config.get("rr_ratio", 2.0))
        if long_signal:
            stop = float(entry - risk_distance)
            tp = float(entry + (risk_distance * rr_ratio))
            return TradeSetup(
                direction="BUY",
                entry_price=float(entry),
                stop_loss=stop,
                take_profit=tp,
                setup_type="Trendilo Bullish + ADX/DI + ALMA/T3",
                confidence=float(max(0.0, min(100.0, adx_line))),
                metadata={
                    "trendilo_direction": direction,
                    "trendilo_avpch": float(ind.get("trendilo_avpch") or 0.0),
                    "trendilo_rms": float(ind.get("trendilo_rms") or 0.0),
                    "adx_stoch_vwma": float(adx_line),
                    "plus_di14": float(plus_di),
                    "minus_di14": float(minus_di),
                    "alma300": float(alma300),
                    "t3_300": float(t3_300),
                    "rr_ratio": float(rr_ratio),
                },
            )

        if short_signal:
            stop = float(entry + risk_distance)
            tp = float(entry - (risk_distance * rr_ratio))
            return TradeSetup(
                direction="SELL",
                entry_price=float(entry),
                stop_loss=stop,
                take_profit=tp,
                setup_type="Trendilo Bearish + ADX/DI + ALMA/T3",
                confidence=float(max(0.0, min(100.0, adx_line))),
                metadata={
                    "trendilo_direction": direction,
                    "trendilo_avpch": float(ind.get("trendilo_avpch") or 0.0),
                    "trendilo_rms": float(ind.get("trendilo_rms") or 0.0),
                    "adx_stoch_vwma": float(adx_line),
                    "plus_di14": float(plus_di),
                    "minus_di14": float(minus_di),
                    "alma300": float(alma300),
                    "t3_300": float(t3_300),
                    "rr_ratio": float(rr_ratio),
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
        if df is None or len(df) < max(80, self.get_required_lookback_bars() // 2):
            return None
        ind = self._compute_indicators(df)
        direction = str(ind.get("trendilo_direction") or "neutral")
        plus_di = float(ind.get("plus_di14") or 0.0)
        minus_di = float(ind.get("minus_di14") or 0.0)
        close = float(df["close"].iloc[-1])
        alma300 = float(ind.get("alma300") or close)
        t3_300 = float(ind.get("t3_300") or close)

        if str(position.direction or "").upper() == "BUY":
            if direction == "bearish":
                return "Trendilo flipped bearish"
            if plus_di < minus_di:
                return "DI flipped bearish"
            if close < alma300 and close < t3_300:
                return "Price lost ALMA/T3 trend filter"
        else:
            if direction == "bullish":
                return "Trendilo flipped bullish"
            if minus_di < plus_di:
                return "DI flipped bullish"
            if close > alma300 and close > t3_300:
                return "Price lost ALMA/T3 trend filter"
        return None

    def get_required_lookback_bars(self) -> int:
        return int(max(320, int(self.config.get("trend_filter_length", 300)) + 40))

    def get_required_daily_lookback_days(self) -> int:
        return 20

    # --------------------------
    # Indicator helpers
    # --------------------------

    @staticmethod
    def _alma(series: pd.Series, length: int, offset: float, sigma: float) -> pd.Series:
        ln = max(2, int(length))
        off = float(max(0.0, min(1.0, float(offset))))
        sig = float(max(0.1, float(sigma)))
        m = off * float(ln - 1)
        s = float(ln) / sig
        idx = np.arange(ln, dtype=float)
        w = np.exp(-((idx - m) ** 2) / (2.0 * (s ** 2)))
        w_sum = float(np.sum(w))
        if not np.isfinite(w_sum) or w_sum <= 1e-12:
            return series.rolling(window=ln, min_periods=1).mean()
        w = w / w_sum
        return series.rolling(window=ln, min_periods=ln).apply(lambda x: float(np.dot(x, w)), raw=True)

    @staticmethod
    def _vwma(series: pd.Series, vol: pd.Series, length: int) -> pd.Series:
        ln = max(1, int(length))
        num = (series * vol).rolling(window=ln, min_periods=1).sum()
        den = vol.rolling(window=ln, min_periods=1).sum().replace(0.0, np.nan)
        return (num / den).ffill()

    @staticmethod
    def _t3(series: pd.Series, length: int, vfactor: float = 0.7) -> pd.Series:
        ln = max(2, int(length))
        v = float(max(0.0, min(1.0, float(vfactor))))
        e1 = series.ewm(span=ln, adjust=False).mean()
        e2 = e1.ewm(span=ln, adjust=False).mean()
        e3 = e2.ewm(span=ln, adjust=False).mean()
        e4 = e3.ewm(span=ln, adjust=False).mean()
        e5 = e4.ewm(span=ln, adjust=False).mean()
        e6 = e5.ewm(span=ln, adjust=False).mean()
        c1 = -v ** 3
        c2 = 3 * v ** 2 + 3 * v ** 3
        c3 = -6 * v ** 2 - 3 * v - 3 * v ** 3
        c4 = 1 + 3 * v + v ** 3 + 3 * v ** 2
        return (c1 * e6) + (c2 * e5) + (c3 * e4) + (c4 * e3)

    @staticmethod
    def _atr(df: pd.DataFrame, period: int = 14) -> float:
        p = max(2, int(period))
        if len(df) < p:
            return 1.0
        high = df["high"].astype(float)
        low = df["low"].astype(float)
        close = df["close"].astype(float)
        prev_close = close.shift(1).fillna(close.iloc[0])
        tr = pd.concat(
            [
                (high - low).abs(),
                (high - prev_close).abs(),
                (low - prev_close).abs(),
            ],
            axis=1,
        ).max(axis=1)
        atr = tr.rolling(window=p, min_periods=1).mean()
        val = float(atr.iloc[-1]) if len(atr) > 0 else 1.0
        if not np.isfinite(val) or val <= 0:
            return 1.0
        return val

    @staticmethod
    def _adx_di(df: pd.DataFrame, period: int = 14) -> Tuple[pd.Series, pd.Series, pd.Series]:
        p = max(2, int(period))
        high = df["high"].astype(float)
        low = df["low"].astype(float)
        close = df["close"].astype(float)
        up_move = high.diff()
        down_move = -low.diff()
        plus_dm = up_move.where((up_move > down_move) & (up_move > 0), 0.0)
        minus_dm = down_move.where((down_move > up_move) & (down_move > 0), 0.0)
        prev_close = close.shift(1).fillna(close.iloc[0])
        tr = pd.concat(
            [
                (high - low).abs(),
                (high - prev_close).abs(),
                (low - prev_close).abs(),
            ],
            axis=1,
        ).max(axis=1)
        atr = tr.ewm(alpha=(1.0 / p), adjust=False).mean().replace(0.0, np.nan)
        plus_di = 100.0 * (plus_dm.ewm(alpha=(1.0 / p), adjust=False).mean() / atr)
        minus_di = 100.0 * (minus_dm.ewm(alpha=(1.0 / p), adjust=False).mean() / atr)
        di_sum = (plus_di + minus_di).replace(0.0, np.nan)
        dx = 100.0 * (plus_di - minus_di).abs() / di_sum
        adx = dx.ewm(alpha=(1.0 / p), adjust=False).mean()
        return adx.fillna(0.0), plus_di.fillna(0.0), minus_di.fillna(0.0)

    def _compute_indicators(self, df: pd.DataFrame) -> Dict[str, Any]:
        close = df["close"].astype(float)
        high = df["high"].astype(float)
        low = df["low"].astype(float)
        vol = df["volume"].astype(float) if "volume" in df.columns else pd.Series(0.0, index=df.index)

        trendilo_pct_lookback = int(self.config.get("trendilo_pct_lookback", 1))
        trendilo_length = int(self.config.get("trendilo_length", 50))
        trendilo_offset = float(self.config.get("trendilo_alma_offset", 0.85))
        trendilo_sigma = float(self.config.get("trendilo_alma_sigma", 6.0))
        trendilo_band_mult = float(self.config.get("trendilo_band_multiplier", 1.0))
        trendilo_use_custom_band_len = bool(self.config.get("trendilo_use_custom_band_length", False))
        trendilo_custom_band_len = int(self.config.get("trendilo_band_length", 20))
        trendilo_band_len = int(trendilo_custom_band_len if trendilo_use_custom_band_len else trendilo_length)
        trendilo_band_len = max(1, trendilo_band_len)
        trend_len = int(self.config.get("trend_filter_length", 300))

        prev_n = close.shift(trendilo_pct_lookback).replace(0.0, np.nan)
        pch = ((close - prev_n) / close.replace(0.0, np.nan)) * 100.0
        pch = pch.replace([np.inf, -np.inf], np.nan)
        avpch = self._alma(pch, trendilo_length, trendilo_offset, trendilo_sigma)
        rms = np.sqrt((avpch.pow(2)).rolling(window=trendilo_band_len, min_periods=trendilo_band_len).mean())
        upper = rms * trendilo_band_mult
        lower = -upper
        dir_num = pd.Series(np.where(avpch > upper, 1, np.where(avpch < lower, -1, 0)), index=df.index)

        adx_period = int(self.config.get("adx_period", 14))
        adx_stoch_period = int(self.config.get("adx_stoch_period", 14))
        adx_vwma_len = int(self.config.get("adx_vwma_length", 8))
        adx, plus_di, minus_di = self._adx_di(df, adx_period)
        ll = adx.rolling(window=adx_stoch_period, min_periods=1).min()
        hh = adx.rolling(window=adx_stoch_period, min_periods=1).max()
        rng = (hh - ll).replace(0.0, np.nan)
        stoch_adx = ((adx - ll) / rng) * 100.0
        stoch_adx_vwma = self._vwma(stoch_adx.fillna(0.0), vol.fillna(0.0), adx_vwma_len).ffill().fillna(0.0)

        alma300 = self._alma(close, trend_len, 0.95, 6.0).ffill()
        t3_300 = self._t3(close, trend_len, float(self.config.get("t3_vfactor", 0.7))).ffill()

        direction = "neutral"
        if int(dir_num.iloc[-1]) > 0:
            direction = "bullish"
        elif int(dir_num.iloc[-1]) < 0:
            direction = "bearish"

        prev_direction = "neutral"
        if len(dir_num) >= 2:
            if int(dir_num.iloc[-2]) > 0:
                prev_direction = "bullish"
            elif int(dir_num.iloc[-2]) < 0:
                prev_direction = "bearish"

        di_direction = "neutral"
        if float(plus_di.iloc[-1]) > float(minus_di.iloc[-1]):
            di_direction = "bullish"
        elif float(minus_di.iloc[-1]) > float(plus_di.iloc[-1]):
            di_direction = "bearish"

        return {
            "trendilo_avpch": float(avpch.iloc[-1]),
            "trendilo_rms": float(rms.iloc[-1]),
            "trendilo_direction": direction,
            "trendilo_prev_direction": prev_direction,
            "adx_stoch_vwma": float(stoch_adx_vwma.iloc[-1]),
            "plus_di14": float(plus_di.iloc[-1]),
            "minus_di14": float(minus_di.iloc[-1]),
            "di_direction": di_direction,
            "alma300": float(alma300.iloc[-1]),
            "t3_300": float(t3_300.iloc[-1]),
        }
