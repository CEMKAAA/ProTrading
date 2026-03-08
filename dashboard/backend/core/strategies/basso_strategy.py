"""Basso Mean Reversion Strategy."""

import logging
from datetime import datetime
from typing import Optional, Dict, Any

import numpy as np
import pandas as pd

from .base import BacktestStrategy, DayContext, TradeSetup

logger = logging.getLogger(__name__)


class BassoStrategy(BacktestStrategy):
    """
    Tom Basso's Mean Reversion Strategy.
    Trades when price overextends from its moving average, targeting reversion to the mean.

    Entry Rules:
        1. Overextension: Price > N ATR from SMA (configurable, default 2.0)
        2. RSI Confirmation: RSI(14) > 70 (short) or RSI(14) < 30 (long)
        3. Reversion Signal: First candle that closes back toward the mean (reversal candle)
        4. Stop Loss: Beyond the extreme (recent high/low + 0.5 ATR buffer)
        5. Take Profit: At the SMA (the mean), with minimum 2:1 R:R enforced

    Key Feature - Volatility-Adjusted Sizing:
        Includes a volatility_factor in trade metadata so the engine could use it
        for position sizing adjustments. The actual sizing is done by the engine.
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
        return ctx

    def find_setup(
        self,
        bar: pd.Series,
        df: pd.DataFrame,
        day_context: DayContext,
        current_bar_index: int,
    ) -> Optional[TradeSetup]:
        sma_period = self.config.get('sma_period', 20)
        atr_period = self.config.get('atr_period', 14)
        rsi_period = self.config.get('rsi_period', 14)
        overext_mult = self.config.get('overextension_atr_multiple', 2.0)
        rsi_overbought = self.config.get('rsi_overbought', 70)
        rsi_oversold = self.config.get('rsi_oversold', 30)
        vol_norm_period = self.config.get('volatility_normalization_period', 60)

        min_bars = max(sma_period, atr_period, rsi_period, vol_norm_period) + 5
        if len(df) < min_bars:
            return None

        close = df['close']

        # Calculate SMA
        sma = close.rolling(sma_period).mean()
        current_sma = sma.iloc[-1]

        if pd.isna(current_sma):
            return None

        # Calculate ATR
        atr = self._calculate_atr_series(df, atr_period)
        current_atr = atr.iloc[-1] if len(atr) > 0 and not pd.isna(atr.iloc[-1]) else day_context.atr

        if current_atr <= 0:
            return None

        # Calculate RSI
        rsi = self._calculate_rsi(close, rsi_period)
        current_rsi = rsi.iloc[-1] if len(rsi) > 0 and not pd.isna(rsi.iloc[-1]) else 50.0

        # Calculate distance from SMA in ATR units
        current_close = close.iloc[-1]
        prev_close = close.iloc[-2]
        distance_from_sma = (current_close - current_sma) / current_atr

        # Volatility factor for position sizing hint
        if len(atr) >= vol_norm_period:
            avg_atr = atr.iloc[-vol_norm_period:].mean()
            volatility_factor = current_atr / avg_atr if avg_atr > 0 else 1.0
        else:
            volatility_factor = 1.0

        # Trend filter: EMA200 direction
        ema200 = close.ewm(span=200, adjust=False).mean()
        use_ema200_filter = self.config.get('use_ema200_trend_filter', True)
        slope_bars = max(1, int(self.config.get('ema_trend_slope_bars', 20)))
        if use_ema200_filter and len(ema200) > slope_bars and not pd.isna(ema200.iloc[-1]) and not pd.isna(ema200.iloc[-1 - slope_bars]):
            current_ema200 = ema200.iloc[-1]
            ema200_prev = ema200.iloc[-1 - slope_bars]
            ema200_rising = current_ema200 > ema200_prev
            ema200_falling = current_ema200 < ema200_prev
        else:
            ema200_rising = False
            ema200_falling = False
            current_ema200 = None

        entry = bar['open']

        # === LONG SETUP (price overextended below SMA) ===
        if distance_from_sma < -overext_mult and current_rsi < rsi_oversold and not ema200_falling:
            # Check for reversal candle: close flip, hammer, or bullish pin bar
            if not self._is_bullish_reversal(df):
                return None  # No reversal yet

            # SL below recent low + buffer
            recent_low = df['low'].iloc[-10:].min()
            sl = recent_low - current_atr * 0.5
            sl_distance = abs(entry - sl)

            min_sl = self.config.get('min_sl_usd', 1.0)
            max_sl = self.config.get('max_sl_usd', 15.0)
            sl_distance = max(min_sl, min(max_sl, sl_distance))
            sl = entry - sl_distance

            # TP at the SMA (the mean)
            tp = current_sma
            # Ensure minimum 2:1 R:R
            if abs(tp - entry) < sl_distance * 2.0:
                tp = entry + sl_distance * 2.0

            return TradeSetup(
                direction='BUY',
                entry_price=entry,
                stop_loss=sl,
                take_profit=tp,
                setup_type='Basso Mean Reversion (Long)',
                confidence=min(100, int(abs(distance_from_sma) * 20)),
                metadata={
                    'sma': float(current_sma),
                    'rsi': float(current_rsi),
                    'distance_atr': float(distance_from_sma),
                    'volatility_factor': float(volatility_factor),
                    'ema200': float(current_ema200) if current_ema200 is not None else None,
                },
            )

        # === SHORT SETUP (price overextended above SMA) ===
        elif distance_from_sma > overext_mult and current_rsi > rsi_overbought and not ema200_rising:
            # Check for reversal candle: close flip, shooting star, or bearish pin bar
            if not self._is_bearish_reversal(df):
                return None

            # SL above recent high + buffer
            recent_high = df['high'].iloc[-10:].max()
            sl = recent_high + current_atr * 0.5
            sl_distance = abs(sl - entry)

            min_sl = self.config.get('min_sl_usd', 1.0)
            max_sl = self.config.get('max_sl_usd', 15.0)
            sl_distance = max(min_sl, min(max_sl, sl_distance))
            sl = entry + sl_distance

            # TP at the SMA (the mean)
            tp = current_sma
            # Ensure minimum 2:1 R:R
            if abs(entry - tp) < sl_distance * 2.0:
                tp = entry - sl_distance * 2.0

            return TradeSetup(
                direction='SELL',
                entry_price=entry,
                stop_loss=sl,
                take_profit=tp,
                setup_type='Basso Mean Reversion (Short)',
                confidence=min(100, int(abs(distance_from_sma) * 20)),
                metadata={
                    'sma': float(current_sma),
                    'rsi': float(current_rsi),
                    'distance_atr': float(distance_from_sma),
                    'volatility_factor': float(volatility_factor),
                    'ema200': float(current_ema200) if current_ema200 is not None else None,
                },
            )

        return None

    def should_close_early(self, bar, df, position, day_context):
        """Adaptive exit for mean reversion trades."""
        sma_period = self.config.get('sma_period', 20)
        rsi_period = self.config.get('rsi_period', 14)
        close = df['close']
        if len(close) < sma_period:
            return None

        current_close = bar['close']
        sma = close.rolling(sma_period).mean().iloc[-1]
        if pd.isna(sma):
            return None

        atr = day_context.atr or 1.0
        initial_risk = abs(position.entry_price - position.stop_loss)
        if initial_risk <= 0:
            return None

        # 1. Mean reversion complete: price reached within 0.3 ATR of SMA
        distance_to_sma = abs(current_close - sma) / atr
        if distance_to_sma < 0.3:
            if position.direction == 'BUY' and current_close > position.entry_price:
                return "Mean Reversion Complete"
            elif position.direction == 'SELL' and current_close < position.entry_price:
                return "Mean Reversion Complete"

        # 2. RSI normalization + profitable (> 1R)
        rsi = self._calculate_rsi(close, rsi_period)
        current_rsi = rsi.iloc[-1] if len(rsi) > 0 and not pd.isna(rsi.iloc[-1]) else 50.0

        if position.direction == 'BUY':
            pnl_r = (current_close - position.entry_price) / initial_risk
            if current_rsi > 55 and pnl_r > 1.0:
                return "RSI Normalized (Long Exit)"
        else:
            pnl_r = (position.entry_price - current_close) / initial_risk
            if current_rsi < 45 and pnl_r > 1.0:
                return "RSI Normalized (Short Exit)"

        # 3. Time-based exit: if trade open > 20 bars and not profitable
        if hasattr(position, 'entry_time') and bar.name is not None:
            bars_held = len(df[df.index >= position.entry_time])
            if bars_held > 20:
                if position.direction == 'BUY' and current_close <= position.entry_price:
                    return "Time Decay (Stale Long)"
                elif position.direction == 'SELL' and current_close >= position.entry_price:
                    return "Time Decay (Stale Short)"

        return None

    def get_required_lookback_bars(self) -> int:
        return max(220, self.config.get('volatility_normalization_period', 60) + 10)

    # ------------------------------------------------------------------
    # Indicator helpers (private)
    # ------------------------------------------------------------------

    @staticmethod
    def _is_bullish_reversal(df: pd.DataFrame) -> bool:
        """Detect bullish reversal: close flip, hammer, or bullish pin bar."""
        if len(df) < 2:
            return False
        c = df.iloc[-1]  # current bar
        p = df.iloc[-2]  # previous bar
        # 1. Simple close flip (original logic)
        if c['close'] > p['close']:
            return True
        # 2. Hammer: long lower wick, small upper wick
        body = abs(c['close'] - c['open'])
        full_range = c['high'] - c['low']
        if full_range < 0.01:
            return False
        lower_wick = min(c['open'], c['close']) - c['low']
        upper_wick = c['high'] - max(c['open'], c['close'])
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
        # 1. Simple close flip
        if c['close'] < p['close']:
            return True
        # 2. Shooting star: long upper wick, small lower wick
        body = abs(c['close'] - c['open'])
        full_range = c['high'] - c['low']
        if full_range < 0.01:
            return False
        upper_wick = c['high'] - max(c['open'], c['close'])
        lower_wick = min(c['open'], c['close']) - c['low']
        if upper_wick > full_range * 0.6 and lower_wick < full_range * 0.15:
            return True
        # 3. Bearish pin bar: upper wick > 2x body
        if upper_wick > body * 2 and lower_wick < body * 0.5:
            return True
        return False

    @staticmethod
    def _calculate_rsi(close: pd.Series, period: int) -> pd.Series:
        """Calculate RSI using Wilder's smoothing (EMA-based)."""
        delta = close.diff()
        gain = delta.where(delta > 0, 0.0)
        loss = (-delta).where(delta < 0, 0.0)
        # Wilder's smoothing = EMA with alpha = 1/period
        avg_gain = gain.ewm(alpha=1.0/period, adjust=False).mean()
        avg_loss = loss.ewm(alpha=1.0/period, adjust=False).mean()
        rs = avg_gain / avg_loss
        rsi = 100 - (100 / (1 + rs))
        return rsi

    @staticmethod
    def _calculate_atr_series(df: pd.DataFrame, period: int) -> pd.Series:
        """Calculate ATR as a full series."""
        high = df['high']
        low = df['low']
        close = df['close']
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
    def _calculate_atr(df: pd.DataFrame, period: int) -> float:
        """Calculate the current (latest) ATR value."""
        if len(df) < period:
            return 1.0
        high = df['high']
        low = df['low']
        close = df['close']
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
