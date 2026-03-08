"""Mean Reversion Lens tool for the Trader's Workbench."""

from __future__ import annotations

from typing import Any, Dict, List

import numpy as np
import pandas as pd

from .tool_base import WorkbenchTool


STRICTNESS_DEV_MULTIPLIER: Dict[int, float] = {
    1: 0.80,  # loose
    2: 0.90,
    3: 1.00,  # normal
    4: 1.12,
    5: 1.25,  # strict
}


class MeanRevTool(WorkbenchTool):
    """Detect Bollinger overextensions and mean-cross flatten signals."""

    @property
    def tool_id(self) -> str:
        return "mean_rev"

    @property
    def display_name(self) -> str:
        return "Mean Reversion Lens"

    @property
    def icon(self) -> str:
        return "bi-arrow-left-right"

    @property
    def description(self) -> str:
        return "Detects Bollinger overextensions and mean-cross flatten signals."

    def get_default_config(self) -> Dict[str, Any]:
        return {
            "sma_period": 30,
            "deviation": 2.0,
            "strictness": 3,
            "show_exit_signals": True,
            "scan_scope": "last_n_days",
            "lookback_days": 2.0,
        }

    @staticmethod
    def _safe_int(value: Any, default: int) -> int:
        try:
            return int(value)
        except Exception:
            return int(default)

    @staticmethod
    def _safe_float(value: Any, default: float) -> float:
        try:
            return float(value)
        except Exception:
            return float(default)

    @staticmethod
    def _ts_unix(ts: Any) -> int:
        try:
            return int(pd.Timestamp(ts).timestamp())
        except Exception:
            return 0

    def _normalized_params(self, config: Dict[str, Any]) -> Dict[str, Any]:
        strictness = self.normalize_strictness(config.get("strictness"), 3)
        sma_period = max(5, min(400, self._safe_int(config.get("sma_period"), 30)))
        deviation = max(0.5, min(8.0, self._safe_float(config.get("deviation"), 2.0)))
        effective_deviation = float(deviation * STRICTNESS_DEV_MULTIPLIER.get(strictness, 1.0))
        show_exit_signals = bool(config.get("show_exit_signals", True))
        return {
            "strictness": int(strictness),
            "sma_period": int(sma_period),
            "deviation": float(deviation),
            "effective_deviation": float(effective_deviation),
            "show_exit_signals": bool(show_exit_signals),
        }

    def _compute_series(self, df: pd.DataFrame, config: Dict[str, Any]) -> Dict[str, Any]:
        p = self._normalized_params(config)
        closes = df["close"].astype(float)
        sma = closes.rolling(window=p["sma_period"], min_periods=p["sma_period"]).mean()
        std = closes.rolling(window=p["sma_period"], min_periods=p["sma_period"]).std()
        upper = sma + (std * p["effective_deviation"])
        lower = sma - (std * p["effective_deviation"])
        distance = closes - sma
        z = distance / std.replace(0.0, pd.NA)
        return {
            "params": p,
            "closes": closes,
            "sma": sma,
            "std": std,
            "upper": upper,
            "lower": lower,
            "distance": distance,
            "z": z,
        }

    def compute_current_state(self, df: pd.DataFrame, config: Dict[str, Any]) -> Dict[str, Any]:
        """Return latest z-score and band-location context for coach/copilot."""
        if df is None or df.empty or "close" not in df.columns:
            return {"state": "unknown", "reason": "no_data"}

        series = self._compute_series(df, config)
        p = series["params"]
        closes = series["closes"]
        sma = series["sma"]
        std = series["std"]
        upper = series["upper"]
        lower = series["lower"]
        distance = series["distance"]
        z = series["z"]

        valid_idx = z.last_valid_index()
        if valid_idx is None:
            return {
                "state": "unknown",
                "reason": "insufficient_bars",
                "sma_period": p["sma_period"],
                "deviation": p["deviation"],
                "effective_deviation": p["effective_deviation"],
                "strictness": p["strictness"],
            }

        z_values = pd.to_numeric(z, errors="coerce").to_numpy()
        valid_positions = np.flatnonzero(np.isfinite(z_values))
        if valid_positions.size <= 0:
            return {
                "state": "unknown",
                "reason": "insufficient_bars",
                "sma_period": p["sma_period"],
                "deviation": p["deviation"],
                "effective_deviation": p["effective_deviation"],
                "strictness": p["strictness"],
            }
        i = int(valid_positions[-1])
        close_val = self._safe_float(closes.iloc[i], 0.0)
        sma_val = self._safe_float(sma.iloc[i], 0.0)
        upper_val = self._safe_float(upper.iloc[i], 0.0)
        lower_val = self._safe_float(lower.iloc[i], 0.0)
        z_val = self._safe_float(z.iloc[i], 0.0)
        dist_val = self._safe_float(distance.iloc[i], 0.0)
        prev_dist = self._safe_float(distance.iloc[i - 1], 0.0) if i > 0 else 0.0
        mean_cross_recent = bool(i > 0 and (dist_val * prev_dist) < 0.0)

        state = "neutral"
        if close_val < lower_val:
            state = "buy_zone"
        elif close_val > upper_val:
            state = "sell_zone"

        return {
            "state": state,
            "z_score": round(z_val, 5),
            "distance": round(dist_val, 5),
            "close": round(close_val, 5),
            "sma_value": round(sma_val, 5),
            "upper_band": round(upper_val, 5),
            "lower_band": round(lower_val, 5),
            "in_buy_zone": bool(close_val < lower_val),
            "in_sell_zone": bool(close_val > upper_val),
            "above_mean": bool(close_val > sma_val),
            "mean_cross_recent": mean_cross_recent,
            "bar_index": i,
            "time_unix": self._ts_unix(valid_idx),
            "sma_period": p["sma_period"],
            "deviation": p["deviation"],
            "effective_deviation": p["effective_deviation"],
            "strictness": p["strictness"],
        }

    def scan(self, df: pd.DataFrame, config: Dict[str, Any]) -> List[Dict[str, Any]]:
        """
        Signal logic mirrors Experiments/MeanRevBacktester.py:
        - Entry signal when price breaches lower/upper Bollinger band.
        - Flatten signal when distance-to-mean changes sign.
        """
        if df is None or len(df) < 3:
            return []
        if "close" not in df.columns:
            return []

        series = self._compute_series(df, config)
        p = series["params"]
        closes = series["closes"]
        sma = series["sma"]
        std = series["std"]
        upper = series["upper"]
        lower = series["lower"]
        distance = series["distance"]
        z_score = series["z"]

        zones: List[Dict[str, Any]] = []
        position = 0  # +1 buy-side mean reversion, -1 sell-side mean reversion
        start_i = max(1, p["sma_period"])

        for i in range(start_i, len(df)):
            c = self._safe_float(closes.iloc[i], float("nan"))
            s = self._safe_float(sma.iloc[i], float("nan"))
            u = self._safe_float(upper.iloc[i], float("nan"))
            l = self._safe_float(lower.iloc[i], float("nan"))
            st = self._safe_float(std.iloc[i], float("nan"))
            d = self._safe_float(distance.iloc[i], float("nan"))
            d_prev = self._safe_float(distance.iloc[i - 1], float("nan")) if i > 0 else float("nan")
            z = self._safe_float(z_score.iloc[i], float("nan"))

            if not pd.notna(c) or not pd.notna(s) or not pd.notna(u) or not pd.notna(l) or not pd.notna(st):
                continue

            ts = df.index[i]
            prev_ts = df.index[i - 1] if i > 0 else ts
            start_unix = self._ts_unix(prev_ts)
            end_unix = self._ts_unix(ts)
            strength = abs(z) / max(1e-9, p["deviation"])

            # Match MeanRevBacktester precedence:
            # 1) lower breach => +1
            # 2) upper breach => -1
            # 3) mean-cross overrides to 0
            signal_pos: Any = np.nan
            signal_type: str = ""
            if c < l:
                signal_pos = 1
                signal_type = "buy_zone"
            if c > u:
                signal_pos = -1
                signal_type = "sell_zone"
            if pd.notna(d) and pd.notna(d_prev) and (d * d_prev) < 0.0:
                signal_pos = 0
                signal_type = "mean_cross"

            prev_position = int(position)
            if pd.isna(signal_pos):
                next_position = prev_position
            else:
                next_position = int(signal_pos)

            if signal_type in {"buy_zone", "sell_zone"} and next_position != prev_position:
                top = max(c, l) if signal_type == "buy_zone" else max(c, u)
                bottom = min(c, l) if signal_type == "buy_zone" else min(c, u)
                zones.append(
                    {
                        "type": signal_type,
                        "top": float(top),
                        "bottom": float(bottom),
                        "bar_index": int(i),
                        "start_time": pd.Timestamp(prev_ts).isoformat(),
                        "end_time": pd.Timestamp(ts).isoformat(),
                        "start_time_unix": int(start_unix),
                        "end_time_unix": int(end_unix),
                        "z_score": float(round(z, 5)),
                        "sma_value": float(round(s, 5)),
                        "upper_band": float(round(u, 5)),
                        "lower_band": float(round(l, 5)),
                        "distance": float(round(d, 5)),
                        "signal_strength": float(round(strength, 5)),
                        "gap_size": float(round(abs(top - bottom), 5)),
                        "original_gap_size": float(round(abs(top - bottom), 5)),
                        "current_gap_size": float(round(abs(top - bottom), 5)),
                    }
                )
            elif signal_type == "mean_cross" and p["show_exit_signals"] and prev_position != 0:
                zones.append(
                    {
                        "type": "mean_cross",
                        "top": float(round(s, 5)),
                        "bottom": float(round(s, 5)),
                        "bar_index": int(i),
                        "start_time": pd.Timestamp(ts).isoformat(),
                        "end_time": pd.Timestamp(ts).isoformat(),
                        "start_time_unix": int(end_unix),
                        "end_time_unix": int(end_unix),
                        "z_score": float(round(z, 5)),
                        "sma_value": float(round(s, 5)),
                        "upper_band": float(round(u, 5)),
                        "lower_band": float(round(l, 5)),
                        "distance": float(round(d, 5)),
                        "signal_strength": float(round(abs(z), 5)),
                        "gap_size": 0.0,
                        "original_gap_size": 0.0,
                        "current_gap_size": 0.0,
                    }
                )

            position = next_position

        return zones
