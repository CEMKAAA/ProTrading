"""
Shared technical indicator calculations.
Used by all live trading strategies to avoid code duplication.
"""

import numpy as np
import pandas as pd


class Indicators:
    """Static utility class with all common technical indicators."""

    @staticmethod
    def calculate_atr(df, period=14):
        """Calculate current ATR value."""
        if len(df) < period:
            return 1.0
        high = df['high']
        low = df['low']
        close = df['close']
        tr = pd.concat([
            high - low,
            (high - close.shift(1)).abs(),
            (low - close.shift(1)).abs(),
        ], axis=1).max(axis=1)
        atr = tr.rolling(period).mean()
        if len(atr) > 0 and not pd.isna(atr.iloc[-1]):
            return float(atr.iloc[-1])
        return 1.0

    @staticmethod
    def calculate_atr_series(df, period=14):
        """Calculate ATR as full series."""
        high = df['high']
        low = df['low']
        close = df['close']
        tr = pd.concat([
            high - low,
            (high - close.shift(1)).abs(),
            (low - close.shift(1)).abs(),
        ], axis=1).max(axis=1)
        return tr.rolling(period).mean()

    @staticmethod
    def calculate_ema(series, period):
        """Calculate Exponential Moving Average."""
        return series.ewm(span=period, adjust=False).mean()

    @staticmethod
    def calculate_sma(series, period):
        """Calculate Simple Moving Average."""
        return series.rolling(period).mean()

    @staticmethod
    def calculate_rsi(close, period=14):
        """Calculate Relative Strength Index."""
        delta = close.diff()
        gain = delta.where(delta > 0, 0.0)
        loss = (-delta).where(delta < 0, 0.0)
        # Wilder's smoothing (EMA with alpha=1/period) is more stable
        # than simple rolling means and matches the backtest implementation.
        avg_gain = gain.ewm(alpha=1.0 / period, adjust=False).mean()
        avg_loss = loss.ewm(alpha=1.0 / period, adjust=False).mean()
        rs = avg_gain / avg_loss
        return 100 - (100 / (1 + rs))

    @staticmethod
    def calculate_macd(close, fast=12, slow=26, signal=9):
        """
        Calculate MACD components.

        Returns:
            Tuple of (macd_line, signal_line, histogram) as pd.Series
        """
        ema_fast = close.ewm(span=fast, adjust=False).mean()
        ema_slow = close.ewm(span=slow, adjust=False).mean()
        macd_line = ema_fast - ema_slow
        signal_line = macd_line.ewm(span=signal, adjust=False).mean()
        histogram = macd_line - signal_line
        return macd_line, signal_line, histogram

    @staticmethod
    def calculate_ichimoku(df, tenkan_period=9, kijun_period=26,
                           senkou_b_period=52, displacement=26):
        """
        Calculate all five Ichimoku Kinko Hyo components.

        Returns:
            Tuple of (tenkan, kijun, senkou_a, senkou_b, chikou) as pd.Series
        """
        # Tenkan-sen (Conversion Line)
        high_t = df['high'].rolling(tenkan_period).max()
        low_t = df['low'].rolling(tenkan_period).min()
        tenkan = (high_t + low_t) / 2

        # Kijun-sen (Base Line)
        high_k = df['high'].rolling(kijun_period).max()
        low_k = df['low'].rolling(kijun_period).min()
        kijun = (high_k + low_k) / 2

        # Senkou Span A (Leading Span A)
        senkou_a = ((tenkan + kijun) / 2).shift(displacement)

        # Senkou Span B (Leading Span B)
        high_s = df['high'].rolling(senkou_b_period).max()
        low_s = df['low'].rolling(senkou_b_period).min()
        senkou_b = ((high_s + low_s) / 2).shift(displacement)

        # Chikou Span (Lagging Span)
        chikou = df['close'].shift(-displacement)

        return tenkan, kijun, senkou_a, senkou_b, chikou

    @staticmethod
    def calculate_adx(df, period=14):
        """Calculate Average Directional Index. Returns 0.0 if insufficient data."""
        if len(df) < period * 2:
            return 0.0

        high = df['high'].values
        low = df['low'].values
        close = df['close'].values

        plus_dm = np.zeros(len(high))
        minus_dm = np.zeros(len(high))
        tr = np.zeros(len(high))

        for i in range(1, len(high)):
            up_move = high[i] - high[i - 1]
            down_move = low[i - 1] - low[i]
            plus_dm[i] = up_move if (up_move > down_move and up_move > 0) else 0
            minus_dm[i] = down_move if (down_move > up_move and down_move > 0) else 0
            tr[i] = max(high[i] - low[i],
                        abs(high[i] - close[i - 1]),
                        abs(low[i] - close[i - 1]))

        # Wilder's smoothing
        atr_smooth = np.zeros(len(high))
        plus_di_smooth = np.zeros(len(high))
        minus_di_smooth = np.zeros(len(high))

        atr_smooth[period] = np.mean(tr[1:period + 1])
        plus_di_smooth[period] = np.mean(plus_dm[1:period + 1])
        minus_di_smooth[period] = np.mean(minus_dm[1:period + 1])

        for i in range(period + 1, len(high)):
            atr_smooth[i] = (atr_smooth[i - 1] * (period - 1) + tr[i]) / period
            plus_di_smooth[i] = (plus_di_smooth[i - 1] * (period - 1) + plus_dm[i]) / period
            minus_di_smooth[i] = (minus_di_smooth[i - 1] * (period - 1) + minus_dm[i]) / period

        dx_values = []
        for i in range(period, len(high)):
            if atr_smooth[i] > 0:
                plus_di = 100 * plus_di_smooth[i] / atr_smooth[i]
                minus_di = 100 * minus_di_smooth[i] / atr_smooth[i]
                di_sum = plus_di + minus_di
                dx = 100 * abs(plus_di - minus_di) / di_sum if di_sum > 0 else 0
                dx_values.append(dx)

        if len(dx_values) < period:
            return 0.0

        adx = np.mean(dx_values[-period:])
        return float(min(100.0, max(0.0, adx)))

    @staticmethod
    def calculate_bollinger(close, period=20, std_dev=2.0):
        """
        Calculate Bollinger Bands.

        Returns:
            Tuple of (upper, middle, lower) as pd.Series
        """
        middle = close.rolling(period).mean()
        std = close.rolling(period).std()
        upper = middle + std * std_dev
        lower = middle - std * std_dev
        return upper, middle, lower

    @staticmethod
    def detect_reversal_candle(df, direction='both'):
        """
        Detect reversal candle patterns on the previous confirmed bar.

        Returns:
            dict with 'detected' bool and 'type' string
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

        # Pin bar
        if lower_wick > body * 2 and upper_wick < body * 0.5:
            if direction in ('bullish', 'both'):
                return {"detected": True, "type": "bullish_pin_bar"}
        if upper_wick > body * 2 and lower_wick < body * 0.5:
            if direction in ('bearish', 'both'):
                return {"detected": True, "type": "bearish_pin_bar"}

        # Engulfing
        prev_body = abs(p["close"] - p["open"])
        if body > prev_body * 1.5:
            if c["close"] > c["open"] and p["close"] < p["open"]:
                if direction in ('bullish', 'both'):
                    return {"detected": True, "type": "bullish_engulfing"}
            if c["close"] < c["open"] and p["close"] > p["open"]:
                if direction in ('bearish', 'both'):
                    return {"detected": True, "type": "bearish_engulfing"}

        # Hammer / Shooting Star
        if lower_wick > full_range * 0.6 and upper_wick < full_range * 0.1:
            if direction in ('bullish', 'both'):
                return {"detected": True, "type": "hammer"}
        if upper_wick > full_range * 0.6 and lower_wick < full_range * 0.1:
            if direction in ('bearish', 'both'):
                return {"detected": True, "type": "shooting_star"}

        return {"detected": False}

    @staticmethod
    def find_simple_fvg(df, direction, min_gap=0.15, lookback=8, sweep_timestamp=None):
        """
        Lightweight FVG (Fair Value Gap) detection.

        Returns:
            dict with 'type', 'top', 'bottom' or None
        """
        if len(df) < 5:
            return None

        for offset in range(2, min(lookback, len(df) - 2)):
            c1 = df.iloc[-offset - 2]
            c3 = df.iloc[-offset]

            # If this is used after a liquidity sweep, only accept FVGs
            # formed at/after the sweep bar.
            if sweep_timestamp is not None and hasattr(c3, 'name') and c3.name is not None:
                if c3.name < sweep_timestamp:
                    continue

            if direction == "bullish":
                gap = c3["low"] - c1["high"]
                if gap > min_gap:
                    return {"type": "bullish_fvg", "top": c3["low"], "bottom": c1["high"]}
            else:
                gap = c1["low"] - c3["high"]
                if gap > min_gap:
                    return {"type": "bearish_fvg", "top": c1["low"], "bottom": c3["high"]}

        return None
