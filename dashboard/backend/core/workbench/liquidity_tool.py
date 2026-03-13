"""Liquidity detection tool for the Trader's Workbench."""

from __future__ import annotations

import math
from typing import Any, Dict, List, Optional

import pandas as pd

from .tool_base import WorkbenchTool
from .analysis_utils import detect_liquidity_zones, symbol_tick_size


def _symbol_tick_size(symbol: str) -> float:
    return symbol_tick_size(symbol)


class LiquidityTool(WorkbenchTool):
    """Detect equal-high/equal-low liquidity pools and sweep events."""

    @property
    def tool_id(self) -> str:
        return "liquidity"

    @property
    def display_name(self) -> str:
        return "Liquidity Detector"

    @property
    def icon(self) -> str:
        return "bi-bullseye"

    @property
    def description(self) -> str:
        return "Finds clustered equal highs/lows and stop-sweep rejection points."

    def get_default_config(self) -> Dict[str, Any]:
        return {
            "strictness": 3,
            "pivot_span": 3,
            "min_touches": 2,
            "lookback_bars": 420,
            "sweep_lookahead": 120,
            "tolerance_atr_mult": 0.12,
        }

    @staticmethod
    def _atr14(df: pd.DataFrame) -> Optional[float]:
        if df is None or df.empty:
            return None
        try:
            high = df["high"].astype(float)
            low = df["low"].astype(float)
            close = df["close"].astype(float)
        except Exception:
            return None
        prev_close = close.shift(1)
        tr = pd.concat(
            [
                (high - low).abs(),
                (high - prev_close).abs(),
                (low - prev_close).abs(),
            ],
            axis=1,
        ).max(axis=1)
        atr = tr.rolling(window=14, min_periods=5).mean()
        last = atr.dropna()
        if last.empty:
            return None
        out = float(last.iloc[-1])
        if not math.isfinite(out) or out <= 0:
            return None
        return out

    @staticmethod
    def _pivot_indices(values: List[float], span: int, *, is_high: bool) -> List[int]:
        out: List[int] = []
        n = len(values)
        s = max(1, int(span))
        if n < (2 * s + 1):
            return out
        for i in range(s, n - s):
            win = values[i - s : i + s + 1]
            v = float(values[i])
            if not math.isfinite(v):
                continue
            if is_high:
                if v >= max(win):
                    out.append(i)
            else:
                if v <= min(win):
                    out.append(i)
        return out

    @staticmethod
    def _cluster_by_tolerance(
        values: List[float],
        indices: List[int],
        tolerance: float,
        min_touches: int,
    ) -> List[Dict[str, Any]]:
        if not values or not indices:
            return []
        tol = max(0.0, float(tolerance))
        touched: List[Dict[str, Any]] = []
        sorted_ix = sorted(indices, key=lambda i: float(values[i]))
        for idx in sorted_ix:
            price = float(values[idx])
            placed = False
            for row in touched:
                ref = float(row["ref_price"])
                if abs(price - ref) <= tol:
                    row["indices"].append(int(idx))
                    row["prices"].append(price)
                    row["ref_price"] = float(sum(row["prices"]) / len(row["prices"]))
                    placed = True
                    break
            if not placed:
                touched.append({"ref_price": price, "indices": [int(idx)], "prices": [price]})
        out: List[Dict[str, Any]] = []
        for row in touched:
            ix = sorted(set(int(i) for i in row["indices"]))
            if len(ix) < int(min_touches):
                continue
            prices = [float(values[i]) for i in ix]
            out.append(
                {
                    "ref_price": float(sum(prices) / len(prices)),
                    "indices": ix,
                    "prices": prices,
                    "touches": len(ix),
                    "price_min": min(prices),
                    "price_max": max(prices),
                }
            )
        return out

    def scan(self, df: pd.DataFrame, config: Dict[str, Any]) -> List[Dict[str, Any]]:
        return detect_liquidity_zones(df=df, config=config)

    def compute_current_state(self, df: pd.DataFrame, config: Dict[str, Any]) -> Dict[str, Any]:
        zones = self.scan(df, config)
        if not zones:
            return {"state": "no_liquidity_structure", "zones_count": 0}
        pools = [z for z in zones if str(z.get("type") or "").startswith("liquidity_pool_")]
        sweeps = [z for z in zones if str(z.get("type") or "").startswith("liquidity_sweep_")]
        try:
            px = float(df["close"].astype(float).iloc[-1])
        except Exception:
            px = None
        nearest: Optional[Dict[str, Any]] = None
        if px is not None and math.isfinite(px) and pools:
            def _dist(z: Dict[str, Any]) -> float:
                level = float(z.get("liquidity_level") or 0.0)
                return abs(level - px)
            nearest = sorted(pools, key=_dist)[0]
        return {
            "state": "liquidity_map_ready",
            "zones_count": int(len(zones)),
            "pools_count": int(len(pools)),
            "sweeps_count": int(len(sweeps)),
            "current_price": float(px) if px is not None and math.isfinite(px) else None,
            "nearest_pool_type": str(nearest.get("type")) if isinstance(nearest, dict) else None,
            "nearest_pool_level": float(nearest.get("liquidity_level")) if isinstance(nearest, dict) else None,
            "latest_sweep_type": str(sweeps[-1].get("type")) if sweeps else None,
        }
