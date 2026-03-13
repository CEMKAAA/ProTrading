"""FVG (Fair Value Gap) detection tool for the Trader's Workbench."""

import re
from typing import Any, Dict, List
import pandas as pd

from .tool_base import WorkbenchTool
from .analysis_utils import (
    DEFAULT_MIN_GAP,
    INSTRUMENT_MIN_GAP,
    STRICTNESS_GAP_MULTIPLIER,
    detect_fvg_zones,
    instrument_min_gap,
)


class FVGTool(WorkbenchTool):
    """Detects 3-candle Fair Value Gap (imbalance) patterns."""

    @property
    def tool_id(self) -> str:
        return "fvg"

    @property
    def display_name(self) -> str:
        return "Fair Value Gap"

    @property
    def icon(self) -> str:
        return "bi-layers-half"

    @property
    def description(self) -> str:
        return "Finds 3-candle imbalance gaps where institutions left unfilled orders."

    def get_default_config(self) -> Dict[str, Any]:
        return {
            "min_gap": None,  # None = auto-detect from symbol
            "show_filled": False,
            "strictness": 3,
            "trend_filter_enabled": True,
            "trend_multiplier": 3,
            "trend_alignment_mode": "prefer",  # prefer | strict
            "timeframe": "M5",
        }

    @staticmethod
    def _timeframe_to_minutes(timeframe: Any, default_minutes: int = 5) -> int:
        try:
            s = str(timeframe or "").strip().upper()
            if not s:
                return int(default_minutes)
            if s.isdigit():
                return max(1, int(s))
            m = re.match(r"^M(\d+)$", s)
            if m:
                return max(1, int(m.group(1)))
            h = re.match(r"^H(\d+)$", s)
            if h:
                return max(1, int(h.group(1)) * 60)
            if s in {"D", "D1", "1D"}:
                return 1440
            m2 = re.match(r"^(\d+)\s*MIN$", s)
            if m2:
                return max(1, int(m2.group(1)))
            h2 = re.match(r"^(\d+)\s*H$", s)
            if h2:
                return max(1, int(h2.group(1)) * 60)
        except Exception:
            return int(default_minutes)
        return int(default_minutes)

    @staticmethod
    def _minutes_to_label(minutes: int) -> str:
        m = max(1, int(minutes))
        if m % 1440 == 0:
            d = m // 1440
            return f"D{d}" if d > 1 else "D1"
        if m % 60 == 0:
            h = m // 60
            return f"H{h}"
        return f"M{m}"

    def compute_trend_context(self, df: pd.DataFrame, config: Dict[str, Any]) -> Dict[str, Any]:
        """Compute higher-timeframe trend context used for FVG direction filtering."""
        base_tf = str(config.get("timeframe") or "M5").upper()
        base_minutes = self._timeframe_to_minutes(base_tf, default_minutes=5)
        try:
            multiplier = int(config.get("trend_multiplier") or 3)
        except Exception:
            multiplier = 3
        multiplier = max(2, min(12, int(multiplier)))
        trend_tf_raw = config.get("trend_timeframe")
        trend_minutes = self._timeframe_to_minutes(trend_tf_raw, default_minutes=base_minutes * multiplier) if trend_tf_raw else (base_minutes * multiplier)
        if trend_minutes <= base_minutes:
            trend_minutes = base_minutes * max(2, multiplier)

        trend_tf_label = self._minutes_to_label(trend_minutes)
        base_tf_label = self._minutes_to_label(base_minutes)
        if df is None or df.empty or "close" not in df.columns:
            return {
                "direction": "unknown",
                "base_timeframe": base_tf_label,
                "trend_timeframe": trend_tf_label,
                "method": "ema_20_50_htf",
            }

        use_df = df[["open", "high", "low", "close", "volume"]].copy()
        try:
            if trend_minutes > base_minutes:
                rule = f"{int(trend_minutes)}min"
                htf = use_df.resample(rule).agg(
                    {
                        "open": "first",
                        "high": "max",
                        "low": "min",
                        "close": "last",
                        "volume": "sum",
                    }
                ).dropna(subset=["open", "high", "low", "close"])
            else:
                htf = use_df
        except Exception:
            htf = use_df

        # Fallback if HTF compression leaves too few points.
        if len(htf) < 55:
            htf = use_df
            trend_tf_label = base_tf_label

        close = htf["close"].astype(float)
        ema_fast = close.ewm(span=20, adjust=False).mean()
        ema_slow = close.ewm(span=50, adjust=False).mean()
        if len(ema_fast) < 5 or len(ema_slow) < 5:
            return {
                "direction": "unknown",
                "base_timeframe": base_tf_label,
                "trend_timeframe": trend_tf_label,
                "method": "ema_20_50_htf",
            }

        fast_now = float(ema_fast.iloc[-1])
        slow_now = float(ema_slow.iloc[-1])
        close_now = float(close.iloc[-1]) if len(close) else 0.0
        fast_prev = float(ema_fast.iloc[-3]) if len(ema_fast) >= 3 else fast_now
        slope = fast_now - fast_prev
        slope_pct = (slope / close_now * 100.0) if abs(close_now) > 1e-9 else 0.0

        direction = "neutral"
        if fast_now > slow_now and slope_pct >= 0.0:
            direction = "bullish"
        elif fast_now < slow_now and slope_pct <= 0.0:
            direction = "bearish"

        strength_pct = abs(fast_now - slow_now) / max(abs(close_now), 1e-9) * 100.0
        return {
            "direction": direction,
            "strength_pct": round(float(strength_pct), 5),
            "slope_pct": round(float(slope_pct), 5),
            "base_timeframe": base_tf_label,
            "trend_timeframe": trend_tf_label,
            "method": "ema_20_50_htf",
        }

    def compute_movement_strength(
        self,
        df: pd.DataFrame,
        config: Dict[str, Any],
        trend_ctx: Dict[str, Any] | None = None,
    ) -> Dict[str, Any]:
        """
        Score directional impulse strength from FVG retention:
        - Same-direction FVGs that remain unfilled -> stronger impulse.
        - Same-direction FVGs that get mitigated/filled -> weakening impulse ("gas running out").
        """
        if df is None or len(df) < 3:
            return {
                "score": 0.0,
                "state": "insufficient_data",
                "direction": "unknown",
                "same_direction_zones": 0,
                "active_count": 0,
                "partially_mitigated_count": 0,
                "filled_count": 0,
                "gas_low": True,
                "explanation": "Not enough bars to compute movement strength.",
            }

        base_cfg = dict(config or {})
        if not isinstance(trend_ctx, dict):
            trend_ctx = base_cfg.get("_trend_context") if isinstance(base_cfg.get("_trend_context"), dict) else self.compute_trend_context(df=df, config=base_cfg)
        trend_direction = str(trend_ctx.get("direction") or "").strip().lower()

        strength_cfg = dict(base_cfg)
        strength_cfg["show_filled"] = True
        strength_cfg["trend_filter_enabled"] = False  # strength uses full zone history, then filters by direction explicitly
        zones_all = self.scan(df=df, config=strength_cfg)
        if not isinstance(zones_all, list):
            zones_all = []

        if trend_direction not in {"bullish", "bearish"}:
            bull_count = sum(1 for z in zones_all if str(z.get("type") or "") == "bullish_fvg")
            bear_count = sum(1 for z in zones_all if str(z.get("type") or "") == "bearish_fvg")
            if bull_count > bear_count:
                trend_direction = "bullish"
            elif bear_count > bull_count:
                trend_direction = "bearish"
            else:
                trend_direction = "unknown"

        if trend_direction == "bullish":
            same = [z for z in zones_all if str(z.get("type") or "") == "bullish_fvg"]
        elif trend_direction == "bearish":
            same = [z for z in zones_all if str(z.get("type") or "") == "bearish_fvg"]
        else:
            same = []

        if not same:
            return {
                "score": 25.0 if trend_direction in {"bullish", "bearish"} else 50.0,
                "state": "no_impulse",
                "direction": trend_direction or "unknown",
                "same_direction_zones": 0,
                "active_count": 0,
                "partially_mitigated_count": 0,
                "filled_count": 0,
                "gas_low": True,
                "explanation": "No same-direction FVG zones available for impulse scoring.",
            }

        latest_bar_index = max(int(z.get("bar_index") or 0) for z in same)
        weighted_support = 0.0
        weighted_exhaustion = 0.0
        weighted_total = 0.0
        active_count = 0
        partial_count = 0
        filled_count = 0

        for z in same:
            top = float(z.get("top") or 0.0)
            bottom = float(z.get("bottom") or 0.0)
            original_gap = float(z.get("original_gap_size") or z.get("gap_size") or abs(top - bottom))
            if original_gap <= 1e-9:
                continue
            current_gap = float(z.get("current_gap_size") if z.get("current_gap_size") is not None else z.get("gap_size") or abs(top - bottom))
            if bool(z.get("filled", False)):
                current_gap = 0.0
            remain_ratio = max(0.0, min(1.0, current_gap / original_gap))
            fill_ratio = 1.0 - remain_ratio
            mitigations = int(z.get("mitigations") or 0)
            if current_gap <= 1e-9 or bool(z.get("filled", False)):
                filled_count += 1
            elif mitigations > 0:
                partial_count += 1
                active_count += 1
            else:
                active_count += 1

            age = max(0, latest_bar_index - int(z.get("bar_index") or 0))
            recency_weight = 1.0 / (1.0 + (age / 20.0))
            weighted_support += recency_weight * remain_ratio
            weighted_exhaustion += recency_weight * fill_ratio
            weighted_total += recency_weight

        if weighted_total <= 1e-9:
            return {
                "score": 0.0,
                "state": "insufficient_data",
                "direction": trend_direction,
                "same_direction_zones": int(len(same)),
                "active_count": active_count,
                "partially_mitigated_count": partial_count,
                "filled_count": filled_count,
                "gas_low": True,
                "explanation": "Zone weights are not sufficient for scoring.",
            }

        retention = max(0.0, min(1.0, weighted_support / weighted_total))
        sample_factor = max(0.25, min(1.0, float(len(same)) / 4.0))
        score = float(100.0 * retention * (0.6 + 0.4 * sample_factor))
        if weighted_exhaustion > weighted_support:
            score *= 0.85
        score = max(0.0, min(100.0, score))

        if score >= 75.0:
            state = "strong"
        elif score >= 55.0:
            state = "steady"
        elif score >= 35.0:
            state = "weakening"
        else:
            state = "exhausted"

        gas_low = bool(score < 35.0 or (filled_count >= max(1, active_count) and len(same) >= 2))
        return {
            "score": round(score, 2),
            "state": state,
            "direction": trend_direction,
            "same_direction_zones": int(len(same)),
            "active_count": int(active_count),
            "partially_mitigated_count": int(partial_count),
            "filled_count": int(filled_count),
            "retention_ratio": round(retention, 5),
            "gas_low": gas_low,
            "explanation": (
                "Higher score means same-direction FVGs stay unfilled (impulse intact); "
                "lower score means more mitigated/filled zones (impulse losing gas)."
            ),
        }

    def scan(self, df: pd.DataFrame, config: Dict[str, Any]) -> List[Dict[str, Any]]:
        """Scan all visible bars for FVG patterns (both bullish and bearish)."""
        if df is None or len(df) < 3:
            return []

        precomputed_trend = config.get("_trend_context")
        if isinstance(precomputed_trend, dict):
            trend_ctx = precomputed_trend
        else:
            trend_ctx = self.compute_trend_context(df=df, config=config)
        scan_cfg = dict(config or {})
        scan_cfg["_trend_context"] = trend_ctx
        scan_cfg["trend_direction"] = str(trend_ctx.get("direction") or "unknown").strip().lower()
        return detect_fvg_zones(df=df, config=scan_cfg)
