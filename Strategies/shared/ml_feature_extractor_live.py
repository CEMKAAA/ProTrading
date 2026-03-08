"""
Live Feature Extractor for ML Trade Filtering.

Builds MLFeatureVector from live trading strategy state.
Adapted from dashboard.backend.core.ml_features.FeatureExtractor
but works with live strategy objects instead of backtest DayState.
"""

import sys
import os
import numpy as np
from typing import Optional, List

# Ensure project root in path for dashboard imports
_project_root = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from dashboard.backend.core.ml_features import MLFeatureVector


class LiveFeatureExtractor:
    """
    Extracts ML features from live strategy state.

    Fills in all 27 MLFeatureVector fields from available live data.
    Fields that are not available for a given strategy default to 0.0
    (which matches what the ML model saw during training for that strategy).
    """

    @staticmethod
    def extract_from_strategy(strategy, setup: dict, df=None) -> MLFeatureVector:
        """
        Extract ML features from a live strategy's current state.

        Args:
            strategy: Live strategy instance (any BaseStrategy subclass)
            setup: Trade setup dict with 'direction', 'entry', 'sl', etc.
            df: Price DataFrame (if None, gets from strategy.data_manager)

        Returns:
            MLFeatureVector with all 27 features populated
        """
        # Get DataFrame from data manager if not provided
        if df is None and hasattr(strategy, 'data_manager'):
            df = strategy.data_manager.get_data()

        direction = setup.get('direction', 'BUY')
        entry_price = setup.get('entry', 0.0)
        sl_price = setup.get('sl', 0.0)
        sl_distance = abs(entry_price - sl_price)
        rr_ratio = setup.get('rr', setup.get('rr_ratio', 2.5))

        # TP-based R:R if available
        tp_price = setup.get('tp')
        if tp_price and sl_distance > 0:
            rr_ratio = abs(tp_price - entry_price) / sl_distance

        # Calculate ATR
        atr = 1.0
        if hasattr(strategy, 'indicators') and df is not None and len(df) >= 14:
            try:
                atr = max(strategy.indicators.calculate_atr(df, 14), 0.01)
            except Exception:
                atr = 1.0

        # Current time features
        hour = 10.0
        dow = 0.0
        now = None
        if hasattr(strategy, '_get_current_time_ny'):
            try:
                now = strategy._get_current_time_ny()
                if now:
                    hour = float(now.hour)
                    dow = float(now.weekday())
            except Exception:
                pass

        # Spread
        spread = 0.0
        if hasattr(strategy, 'mt5') and strategy.mt5 and hasattr(strategy, 'symbol'):
            try:
                tick = strategy.mt5.symbol_info_tick(strategy.symbol)
                if tick:
                    spread = tick.ask - tick.bid
            except Exception:
                pass

        # Session levels
        session_levels = LiveFeatureExtractor._get_session_levels(strategy)

        asian_range = 0.0
        pd_range = 0.0
        london_range = 0.0
        asian_high = session_levels.get('asian_high', 0)
        asian_low = session_levels.get('asian_low', 0)
        pd_high = session_levels.get('pd_high', 0)
        pd_low = session_levels.get('pd_low', 0)
        london_high = session_levels.get('london_high', 0)
        london_low = session_levels.get('london_low', 0)

        if asian_high and asian_low:
            asian_range = (asian_high - asian_low) / atr
        if pd_high and pd_low:
            pd_range = (pd_high - pd_low) / atr
        if london_high and london_low:
            london_range = (london_high - london_low) / atr

        # Daily context
        daily_pnl_pct = 0.0
        trades_today = 0.0
        if hasattr(strategy, 'risk_manager'):
            trades_today = float(getattr(strategy.risk_manager, 'daily_trades_count', 0))

        # HTF nearest level distance
        htf_dist = 0.0
        all_session_vals = [v for v in [asian_high, asian_low, pd_high, pd_low,
                                         london_high, london_low] if v and v > 0]
        if all_session_vals and entry_price > 0:
            distances = [abs(entry_price - lvl) / atr for lvl in all_session_vals]
            htf_dist = min(distances)

        # Confluence count
        confluence_count = 0.0
        all_levels = list(all_session_vals)
        round_50 = round(entry_price / 50) * 50
        all_levels.extend([round_50 - 50, round_50, round_50 + 50])
        for lvl in all_levels:
            if abs(entry_price - lvl) <= atr:
                confluence_count += 1.0

        # ADX
        adx_value = 0.0
        if hasattr(strategy, 'indicators') and df is not None and len(df) >= 28:
            try:
                adx_value = strategy.indicators.calculate_adx(df, 14)
            except Exception:
                pass

        # Hours to session close
        hours_to_close = max(0.0, 16.0 - hour)

        # Consecutive results (win/loss streak)
        consec = 0.0
        # Not easily available in live trading, leave as 0

        # Proximity to round number
        round_dist = 0.0
        if entry_price > 0 and atr > 0:
            nearest_round = round(entry_price / 50) * 50
            round_dist = abs(entry_price - nearest_round) / atr

        # Volatility regime
        volatility_regime = 50.0
        if df is not None and len(df) >= 60:
            try:
                atr_series = LiveFeatureExtractor._calculate_atr_series(df, 14)
                if len(atr_series.dropna()) >= 60:
                    current_atr = atr_series.iloc[-1]
                    percentile = (atr_series.iloc[-60:] < current_atr).sum() / 60 * 100
                    volatility_regime = float(percentile)
            except Exception:
                pass

        # Minutes since ORB (ORB-specific, default 0 for non-ORB strategies)
        mins_since_orb = 0.0
        if now and hour >= 9:
            mins_since_orb = max(0.0, (hour - 9) * 60 + float(now.minute) - 45)

        return MLFeatureVector(
            bias_direction=0.0,  # Strategy-specific, default neutral
            bias_strength=0.0,
            orb_range_atr=0.0,  # ORB-specific, 0 for non-ORB
            breakout_distance_atr=0.0,
            asian_range_atr=asian_range,
            pd_range_atr=pd_range,
            london_range_atr=london_range,
            fvg_size_atr=0.0,  # ICT-specific
            has_order_block=0.0,
            ob_body_percent=0.0,
            sl_distance_atr=sl_distance / atr if atr > 0 else 0.0,
            rr_ratio=rr_ratio,
            spread_atr=spread / atr if atr > 0 else 0.0,
            hour_of_day=hour,
            day_of_week=dow,
            minutes_since_orb=mins_since_orb,
            daily_pnl_pct=daily_pnl_pct,
            trades_today=trades_today,
            displacement_magnitude_atr=0.0,
            volatility_regime=volatility_regime,
            htf_nearest_level_distance_atr=htf_dist,
            confluence_count=confluence_count,
            adx_14=adx_value,
            hours_to_session_close=hours_to_close,
            consecutive_results=consec,
            proximity_to_round_number=round_dist,
            fvg_fill_ratio=0.0,
        )

    @staticmethod
    def _get_session_levels(strategy) -> dict:
        """Get session levels from strategy's session detector or data manager."""
        levels = {}

        if hasattr(strategy, 'session_detector'):
            try:
                from datetime import date
                levels = strategy.session_detector.get_session_levels(date.today())
            except Exception:
                pass

        return levels

    @staticmethod
    def _calculate_atr_series(df, period: int = 14):
        """Calculate ATR series from DataFrame."""
        high = df['high']
        low = df['low']
        close = df['close']
        prev_close = close.shift(1)
        tr = np.maximum(
            high - low,
            np.maximum(abs(high - prev_close), abs(low - prev_close))
        )
        return tr.rolling(window=period).mean()
