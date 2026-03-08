"""Event detection for Workbench copilot loop."""

from __future__ import annotations

from typing import Any, Dict, List


def _to_int(v: Any, default: int = 0) -> int:
    try:
        if v is None:
            return int(default)
        return int(v)
    except Exception:
        return int(default)


def _to_float(v: Any, default: float = 0.0) -> float:
    try:
        if v is None:
            return float(default)
        return float(v)
    except Exception:
        return float(default)


def detect_events(
    prev_snapshot: Dict[str, Any] | None,
    snapshot: Dict[str, Any],
    config: Dict[str, Any] | None = None,
) -> List[Dict[str, Any]]:
    """Detect meaningful copilot events from snapshot transitions."""
    cfg = config or {}
    emit_bar_events = bool(cfg.get("emit_bar_events", False))
    review_interval_bars = max(10, _to_int(cfg.get("review_interval_bars"), 50))
    risk_alert_usd = max(1.0, _to_float(cfg.get("risk_alert_usd"), 250.0))
    events: List[Dict[str, Any]] = []

    def push(event_type: str, severity: str, payload: Dict[str, Any], priority: int) -> None:
        events.append(
            {
                "event_type": str(event_type),
                "severity": str(severity),
                "payload": payload if isinstance(payload, dict) else {},
                "priority": int(priority),
            }
        )

    if prev_snapshot is None:
        push(
            event_type="SESSION_SNAPSHOT",
            severity="info",
            payload={
                "current_bar": snapshot.get("current_bar"),
                "total_bars": snapshot.get("total_bars"),
            },
            priority=20,
        )
        return events

    current_bar = _to_int(snapshot.get("current_bar"))
    prev_bar = _to_int(prev_snapshot.get("current_bar"))
    if emit_bar_events and current_bar != prev_bar:
        push(
            event_type="BAR_ADVANCED",
            severity="debug",
            payload={"from_bar": prev_bar, "to_bar": current_bar},
            priority=10,
        )

    prev_open = _to_int(prev_snapshot.get("open_positions_count"))
    now_open = _to_int(snapshot.get("open_positions_count"))
    if now_open > prev_open:
        push(
            event_type="TRADE_OPENED",
            severity="info",
            payload={"open_positions_count": now_open},
            priority=80,
        )

    closed_now = _to_int(snapshot.get("new_closed_trades_count"))
    if closed_now > 0:
        push(
            event_type="TRADE_CLOSED",
            severity="info",
            payload={"new_closed_trades_count": closed_now},
            priority=80,
        )

    prev_open_pnl = _to_float(prev_snapshot.get("open_pnl"), 0.0)
    now_open_pnl = _to_float(snapshot.get("open_pnl"), 0.0)
    if now_open_pnl <= (-risk_alert_usd) and prev_open_pnl > (-risk_alert_usd):
        push(
            event_type="RISK_BREACH",
            severity="high",
            payload={
                "open_pnl": round(now_open_pnl, 4),
                "threshold": -risk_alert_usd,
            },
            priority=100,
        )

    if current_bar != prev_bar and current_bar > 0 and (current_bar % review_interval_bars) == 0:
        push(
            event_type="PERIODIC_REVIEW",
            severity="info",
            payload={"review_interval_bars": review_interval_bars},
            priority=40,
        )

    prev_completed = bool(prev_snapshot.get("is_completed"))
    now_completed = bool(snapshot.get("is_completed"))
    if now_completed and not prev_completed:
        push(
            event_type="REPLAY_COMPLETED",
            severity="info",
            payload={
                "final_balance": snapshot.get("balance"),
                "total_pnl": snapshot.get("total_pnl"),
            },
            priority=90,
        )

    prev_regime = str(prev_snapshot.get("market_regime") or "").strip().lower()
    now_regime = str(snapshot.get("market_regime") or "").strip().lower()
    if now_regime and prev_regime and now_regime != prev_regime:
        push(
            event_type="REGIME_SHIFT",
            severity="info",
            payload={
                "from_regime": prev_regime,
                "to_regime": now_regime,
            },
            priority=60,
        )

    return events
