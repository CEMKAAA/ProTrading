"""Deterministic advice generation for Workbench copilot events."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict, List

from .policy_engine import normalize_mode, is_action_allowed
from .routing import route_advices_by_confidence


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


def _extract_fvg_context(snapshot: Dict[str, Any]) -> Dict[str, Any]:
    ctx = snapshot.get("fvg_context") if isinstance(snapshot.get("fvg_context"), dict) else {}
    if ctx:
        return ctx
    # Backward-compatible fallback if snapshot is missing enriched context.
    tool_state = snapshot.get("tool_state") if isinstance(snapshot.get("tool_state"), dict) else {}
    return {
        "enabled": bool(tool_state.get("fvg_enabled")),
        "zones_count": _safe_int(tool_state.get("fvg_last_zone_count"), 0),
    }


def _extract_utc_hour(snapshot: Dict[str, Any]) -> int | None:
    latest = snapshot.get("latest_bar") if isinstance(snapshot.get("latest_bar"), dict) else {}
    ts = _safe_int(latest.get("time"), 0)
    if ts <= 0:
        return None
    # Accept both seconds and milliseconds epoch.
    if ts > 10_000_000_000:
        ts = int(ts / 1000)
    try:
        return int(datetime.fromtimestamp(int(ts), timezone.utc).hour)
    except Exception:
        return None


def _passes_fvg_environment_gate(snapshot: Dict[str, Any], cfg: Dict[str, Any]) -> bool:
    # Regime gate: soft mode, only block when regime is present and explicitly disallowed.
    allowed_regimes = [
        str(x or "").strip().lower()
        for x in (cfg.get("fvg_entry_allowed_regimes") if isinstance(cfg.get("fvg_entry_allowed_regimes"), list) else [])
        if str(x or "").strip()
    ]
    regime = str(snapshot.get("market_regime") or "").strip().lower()
    if allowed_regimes and regime and regime not in allowed_regimes:
        return False

    # Session gate: if enabled and time exists, require hour in window.
    if not bool(cfg.get("fvg_entry_require_active_session", True)):
        return True
    hour = _extract_utc_hour(snapshot)
    if hour is None:
        return True  # permissive fallback when timestamp is unavailable
    start_h = max(0, min(23, _safe_int(cfg.get("fvg_entry_session_utc_start"), 6)))
    end_h = max(0, min(23, _safe_int(cfg.get("fvg_entry_session_utc_end"), 23)))
    if start_h == end_h:
        return True
    if start_h < end_h:
        return bool(start_h <= hour < end_h)
    # Overnight wrap window, e.g. 22 -> 6
    return bool(hour >= start_h or hour < end_h)


def _build_fvg_entry_action(snapshot: Dict[str, Any], nearest_zone: Dict[str, Any], rr_target: float) -> Dict[str, Any]:
    close = _safe_float((snapshot.get("latest_bar") or {}).get("close"), 0.0)
    if close <= 0.0:
        return {}
    ztype = str(nearest_zone.get("type") or "").lower()
    top = _safe_float(nearest_zone.get("top"), 0.0)
    bottom = _safe_float(nearest_zone.get("bottom"), 0.0)
    if top <= 0.0 and bottom <= 0.0:
        return {}
    high = max(top, bottom)
    low = min(top, bottom)
    zone_height = max(abs(high - low), close * 0.0005)
    rr = max(1.2, float(rr_target))
    if ztype.startswith("bullish"):
        # Directional sanity: for a BUY idea, stop must stay below entry.
        # If price is below bullish zone low, SL from zone would be above/near entry.
        if close < low:
            return {}
        stop_loss = low - (zone_height * 0.25)
        risk = max(close - stop_loss, zone_height * 0.5)
        take_profit = close + (risk * rr)
        direction = "BUY"
    else:
        # Directional sanity: for a SELL idea, stop must stay above entry.
        # If price is above bearish zone high, SL from zone would be below/near entry.
        if close > high:
            return {}
        stop_loss = high + (zone_height * 0.25)
        risk = max(stop_loss - close, zone_height * 0.5)
        take_profit = close - (risk * rr)
        direction = "SELL"
    return {
        "action_type": "SUGGEST_ENTRY",
        "direction": direction,
        "stop_loss": round(float(stop_loss), 6),
        "take_profit": round(float(take_profit), 6),
        "lot_size": 0.01,
        "tool_id": "fvg",
    }


def _maybe_fvg_entry_advice(snapshot: Dict[str, Any], cfg: Dict[str, Any], source_event_type: str) -> Dict[str, Any] | None:
    fvg_ctx = _extract_fvg_context(snapshot)
    if not bool(fvg_ctx.get("enabled", False)):
        return None
    if _safe_int(snapshot.get("open_positions_count"), 0) > 0:
        return None
    if not _passes_fvg_environment_gate(snapshot=snapshot, cfg=cfg):
        return None

    threshold_pct = max(0.01, _safe_float(cfg.get("fvg_entry_proximity_pct"), 0.20))
    candidates: List[Dict[str, Any]] = []
    bull = fvg_ctx.get("nearest_bullish") if isinstance(fvg_ctx.get("nearest_bullish"), dict) else None
    bear = fvg_ctx.get("nearest_bearish") if isinstance(fvg_ctx.get("nearest_bearish"), dict) else None
    if bull:
        candidates.append(bull)
    if bear:
        candidates.append(bear)
    if not candidates:
        return None
    nearest = sorted(candidates, key=lambda z: _safe_float(z.get("distance_pct"), 9999.0))[0]
    dist_pct = _safe_float(nearest.get("distance_pct"), 9999.0)
    inside = bool(nearest.get("inside"))
    if (not inside) and dist_pct > threshold_pct:
        return None

    tool_state = snapshot.get("tool_state") if isinstance(snapshot.get("tool_state"), dict) else {}
    fvg_cfg = tool_state.get("fvg_config") if isinstance(tool_state.get("fvg_config"), dict) else {}
    trend_filter_enabled = bool(fvg_cfg.get("trend_filter_enabled", True))
    trend_mode = str(fvg_cfg.get("trend_alignment_mode") or "prefer").strip().lower()
    if trend_mode not in {"prefer", "strict"}:
        trend_mode = "prefer"
    trend_direction = str(fvg_ctx.get("trend_direction") or nearest.get("trend_direction") or "").strip().lower()
    trend_aligned = bool(nearest.get("trend_aligned", False))

    if trend_filter_enabled:
        if trend_direction in {"bullish", "bearish"} and not trend_aligned:
            return None
        if trend_mode == "strict" and trend_direction not in {"bullish", "bearish"}:
            return None

    movement = fvg_ctx.get("movement_strength") if isinstance(fvg_ctx.get("movement_strength"), dict) else {}
    movement_score = _safe_float(movement.get("score"), 50.0)
    min_movement = max(0.0, min(100.0, _safe_float(cfg.get("fvg_entry_min_movement_strength"), 35.0)))
    if movement_score < min_movement:
        return None

    action = _build_fvg_entry_action(
        snapshot=snapshot,
        nearest_zone=nearest,
        rr_target=_safe_float(cfg.get("auto_paper_rr_target"), 1.8),
    )
    if not action:
        return None
    close = _safe_float((snapshot.get("latest_bar") or {}).get("close"), 0.0)
    direction = str(action.get("direction") or "")
    zone_tag = "inside" if inside else f"{dist_pct:.3f}% away"
    current_gap = _safe_float(nearest.get("current_gap_size"), _safe_float(nearest.get("gap_size"), 0.0))
    original_gap = _safe_float(nearest.get("original_gap_size"), _safe_float(nearest.get("gap_size"), 0.0))
    mitigations = _safe_int(nearest.get("mitigations"), 0)
    confidence = 0.78 if inside else 0.72
    confidence = max(0.55, min(0.92, confidence * (0.8 + 0.2 * min(1.0, movement_score / 100.0))))
    return _mk_advice(
        advice_type="SUGGEST_ENTRY",
        summary=(
            f"FVG context supports {direction} idea: price {zone_tag} from nearest {str(nearest.get('type') or '').replace('_', ' ')} zone "
            f"(gap_now={current_gap:.5f}, gap_orig={original_gap:.5f}, mitigations={mitigations}, trend={trend_direction or 'unknown'}, movement={movement_score:.1f}/100)."
        ),
        confidence=confidence,
        source_event_type=source_event_type,
        evidence={
            "close_price": close,
            "fvg_zones_count": _safe_int(fvg_ctx.get("zones_count"), 0),
            "nearest_zone_type": nearest.get("type"),
            "nearest_zone_top": nearest.get("top"),
            "nearest_zone_bottom": nearest.get("bottom"),
            "nearest_zone_distance_pct": dist_pct,
            "nearest_zone_inside": inside,
            "nearest_zone_current_gap_size": current_gap,
            "nearest_zone_original_gap_size": original_gap,
            "nearest_zone_mitigations": mitigations,
            "nearest_zone_trend_aligned": trend_aligned,
            "trend_direction": trend_direction,
            "trend_filter_enabled": trend_filter_enabled,
            "trend_alignment_mode": trend_mode,
            "movement_strength_score": movement_score,
            "movement_strength_state": str(movement.get("state") or ""),
            "movement_strength_min_required": min_movement,
            "proximity_threshold_pct": threshold_pct,
        },
        action=action,
    )


def _mk_advice(
    advice_type: str,
    summary: str,
    confidence: float,
    source_event_type: str,
    evidence: Dict[str, Any],
    action: Dict[str, Any] | None = None,
) -> Dict[str, Any]:
    return {
        "advice_type": str(advice_type),
        "summary": str(summary),
        "confidence": float(max(0.0, min(1.0, confidence))),
        "source_event_type": str(source_event_type),
        "source_event_priority": 0,
        "evidence_json": evidence or {},
        "action_json": action or {},
        "status": "NEW",
        "delivery": "ACTIONABLE",
    }


def generate_advices(
    snapshot: Dict[str, Any],
    events: List[Dict[str, Any]],
    mode: str | None,
    config: Dict[str, Any] | None = None,
) -> List[Dict[str, Any]]:
    """Generate deterministic advices from detected events."""
    m = normalize_mode(mode)
    if m == "OBSERVE" or not events:
        return []

    advices: List[Dict[str, Any]] = []
    cfg = config or {}

    for ev in events:
        et = str(ev.get("event_type") or "")
        payload = ev.get("payload") if isinstance(ev.get("payload"), dict) else {}
        event_priority = int(ev.get("priority") or 0)

        if et == "RISK_BREACH":
            action_type = "SUGGEST_RISK_ADJUSTMENT"
            if is_action_allowed(m, action_type):
                advices.append(
                    _mk_advice(
                        advice_type=action_type,
                        summary=(
                            "Open-position drawdown crossed your alert threshold. "
                            "Reduce exposure or tighten invalidation before taking new entries."
                        ),
                        confidence=0.92,
                        source_event_type=et,
                        evidence={
                            "open_pnl": payload.get("open_pnl"),
                            "threshold": payload.get("threshold"),
                            "open_positions_count": snapshot.get("open_positions_count"),
                        },
                        action={"action_type": action_type, "priority": "high"},
                    )
                )

        elif et == "TRADE_OPENED":
            action_type = "SUGGEST_EXIT"
            if is_action_allowed(m, action_type):
                advices.append(
                    _mk_advice(
                        advice_type=action_type,
                        summary=(
                            "New position detected. Confirm stop/target remains valid and do not widen risk."
                        ),
                        confidence=0.82,
                        source_event_type=et,
                        evidence={
                            "open_positions_count": payload.get("open_positions_count"),
                            "current_bar": snapshot.get("current_bar"),
                        },
                        action={"action_type": "REVIEW_NOTE", "checklist": ["sl_locked", "tp_defined"]},
                    )
                )

        elif et == "TRADE_CLOSED":
            action_type = "REVIEW_NOTE"
            if is_action_allowed(m, action_type):
                advices.append(
                    _mk_advice(
                        advice_type=action_type,
                        summary=(
                            "Trade closed. Capture one lesson before opening a new position."
                        ),
                        confidence=0.78,
                        source_event_type=et,
                        evidence={
                            "new_closed_trades_count": payload.get("new_closed_trades_count"),
                            "balance": snapshot.get("balance"),
                            "total_pnl": snapshot.get("total_pnl"),
                        },
                        action={"action_type": action_type},
                    )
                )

        elif et == "PERIODIC_REVIEW":
            action_type = "REVIEW_NOTE"
            if is_action_allowed(m, action_type):
                win = int(snapshot.get("wins") or 0)
                loss = int(snapshot.get("losses") or 0)
                trades = max(1, int(snapshot.get("trades_count") or 0))
                win_rate = round((win / trades) * 100.0, 1)
                advices.append(
                    _mk_advice(
                        advice_type=action_type,
                        summary=(
                            f"Periodic review: win-rate {win_rate}%. Keep process focus on setup quality and risk consistency."
                        ),
                        confidence=0.70,
                        source_event_type=et,
                        evidence={
                            "wins": win,
                            "losses": loss,
                            "trades_count": trades,
                            "review_interval_bars": payload.get("review_interval_bars"),
                            "fvg_context": _extract_fvg_context(snapshot),
                        },
                        action={"action_type": action_type},
                    )
                )
            if is_action_allowed(m, "AUTO_TOOL_SCAN"):
                tool_state = snapshot.get("tool_state") if isinstance(snapshot.get("tool_state"), dict) else {}
                fvg_cfg = tool_state.get("fvg_config") if isinstance(tool_state.get("fvg_config"), dict) else {}
                strictness = _safe_int(fvg_cfg.get("strictness"), 3)
                strictness = max(1, min(5, strictness))
                trend_filter_enabled = bool(fvg_cfg.get("trend_filter_enabled", True))
                trend_alignment_mode = str(fvg_cfg.get("trend_alignment_mode") or "prefer").strip().lower()
                if trend_alignment_mode not in {"prefer", "strict"}:
                    trend_alignment_mode = "prefer"
                trend_multiplier = max(2, min(12, _safe_int(fvg_cfg.get("trend_multiplier"), 3)))
                advices.append(
                    _mk_advice(
                        advice_type="AUTO_TOOL_SCAN",
                        summary=(
                            "Refresh FVG map on current context before next entry decision."
                        ),
                        confidence=0.74,
                        source_event_type=et,
                        evidence={
                            "current_bar": snapshot.get("current_bar"),
                            "fvg_scan_count": tool_state.get("fvg_scan_count"),
                            "fvg_last_zone_count": tool_state.get("fvg_last_zone_count"),
                        },
                        action={
                            "action_type": "AUTO_TOOL_SCAN",
                            "tool_id": "fvg",
                            "config": {
                                "show_filled": False,
                                "strictness": strictness,
                                "trend_filter_enabled": trend_filter_enabled,
                                "trend_alignment_mode": trend_alignment_mode,
                                "trend_multiplier": trend_multiplier,
                            },
                        },
                    )
                )
            if is_action_allowed(m, "SUGGEST_ENTRY"):
                fvg_entry = _maybe_fvg_entry_advice(snapshot=snapshot, cfg=cfg, source_event_type=et)
                if fvg_entry is not None:
                    advices.append(fvg_entry)

        elif et == "REPLAY_COMPLETED":
            action_type = "REVIEW_NOTE"
            if is_action_allowed(m, action_type):
                pnl = _safe_float(snapshot.get("total_pnl"), 0.0)
                advices.append(
                    _mk_advice(
                        advice_type=action_type,
                        summary=(
                            "Replay finished. Run a full post-session review and document two concrete improvements."
                        ),
                        confidence=0.88,
                        source_event_type=et,
                        evidence={
                            "final_balance": payload.get("final_balance"),
                            "total_pnl": pnl,
                        },
                        action={"action_type": action_type},
                    )
                )

        elif et == "REGIME_SHIFT":
            action_type = "REVIEW_NOTE"
            if is_action_allowed(m, action_type):
                advices.append(
                    _mk_advice(
                        advice_type=action_type,
                        summary=(
                            "Market regime changed. Re-validate setup assumptions before new entries."
                        ),
                        confidence=0.74,
                        source_event_type=et,
                        evidence={
                            "from_regime": payload.get("from_regime"),
                            "to_regime": payload.get("to_regime"),
                            "current_bar": snapshot.get("current_bar"),
                        },
                        action={"action_type": action_type},
                    )
                )

        elif et == "TOOL_SIGNAL_CHANGED":
            fvg_entry_added = False
            if is_action_allowed(m, "SUGGEST_ENTRY"):
                fvg_entry = _maybe_fvg_entry_advice(snapshot=snapshot, cfg=cfg, source_event_type=et)
                if fvg_entry is not None:
                    advices.append(fvg_entry)
                    fvg_entry_added = True
            action_type = "REVIEW_NOTE"
            if is_action_allowed(m, action_type):
                tool_id = str(payload.get("tool_id") or "tool")
                zones_count = int(payload.get("zones_count") or 0)
                summary = (
                    f"{tool_id} signal updated ({zones_count} zones). Align next entry only if structure and risk both match."
                )
                if fvg_entry_added:
                    summary = (
                        f"{tool_id} signal updated ({zones_count} zones). Candidate setup identified; validate SL/TP before execution."
                    )
                advices.append(
                    _mk_advice(
                        advice_type=action_type,
                        summary=summary,
                        confidence=0.68,
                        source_event_type=et,
                        evidence={
                            "tool_id": tool_id,
                            "zones_count": zones_count,
                            "bar_index": payload.get("bar_index"),
                            "fvg_context": _extract_fvg_context(snapshot),
                        },
                        action={"action_type": action_type},
                    )
                )

        elif et == "MANUAL_OVERRIDE":
            action_type = "REVIEW_NOTE"
            if is_action_allowed(m, action_type):
                advices.append(
                    _mk_advice(
                        advice_type=action_type,
                        summary=(
                            "Manual override logged. Add one-line rationale so later review can validate process consistency."
                        ),
                        confidence=0.66,
                        source_event_type=et,
                        evidence={
                            "override_type": payload.get("override_type"),
                            "action_type": payload.get("action_type"),
                        },
                        action={"action_type": action_type},
                    )
                )

        if advices:
            last = advices[-1]
            if str(last.get("source_event_type") or "") == et:
                last["source_event_priority"] = event_priority

    return route_advices_by_confidence(advices=advices, config=cfg)
