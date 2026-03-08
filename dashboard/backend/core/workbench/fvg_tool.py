"""FVG (Fair Value Gap) detection tool for the Trader's Workbench."""

import re
import math
from typing import Any, Dict, List
import pandas as pd

from .tool_base import WorkbenchTool

# Per-instrument minimum gap size defaults (from production strategies)
INSTRUMENT_MIN_GAP: Dict[str, float] = {
    "XAUUSD": 0.15,
    "NAS100": 1.0,
    "US500": 1.0,
    "GBPUSD": 0.0001,
    "EURUSD": 0.0001,
}

DEFAULT_MIN_GAP = 0.15
STRICTNESS_GAP_MULTIPLIER: Dict[int, float] = {
    1: 0.70,  # loose
    2: 0.85,
    3: 1.00,  # balanced
    4: 1.20,
    5: 1.45,  # strict
}


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

        symbol = config.get("symbol", "XAUUSD")
        min_gap = config.get("min_gap")
        if min_gap is None:
            min_gap = INSTRUMENT_MIN_GAP.get(symbol, DEFAULT_MIN_GAP)
        strictness = self.normalize_strictness(config.get("strictness"), 3)
        min_gap = float(min_gap) * float(STRICTNESS_GAP_MULTIPLIER.get(strictness, 1.0))

        show_filled = config.get("show_filled", False)
        trend_filter_enabled = bool(config.get("trend_filter_enabled", True))
        trend_alignment_mode = str(config.get("trend_alignment_mode") or "prefer").strip().lower()
        if trend_alignment_mode not in {"prefer", "strict"}:
            trend_alignment_mode = "prefer"
        precomputed_trend = config.get("_trend_context")
        if isinstance(precomputed_trend, dict):
            trend_ctx = precomputed_trend
        else:
            trend_ctx = self.compute_trend_context(df=df, config=config)
        trend_direction = str(trend_ctx.get("direction") or "unknown").strip().lower()

        n = len(df)
        zones_active_bull: List[Dict[str, Any]] = []
        zones_active_bear: List[Dict[str, Any]] = []
        zones_filled: List[Dict[str, Any]] = []

        def _refresh_current_gap_size(zone: Dict[str, Any]) -> None:
            top = float(zone.get("top") or 0.0)
            bottom = float(zone.get("bottom") or 0.0)
            zone["current_gap_size"] = round(max(0.0, abs(top - bottom)), 5)

        def _normalize_zone_bounds(zone: Dict[str, Any]) -> None:
            """Clamp zone bounds to physically valid FVG geometry."""
            z_type = str(zone.get("type") or "").lower()
            top = float(zone.get("top") or 0.0)
            bottom = float(zone.get("bottom") or 0.0)
            origin_top = float(zone.get("origin_top") if zone.get("origin_top") is not None else top)
            origin_bottom = float(zone.get("origin_bottom") if zone.get("origin_bottom") is not None else bottom)
            filled = bool(zone.get("filled", False))

            if not (math.isfinite(top) and math.isfinite(bottom)):
                return

            if z_type == "bullish_fvg":
                # Bullish geometry: bottom is anchored to c1.high, top can only move downward with mitigation.
                bottom = origin_bottom
                top = min(top, origin_top)
                top = max(top, bottom)
                if filled:
                    top = bottom
            elif z_type == "bearish_fvg":
                # Bearish geometry: top is anchored to c1.low, bottom can only move upward with mitigation.
                top = origin_top
                bottom = max(bottom, origin_bottom)
                bottom = min(bottom, top)
                if filled:
                    bottom = top
            else:
                hi = max(top, bottom)
                lo = min(top, bottom)
                top, bottom = hi, lo
                if filled:
                    top = bottom

            zone["top"] = float(top)
            zone["bottom"] = float(bottom)
            _refresh_current_gap_size(zone)

        for i in range(2, n):
            c1 = df.iloc[i - 2]  # First candle
            c3 = df.iloc[i]      # Third candle
            ts = df.index[i]
            ts_unix = int(ts.timestamp()) if hasattr(ts, "timestamp") else 0

            # 1) Update existing zones with this candle first.
            # Bullish FVG:
            # - if candle low <= bottom => fully filled/cancelled
            # - if bottom < candle low < top => partial mitigation, top moves down to candle low
            if zones_active_bull:
                next_bull: List[Dict[str, Any]] = []
                low_i = float(c3["low"])
                for z in zones_active_bull:
                    z_bottom = float(z["bottom"])
                    z_top = float(z["top"])
                    if low_i <= z_bottom:
                        z["filled"] = True
                        z["current_gap_size"] = 0.0
                        z["filled_at_unix"] = ts_unix
                        _normalize_zone_bounds(z)
                        if show_filled:
                            zones_filled.append(z)
                        continue
                    if z_bottom < low_i < z_top:
                        z["top"] = float(low_i)
                        z["mitigations"] = int(z.get("mitigations", 0)) + 1
                        z["last_mitigated_unix"] = ts_unix
                        _normalize_zone_bounds(z)
                    next_bull.append(z)
                zones_active_bull = next_bull

            # Bearish FVG:
            # - if candle high >= top => fully filled/cancelled
            # - if bottom < candle high < top => partial mitigation, bottom moves up to candle high
            if zones_active_bear:
                next_bear: List[Dict[str, Any]] = []
                high_i = float(c3["high"])
                for z in zones_active_bear:
                    z_bottom = float(z["bottom"])
                    z_top = float(z["top"])
                    if high_i >= z_top:
                        z["filled"] = True
                        z["current_gap_size"] = 0.0
                        z["filled_at_unix"] = ts_unix
                        _normalize_zone_bounds(z)
                        if show_filled:
                            zones_filled.append(z)
                        continue
                    if z_bottom < high_i < z_top:
                        z["bottom"] = float(high_i)
                        z["mitigations"] = int(z.get("mitigations", 0)) + 1
                        z["last_mitigated_unix"] = ts_unix
                        _normalize_zone_bounds(z)
                    next_bear.append(z)
                zones_active_bear = next_bear

            # --- Bullish FVG: candle3.low > candle1.high ---
            bull_gap = c3["low"] - c1["high"]
            if bull_gap > min_gap:
                start_ts = df.index[i - 2]
                end_ts = df.index[i]
                zones_active_bull.append({
                    "type": "bullish_fvg",
                    "top": float(c3["low"]),
                    "bottom": float(c1["high"]),
                    "origin_top": float(c3["low"]),
                    "origin_bottom": float(c1["high"]),
                    "start_time": str(start_ts),
                    "end_time": str(end_ts),
                    "start_time_unix": int(start_ts.timestamp()) if hasattr(start_ts, "timestamp") else 0,
                    "end_time_unix": int(end_ts.timestamp()) if hasattr(end_ts, "timestamp") else 0,
                    "bar_index": i,
                    "original_gap_size": round(bull_gap, 5),
                    "current_gap_size": round(bull_gap, 5),
                    "gap_size": round(bull_gap, 5),
                    "mitigations": 0,
                    "filled": False,
                })

            # --- Bearish FVG: candle1.low > candle3.high ---
            bear_gap = c1["low"] - c3["high"]
            if bear_gap > min_gap:
                start_ts = df.index[i - 2]
                end_ts = df.index[i]
                zones_active_bear.append({
                    "type": "bearish_fvg",
                    "top": float(c1["low"]),
                    "bottom": float(c3["high"]),
                    "origin_top": float(c1["low"]),
                    "origin_bottom": float(c3["high"]),
                    "start_time": str(start_ts),
                    "end_time": str(end_ts),
                    "start_time_unix": int(start_ts.timestamp()) if hasattr(start_ts, "timestamp") else 0,
                    "end_time_unix": int(end_ts.timestamp()) if hasattr(end_ts, "timestamp") else 0,
                    "bar_index": i,
                    "original_gap_size": round(bear_gap, 5),
                    "current_gap_size": round(bear_gap, 5),
                    "gap_size": round(bear_gap, 5),
                    "mitigations": 0,
                    "filled": False,
                })

        zones: List[Dict[str, Any]] = [*zones_active_bull, *zones_active_bear]
        if show_filled and zones_filled:
            zones.extend(zones_filled)

        for z in zones:
            _normalize_zone_bounds(z)
            ztype = str(z.get("type") or "")
            aligned = (
                (trend_direction == "bullish" and ztype == "bullish_fvg")
                or (trend_direction == "bearish" and ztype == "bearish_fvg")
            )
            z["trend_direction"] = trend_direction
            z["trend_timeframe"] = str(trend_ctx.get("trend_timeframe") or "")
            z["trend_base_timeframe"] = str(trend_ctx.get("base_timeframe") or "")
            z["trend_aligned"] = bool(aligned)

        if trend_filter_enabled:
            if trend_direction == "bullish":
                zones = [z for z in zones if str(z.get("type") or "") == "bullish_fvg"]
            elif trend_direction == "bearish":
                zones = [z for z in zones if str(z.get("type") or "") == "bearish_fvg"]
            elif trend_alignment_mode == "strict":
                zones = []

        zones.sort(key=lambda z: int(z.get("bar_index") or 0))
        return zones
