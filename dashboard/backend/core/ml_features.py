"""
ML Feature Extraction for Trade Filtering

Extracts 35 features at the moment of trade entry for ML model input.
V1: 19 base features (bias, ORB, session, ICT, risk, time, daily)
V2: 8 extended features (volatility regime, ADX, confluence, streaks)
V3: 8 strategy-adaptive features (read from strategy metadata)

All continuous features are ATR-normalized for scale invariance across time periods.
"""

import numpy as np
from dataclasses import dataclass, fields, asdict
from typing import Optional, Dict, List, Any
from .timezone_config import SESSION_CLOSE_HOUR


@dataclass
class MLFeatureVector:
    """All features available at the moment of trade entry decision."""

    # Bias & Trend
    bias_direction: float = 0.0       # 1.0=bullish, -1.0=bearish, 0.0=neutral
    bias_strength: float = 0.0        # 0-100 score

    # ORB Context (ATR-normalized)
    orb_range_atr: float = 0.0        # (orb_high - orb_low) / atr
    breakout_distance_atr: float = 0.0  # Distance past ORB level / atr

    # Session Ranges (ATR-normalized)
    asian_range_atr: float = 0.0      # (asian_high - asian_low) / atr
    pd_range_atr: float = 0.0         # (pd_high - pd_low) / atr
    london_range_atr: float = 0.0     # (london_high - london_low) / atr

    # ICT Pattern Quality
    fvg_size_atr: float = 0.0         # FVG gap size / atr
    has_order_block: float = 0.0      # 0.0 or 1.0
    ob_body_percent: float = 0.0      # OB body % (0-100), 0 if no OB

    # Risk Context (ATR-normalized)
    sl_distance_atr: float = 0.0      # Stop loss distance / atr
    rr_ratio: float = 0.0            # Risk:Reward ratio being used
    spread_atr: float = 0.0          # Current spread / atr

    # Time Features
    hour_of_day: float = 0.0         # 0-23 NY time
    day_of_week: float = 0.0         # 0=Mon, 4=Fri
    minutes_since_orb: float = 0.0   # Minutes since ORB end (09:45)

    # Daily Context
    daily_pnl_pct: float = 0.0       # Today's P&L / balance (as ratio)
    trades_today: float = 0.0        # Number of trades taken today

    # Displacement Quality (ATR-normalized)
    displacement_magnitude_atr: float = 0.0  # Displacement candle body / atr

    # V2 Features
    volatility_regime: float = 0.0        # ATR percentile: 0=low, 50=normal, 100=high
    htf_nearest_level_distance_atr: float = 0.0  # Distance to nearest HTF support/resistance
    confluence_count: float = 0.0         # Number of levels within 1 ATR of entry
    adx_14: float = 0.0                   # Trend strength (0-100)
    hours_to_session_close: float = 0.0   # Hours remaining until session end
    consecutive_results: float = 0.0      # Win streak (+) or loss streak (-)
    proximity_to_round_number: float = 0.0  # Distance to $XX00/$XX50 in ATR
    fvg_fill_ratio: float = 0.0           # How much of FVG was filled before entry (0-1)

    # V3 Strategy-Adaptive Features (read from setup metadata)
    setup_confidence: float = 0.0          # Strategy's confidence in this specific setup (0-100)
    strategy_rsi: float = 50.0            # RSI at entry (0-100), 50.0 = unknown/neutral
    strategy_momentum: float = 0.0        # ATR-normalized momentum (MACD hist, ROC, linreg)
    strategy_mean_reversion_z: float = 0.0 # Distance from mean in standardized units
    strategy_volatility_factor: float = 1.0 # Local vol vs baseline (1.0 = average)
    strategy_squeeze_metric: float = 0.0   # Compression/freshness (squeeze ratio, bars ago)
    strategy_pattern_quality: float = 0.0  # Pattern quality score (confluence score, etc.)
    strategy_trend_alignment: float = 0.0  # Trade vs trend alignment (-1 to +1)


class FeatureExtractor:
    """Extracts ML features from the backtest engine state at trade time."""

    @staticmethod
    def extract(day_state, setup: dict, bar, config, balance: float,
                spread: float, entry_price: float, sl_distance: float,
                rr_ratio: float, df=None, recent_results: list = None) -> MLFeatureVector:
        """
        Extract features from current engine state.

        Args:
            day_state: DayState object with session levels and bias
            setup: Trade setup dict from _find_trade_setup
            bar: Current bar data
            config: BacktestConfig
            balance: Current account balance
            spread: Current spread cost
            entry_price: Calculated entry price
            sl_distance: Stop loss distance in USD
            rr_ratio: Risk:reward ratio being used
            df: DataFrame with recent bars (for V2 features like ADX, ATR history)
            recent_results: List of recent trade results (1=win, 0=loss) for streak
        """
        atr = max(day_state.atr, 0.01)  # Prevent division by zero
        direction = setup['direction']

        # Bias
        bias_dir = 1.0 if day_state.bias == "bullish" else (-1.0 if day_state.bias == "bearish" else 0.0)

        # ORB Context
        orb_high = day_state.orb_high or 0.0
        orb_low = day_state.orb_low or 0.0
        orb_range = (orb_high - orb_low) if (orb_high and orb_low) else 0.0

        breakout_dist = 0.0
        if direction == 'BUY' and orb_high:
            breakout_dist = (entry_price - orb_high) / atr
        elif direction == 'SELL' and orb_low:
            breakout_dist = (orb_low - entry_price) / atr

        # Session Ranges
        asian_range = 0.0
        if day_state.asian_high and day_state.asian_low:
            asian_range = (day_state.asian_high - day_state.asian_low) / atr

        pd_range = 0.0
        if day_state.pd_high and day_state.pd_low:
            pd_range = (day_state.pd_high - day_state.pd_low) / atr

        london_range = 0.0
        if day_state.london_high and day_state.london_low:
            london_range = (day_state.london_high - day_state.london_low) / atr

        # ICT Quality
        fvg = setup.get('fvg')
        fvg_size = (fvg['size'] / atr) if fvg else 0.0

        ob = setup.get('ob')
        has_ob = 1.0 if ob else 0.0
        ob_body = ob.get('body_pct', 0.0) if ob else 0.0

        # Time
        bar_time = bar.name
        hour = bar_time.hour if hasattr(bar_time, 'hour') else 10
        dow = bar_time.weekday() if hasattr(bar_time, 'weekday') else 0
        # Minutes since ORB end (09:45)
        mins_since_orb = (hour - 9) * 60 + (bar_time.minute if hasattr(bar_time, 'minute') else 0) - 45
        mins_since_orb = max(0.0, float(mins_since_orb))

        # Daily Context
        daily_pnl_pct = day_state.daily_pnl / max(balance, 1.0)

        # Displacement magnitude (from FVG middle candle if available)
        disp_mag = 0.0
        if fvg and 'size' in fvg:
            disp_mag = fvg['size'] / atr  # Approximation using FVG size

        # === V2 Features ===

        # Volatility Regime: ATR percentile over lookback period
        volatility_regime = 50.0  # default = normal
        if df is not None and len(df) >= 60:
            atr_series = FeatureExtractor._calculate_atr_series(df, period=14)
            if len(atr_series) >= 60:
                current_atr = atr_series.iloc[-1]
                percentile = (atr_series.iloc[-60:] < current_atr).sum() / 60 * 100
                volatility_regime = float(percentile)

        # HTF Nearest Level Distance: distance to nearest session level
        htf_dist = 0.0
        session_levels = []
        for attr_name in ['asian_high', 'asian_low', 'pd_high', 'pd_low', 'london_high', 'london_low']:
            val = getattr(day_state, attr_name, None)
            if val and val > 0:
                session_levels.append(val)
        if session_levels:
            distances = [abs(entry_price - lvl) / atr for lvl in session_levels]
            htf_dist = min(distances)

        # Confluence Count: how many levels within 1 ATR of entry
        confluence_count = 0.0
        all_levels = list(session_levels)
        # Add ORB levels
        if orb_high: all_levels.append(orb_high)
        if orb_low: all_levels.append(orb_low)
        # Add round numbers near entry
        round_50_level = round(entry_price / 50) * 50
        all_levels.extend([round_50_level - 50, round_50_level, round_50_level + 50])
        for lvl in all_levels:
            if abs(entry_price - lvl) <= atr:
                confluence_count += 1.0

        # ADX(14): trend strength
        adx_value = 0.0
        if df is not None and len(df) >= 28:
            adx_value = FeatureExtractor._calculate_adx(df, period=14)

        # Hours to Session Close
        session_close_hour = SESSION_CLOSE_HOUR
        hours_to_close = max(0.0, float(session_close_hour - hour))

        # Consecutive Results (win/loss streak)
        consec = 0.0
        if recent_results:
            streak = 0
            last_result = recent_results[-1] if recent_results else None
            for r in reversed(recent_results):
                if r == last_result:
                    streak += 1
                else:
                    break
            consec = float(streak) if last_result == 1 else float(-streak)

        # Proximity to Round Number ($XX00 or $XX50)
        nearest_round = round(entry_price / 50) * 50
        round_dist = abs(entry_price - nearest_round) / atr

        # FVG Fill Ratio: how much of the FVG was filled before entry
        fvg_fill = 0.0
        if fvg and fvg.get('size', 0) > 0:
            fvg_top = fvg.get('top', 0)
            fvg_bottom = fvg.get('bottom', 0)
            if fvg_top > fvg_bottom:
                if direction == 'BUY':
                    filled = max(0, fvg_top - entry_price)
                else:
                    filled = max(0, entry_price - fvg_bottom)
                fvg_fill = min(1.0, filled / fvg['size'])

        # === V3 Strategy-Adaptive Features ===
        metadata = setup.get('metadata') or {}

        # 1. Setup confidence (strategy's own confidence in this setup)
        # TradeSetup.confidence is mapped to setup['bias_strength'] in the engine
        setup_conf = float(metadata.get('confidence', setup.get('bias_strength', 0)))

        # 2. RSI at entry (Basso, Confluence Zone, VWAP provide this)
        strat_rsi = float(metadata.get('rsi', 50.0))

        # 3. Momentum (ATR-normalized): MACD histogram, ROC, linreg slope
        strat_momentum = 0.0
        if 'histogram' in metadata:
            strat_momentum = float(metadata['histogram']) / atr
        elif 'roc' in metadata:
            strat_momentum = float(metadata['roc']) / 10.0  # ROC is percentage
        elif 'momentum' in metadata:
            strat_momentum = float(metadata['momentum']) / atr

        # 4. Mean reversion z-score: VWAP deviation_sigma, Basso distance_atr
        strat_mr_z = 0.0
        if 'deviation_sigma' in metadata:
            strat_mr_z = float(metadata['deviation_sigma'])
        elif 'distance_atr' in metadata:
            strat_mr_z = float(metadata['distance_atr'])

        # 5. Volatility factor (local vol vs baseline)
        strat_vol = 1.0
        if 'volatility_factor' in metadata:
            strat_vol = float(metadata['volatility_factor'])
        elif 'bandwidth' in metadata and 'bandwidth_min' in metadata:
            bw_min = float(metadata.get('bandwidth_min', 0))
            if bw_min > 0.0001:
                strat_vol = float(metadata['bandwidth']) / bw_min

        # 6. Squeeze metric (compression freshness)
        strat_squeeze = 0.0
        if 'squeeze_bars_ago' in metadata:
            strat_squeeze = max(0.0, 6.0 - float(metadata['squeeze_bars_ago']))
        elif 'bandwidth' in metadata and 'bandwidth_min' in metadata:
            bw = float(metadata.get('bandwidth', 0))
            bw_min = float(metadata.get('bandwidth_min', 0))
            if bw_min > 0.0001:
                strat_squeeze = bw / bw_min  # expansion ratio

        # 7. Pattern quality (Confluence score, zone levels)
        strat_quality = 0.0
        if 'confluence_score' in metadata:
            strat_quality = float(metadata['confluence_score'])
        elif 'levels_in_zone' in metadata:
            strat_quality = float(metadata['levels_in_zone']) * 20.0  # Scale to ~0-100

        # 8. Trend alignment (-1 to +1): trade direction vs higher TF trend
        strat_trend = 0.0
        if 'ema200_slope' in metadata:
            slope = metadata['ema200_slope']
            if direction == 'BUY':
                strat_trend = 1.0 if slope == 'rising' else (-1.0 if slope == 'falling' else 0.0)
            else:
                strat_trend = 1.0 if slope == 'falling' else (-1.0 if slope == 'rising' else 0.0)
        elif 'ema200' in metadata and 'ema_fast' in metadata:
            # MACD: EMA stack alignment
            ema_fast_val = float(metadata.get('ema_fast', 0))
            ema200_val = float(metadata.get('ema200', 0))
            if ema200_val > 0:
                if direction == 'BUY':
                    strat_trend = 1.0 if ema_fast_val > ema200_val else -1.0
                else:
                    strat_trend = 1.0 if ema_fast_val < ema200_val else -1.0

        return MLFeatureVector(
            bias_direction=bias_dir,
            bias_strength=float(day_state.bias_strength),
            orb_range_atr=orb_range / atr,
            breakout_distance_atr=breakout_dist,
            asian_range_atr=asian_range,
            pd_range_atr=pd_range,
            london_range_atr=london_range,
            fvg_size_atr=fvg_size,
            has_order_block=has_ob,
            ob_body_percent=ob_body,
            sl_distance_atr=sl_distance / atr,
            rr_ratio=rr_ratio,
            spread_atr=spread / atr,
            hour_of_day=float(hour),
            day_of_week=float(dow),
            minutes_since_orb=mins_since_orb,
            daily_pnl_pct=daily_pnl_pct,
            trades_today=float(day_state.daily_trades),
            displacement_magnitude_atr=disp_mag,
            # V2 Features
            volatility_regime=volatility_regime,
            htf_nearest_level_distance_atr=htf_dist,
            confluence_count=confluence_count,
            adx_14=adx_value,
            hours_to_session_close=hours_to_close,
            consecutive_results=consec,
            proximity_to_round_number=round_dist,
            fvg_fill_ratio=fvg_fill,
            # V3 Strategy-Adaptive Features
            setup_confidence=setup_conf,
            strategy_rsi=strat_rsi,
            strategy_momentum=strat_momentum,
            strategy_mean_reversion_z=strat_mr_z,
            strategy_volatility_factor=strat_vol,
            strategy_squeeze_metric=strat_squeeze,
            strategy_pattern_quality=strat_quality,
            strategy_trend_alignment=strat_trend,
        )

    @staticmethod
    def _calculate_atr_series(df, period: int = 14):
        """Calculate ATR series from DataFrame with high/low/close columns."""
        high = df['high']
        low = df['low']
        close = df['close']
        prev_close = close.shift(1)
        tr = np.maximum(
            high - low,
            np.maximum(abs(high - prev_close), abs(low - prev_close))
        )
        return tr.rolling(window=period).mean()

    @staticmethod
    def _calculate_adx(df, period: int = 14) -> float:
        """Calculate current ADX(14) value from DataFrame."""
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
            tr[i] = max(high[i] - low[i], abs(high[i] - close[i - 1]), abs(low[i] - close[i - 1]))

        # Smoothed averages (Wilder's smoothing)
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

        # Calculate DI and DX
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

        # ADX = smoothed DX
        adx = np.mean(dx_values[-period:])
        return float(min(100.0, max(0.0, adx)))

    @staticmethod
    def to_dict(features: MLFeatureVector) -> Dict[str, float]:
        """Convert feature vector to dictionary for JSON serialization."""
        return asdict(features)

    @staticmethod
    def to_array(features: MLFeatureVector) -> np.ndarray:
        """Convert feature vector to numpy array for model input."""
        return np.array([getattr(features, f.name) for f in fields(features)], dtype=np.float64)

    @staticmethod
    def feature_names() -> List[str]:
        """Return ordered list of feature names for model training."""
        return [f.name for f in fields(MLFeatureVector)]

    @staticmethod
    def from_dict(d: Dict[str, float]) -> MLFeatureVector:
        """Reconstruct feature vector from dictionary."""
        return MLFeatureVector(**{k: v for k, v in d.items() if k in {f.name for f in fields(MLFeatureVector)}})
