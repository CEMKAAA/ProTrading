"""
Telemetry adapters for guided trading simulation.
Normalizes strategy/manager state into a standard contract.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict, Tuple


def _to_float(value: Any, default: float = 0.0) -> float:
    try:
        if value is None:
            return default
        return float(value)
    except Exception:
        return default


def _to_int(value: Any, default: int = 0) -> int:
    try:
        if value is None:
            return default
        return int(value)
    except Exception:
        return default


def _extract_price(state: Dict[str, Any]) -> float:
    for key in ("price", "current_price", "last_price", "entry_price"):
        if key in state:
            return _to_float(state.get(key), 0.0)
    return 0.0


def _extract_spread(state: Dict[str, Any]) -> float:
    for key in ("spread", "current_spread", "spread_points"):
        if key in state:
            return _to_float(state.get(key), 0.0)
    return 0.0


def _is_orb_strategy(strategy_id: str) -> bool:
    sid = (strategy_id or "").lower()
    return "orb" in sid


def _is_liquidity_strategy(strategy_id: str) -> bool:
    sid = (strategy_id or "").lower()
    return "liquidity_sweep" in sid


def _is_keltner_strategy(strategy_id: str) -> bool:
    sid = (strategy_id or "").lower()
    return "keltner" in sid


def _extract_common_inputs(state: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "bias": str(state.get("bias") or "neutral"),
        "bias_strength": _to_int(state.get("bias_strength"), 0),
        "suggested_entry": _to_float(state.get("entry_price"), 0.0),
        "suggested_sl": _to_float(state.get("stop_loss"), 0.0),
        "suggested_tp": _to_float(state.get("take_profit"), 0.0),
        "rr_estimate": _to_float(state.get("rr"), 0.0),
        "invalidation_reason": str(state.get("invalidation_reason") or ""),
        "setup_detected": bool(
            state.get("setup_detected")
            or state.get("signal")
            or state.get("entry_signal")
            or state.get("trade_signal")
        ),
        "is_connected": bool(state.get("is_connected", False)),
    }


def _extract_orb_inputs(state: Dict[str, Any]) -> Dict[str, Any]:
    levels = state.get("levels") if isinstance(state.get("levels"), dict) else {}
    orb_high = _to_float(state.get("orb_high", levels.get("orb_high")), 0.0)
    orb_low = _to_float(state.get("orb_low", levels.get("orb_low")), 0.0)
    price = _extract_price(state)
    range_size_pct = ((orb_high - orb_low) / price * 100.0) if price > 0 and orb_high > orb_low else 0.0
    breakout_side = str(state.get("breakout_side") or "").lower()
    if not breakout_side and price > 0 and orb_high > 0 and orb_low > 0:
        if price > orb_high:
            breakout_side = "up"
        elif price < orb_low:
            breakout_side = "down"
    displacement = bool(state.get("displacement_detected") or state.get("has_displacement"))
    fvg = bool(state.get("fvg_detected") or state.get("has_fvg"))
    return {
        "orb_high": orb_high,
        "orb_low": orb_low,
        "range_size_pct": round(range_size_pct, 3),
        "breakout_side": breakout_side,
        "displacement_detected": displacement,
        "fvg_detected": fvg,
        "fvg_size": _to_float(state.get("fvg_size"), 0.0),
    }


def _extract_liquidity_inputs(state: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "sweep_detected": bool(state.get("sweep_detected") or state.get("liquidity_sweep_detected")),
        "rejection_confirmed": bool(state.get("rejection_confirmed") or state.get("reversal_confirmed")),
        "sweep_side": str(state.get("sweep_side") or state.get("sweep_direction") or ""),
        "liquidity_level": _to_float(state.get("liquidity_level"), 0.0),
    }


def _extract_keltner_inputs(state: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "squeeze_on": bool(state.get("squeeze_on") or state.get("squeeze_active")),
        "squeeze_fired": bool(state.get("squeeze_fired") or state.get("breakout_confirmed")),
        "adx_value": _to_float(state.get("adx") or state.get("adx_value"), 0.0),
        "trend_ok": bool(state.get("trend_ok", False)),
        "momentum_ok": bool(state.get("momentum_ok", False)),
    }


def _extract_step_inputs(strategy_id: str, state: Dict[str, Any]) -> Dict[str, Any]:
    step_inputs = _extract_common_inputs(state)
    if _is_orb_strategy(strategy_id):
        step_inputs.update(_extract_orb_inputs(state))
    if _is_liquidity_strategy(strategy_id):
        step_inputs.update(_extract_liquidity_inputs(state))
    if _is_keltner_strategy(strategy_id):
        step_inputs.update(_extract_keltner_inputs(state))
    return step_inputs


def _compute_signals(strategy_id: str, step_inputs: Dict[str, Any], state: Dict[str, Any], telemetry_ok: bool) -> Dict[str, bool]:
    setup_detected = bool(step_inputs.get("setup_detected", False))
    risk_defined = step_inputs.get("suggested_sl", 0.0) > 0.0
    invalidation_reason = str(step_inputs.get("invalidation_reason") or "")
    ml_probability = _to_float(state.get("ml_probability"), -1.0)
    ml_threshold = _to_float(state.get("ml_threshold"), 0.55)
    ml_pass = (ml_probability >= 0.0 and ml_probability >= ml_threshold)

    signals = {
        "telemetry_available": telemetry_ok,
        "telemetry_missing": not telemetry_ok,
        "has_orb_range": step_inputs.get("orb_high", 0.0) > step_inputs.get("orb_low", 0.0) > 0.0,
        "bias_ok": _to_int(step_inputs.get("bias_strength"), 0) >= 40,
        "bias_conflict": str(step_inputs.get("bias", "neutral")).lower() == "neutral",
        "breakout_detected": bool(step_inputs.get("breakout_side")),
        "fvg_confirmed": bool(step_inputs.get("displacement_detected")) and bool(step_inputs.get("fvg_detected")),
        "sweep_detected": bool(step_inputs.get("sweep_detected")),
        "rejection_confirmed": bool(step_inputs.get("rejection_confirmed")),
        "squeeze_on": bool(step_inputs.get("squeeze_on")),
        "squeeze_fired": bool(step_inputs.get("squeeze_fired")),
        "trend_ok": bool(step_inputs.get("trend_ok")),
        "momentum_ok": bool(step_inputs.get("momentum_ok")),
        "adx_ok": _to_float(step_inputs.get("adx_value"), 0.0) >= 20.0,
        "setup_detected": setup_detected,
        "risk_defined": risk_defined,
        "setup_invalidated": bool(invalidation_reason),
        "review_ready": bool(state.get("last_closed_trade") or state.get("last_trade_result")),
        "review_blocked": False,
        "ml_pass": ml_pass,
        "ml_fail": (ml_probability >= 0.0 and not ml_pass),
    }

    # If strategy isn't an ML wrapper, ML gate should not block.
    if not strategy_id.endswith("_ml_strategy"):
        signals["ml_pass"] = True
        signals["ml_fail"] = False
    if not _is_orb_strategy(strategy_id):
        signals["has_orb_range"] = True
        signals["breakout_detected"] = signals["setup_detected"]
        signals["fvg_confirmed"] = signals["setup_detected"]
    if not _is_liquidity_strategy(strategy_id):
        signals["sweep_detected"] = signals["setup_detected"]
        signals["rejection_confirmed"] = signals["setup_detected"]
    if not _is_keltner_strategy(strategy_id):
        signals["squeeze_on"] = signals["setup_detected"]
        signals["squeeze_fired"] = signals["setup_detected"]
        signals["trend_ok"] = True
        signals["momentum_ok"] = True
        signals["adx_ok"] = True
    return signals


def _build_explanations(state: Dict[str, Any], signals: Dict[str, bool], telemetry_ok: bool) -> list[str]:
    notes: list[str] = []
    if not telemetry_ok:
        notes.append("Live strategy telemetry unavailable; fallback to WAIT.")
    if signals.get("setup_invalidated"):
        reason = state.get("invalidation_reason") or "invalidation condition triggered"
        notes.append(f"Setup invalidated: {reason}")
    if signals.get("ml_fail"):
        notes.append("ML probability is below threshold.")
    return notes


def load_strategy_state(strategy_id: str) -> Tuple[Dict[str, Any], bool]:
    """Read current strategy state from StrategyManager if available."""
    try:
        from Strategies.strategy_manager import StrategyManager

        manager = StrategyManager()
        state = manager.get_strategy_state(strategy_id) or {}
        status = manager.get_strategy_status(strategy_id)
        if "status" not in state:
            state["status"] = status
        return state, True
    except Exception as exc:
        return {"status": "unavailable", "error": str(exc)}, False


def build_telemetry(strategy_id: str, symbol: str, timeframe: str, mode: str = "demo") -> Dict[str, Any]:
    state, ok = load_strategy_state(strategy_id)
    step_inputs = _extract_step_inputs(strategy_id, state)
    signals = _compute_signals(strategy_id, step_inputs, state, ok)
    explanations = _build_explanations(state, signals, ok)

    is_connected = bool(state.get("is_connected", ok))
    open_positions = _to_int(state.get("open_positions"), 0)
    daily_pnl = _to_float(state.get("daily_pnl"), 0.0)

    telemetry = {
        "strategy_id": strategy_id,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "mode": mode if mode in ("demo", "live") else "demo",
        "market": {
            "symbol": symbol,
            "timeframe": timeframe,
            "price": _extract_price(state),
            "spread": _extract_spread(state),
        },
        "risk": {
            "can_trade": is_connected and not signals.get("setup_invalidated", False),
            "daily_trades": _to_int(state.get("daily_trades"), 0),
            "daily_pnl": daily_pnl,
            "open_positions": open_positions,
        },
        "step_inputs": step_inputs,
        "signals": signals,
        "explanations": explanations,
        "telemetry_available": ok,
        "raw_state": state,
    }
    return telemetry
