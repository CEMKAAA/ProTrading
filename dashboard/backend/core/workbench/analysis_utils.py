"""Shared FVG and liquidity analysis helpers.

These helpers are used by both Workbench tools and backtest strategies so
signal geometry stays consistent across planner, chart tools, and simulation.
"""

from __future__ import annotations

import math
import re
from typing import Any, Dict, List, Optional

import pandas as pd

from .symbol_utils import normalize_strategy_symbol


INSTRUMENT_MIN_GAP: Dict[str, float] = {
    "XAUUSD": 0.15,
    "NAS100": 1.0,
    "US500": 1.0,
    "GBPUSD": 0.0001,
    "EURUSD": 0.0001,
}

DEFAULT_MIN_GAP = 0.15

STRICTNESS_GAP_MULTIPLIER: Dict[int, float] = {
    1: 0.70,
    2: 0.85,
    3: 1.00,
    4: 1.20,
    5: 1.45,
}

STRICTNESS_TOLERANCE_MULTIPLIER: Dict[int, float] = {
    1: 1.50,
    2: 1.25,
    3: 1.00,
    4: 0.80,
    5: 0.65,
}


def normalize_strictness(value: Any, default: int = 3) -> int:
    try:
        out = int(value)
    except Exception:
        out = int(default)
    return max(1, min(5, out))


def safe_int(value: Any, default: int) -> int:
    try:
        return int(value)
    except Exception:
        return int(default)


def safe_float(value: Any, default: float) -> float:
    try:
        out = float(value)
    except Exception:
        return float(default)
    if not math.isfinite(out):
        return float(default)
    return float(out)


def timeframe_to_minutes(timeframe: Any, default_minutes: int = 5) -> int:
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


def resample_ohlcv(df: pd.DataFrame, rule: str) -> pd.DataFrame:
    if df is None or df.empty:
        return pd.DataFrame(columns=["open", "high", "low", "close", "volume"])
    use_df = df.copy()
    if "volume" not in use_df.columns:
        use_df["volume"] = 0.0
    out = (
        use_df[["open", "high", "low", "close", "volume"]]
        .resample(rule)
        .agg(
            {
                "open": "first",
                "high": "max",
                "low": "min",
                "close": "last",
                "volume": "sum",
            }
        )
        .dropna(subset=["open", "high", "low", "close"])
    )
    return out


def atr_series(df: pd.DataFrame, period: int = 14) -> pd.Series:
    if df is None or df.empty or not {"high", "low", "close"}.issubset(df.columns):
        return pd.Series(dtype=float)
    high = df["high"].astype(float)
    low = df["low"].astype(float)
    close = df["close"].astype(float)
    prev_close = close.shift(1)
    tr = pd.concat(
        [
            (high - low).abs(),
            (high - prev_close).abs(),
            (low - prev_close).abs(),
        ],
        axis=1,
    ).max(axis=1)
    return tr.rolling(window=max(2, int(period)), min_periods=max(2, int(period // 2))).mean()


def atr_last(df: pd.DataFrame, period: int = 14) -> Optional[float]:
    atr = atr_series(df, period)
    last = atr.dropna()
    if last.empty:
        return None
    out = float(last.iloc[-1])
    if not math.isfinite(out) or out <= 0:
        return None
    return out


def instrument_min_gap(symbol: Any) -> float:
    raw_symbol = str(symbol or "")
    base = normalize_strategy_symbol(raw_symbol) or raw_symbol.strip().upper() or "XAUUSD"
    return float(INSTRUMENT_MIN_GAP.get(base, DEFAULT_MIN_GAP))


def symbol_tick_size(symbol: Any) -> float:
    s = normalize_strategy_symbol(symbol)
    if s in {"XAUUSD"}:
        return 0.05
    if s in {"US500", "NAS100"}:
        return 0.25
    if s.endswith("USD") and (s.startswith("EUR") or s.startswith("GBP")):
        return 0.0001
    return 0.01


def ts_iso(ts: Any) -> str:
    try:
        return pd.Timestamp(ts).isoformat()
    except Exception:
        return ""


def ts_unix(ts: Any) -> int:
    try:
        return int(pd.Timestamp(ts).timestamp())
    except Exception:
        return 0


def evaluate_sweep_rejection(
    *,
    pool_boundary: float,
    swept_price: float,
    bar_high: float,
    bar_low: float,
    atr: Optional[float] = None,
) -> Dict[str, Any]:
    pool_boundary_f = float(pool_boundary)
    swept_price_f = float(swept_price)
    bar_high_f = float(bar_high)
    bar_low_f = float(bar_low)
    bar_range = max(1e-12, bar_high_f - bar_low_f)
    # Clamp bar_range so high-volatility bars (news spikes) don't
    # suppress the rejection ratio.  A $2 wick on a $20 NFP candle is
    # still a legitimate sweep — cap range at 2×ATR.
    if atr is not None and float(atr) > 0:
        bar_range = min(bar_range, float(atr) * 2.0)
    wick_beyond = abs(swept_price_f - pool_boundary_f)
    rejection_ratio = float(max(0.0, min(1.0, wick_beyond / bar_range)))
    if rejection_ratio > 0.60:
        quality = "strong"
    elif rejection_ratio > 0.30:
        quality = "moderate"
    else:
        quality = "weak"
    return {
        "pool_boundary": pool_boundary_f,
        "swept_price": swept_price_f,
        "bar_range": float(bar_range),
        "wick_beyond": float(wick_beyond),
        "rejection_ratio": rejection_ratio,
        "rejection_quality": quality,
    }


def _normalize_fvg_zone_bounds(zone: Dict[str, Any]) -> None:
    z_type = str(zone.get("type") or "").lower()
    top = float(zone.get("top") or 0.0)
    bottom = float(zone.get("bottom") or 0.0)
    origin_top = float(zone.get("origin_top") if zone.get("origin_top") is not None else top)
    origin_bottom = float(zone.get("origin_bottom") if zone.get("origin_bottom") is not None else bottom)
    filled = bool(zone.get("filled", False))

    if not (math.isfinite(top) and math.isfinite(bottom)):
        return

    if z_type == "bullish_fvg":
        bottom = origin_bottom
        top = min(top, origin_top)
        top = max(top, bottom)
        if filled:
            top = bottom
    elif z_type == "bearish_fvg":
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
    zone["current_gap_size"] = round(max(0.0, abs(top - bottom)), 5)


def detect_fvg_zones(df: pd.DataFrame, config: Dict[str, Any]) -> List[Dict[str, Any]]:
    if df is None or len(df) < 3:
        return []

    raw_symbol = str(config.get("symbol") or "XAUUSD")
    symbol = normalize_strategy_symbol(raw_symbol) or raw_symbol.strip().upper() or "XAUUSD"
    min_gap_raw = config.get("min_gap")
    base_gap = float(INSTRUMENT_MIN_GAP.get(symbol, DEFAULT_MIN_GAP))
    if min_gap_raw is None:
        min_gap_value = base_gap
    else:
        try:
            min_gap_value = float(min_gap_raw)
        except Exception:
            min_gap_value = base_gap
    if (not math.isfinite(min_gap_value)) or min_gap_value <= 0.0:
        min_gap_value = base_gap

    strictness = normalize_strictness(config.get("strictness"), 3)
    min_gap = float(min_gap_value) * float(STRICTNESS_GAP_MULTIPLIER.get(strictness, 1.0))

    show_filled = bool(config.get("show_filled", False))
    trend_filter_enabled = bool(config.get("trend_filter_enabled", True))
    trend_alignment_mode = str(config.get("trend_alignment_mode") or "prefer").strip().lower()
    if trend_alignment_mode not in {"prefer", "strict"}:
        trend_alignment_mode = "prefer"
    trend_ctx = config.get("_trend_context") if isinstance(config.get("_trend_context"), dict) else {}
    trend_direction = str(config.get("trend_direction") or trend_ctx.get("direction") or "unknown").strip().lower()

    zones_active_bull: List[Dict[str, Any]] = []
    zones_active_bear: List[Dict[str, Any]] = []
    zones_filled: List[Dict[str, Any]] = []

    for i in range(2, len(df)):
        c1 = df.iloc[i - 2]
        c3 = df.iloc[i]
        ts = df.index[i]
        ts_unix_val = int(ts.timestamp()) if hasattr(ts, "timestamp") else 0

        if zones_active_bull:
            next_bull: List[Dict[str, Any]] = []
            low_i = float(c3["low"])
            for zone in zones_active_bull:
                z_bottom = float(zone["bottom"])
                z_top = float(zone["top"])
                if low_i <= z_bottom:
                    zone["filled"] = True
                    zone["current_gap_size"] = 0.0
                    zone["filled_at_unix"] = ts_unix_val
                    _normalize_fvg_zone_bounds(zone)
                    if show_filled:
                        zones_filled.append(zone)
                    continue
                if z_bottom < low_i < z_top:
                    zone["top"] = float(low_i)
                    zone["mitigations"] = int(zone.get("mitigations", 0)) + 1
                    zone["last_mitigated_unix"] = ts_unix_val
                    _normalize_fvg_zone_bounds(zone)
                next_bull.append(zone)
            zones_active_bull = next_bull

        if zones_active_bear:
            next_bear: List[Dict[str, Any]] = []
            high_i = float(c3["high"])
            for zone in zones_active_bear:
                z_bottom = float(zone["bottom"])
                z_top = float(zone["top"])
                if high_i >= z_top:
                    zone["filled"] = True
                    zone["current_gap_size"] = 0.0
                    zone["filled_at_unix"] = ts_unix_val
                    _normalize_fvg_zone_bounds(zone)
                    if show_filled:
                        zones_filled.append(zone)
                    continue
                if z_bottom < high_i < z_top:
                    zone["bottom"] = float(high_i)
                    zone["mitigations"] = int(zone.get("mitigations", 0)) + 1
                    zone["last_mitigated_unix"] = ts_unix_val
                    _normalize_fvg_zone_bounds(zone)
                next_bear.append(zone)
            zones_active_bear = next_bear

        bull_gap = float(c3["low"]) - float(c1["high"])
        if bull_gap > min_gap:
            start_ts = df.index[i - 2]
            end_ts = df.index[i]
            zones_active_bull.append(
                {
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
                }
            )

        bear_gap = float(c1["low"]) - float(c3["high"])
        if bear_gap > min_gap:
            start_ts = df.index[i - 2]
            end_ts = df.index[i]
            zones_active_bear.append(
                {
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
                }
            )

    zones: List[Dict[str, Any]] = [*zones_active_bull, *zones_active_bear]
    if show_filled and zones_filled:
        zones.extend(zones_filled)

    for zone in zones:
        _normalize_fvg_zone_bounds(zone)
        ztype = str(zone.get("type") or "")
        aligned = (
            (trend_direction == "bullish" and ztype == "bullish_fvg")
            or (trend_direction == "bearish" and ztype == "bearish_fvg")
        )
        zone["trend_direction"] = trend_direction
        zone["trend_timeframe"] = str(trend_ctx.get("trend_timeframe") or "")
        zone["trend_base_timeframe"] = str(trend_ctx.get("base_timeframe") or "")
        zone["trend_aligned"] = bool(aligned)

    if trend_filter_enabled:
        if trend_direction == "bullish":
            zones = [z for z in zones if str(z.get("type") or "") == "bullish_fvg"]
        elif trend_direction == "bearish":
            zones = [z for z in zones if str(z.get("type") or "") == "bearish_fvg"]
        elif trend_alignment_mode == "strict":
            zones = []

    zones.sort(key=lambda z: int(z.get("bar_index") or 0))
    return zones


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


def detect_liquidity_zones(df: pd.DataFrame, config: Dict[str, Any]) -> List[Dict[str, Any]]:
    if df is None or len(df) < 20:
        return []
    if not {"open", "high", "low", "close"}.issubset(set(df.columns)):
        return []

    strictness = normalize_strictness(config.get("strictness"), 3)
    lookback_bars = max(30, min(5000, safe_int(config.get("lookback_bars"), 420)))
    work = df.tail(lookback_bars).copy()
    opens = [float(x) for x in work["open"].astype(float).tolist()]
    highs = [float(x) for x in work["high"].astype(float).tolist()]
    lows = [float(x) for x in work["low"].astype(float).tolist()]
    closes = [float(x) for x in work["close"].astype(float).tolist()]
    index_vals = list(work.index)
    n = len(work)
    if n < 20:
        return []

    pivot_span_default = 2 + (strictness // 2)
    pivot_span = max(1, min(12, safe_int(config.get("pivot_span"), pivot_span_default)))
    min_touches = max(2, min(6, safe_int(config.get("min_touches"), 2)))
    sweep_lookahead = max(5, min(500, safe_int(config.get("sweep_lookahead"), 120)))
    atr_mult = max(0.02, min(2.0, safe_float(config.get("tolerance_atr_mult"), 0.12)))
    atr = atr_last(work, 14)
    tick = symbol_tick_size(str(config.get("symbol") or ""))
    tol = max(float(tick), float((atr or tick) * atr_mult * STRICTNESS_TOLERANCE_MULTIPLIER.get(strictness, 1.0)))

    high_pivots = _pivot_indices(highs, pivot_span, is_high=True)
    low_pivots = _pivot_indices(lows, pivot_span, is_high=False)

    high_clusters = _cluster_by_tolerance(highs, high_pivots, tol, min_touches)
    low_clusters = _cluster_by_tolerance(lows, low_pivots, tol, min_touches)

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
                "start_time": ts_iso(index_vals[idx_min]),
                "end_time": ts_iso(index_vals[idx_max]),
                "start_time_unix": ts_unix(index_vals[idx_min]),
                "end_time_unix": ts_unix(index_vals[idx_max]),
                "filled": False,
            }
        )

        sweep_end = min(n, idx_max + 1 + sweep_lookahead)
        sweep_idx = None
        sweep_price = None
        best_rej = -1.0
        pool_boundary = float(z_top if is_high else z_bottom)
        # Find the sweep with strongest rejection instead of just the
        # first chronological one — second/third sweeps of a pool are
        # often the real institutional stop hunts.
        if is_high:
            for j in range(idx_max + 1, sweep_end):
                if highs[j] > z_top and closes[j] < ref:
                    rej = evaluate_sweep_rejection(
                        pool_boundary=pool_boundary,
                        swept_price=float(highs[j]),
                        bar_high=float(highs[j]),
                        bar_low=float(lows[j]),
                        atr=atr,
                    )
                    if rej["rejection_ratio"] > best_rej:
                        best_rej = rej["rejection_ratio"]
                        sweep_idx = j
                        sweep_price = highs[j]
        else:
            for j in range(idx_max + 1, sweep_end):
                if lows[j] < z_bottom and closes[j] > ref:
                    rej = evaluate_sweep_rejection(
                        pool_boundary=pool_boundary,
                        swept_price=float(lows[j]),
                        bar_high=float(highs[j]),
                        bar_low=float(lows[j]),
                        atr=atr,
                    )
                    if rej["rejection_ratio"] > best_rej:
                        best_rej = rej["rejection_ratio"]
                        sweep_idx = j
                        sweep_price = lows[j]
        if sweep_idx is None:
            return

        rejection = evaluate_sweep_rejection(
            pool_boundary=pool_boundary,
            swept_price=float(sweep_price or ref),
            bar_high=float(highs[sweep_idx]),
            bar_low=float(lows[sweep_idx]),
            atr=atr,
        )
        zones.append(
            {
                "type": "liquidity_sweep_high" if is_high else "liquidity_sweep_low",
                "top": float(max(pool_boundary, float(sweep_price or pool_boundary))),
                "bottom": float(min(pool_boundary, float(sweep_price or pool_boundary))),
                "liquidity_level": ref,
                "ref_price": ref,
                "pool_boundary": float(pool_boundary),
                "swept_price": float(sweep_price or ref),
                "rejection_ratio": float(rejection["rejection_ratio"]),
                "rejection_quality": str(rejection["rejection_quality"]),
                "sweep_bar_open": float(opens[sweep_idx]),
                "sweep_bar_close": float(closes[sweep_idx]),
                "sweep_bar_high": float(highs[sweep_idx]),
                "sweep_bar_low": float(lows[sweep_idx]),
                "swept_pool_touches": int(cluster["touches"]),
                "bar_index": int(sweep_idx),
                "start_time": ts_iso(index_vals[idx_max]),
                "end_time": ts_iso(index_vals[sweep_idx]),
                "start_time_unix": ts_unix(index_vals[idx_max]),
                "end_time_unix": ts_unix(index_vals[sweep_idx]),
                "filled": False,
            }
        )

    for row in high_clusters:
        _append_pool(row, is_high=True)
    for row in low_clusters:
        _append_pool(row, is_high=False)

    zones.sort(key=lambda z: int(z.get("end_time_unix") or 0))
    return zones[-200:]


def detect_liquidity_pools(df: pd.DataFrame, config: Dict[str, Any]) -> List[Dict[str, Any]]:
    return detect_liquidity_zones(df, config)


def _sweep_quality_rank(quality: str) -> int:
    q = str(quality or "").strip().lower()
    if q == "strong":
        return 2
    if q == "moderate":
        return 1
    return 0


def filter_sweep_candidates(
    sweeps: List[Dict[str, Any]],
    *,
    entry_price: float,
    direction: str,
    atr: float,
    max_age_bars: int,
    max_distance_atr: float,
    min_rejection_ratio: float = 0.0,
    current_bar_index: Optional[int] = None,
) -> List[Dict[str, Any]]:
    if not sweeps:
        return []

    out: List[Dict[str, Any]] = []
    want = str(direction or "").strip().lower()
    max_dist = max(0.0, float(atr or 0.0) * float(max_distance_atr or 0.0))
    current_idx = int(current_bar_index) if current_bar_index is not None else None

    for row in sweeps:
        ztype = str(row.get("type") or "").strip().lower()
        row_dir = "bearish" if ztype == "liquidity_sweep_high" else ("bullish" if ztype == "liquidity_sweep_low" else "")
        if want and row_dir != want:
            continue
        rr = safe_float(row.get("rejection_ratio"), 0.0)
        if rr < float(min_rejection_ratio):
            continue
        swept_price = safe_float(row.get("swept_price"), safe_float(row.get("pool_boundary"), safe_float(row.get("liquidity_level"), 0.0)))
        if max_dist > 0.0 and abs(float(entry_price) - swept_price) > max_dist:
            continue
        age_bars: Optional[int] = None
        if current_idx is not None and row.get("bar_index") is not None:
            age_bars = max(0, current_idx - int(row.get("bar_index") or 0))
            if age_bars > int(max_age_bars):
                continue
        item = dict(row)
        item["distance_to_entry"] = abs(float(entry_price) - swept_price)
        item["age_bars"] = age_bars
        out.append(item)

    out.sort(
        key=lambda x: (
            -_sweep_quality_rank(str(x.get("rejection_quality") or "")),
            -safe_float(x.get("rejection_ratio"), 0.0),
            safe_float(x.get("distance_to_entry"), 10**9),
            safe_int(x.get("age_bars"), 10**9),
        )
    )
    return out
