"""Snapshot builder for Workbench copilot loop."""

from __future__ import annotations

from datetime import datetime, timezone
import math
from typing import Any, Dict


def _safe_float(v: Any, default: float = 0.0) -> float:
    try:
        if v is None:
            return float(default)
        return float(v)
    except Exception:
        return float(default)


def _safe_int(v: Any, default: int = 0) -> int:
    try:
        if v is None:
            return int(default)
        return int(v)
    except Exception:
        return int(default)


def _extract_latest_bar(advance_result: Dict[str, Any]) -> Dict[str, Any]:
    bars = advance_result.get("bars") if isinstance(advance_result.get("bars"), list) else []
    if not bars:
        return {}
    last = bars[-1] if isinstance(bars[-1], dict) else {}
    return {
        "time": int(last.get("time") or 0),
        "open": _safe_float(last.get("open"), 0.0),
        "high": _safe_float(last.get("high"), 0.0),
        "low": _safe_float(last.get("low"), 0.0),
        "close": _safe_float(last.get("close"), 0.0),
        "volume": _safe_float(last.get("volume"), 0.0),
    }


def _extract_indicator_last(indicators: Any) -> Dict[str, Any]:
    if not isinstance(indicators, dict):
        return {}
    out: Dict[str, Any] = {}
    for key, value in indicators.items():
        if isinstance(value, list):
            if not value:
                continue
            last = value[-1]
            if isinstance(last, dict):
                out[str(key)] = {
                    "time": int(last.get("time") or 0),
                    "value": _safe_float(last.get("value"), 0.0),
                }
            elif isinstance(last, (int, float)):
                out[str(key)] = _safe_float(last, 0.0)
        elif isinstance(value, (int, float)):
            out[str(key)] = _safe_float(value, 0.0)
    return out


def _extract_fvg_zones(tool_state: Dict[str, Any], tool_state_full: Dict[str, Any]) -> list[Dict[str, Any]]:
    raw_sources: list[Any] = []
    raw_sources.append(tool_state.get("fvg_zones_preview"))
    tools = tool_state.get("tools") if isinstance(tool_state.get("tools"), dict) else {}
    if isinstance(tools.get("fvg"), dict):
        raw_sources.append(tools.get("fvg", {}).get("zones_sample"))
    if isinstance(tool_state_full.get("fvg"), dict):
        raw_sources.append(tool_state_full.get("fvg", {}).get("zones_sample"))

    zones: list[Dict[str, Any]] = []
    seen: set[tuple[str, float, float, int]] = set()
    for raw in raw_sources:
        if not isinstance(raw, list):
            continue
        for z in raw:
            if not isinstance(z, dict):
                continue
            zt = str(z.get("type") or "").strip().lower()
            top = _safe_float(z.get("top"), float("nan"))
            bottom = _safe_float(z.get("bottom"), float("nan"))
            if not (math.isfinite(top) and math.isfinite(bottom)):
                continue
            high = max(float(top), float(bottom))
            low = min(float(top), float(bottom))
            start_ts = _safe_int(z.get("start_time_unix"), 0)
            key = (zt, round(high, 6), round(low, 6), start_ts)
            if key in seen:
                continue
            seen.add(key)
            zones.append(
                {
                    "type": zt,
                    "top": high,
                    "bottom": low,
                    "mid": (high + low) * 0.5,
                    "height": abs(high - low),
                    "gap_size": _safe_float(z.get("gap_size"), abs(high - low)),
                    "original_gap_size": _safe_float(z.get("original_gap_size"), _safe_float(z.get("gap_size"), abs(high - low))),
                    "current_gap_size": _safe_float(z.get("current_gap_size"), _safe_float(z.get("gap_size"), abs(high - low))),
                    "mitigations": _safe_int(z.get("mitigations"), 0),
                    "filled": bool(z.get("filled", False)),
                    "trend_direction": str(z.get("trend_direction") or "").strip().lower(),
                    "trend_timeframe": str(z.get("trend_timeframe") or "").strip(),
                    "trend_aligned": bool(z.get("trend_aligned", False)),
                    "start_time_unix": start_ts,
                }
            )
    return zones


def _build_fvg_context(latest_bar: Dict[str, Any], tool_state: Dict[str, Any], tool_state_full: Dict[str, Any]) -> Dict[str, Any]:
    zones = _extract_fvg_zones(tool_state=tool_state, tool_state_full=tool_state_full)
    trend_meta = tool_state.get("fvg_trend") if isinstance(tool_state.get("fvg_trend"), dict) else {}
    aligned_count = int(sum(1 for z in zones if bool(z.get("trend_aligned", False))))
    counter_count = int(sum(1 for z in zones if ("trend_aligned" in z and not bool(z.get("trend_aligned", False)))))
    mitigated_count = int(sum(1 for z in zones if _safe_int(z.get("mitigations"), 0) > 0))
    filled_count = int(sum(1 for z in zones if bool(z.get("filled", False))))
    out: Dict[str, Any] = {
        "enabled": bool(tool_state.get("fvg_enabled")),
        "zones_count": int(len(zones)),
        "bullish_count": int(sum(1 for z in zones if str(z.get("type") or "").startswith("bullish"))),
        "bearish_count": int(sum(1 for z in zones if str(z.get("type") or "").startswith("bearish"))),
        "trend_direction": str(trend_meta.get("direction") or ""),
        "trend_timeframe": str(trend_meta.get("trend_timeframe") or ""),
        "trend_base_timeframe": str(trend_meta.get("base_timeframe") or ""),
        "aligned_count": aligned_count,
        "countertrend_count": counter_count,
        "mitigated_count": mitigated_count,
        "filled_count": filled_count,
    }
    movement = tool_state.get("fvg_movement_strength") if isinstance(tool_state.get("fvg_movement_strength"), dict) else {}
    out["movement_strength"] = movement
    close = _safe_float(latest_bar.get("close"), 0.0)
    if close <= 0.0 or not zones:
        return out

    def _nearest(candidates: list[Dict[str, Any]]) -> Dict[str, Any] | None:
        nearest = None
        best_dist = float("inf")
        for z in candidates:
            low = _safe_float(z.get("bottom"), 0.0)
            high = _safe_float(z.get("top"), 0.0)
            if low <= close <= high:
                dist = 0.0
            else:
                dist = min(abs(close - low), abs(close - high))
            if dist < best_dist:
                nearest = z
                best_dist = dist
        if nearest is None:
            return None
        low = _safe_float(nearest.get("bottom"), 0.0)
        high = _safe_float(nearest.get("top"), 0.0)
        inside = bool(low <= close <= high)
        dist = 0.0 if inside else min(abs(close - low), abs(close - high))
        return {
            "type": str(nearest.get("type") or ""),
            "top": high,
            "bottom": low,
            "mid": _safe_float(nearest.get("mid"), (high + low) * 0.5),
            "height": _safe_float(nearest.get("height"), abs(high - low)),
            "inside": inside,
            "distance": float(dist),
            "distance_pct": float((dist / close) * 100.0 if close > 0 else 0.0),
            "gap_size": _safe_float(nearest.get("gap_size"), abs(high - low)),
            "original_gap_size": _safe_float(nearest.get("original_gap_size"), _safe_float(nearest.get("gap_size"), abs(high - low))),
            "current_gap_size": _safe_float(nearest.get("current_gap_size"), _safe_float(nearest.get("gap_size"), abs(high - low))),
            "mitigations": _safe_int(nearest.get("mitigations"), 0),
            "filled": bool(nearest.get("filled", False)),
            "trend_direction": str(nearest.get("trend_direction") or "").strip().lower(),
            "trend_timeframe": str(nearest.get("trend_timeframe") or "").strip(),
            "trend_aligned": bool(nearest.get("trend_aligned", False)),
        }

    bullish = [z for z in zones if str(z.get("type") or "").startswith("bullish")]
    bearish = [z for z in zones if str(z.get("type") or "").startswith("bearish")]
    nearest_bull = _nearest(bullish)
    nearest_bear = _nearest(bearish)
    out["close_price"] = float(close)
    out["nearest_bullish"] = nearest_bull
    out["nearest_bearish"] = nearest_bear
    return out


def build_snapshot(session: Any, advance_result: Dict[str, Any]) -> Dict[str, Any]:
    """Build a compact, JSON-safe snapshot for event/advice processing."""
    open_positions = advance_result.get("open_positions") or []
    closed_trades = advance_result.get("closed_trades") or []
    day_context = advance_result.get("day_context") if isinstance(advance_result.get("day_context"), dict) else {}
    market_regime = str(
        day_context.get("regime")
        or day_context.get("bias_label")
        or day_context.get("bias")
        or ""
    ).strip()
    latest_bar = _extract_latest_bar(advance_result)
    indicators = advance_result.get("indicators") if isinstance(advance_result.get("indicators"), dict) else {}
    tool_state = advance_result.get("tool_state") if isinstance(advance_result.get("tool_state"), dict) else {}
    snapshot = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "session_id": int(session.id),
        "strategy_id": str(session.strategy_id or ""),
        "symbol": str(session.symbol or ""),
        "timeframe": str(session.timeframe or ""),
        "status": str(advance_result.get("status") or session.status or "active").lower(),
        "current_bar": int(advance_result.get("current_bar") or session.current_bar or 0),
        "total_bars": int(advance_result.get("total_bars") or session.total_bars or 0),
        "balance": _safe_float(advance_result.get("balance"), _safe_float(session.current_balance, 0.0)),
        "initial_balance": _safe_float(session.initial_balance, 0.0),
        "total_pnl": _safe_float(advance_result.get("total_pnl"), _safe_float(session.total_pnl, 0.0)),
        "open_pnl": _safe_float(advance_result.get("open_pnl"), 0.0),
        "trades_count": int(advance_result.get("trades_count") or session.trades_count or 0),
        "wins": int(advance_result.get("wins") or session.wins or 0),
        "losses": int(advance_result.get("losses") or session.losses or 0),
        "open_positions_count": int(len(open_positions)),
        "new_closed_trades_count": int(len(closed_trades)),
        "open_positions": open_positions,
        "closed_trades_sample": closed_trades[:5],
        "market_regime": market_regime,
        "latest_bar": latest_bar,
        "indicator_last": _extract_indicator_last(indicators),
        "tool_state": tool_state,
        "tool_state_full": tool_state.get("tools") if isinstance(tool_state.get("tools"), dict) else {},
    }
    snapshot["fvg_context"] = _build_fvg_context(
        latest_bar=latest_bar,
        tool_state=tool_state,
        tool_state_full=snapshot["tool_state_full"] if isinstance(snapshot.get("tool_state_full"), dict) else {},
    )
    total_bars = int(snapshot["total_bars"])
    current_bar = int(snapshot["current_bar"])
    snapshot["is_completed"] = bool(total_bars > 0 and current_bar >= (total_bars - 1))
    return snapshot
