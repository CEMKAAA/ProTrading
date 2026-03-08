"""Liquidity detection tool for the Trader's Workbench."""

from __future__ import annotations

import math
from typing import Any, Dict, List, Optional

import pandas as pd

from .tool_base import WorkbenchTool


STRICTNESS_TOLERANCE_MULTIPLIER: Dict[int, float] = {
    1: 1.50,
    2: 1.25,
    3: 1.00,
    4: 0.80,
    5: 0.65,
}


def _safe_int(value: Any, default: int) -> int:
    try:
        return int(value)
    except Exception:
        return int(default)


def _safe_float(value: Any, default: float) -> float:
    try:
        return float(value)
    except Exception:
        return float(default)


def _symbol_tick_size(symbol: str) -> float:
    s = str(symbol or "").upper()
    if s in {"XAUUSD"}:
        return 0.05
    if s in {"US500", "NAS100"}:
        return 0.25
    if s.endswith("USD") and (s.startswith("EUR") or s.startswith("GBP")):
        return 0.0001
    return 0.01


def _ts_iso(ts: Any) -> str:
    try:
        return pd.Timestamp(ts).isoformat()
    except Exception:
        return ""


def _ts_unix(ts: Any) -> int:
    try:
        return int(pd.Timestamp(ts).timestamp())
    except Exception:
        return 0


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
        if df is None or len(df) < 20:
            return []
        if not {"open", "high", "low", "close"}.issubset(set(df.columns)):
            return []

        strictness = self.normalize_strictness(config.get("strictness"), 3)
        lookback_bars = max(30, min(5000, _safe_int(config.get("lookback_bars"), 420)))
        work = df.tail(lookback_bars).copy()
        highs = [float(x) for x in work["high"].astype(float).tolist()]
        lows = [float(x) for x in work["low"].astype(float).tolist()]
        closes = [float(x) for x in work["close"].astype(float).tolist()]
        index_vals = list(work.index)
        n = len(work)
        if n < 20:
            return []

        pivot_span_default = 2 + (strictness // 2)
        pivot_span = max(1, min(12, _safe_int(config.get("pivot_span"), pivot_span_default)))
        min_touches = max(2, min(6, _safe_int(config.get("min_touches"), 2)))
        sweep_lookahead = max(5, min(500, _safe_int(config.get("sweep_lookahead"), 120)))
        atr_mult = max(0.02, min(2.0, _safe_float(config.get("tolerance_atr_mult"), 0.12)))
        atr = self._atr14(work)
        tick = _symbol_tick_size(str(config.get("symbol") or ""))
        tol = max(float(tick), float((atr or tick) * atr_mult * STRICTNESS_TOLERANCE_MULTIPLIER.get(strictness, 1.0)))

        high_pivots = self._pivot_indices(highs, pivot_span, is_high=True)
        low_pivots = self._pivot_indices(lows, pivot_span, is_high=False)

        high_clusters = self._cluster_by_tolerance(highs, high_pivots, tol, min_touches)
        low_clusters = self._cluster_by_tolerance(lows, low_pivots, tol, min_touches)

        zones: List[Dict[str, Any]] = []

        def _append_pool(cluster: Dict[str, Any], *, is_high: bool) -> None:
            idx_min = int(min(cluster["indices"]))
            idx_max = int(max(cluster["indices"]))
            ref = float(cluster["ref_price"])
            z_top = float(cluster["price_max"] + tol * 0.35)
            z_bottom = float(cluster["price_min"] - tol * 0.35)
            ztype = "liquidity_pool_high" if is_high else "liquidity_pool_low"
            zones.append(
                {
                    "type": ztype,
                    "top": z_top,
                    "bottom": z_bottom,
                    "liquidity_level": ref,
                    "touches": int(cluster["touches"]),
                    "bar_index": int(idx_max),
                    "start_time": _ts_iso(index_vals[idx_min]),
                    "end_time": _ts_iso(index_vals[idx_max]),
                    "start_time_unix": _ts_unix(index_vals[idx_min]),
                    "end_time_unix": _ts_unix(index_vals[idx_max]),
                    "filled": False,
                }
            )

            sweep_end = min(n, idx_max + 1 + sweep_lookahead)
            sweep_idx = None
            sweep_price = None
            if is_high:
                for j in range(idx_max + 1, sweep_end):
                    if highs[j] > z_top and closes[j] < ref:
                        sweep_idx = j
                        sweep_price = highs[j]
                        break
            else:
                for j in range(idx_max + 1, sweep_end):
                    if lows[j] < z_bottom and closes[j] > ref:
                        sweep_idx = j
                        sweep_price = lows[j]
                        break
            if sweep_idx is None:
                return
            zones.append(
                {
                    "type": "liquidity_sweep_high" if is_high else "liquidity_sweep_low",
                    "top": float(max(ref, float(sweep_price or ref))),
                    "bottom": float(min(ref, float(sweep_price or ref))),
                    "liquidity_level": ref,
                    "swept_price": float(sweep_price or ref),
                    "swept_pool_touches": int(cluster["touches"]),
                    "bar_index": int(sweep_idx),
                    "start_time": _ts_iso(index_vals[idx_max]),
                    "end_time": _ts_iso(index_vals[sweep_idx]),
                    "start_time_unix": _ts_unix(index_vals[idx_max]),
                    "end_time_unix": _ts_unix(index_vals[sweep_idx]),
                    "filled": False,
                }
            )

        for row in high_clusters:
            _append_pool(row, is_high=True)
        for row in low_clusters:
            _append_pool(row, is_high=False)

        zones.sort(key=lambda z: int(z.get("end_time_unix") or 0))
        return zones[-200:]

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
