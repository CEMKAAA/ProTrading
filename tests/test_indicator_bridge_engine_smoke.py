from __future__ import annotations

import threading
import time
from datetime import datetime, timezone
from typing import Any, Dict, List

from dashboard.backend.models.database import SessionLocal, TelegramAutomationExecutionLogModel
from dashboard.backend.services.telegram_bridge_service import TelegramBridgeService


class _FakeBridgeBroker:
    def __init__(self) -> None:
        self._lock = threading.RLock()
        self._positions: Dict[int, Dict[str, Any]] = {}
        self._next_ticket = 900001
        self._next_order = 800001
        self._next_deal = 700001
        self._ask = 71700.20
        self._bid = 71700.00
        self._transient_hide_count = 0

    def set_tick(self, *, ask: float, bid: float) -> None:
        with self._lock:
            self._ask = float(ask)
            self._bid = float(bid)

    def hide_positions_once(self, *, count: int = 1) -> None:
        with self._lock:
            self._transient_hide_count = int(max(0, count))

    def get_symbol_info(self, *, symbol: str) -> Dict[str, Any]:
        return {
            "resolved_symbol": str(symbol),
            "digits": 2,
            "point": 0.01,
            "trade_stops_level": 0,
            "volume_min": 0.01,
            "volume_step": 0.01,
            "volume_max": 100.0,
        }

    def get_symbol_tick(self, *, symbol: str, resolve_symbol: bool = False) -> Dict[str, Any]:
        with self._lock:
            return {"ask": float(self._ask), "bid": float(self._bid), "last": (float(self._ask) + float(self._bid)) / 2.0}

    def get_recent_candles(
        self,
        *,
        symbol: str,
        timeframe: str,
        count: int,
        resolve_symbol: bool = False,
    ) -> List[Dict[str, Any]]:
        n = int(max(5, int(count or 5)))
        base = 71700.0
        out: List[Dict[str, Any]] = []
        for i in range(n):
            c = base + (i * 0.05)
            out.append(
                {
                    "time": i,
                    "open": c - 0.1,
                    "high": c + 0.2,
                    "low": c - 0.2,
                    "close": c,
                    "volume": 100.0,
                }
            )
        return out

    def place_market_order(
        self,
        *,
        symbol: str,
        direction: str,
        lot_size: float,
        stop_loss: float | None,
        take_profit: float | None,
        comment: str,
        magic: int | None = None,
    ) -> Dict[str, Any]:
        side = str(direction).strip().upper()
        if side not in {"BUY", "SELL"}:
            return {"ok": False, "error": "invalid_direction"}
        with self._lock:
            ticket = int(self._next_ticket)
            self._next_ticket += 1
            order = int(self._next_order)
            self._next_order += 1
            deal = int(self._next_deal)
            self._next_deal += 1
            entry_price = float(self._ask if side == "BUY" else self._bid)
            self._positions[int(ticket)] = {
                "ticket": int(ticket),
                "direction": str(side),
                "symbol": str(symbol),
                "entry_price": float(entry_price),
                "lot_size": float(lot_size),
                "stop_loss": (float(stop_loss) if stop_loss is not None else 0.0),
                "take_profit": (float(take_profit) if take_profit is not None else 0.0),
                "comment": str(comment or ""),
                "magic": int(magic or 0),
            }
        return {
            "ok": True,
            "position": int(ticket),
            "order": int(order),
            "deal": int(deal),
            "lot_size": float(lot_size),
        }

    def close_position(
        self,
        *,
        symbol: str,
        position_ticket: int,
        lot_size: float | None = None,
        comment: str | None = None,
    ) -> Dict[str, Any]:
        t = int(position_ticket or 0)
        with self._lock:
            row = dict(self._positions.get(int(t)) or {})
            if not row:
                return {"ok": False, "error": "position_not_found"}
            cur_lot = float(row.get("lot_size") or 0.0)
            close_lot = float(lot_size) if lot_size is not None else float(cur_lot)
            if close_lot <= 0.0:
                return {"ok": False, "error": "invalid_close_lot"}
            if close_lot >= cur_lot - 1e-12:
                self._positions.pop(int(t), None)
            else:
                row["lot_size"] = float(cur_lot - close_lot)
                self._positions[int(t)] = dict(row)
        return {"ok": True, "closed_lot": float(close_lot)}

    def modify_position_sl_tp(
        self,
        *,
        symbol: str,
        position_ticket: int,
        stop_loss: float | None = None,
        take_profit: float | None = None,
        comment: str | None = None,
    ) -> Dict[str, Any]:
        t = int(position_ticket or 0)
        with self._lock:
            row = dict(self._positions.get(int(t)) or {})
            if not row:
                return {"ok": False, "error": "position_not_found"}
            if stop_loss is not None:
                row["stop_loss"] = float(stop_loss)
            if take_profit is not None:
                row["take_profit"] = float(take_profit)
            self._positions[int(t)] = dict(row)
        return {"ok": True}

    def get_open_positions(self, *, symbol: str) -> List[Dict[str, Any]]:
        sym = str(symbol).strip().upper()
        with self._lock:
            if self._transient_hide_count > 0:
                self._transient_hide_count -= 1
                return []
            rows = [dict(v) for v in self._positions.values() if str(v.get("symbol") or "").strip().upper() == sym]
            ask = float(self._ask)
            bid = float(self._bid)
        out: List[Dict[str, Any]] = []
        for r in rows:
            side = str(r.get("direction") or "").strip().upper()
            entry = float(r.get("entry_price") or 0.0)
            lot = float(r.get("lot_size") or 0.0)
            cur = float(bid if side == "BUY" else ask)
            pnl = float((cur - entry) * lot) if side == "BUY" else float((entry - cur) * lot)
            out.append(
                {
                    "ticket": int(r.get("ticket") or 0),
                    "direction": str(side),
                    "symbol": str(r.get("symbol") or ""),
                    "entry_price": float(entry),
                    "current_price": float(cur),
                    "lot_size": float(lot),
                    "stop_loss": float(r.get("stop_loss") or 0.0),
                    "take_profit": float(r.get("take_profit") or 0.0),
                    "profit_loss": float(pnl),
                    "comment": str(r.get("comment") or ""),
                }
            )
        return out


def _build_service(
    monkeypatch,
    *,
    terminal_family: str = "mt4",
    mode_advanced: bool = True,
    mode_normal: bool = True,
    signal_confirm_sec: float = 0.0,
):
    svc = TelegramBridgeService()
    fam = str(terminal_family).strip().lower() or "mt4"
    broker = _FakeBridgeBroker()
    svc._live_service = broker
    monkeypatch.setattr(svc, "_mt4_exec_enabled", lambda: True)
    monkeypatch.setattr(svc, "_mt4_exec_profile_enabled", lambda profile: True)
    monkeypatch.setattr(svc, "_indicator_reversal_confirm_sec", lambda: 0.20)
    monkeypatch.setattr(
        svc,
        "_resolve_indicator_bridge_instance_runtime_config",
        lambda **kwargs: {
            "terminal_family": str(fam),
            "indicator": "Intrepid Trend Direction",
            "symbol": "BTCUSDM",
            "timeframe": "M1",
            "instance_key": f"{str(fam)}|intrepid trend direction|BTCUSDM|M1",
            "automation_enabled": True,
            "effective_automation_enabled": True,
            "lot_size": 0.5,
            "execution_modes": {
                "advanced": bool(mode_advanced),
                "normal": bool(mode_normal),
                "sync": False,
            },
            "mode_lots": {
                "advanced": 0.5,
                "advanced_v2": 0.5,
                "normal": 0.4,
                "sync": 0.1,
            },
            "signal_confirm_sec": float(signal_confirm_sec),
            "sync": {
                "direction_tf": "M5",
                "entry_tf": "M1",
                "exit_tf": "M1",
                "reentry_enabled": True,
            },
        },
    )
    return svc, broker


def _payload(*, hint: str, message: str, event_ts: str | None = None) -> Dict[str, Any]:
    return {
        "indicator": r"IntrepidIndicator\Intrepid Trend Direction",
        "signal_profile": "intrepid",
        "signal_hint": str(hint).upper(),
        "symbol": "BTCUSDm",
        "timeframe": "M1",
        "message": str(message),
        "event_ts": str(event_ts or datetime.now(timezone.utc).isoformat()),
        "bridge_event_type": "signal",
        "ingest_source": "bridge",
    }


def _cleanup_execution_logs_for_tickets(*tickets: int) -> None:
    clean = [int(t) for t in tickets if int(t or 0) > 0]
    if not clean:
        return
    db = SessionLocal()
    try:
        (
            db.query(TelegramAutomationExecutionLogModel)
            .filter(TelegramAutomationExecutionLogModel.ticket.in_(clean))
            .delete(synchronize_session=False)
        )
        db.commit()
    finally:
        db.close()


def test_signatics_level_update_only_modifies_latest_matching_open_trade(monkeypatch):
    svc, broker = _build_service(monkeypatch)
    monkeypatch.setattr(svc, "_append_automation_execution_log", lambda **kwargs: None)
    broker.set_tick(ask=4335.20, bid=4335.00)

    first = broker.place_market_order(
        symbol="XAUUSDM",
        direction="SELL",
        lot_size=0.10,
        stop_loss=4350.0,
        take_profit=4300.0,
        comment="older",
    )
    second = broker.place_market_order(
        symbol="XAUUSDM",
        direction="SELL",
        lot_size=0.10,
        stop_loss=4348.0,
        take_profit=4298.0,
        comment="latest",
    )
    first_ticket = int(first["position"])
    second_ticket = int(second["position"])
    now = datetime.now(timezone.utc)
    with svc._lock:
        svc._active_confirmation_signal_ladders = {
            f"old:{first_ticket}": {
                "profile": "signatics",
                "symbol": "XAUUSDM",
                "timeframe": "M1",
                "direction": "SELL",
                "broker_ticket": first_ticket,
                "created_at": "2026-06-08T17:00:00+00:00",
                "entry_price": 4335.0,
                "initial_stop_loss": 4350.0,
                "broker_take_profit": 4300.0,
                "highest_tp_reached": 0,
                "half_be_done": False,
            },
            f"new:{second_ticket}": {
                "profile": "signatics",
                "symbol": "XAUUSDM",
                "timeframe": "M1",
                "direction": "SELL",
                "broker_ticket": second_ticket,
                "created_at": now.isoformat(),
                "entry_price": 4335.0,
                "initial_stop_loss": 4348.0,
                "broker_take_profit": 4298.0,
                "highest_tp_reached": 0,
                "half_be_done": False,
            },
        }

    out = svc._handle_signatics_level_update(
        family="mt4",
        profile="signatics",
        indicator="SIGNATICS-ALGO V2 (2) [Buffer]",
        symbol="XAUUSDM",
        timeframe="M1",
        direction="SELL",
        payload={
            "secondary_entry": 4335.0,
            "secondary_stop_loss": 4355.0,
            "secondary_tp1": 4320.0,
            "secondary_tp2": 4305.0,
            "secondary_tp3": 4290.0,
            "signatics_source": "SA_SL_1",
        },
        event_ts=now.isoformat(),
    )

    assert out["updated_count"] == 1
    assert int(out["updated"][0]["ticket"]) == second_ticket
    with broker._lock:
        assert broker._positions[first_ticket]["stop_loss"] == 4350.0
        assert broker._positions[first_ticket]["take_profit"] == 4300.0
        assert broker._positions[second_ticket]["stop_loss"] == 4355.0
        assert broker._positions[second_ticket]["take_profit"] == 4290.0


def test_smoke_bridge_listener_register_and_signal_flow(monkeypatch):
    svc, broker = _build_service(monkeypatch)
    try:
        out_register = svc.ingest_indicator_bridge_signal(
            terminal_family="mt4",
            payload={
                "indicator": "Intrepid Trend Direction",
                "signal_profile": "intrepid",
                "symbol": "BTCUSDm",
                "timeframe": "M1",
                "bridge_event_type": "register",
                "ingest_source": "bridge",
            },
        )
        assert out_register.get("ok") is True
        assert out_register.get("executed") is False

        out_signal = svc.ingest_indicator_bridge_signal(
            terminal_family="mt4",
            payload=_payload(hint="SELL", message="SMOKE SELL 1"),
        )
        assert out_signal.get("ok") is True
        assert out_signal.get("executed") is True
        open_rows = broker.get_open_positions(symbol="BTCUSDm")
        # advanced(0.5) + normal(0.4)
        assert len(open_rows) == 2
        assert {str(r.get("direction")) for r in open_rows} == {"SELL"}
    finally:
        svc.stop()


def test_smoke_bridge_v2_confirmed_signal_bypasses_backend_wait(monkeypatch):
    svc, broker = _build_service(monkeypatch, signal_confirm_sec=20.0)
    try:
        payload = _payload(hint="SELL", message="V2 CONFIRMED SELL")
        payload["bridge_event_type"] = "confirmed_signal"
        payload["bridge_version"] = "v2"
        payload["confirmed_direction"] = "SELL"
        out = svc.ingest_indicator_bridge_signal(terminal_family="mt4", payload=payload)
        assert out.get("ok") is True
        assert out.get("executed") is True
        open_rows = broker.get_open_positions(symbol="BTCUSDm")
        assert len(open_rows) == 2
        assert {str(r.get("direction")) for r in open_rows} == {"SELL"}
    finally:
        svc.stop()


def test_smoke_bridge_v2_confirmed_signal_requires_resolved_direction_when_supplied(monkeypatch):
    svc, broker = _build_service(monkeypatch, signal_confirm_sec=20.0)
    try:
        payload = _payload(hint="BUY", message="V2 CONFIRMED BUY WITH NONE RESOLVED")
        payload["bridge_event_type"] = "confirmed_signal"
        payload["bridge_version"] = "v2"
        payload["confirmed_direction"] = "BUY"
        payload["resolved_signal"] = "NONE"
        out = svc.ingest_indicator_bridge_signal(terminal_family="mt4", payload=payload)
        assert out.get("ok") is True
        assert out.get("executed") is False
        assert out.get("reason") == "confirmed_signal_without_resolved_direction"
        assert broker.get_open_positions(symbol="BTCUSDm") == []

        mismatch = dict(payload)
        mismatch["resolved_signal"] = "SELL"
        out_mismatch = svc.ingest_indicator_bridge_signal(terminal_family="mt4", payload=mismatch)
        assert out_mismatch.get("ok") is True
        assert out_mismatch.get("executed") is False
        assert out_mismatch.get("reason") == "confirmed_signal_resolved_mismatch"
        assert broker.get_open_positions(symbol="BTCUSDm") == []
    finally:
        svc.stop()


def test_smoke_bridge_v2_resolved_state_corrects_stuck_reverse(monkeypatch):
    svc, broker = _build_service(monkeypatch, signal_confirm_sec=20.0)
    try:
        sell_payload = _payload(hint="SELL", message="V2 CONFIRMED SELL FIRST")
        sell_payload["bridge_event_type"] = "confirmed_signal"
        sell_payload["bridge_version"] = "v2"
        sell_payload["confirmed_direction"] = "SELL"
        first = svc.ingest_indicator_bridge_signal(terminal_family="mt4", payload=sell_payload)
        assert first.get("ok") is True
        assert first.get("executed") is True
        assert {str(r.get("direction")) for r in broker.get_open_positions(symbol="BTCUSDm")} == {"SELL"}

        state_payload = {
            "indicator": r"IntrepidIndicator\Intrepid Trend Direction",
            "signal_profile": "intrepid",
            "signal_hint": "BUY",
            "symbol": "BTCUSDm",
            "timeframe": "M1",
            "message": "V2 RESOLVED STATE BUY",
            "event_ts": datetime.now(timezone.utc).isoformat(),
            "bridge_event_type": "resolved_state",
            "bridge_version": "v2",
            "confirmed_direction": "BUY",
            "pending_direction": "",
            "ingest_source": "bridge",
        }
        rec = svc.ingest_indicator_bridge_signal(terminal_family="mt4", payload=state_payload)
        assert rec.get("ok") is True
        reconcile = dict(rec.get("reconcile") or {})
        assert reconcile.get("reason") == "conflict_forwarded_as_confirmed_signal"
        assert {str(r.get("direction")) for r in broker.get_open_positions(symbol="BTCUSDm")} == {"BUY"}
    finally:
        svc.stop()


def test_smoke_bridge_v2_resolved_state_does_not_reconcile_while_pending(monkeypatch):
    svc, broker = _build_service(monkeypatch, signal_confirm_sec=0.0)
    try:
        sell_payload = _payload(hint="SELL", message="V2 CONFIRMED SELL PENDING TEST")
        sell_payload["bridge_event_type"] = "confirmed_signal"
        sell_payload["bridge_version"] = "v2"
        sell_payload["confirmed_direction"] = "SELL"
        first = svc.ingest_indicator_bridge_signal(terminal_family="mt4", payload=sell_payload)
        assert first.get("executed") is True
        state_payload = {
            "indicator": r"IntrepidIndicator\Intrepid Trend Direction",
            "signal_profile": "intrepid",
            "signal_hint": "BUY",
            "symbol": "BTCUSDm",
            "timeframe": "M1",
            "bridge_event_type": "resolved_state",
            "bridge_version": "v2",
            "confirmed_direction": "BUY",
            "pending_direction": "BUY",
            "ingest_source": "bridge",
        }
        rec = svc.ingest_indicator_bridge_signal(terminal_family="mt4", payload=state_payload)
        assert rec.get("ok") is True
        assert dict(rec.get("reconcile") or {}).get("reason") == "pending_signal_in_progress"
        assert {str(r.get("direction")) for r in broker.get_open_positions(symbol="BTCUSDm")} == {"SELL"}
    finally:
        svc.stop()


def test_smoke_bridge_v2_secondary_governor_waits_for_agreement(monkeypatch):
    svc, broker = _build_service(monkeypatch, signal_confirm_sec=0.0)
    try:
        payload = _payload(hint="SELL", message="SECONDARY GOV SELL WAIT")
        payload.update(
            {
                "bridge_event_type": "confirmed_signal",
                "bridge_version": "v2",
                "secondary_enabled": True,
                "secondary_governor_enabled": True,
                "secondary_signal": "BUY",
            }
        )
        wait_out = svc.ingest_indicator_bridge_signal(terminal_family="mt4", payload=payload)
        assert wait_out.get("ok") is True
        assert wait_out.get("executed") is False
        assert str(wait_out.get("reason") or "") == "secondary_governor_waiting_direction_mismatch"
        assert len(broker.get_open_positions(symbol="BTCUSDm")) == 0

        state_payload = {
            "indicator": r"IntrepidIndicator\Intrepid Trend Direction",
            "signal_profile": "intrepid",
            "signal_hint": "SELL",
            "symbol": "BTCUSDm",
            "timeframe": "M1",
            "bridge_event_type": "resolved_state",
            "bridge_version": "v2",
            "resolved_signal": "SELL",
            "confirmed_direction": "SELL",
            "pending_direction": "",
            "secondary_enabled": True,
            "secondary_governor_enabled": True,
            "secondary_signal": "SELL",
            "ingest_source": "bridge",
        }
        rec = svc.ingest_indicator_bridge_signal(terminal_family="mt4", payload=state_payload)
        assert rec.get("ok") is True
        assert dict(rec.get("reconcile") or {}).get("reason") == "secondary_governor_agreement_forwarded_as_confirmed_signal"
        open_rows = broker.get_open_positions(symbol="BTCUSDm")
        assert len(open_rows) == 2
        assert {str(r.get("direction")) for r in open_rows} == {"SELL"}
    finally:
        svc.stop()


def test_smoke_bridge_v2_secondary_governor_closes_on_secondary_reverse(monkeypatch):
    svc, broker = _build_service(monkeypatch, signal_confirm_sec=0.0)
    try:
        payload = _payload(hint="SELL", message="SECONDARY GOV SELL OPEN")
        payload.update(
            {
                "bridge_event_type": "confirmed_signal",
                "bridge_version": "v2",
                "secondary_enabled": True,
                "secondary_governor_enabled": True,
                "secondary_signal": "SELL",
            }
        )
        opened = svc.ingest_indicator_bridge_signal(terminal_family="mt4", payload=payload)
        assert opened.get("executed") is True
        assert len(broker.get_open_positions(symbol="BTCUSDm")) == 2

        reverse_state = {
            "indicator": r"IntrepidIndicator\Intrepid Trend Direction",
            "signal_profile": "intrepid",
            "signal_hint": "SELL",
            "symbol": "BTCUSDm",
            "timeframe": "M1",
            "bridge_event_type": "resolved_state",
            "bridge_version": "v2",
            "resolved_signal": "SELL",
            "confirmed_direction": "SELL",
            "pending_direction": "",
            "secondary_enabled": True,
            "secondary_governor_enabled": True,
            "secondary_signal": "BUY",
            "ingest_source": "bridge",
        }
        closed = svc.ingest_indicator_bridge_signal(terminal_family="mt4", payload=reverse_state)
        assert closed.get("ok") is True
        assert dict(closed.get("reconcile") or {}).get("reason") == "secondary_governor_waiting_direction_mismatch"
        assert int((closed.get("secondary_governor_close") or {}).get("closed_count") or 0) == 2
        assert len(broker.get_open_positions(symbol="BTCUSDm")) == 0

        aligned_again = dict(reverse_state)
        aligned_again["secondary_signal"] = "SELL"
        reopened = svc.ingest_indicator_bridge_signal(terminal_family="mt4", payload=aligned_again)
        assert reopened.get("ok") is True
        assert dict(reopened.get("reconcile") or {}).get("reason") == "secondary_governor_agreement_forwarded_as_confirmed_signal"
        assert len(broker.get_open_positions(symbol="BTCUSDm")) == 2
        assert {str(r.get("direction")) for r in broker.get_open_positions(symbol="BTCUSDm")} == {"SELL"}
    finally:
        svc.stop()


def test_smoke_bridge_v2_secondary_entry_gate_waits_without_secondary_exit(monkeypatch):
    svc, broker = _build_service(monkeypatch, signal_confirm_sec=0.0)
    try:
        payload = _payload(hint="SELL", message="SECONDARY ENTRY GATE SELL WAIT")
        payload.update(
            {
                "bridge_event_type": "confirmed_signal",
                "bridge_version": "v2",
                "secondary_enabled": True,
                "secondary_entry_gate_enabled": True,
                "secondary_signal": "BUY",
            }
        )
        wait_out = svc.ingest_indicator_bridge_signal(terminal_family="mt4", payload=payload)
        assert wait_out.get("ok") is True
        assert wait_out.get("executed") is False
        assert str(wait_out.get("reason") or "") == "secondary_entry_gate_waiting_direction_mismatch"
        assert len(broker.get_open_positions(symbol="BTCUSDm")) == 0

        state_payload = {
            "indicator": r"IntrepidIndicator\Intrepid Trend Direction",
            "signal_profile": "intrepid",
            "signal_hint": "SELL",
            "symbol": "BTCUSDm",
            "timeframe": "M1",
            "bridge_event_type": "resolved_state",
            "bridge_version": "v2",
            "resolved_signal": "SELL",
            "confirmed_direction": "SELL",
            "pending_direction": "",
            "secondary_enabled": True,
            "secondary_entry_gate_enabled": True,
            "secondary_signal": "SELL",
            "ingest_source": "bridge",
        }
        opened = svc.ingest_indicator_bridge_signal(terminal_family="mt4", payload=state_payload)
        assert opened.get("ok") is True
        assert dict(opened.get("reconcile") or {}).get("reason") == "secondary_entry_gate_agreement_forwarded_as_confirmed_signal"
        assert len(broker.get_open_positions(symbol="BTCUSDm")) == 2

        secondary_reverse = dict(state_payload)
        secondary_reverse["secondary_signal"] = "BUY"
        blocked = svc.ingest_indicator_bridge_signal(terminal_family="mt4", payload=secondary_reverse)
        assert blocked.get("ok") is True
        assert dict(blocked.get("reconcile") or {}).get("reason") == "secondary_entry_gate_waiting_direction_mismatch"
        # Entry-gate mode must not close the existing SELL just because secondary flipped.
        assert len(broker.get_open_positions(symbol="BTCUSDm")) == 2
        assert {str(r.get("direction")) for r in broker.get_open_positions(symbol="BTCUSDm")} == {"SELL"}

        main_reverse = dict(state_payload)
        main_reverse["signal_hint"] = "BUY"
        main_reverse["resolved_signal"] = "BUY"
        main_reverse["confirmed_direction"] = "BUY"
        main_reverse["secondary_signal"] = "SELL"
        closed = svc.ingest_indicator_bridge_signal(terminal_family="mt4", payload=main_reverse)
        assert closed.get("ok") is True
        rec = dict(closed.get("reconcile") or {})
        assert rec.get("reason") == "secondary_entry_gate_waiting_direction_mismatch"
        assert rec.get("corrected") is True
        assert int((rec.get("close_result") or {}).get("closed_count") or 0) == 2
        # Main reverse must close stale positions even when secondary blocks the new entry.
        assert len(broker.get_open_positions(symbol="BTCUSDm")) == 0
    finally:
        svc.stop()


def test_smoke_bridge_v2_secondary_entry_gate_uses_arrow_resolved_signal(monkeypatch):
    svc, broker = _build_service(monkeypatch, signal_confirm_sec=0.0)
    try:
        state_payload = {
            "indicator": r"IntrepidIndicator\Intrepid Trend Direction",
            "signal_profile": "intrepid",
            "signal_hint": "SELL",
            "symbol": "BTCUSDm",
            "timeframe": "M1",
            "bridge_event_type": "resolved_state",
            "bridge_version": "v2",
            "resolved_signal": "SELL",
            "confirmed_direction": "SELL",
            "pending_direction": "",
            "secondary_enabled": True,
            "secondary_entry_gate_enabled": True,
            "secondary_raw_signal": "NONE",
            "secondary_signal": "SELL",
            "secondary_resolved_signal": "SELL",
            "ingest_source": "bridge",
        }
        opened = svc.ingest_indicator_bridge_signal(terminal_family="mt4", payload=state_payload)
        assert opened.get("ok") is True
        assert dict(opened.get("reconcile") or {}).get("reason") == "secondary_entry_gate_agreement_forwarded_as_confirmed_signal"
        assert len(broker.get_open_positions(symbol="BTCUSDm")) == 2
        assert {str(r.get("direction")) for r in broker.get_open_positions(symbol="BTCUSDm")} == {"SELL"}
    finally:
        svc.stop()


def test_smoke_bridge_v2_secondary_entry_gate_optional_none_timeout_closes(monkeypatch):
    svc, broker = _build_service(monkeypatch, signal_confirm_sec=0.0)
    try:
        monkeypatch.setattr(svc, "get_indicator_bridge_dual_gate_settings", lambda: {"none_close_enabled": True})
        state_payload = {
            "indicator": r"IntrepidIndicator\Intrepid Trend Direction",
            "signal_profile": "intrepid",
            "signal_hint": "SELL",
            "symbol": "BTCUSDm",
            "timeframe": "M1",
            "bridge_event_type": "resolved_state",
            "bridge_version": "v2",
            "resolved_signal": "SELL",
            "confirmed_direction": "SELL",
            "pending_direction": "",
            "confirm_seconds": 0,
            "secondary_enabled": True,
            "secondary_entry_gate_enabled": True,
            "secondary_signal": "SELL",
            "secondary_resolved_signal": "SELL",
            "ingest_source": "bridge",
        }
        opened = svc.ingest_indicator_bridge_signal(terminal_family="mt4", payload=state_payload)
        assert opened.get("ok") is True
        assert dict(opened.get("reconcile") or {}).get("reason") == "secondary_entry_gate_agreement_forwarded_as_confirmed_signal"
        assert len(broker.get_open_positions(symbol="BTCUSDm")) == 2

        none_state = dict(state_payload)
        none_state["signal_hint"] = ""
        none_state["resolved_signal"] = "NONE"
        none_state["confirmed_direction"] = ""
        none_state["secondary_signal"] = "NONE"
        none_state["secondary_resolved_signal"] = "SELL"
        closed = svc.ingest_indicator_bridge_signal(terminal_family="mt4", payload=none_state)
        assert closed.get("ok") is True
        rec = dict(closed.get("reconcile") or {})
        assert rec.get("reason") == "resolved_none_timeout_close"
        assert int((rec.get("close_result") or {}).get("closed_count") or 0) == 2
        assert broker.get_open_positions(symbol="BTCUSDm") == []
    finally:
        svc.stop()


def test_smoke_bridge_reverse_close_then_guard_replay_reopens(monkeypatch):
    svc, broker = _build_service(monkeypatch, signal_confirm_sec=0.20)
    try:
        first = svc.ingest_indicator_bridge_signal(
            terminal_family="mt4",
            payload=_payload(hint="SELL", message="SMOKE SELL A"),
        )
        assert first.get("ok") is True
        assert first.get("executed") is False
        assert str(first.get("reason") or "") == "reversal_guard_waiting"
        assert len(broker.get_open_positions(symbol="BTCUSDm")) == 0

        # Replay first direction after wait window.
        deadline0 = time.time() + 1.2
        opened_sell = broker.get_open_positions(symbol="BTCUSDm")
        while len(opened_sell) < 2 and time.time() < deadline0:
            time.sleep(0.05)
            opened_sell = broker.get_open_positions(symbol="BTCUSDm")
        if len(opened_sell) < 2:
            replay_first = dict(_payload(hint="SELL", message="SMOKE SELL A"))
            replay_first["__guard_replay"] = True
            first_replay = svc.ingest_indicator_bridge_signal(
                terminal_family="mt4",
                payload=replay_first,
            )
            assert first_replay.get("ok") is True
            deadline0b = time.time() + 0.8
            opened_sell = broker.get_open_positions(symbol="BTCUSDm")
            while len(opened_sell) < 2 and time.time() < deadline0b:
                time.sleep(0.05)
                opened_sell = broker.get_open_positions(symbol="BTCUSDm")
        assert len(opened_sell) == 2
        assert {str(r.get("direction")) for r in opened_sell} == {"SELL"}

        second = svc.ingest_indicator_bridge_signal(
            terminal_family="mt4",
            payload=_payload(hint="BUY", message="SMOKE BUY B"),
        )
        assert second.get("ok") is True
        assert second.get("executed") is False
        assert str(second.get("reason") or "") == "reversal_guard_waiting"
        # Reverse close should be immediate.
        assert len(broker.get_open_positions(symbol="BTCUSDm")) == 0

        # Worker replay may open automatically; if not, trigger deterministic replay.
        deadline = time.time() + 1.2
        reopened = broker.get_open_positions(symbol="BTCUSDm")
        while len(reopened) < 2 and time.time() < deadline:
            time.sleep(0.05)
            reopened = broker.get_open_positions(symbol="BTCUSDm")
        if len(reopened) < 2:
            replay_payload = dict(_payload(hint="BUY", message="SMOKE BUY B"))
            replay_payload["__guard_replay"] = True
            third = svc.ingest_indicator_bridge_signal(
                terminal_family="mt4",
                payload=replay_payload,
            )
            assert third.get("ok") is True
            assert (
                bool(third.get("executed"))
                or str(third.get("reason") or "") == "same_direction_already_open"
                or any(str((x or {}).get("reason") or "") == "same_direction_already_open" for x in (third.get("mode_results") or []))
            )
            deadline2 = time.time() + 0.8
            reopened = broker.get_open_positions(symbol="BTCUSDm")
            while len(reopened) < 2 and time.time() < deadline2:
                time.sleep(0.05)
                reopened = broker.get_open_positions(symbol="BTCUSDm")

        assert len(reopened) == 2
        assert {str(r.get("direction")) for r in reopened} == {"BUY"}
    finally:
        svc.stop()


def test_smoke_bridge_parallel_burst_does_not_duplicate_same_mode_positions(monkeypatch):
    svc, broker = _build_service(monkeypatch)
    try:
        barrier = threading.Barrier(3)
        out_rows: List[Dict[str, Any]] = []

        def _worker(msg: str) -> None:
            barrier.wait()
            out = svc.ingest_indicator_bridge_signal(
                terminal_family="mt4",
                payload=_payload(hint="SELL", message=msg),
            )
            out_rows.append(dict(out or {}))

        threads = [
            threading.Thread(target=_worker, args=(f"BURST SELL {i}",), daemon=True)
            for i in range(3)
        ]
        for t in threads:
            t.start()
        for t in threads:
            t.join(5.0)

        open_rows = broker.get_open_positions(symbol="BTCUSDm")
        # Never more than one live position per mode for same combo.
        assert len(open_rows) == 2
        assert {str(r.get("direction")) for r in open_rows} == {"SELL"}
        assert len(out_rows) == 3
    finally:
        svc.stop()


def test_smoke_transient_missing_position_not_marked_closed_immediately(monkeypatch):
    svc, broker = _build_service(monkeypatch, mode_advanced=True, mode_normal=False)
    try:
        monkeypatch.setattr(svc, "_confirm_ladder_missing_retries", lambda: 2)
        monkeypatch.setattr(svc, "_confirm_ladder_missing_grace_sec", lambda: 0.0)

        out = svc.ingest_indicator_bridge_signal(
            terminal_family="mt4",
            payload=_payload(hint="SELL", message="MISS SELL"),
        )
        assert out.get("executed") is True

        with svc._lock:
            keys = list(svc._active_confirmation_signal_ladders.keys())
        assert len(keys) == 1
        k0 = str(keys[0])

        # _push_confirmation_signal_ladders() performs an execution reconcile
        # pass before the ladder pass, so the fake transient miss must cover
        # both reads to exercise the ladder missing-position branch.
        broker.hide_positions_once(count=2)
        svc._push_confirmation_signal_ladders()
        with svc._lock:
            assert k0 in svc._active_confirmation_signal_ladders
            miss = int((svc._active_confirmation_signal_ladders.get(k0) or {}).get("missing_seen_count") or 0)
        assert miss == 1
    finally:
        svc.stop()


def test_smoke_mt5_bridge_listener_register_and_signal_flow(monkeypatch):
    svc, broker = _build_service(monkeypatch, terminal_family="mt5")
    try:
        out_register = svc.ingest_indicator_bridge_signal(
            terminal_family="mt5",
            payload={
                "indicator": "Intrepid Trend Direction",
                "signal_profile": "intrepid",
                "symbol": "BTCUSDm",
                "timeframe": "M1",
                "bridge_event_type": "register",
                "ingest_source": "bridge",
            },
        )
        assert out_register.get("ok") is True
        assert out_register.get("executed") is False

        out_signal = svc.ingest_indicator_bridge_signal(
            terminal_family="mt5",
            payload=_payload(hint="SELL", message="MT5 SMOKE SELL 1"),
        )
        assert out_signal.get("ok") is True
        assert out_signal.get("executed") is True
        open_rows = broker.get_open_positions(symbol="BTCUSDm")
        assert len(open_rows) == 2
        assert {str(r.get("direction")) for r in open_rows} == {"SELL"}
    finally:
        svc.stop()


def test_smoke_mt5_bridge_reverse_close_then_guard_replay_reopens(monkeypatch):
    svc, broker = _build_service(monkeypatch, terminal_family="mt5", signal_confirm_sec=0.20)
    try:
        first = svc.ingest_indicator_bridge_signal(
            terminal_family="mt5",
            payload=_payload(hint="SELL", message="MT5 SMOKE SELL A"),
        )
        assert first.get("ok") is True
        assert first.get("executed") is False
        assert str(first.get("reason") or "") == "reversal_guard_waiting"
        assert len(broker.get_open_positions(symbol="BTCUSDm")) == 0

        deadline0 = time.time() + 1.2
        opened_sell = broker.get_open_positions(symbol="BTCUSDm")
        while len(opened_sell) < 2 and time.time() < deadline0:
            time.sleep(0.05)
            opened_sell = broker.get_open_positions(symbol="BTCUSDm")
        if len(opened_sell) < 2:
            replay_first = dict(_payload(hint="SELL", message="MT5 SMOKE SELL A"))
            replay_first["__guard_replay"] = True
            first_replay = svc.ingest_indicator_bridge_signal(
                terminal_family="mt5",
                payload=replay_first,
            )
            assert first_replay.get("ok") is True
            deadline0b = time.time() + 0.8
            opened_sell = broker.get_open_positions(symbol="BTCUSDm")
            while len(opened_sell) < 2 and time.time() < deadline0b:
                time.sleep(0.05)
                opened_sell = broker.get_open_positions(symbol="BTCUSDm")
        assert len(opened_sell) == 2
        assert {str(r.get("direction")) for r in opened_sell} == {"SELL"}

        second = svc.ingest_indicator_bridge_signal(
            terminal_family="mt5",
            payload=_payload(hint="BUY", message="MT5 SMOKE BUY B"),
        )
        assert second.get("ok") is True
        assert second.get("executed") is False
        assert str(second.get("reason") or "") == "reversal_guard_waiting"
        assert len(broker.get_open_positions(symbol="BTCUSDm")) == 0

        deadline = time.time() + 1.2
        reopened = broker.get_open_positions(symbol="BTCUSDm")
        while len(reopened) < 2 and time.time() < deadline:
            time.sleep(0.05)
            reopened = broker.get_open_positions(symbol="BTCUSDm")
        if len(reopened) < 2:
            replay_payload = dict(_payload(hint="BUY", message="MT5 SMOKE BUY B"))
            replay_payload["__guard_replay"] = True
            third = svc.ingest_indicator_bridge_signal(
                terminal_family="mt5",
                payload=replay_payload,
            )
            assert third.get("ok") is True
            assert (
                bool(third.get("executed"))
                or str(third.get("reason") or "") == "same_direction_already_open"
                or any(str((x or {}).get("reason") or "") == "same_direction_already_open" for x in (third.get("mode_results") or []))
            )
            deadline2 = time.time() + 0.8
            reopened = broker.get_open_positions(symbol="BTCUSDm")
            while len(reopened) < 2 and time.time() < deadline2:
                time.sleep(0.05)
                reopened = broker.get_open_positions(symbol="BTCUSDm")

        assert len(reopened) == 2
        assert {str(r.get("direction")) for r in reopened} == {"BUY"}
    finally:
        svc.stop()


def test_smoke_mt5_bridge_parallel_burst_does_not_duplicate_same_mode_positions(monkeypatch):
    svc, broker = _build_service(monkeypatch, terminal_family="mt5")
    try:
        barrier = threading.Barrier(3)
        out_rows: List[Dict[str, Any]] = []

        def _worker(msg: str) -> None:
            barrier.wait()
            out = svc.ingest_indicator_bridge_signal(
                terminal_family="mt5",
                payload=_payload(hint="SELL", message=msg),
            )
            out_rows.append(dict(out or {}))

        threads = [
            threading.Thread(target=_worker, args=(f"MT5 BURST SELL {i}",), daemon=True)
            for i in range(3)
        ]
        for t in threads:
            t.start()
        for t in threads:
            t.join(5.0)

        open_rows = broker.get_open_positions(symbol="BTCUSDm")
        assert len(open_rows) == 2
        assert {str(r.get("direction")) for r in open_rows} == {"SELL"}
        assert len(out_rows) == 3
    finally:
        svc.stop()


def test_smoke_mt5_transient_missing_position_not_marked_closed_immediately(monkeypatch):
    svc, broker = _build_service(
        monkeypatch,
        terminal_family="mt5",
        mode_advanced=True,
        mode_normal=False,
    )
    try:
        monkeypatch.setattr(svc, "_confirm_ladder_missing_retries", lambda: 2)
        monkeypatch.setattr(svc, "_confirm_ladder_missing_grace_sec", lambda: 0.0)

        out = svc.ingest_indicator_bridge_signal(
            terminal_family="mt5",
            payload=_payload(hint="SELL", message="MT5 MISS SELL"),
        )
        assert out.get("executed") is True

        with svc._lock:
            keys = list(svc._active_confirmation_signal_ladders.keys())
        assert len(keys) == 1
        k0 = str(keys[0])

        # _push_confirmation_signal_ladders() performs an execution reconcile
        # pass before the ladder pass, so the fake transient miss must cover
        # both reads to exercise the ladder missing-position branch.
        broker.hide_positions_once(count=2)
        svc._push_confirmation_signal_ladders()
        with svc._lock:
            assert k0 in svc._active_confirmation_signal_ladders
            miss = int((svc._active_confirmation_signal_ladders.get(k0) or {}).get("missing_seen_count") or 0)
        assert miss == 1
    finally:
        svc.stop()


def test_smoke_signal_clear_cancels_pending_open(monkeypatch):
    svc, broker = _build_service(monkeypatch, signal_confirm_sec=0.35)
    try:
        first = svc.ingest_indicator_bridge_signal(
            terminal_family="mt4",
            payload=_payload(hint="BUY", message="SMOKE BUY WAIT"),
        )
        assert first.get("ok") is True
        assert first.get("executed") is False
        assert str(first.get("reason") or "") == "reversal_guard_waiting"
        assert len(broker.get_open_positions(symbol="BTCUSDm")) == 0

        clear_out = svc.ingest_indicator_bridge_signal(
            terminal_family="mt4",
            payload={
                "indicator": r"IntrepidIndicator\Intrepid Trend Direction",
                "signal_profile": "intrepid",
                "symbol": "BTCUSDm",
                "timeframe": "M1",
                "signal_hint": "NONE",
                "bridge_event_type": "signal_clear",
                "ingest_source": "bridge",
            },
        )
        assert clear_out.get("ok") is True
        assert clear_out.get("executed") is False
        assert str(clear_out.get("reason") or "") == "signal_cleared"
        assert int(clear_out.get("cleared_pending_count") or 0) >= 1

        # Wait longer than confirm window; open should stay canceled.
        deadline = time.time() + 1.2
        while time.time() < deadline:
            assert len(broker.get_open_positions(symbol="BTCUSDm")) == 0
            time.sleep(0.05)
    finally:
        svc.stop()


def test_smoke_advanced_v2_runner_stage_registered(monkeypatch):
    svc, broker = _build_service(monkeypatch, mode_advanced=False, mode_normal=False, signal_confirm_sec=0.0)
    try:
        monkeypatch.setattr(
            svc,
            "_resolve_indicator_bridge_instance_runtime_config",
            lambda **kwargs: {
                "terminal_family": "mt4",
                "indicator": "Intrepid Trend Direction",
                "symbol": "BTCUSDM",
                "timeframe": "M1",
                "instance_key": "mt4|intrepid trend direction|BTCUSDM|M1",
                "automation_enabled": True,
                "effective_automation_enabled": True,
                "lot_size": 0.5,
                "execution_modes": {
                    "advanced": False,
                    "advanced_v2": True,
                    "normal": False,
                    "sync": False,
                },
                "mode_lots": {
                    "advanced": 0.5,
                    "advanced_v2": 0.5,
                    "normal": 0.4,
                    "sync": 0.1,
                },
                "signal_confirm_sec": 0.0,
                "sync": {
                    "direction_tf": "M5",
                    "entry_tf": "M1",
                    "exit_tf": "M1",
                    "reentry_enabled": True,
                },
            },
        )
        out = svc.ingest_indicator_bridge_signal(
            terminal_family="mt4",
            payload=_payload(hint="SELL", message="SMOKE ADV2 SELL"),
        )
        assert out.get("ok") is True
        assert out.get("executed") is True
        open_rows = broker.get_open_positions(symbol="BTCUSDm")
        assert len(open_rows) == 1
        with svc._lock:
            ladders = [dict(v) for v in svc._active_confirmation_signal_ladders.values() if isinstance(v, dict)]
        assert len(ladders) == 1
        row = ladders[0]
        assert str(row.get("execution_mode") or "") == "advanced_v2"
        tps = list(row.get("tps") or [])
        assert len(tps) == 4
        assert (tps[-1] or {}).get("price") is None
    finally:
        svc.stop()


def test_smoke_v2_indicator_advanced_v2_policies_open_distinct_ladders(monkeypatch):
    svc, broker = _build_service(monkeypatch, mode_advanced=False, mode_normal=False, signal_confirm_sec=0.0)
    try:
        monkeypatch.setattr(
            svc,
            "_resolve_indicator_bridge_instance_runtime_config",
            lambda **kwargs: {
                "terminal_family": "mt4",
                "indicator": "Intrepid Trend Direction",
                "symbol": "BTCUSDM",
                "timeframe": "M1",
                "instance_key": "mt4|intrepid trend direction|BTCUSDM|M1",
                "automation_enabled": True,
                "effective_automation_enabled": True,
                "lot_size": 0.5,
                "execution_modes": {
                    "advanced": False,
                    "advanced_v2": True,
                    "normal": False,
                    "sync": False,
                },
                "advanced_v2_policies": {
                    "conservative": True,
                    "balanced": False,
                    "advanced": True,
                },
                "mode_lots": {
                    "advanced": 0.5,
                    "advanced_v2": 0.5,
                    "normal": 0.4,
                    "sync": 0.1,
                },
                "signal_confirm_sec": 0.0,
                "sync": {
                    "direction_tf": "M5",
                    "entry_tf": "M1",
                    "exit_tf": "M1",
                    "reentry_enabled": True,
                },
            },
        )
        payload = _payload(hint="SELL", message="V2 POLICY SELL")
        payload["bridge_event_type"] = "confirmed_signal"
        payload["bridge_version"] = "v2"
        payload["confirmed_direction"] = "SELL"
        out = svc.ingest_indicator_bridge_signal(terminal_family="mt4", payload=payload)
        assert out.get("ok") is True
        assert out.get("executed") is True
        assert len(broker.get_open_positions(symbol="BTCUSDm")) == 2
        with svc._lock:
            ladders = [dict(v) for v in svc._active_confirmation_signal_ladders.values() if isinstance(v, dict)]
        assert len(ladders) == 2
        assert {str((r.get("advanced_v2_cfg") or {}).get("policy")) for r in ladders} == {"conservative", "advanced"}
        assert {str(r.get("source_tag") or "").split("|")[-1] for r in ladders} == {
            "advanced_v2_conservative",
            "advanced_v2_advanced",
        }
    finally:
        svc.stop()


def test_smoke_v2_indicator_advanced_v2_conservative_moves_sl_to_be_on_tp1(monkeypatch):
    svc, broker = _build_service(monkeypatch, mode_advanced=False, mode_normal=False, signal_confirm_sec=0.0)
    try:
        monkeypatch.setattr(
            svc,
            "_resolve_indicator_bridge_instance_runtime_config",
            lambda **kwargs: {
                "terminal_family": "mt4",
                "indicator": "Intrepid Trend Direction",
                "symbol": "BTCUSDM",
                "timeframe": "M1",
                "instance_key": "mt4|intrepid trend direction|BTCUSDM|M1",
                "automation_enabled": True,
                "effective_automation_enabled": True,
                "lot_size": 0.5,
                "execution_modes": {
                    "advanced": False,
                    "advanced_v2": True,
                    "normal": False,
                    "sync": False,
                },
                "advanced_v2_policies": {
                    "conservative": True,
                    "balanced": False,
                    "advanced": False,
                },
                "mode_lots": {
                    "advanced": 0.5,
                    "advanced_v2": 0.5,
                    "normal": 0.4,
                    "sync": 0.1,
                },
                "signal_confirm_sec": 0.0,
                "sync": {
                    "direction_tf": "M5",
                    "entry_tf": "M1",
                    "exit_tf": "M1",
                    "reentry_enabled": True,
                },
            },
        )
        payload = _payload(hint="BUY", message="V2 CONS BUY")
        payload["bridge_event_type"] = "confirmed_signal"
        payload["bridge_version"] = "v2"
        payload["confirmed_direction"] = "BUY"
        out = svc.ingest_indicator_bridge_signal(terminal_family="mt4", payload=payload)
        assert out.get("ok") is True
        assert out.get("executed") is True
        with svc._lock:
            ladders = [dict(v) for v in svc._active_confirmation_signal_ladders.values() if isinstance(v, dict)]
        assert len(ladders) == 1
        row = ladders[0]
        ticket = int(row.get("broker_ticket") or 0)
        entry = float(row.get("entry_price") or 0.0)
        tp1 = float((row.get("tps") or [])[0].get("price"))
        broker.set_tick(ask=float(tp1 + 0.20), bid=float(tp1 + 0.10))
        svc._push_confirmation_signal_ladders()
        positions = broker.get_open_positions(symbol="BTCUSDm")
        pos = next((p for p in positions if int(p.get("ticket") or 0) == ticket), None)
        assert pos is not None
        assert float(pos.get("lot_size") or 0.0) < 0.5
        assert abs(float(pos.get("stop_loss") or 0.0) - float(entry)) <= 0.02
        with svc._lock:
            updated = next(dict(v) for v in svc._active_confirmation_signal_ladders.values() if int(v.get("broker_ticket") or 0) == ticket)
        assert int(updated.get("last_sl_update_tp_index") or 0) == 1
        assert abs(float(updated.get("last_applied_sl") or 0.0) - float(entry)) <= 0.02
    finally:
        svc.stop()


def test_indicator_bridge_state_recovers_live_open_trade_from_audit_when_ladder_memory_missing(monkeypatch):
    svc, broker = _build_service(monkeypatch, mode_advanced=False, mode_normal=True, signal_confirm_sec=0.0)
    expected_ticket = 0
    try:
        expected_ticket = 987000000 + int(time.time_ns() % 1000000)
        with broker._lock:
            broker._next_ticket = int(expected_ticket)
        data = broker.place_market_order(
            symbol="BTCUSDM",
            direction="SELL",
            lot_size=0.10,
            stop_loss=None,
            take_profit=None,
            comment="mt4recover",
        )
        ticket = int(data.get("position") or 0)
        assert ticket == int(expected_ticket)
        source_tag = "mt4|generic|intrepid trend direction|BTCUSDM|M1|normal"
        svc._append_automation_execution_log(
            source_type="mt_indicator",
            source_name="Intrepid Trend Direction",
            trigger="indicator_signal",
            status="opened",
            symbol="BTCUSDM",
            timeframe="M1",
            direction="SELL",
            lot=0.10,
            ticket=int(ticket),
            message="order_opened",
            profile="generic",
            indicator="Intrepid Trend Direction",
            source_tag=str(source_tag),
            opened_at=svc._now_iso(),
            execution_mode="normal",
        )
        reg = svc.ingest_indicator_bridge_signal(
            terminal_family="mt4",
            payload={
                "indicator": "Intrepid Trend Direction",
                "signal_profile": "generic",
                "symbol": "BTCUSDm",
                "timeframe": "M1",
                "bridge_event_type": "register",
                "bridge_version": "v2",
                "ingest_source": "bridge",
            },
        )
        assert reg.get("ok") is True
        state = svc.get_indicator_bridge_state(limit=50)
        rows = list(((state.get("open_trades") or {}).get("rows") or []))
        recovered = next((r for r in rows if int(r.get("ticket") or 0) == int(ticket)), None)
        assert recovered is not None
        assert recovered.get("recovered_from_audit") is True
        assert str(recovered.get("execution_mode") or "") == "normal"
        assert str(recovered.get("direction") or "") == "SELL"
    finally:
        _cleanup_execution_logs_for_tickets(int(expected_ticket))
        svc.stop()


def test_indicator_bridge_reconcile_logs_closed_indicator_signal_trade(monkeypatch):
    svc, broker = _build_service(monkeypatch, mode_advanced=True, mode_normal=False, signal_confirm_sec=0.0)
    expected_ticket = 0
    try:
        monkeypatch.setattr(svc, "_execution_reconcile_interval_sec", lambda: 0.0)
        monkeypatch.setattr(broker, "get_live_status", lambda: {"mt5_available": True}, raising=False)

        expected_ticket = 988000000 + int(time.time_ns() % 1000000)
        with broker._lock:
            broker._next_ticket = int(expected_ticket)
        data = broker.place_market_order(
            symbol="BTCUSDM",
            direction="SELL",
            lot_size=0.10,
            stop_loss=77531.78,
            take_profit=77281.03,
            comment="mt4reconcile",
        )
        ticket = int(data.get("position") or 0)
        assert ticket == int(expected_ticket)
        source_tag = "mt4|kforex|kforex scalping|BTCUSDM|M1|advanced"
        opened_at = svc._now_iso()
        svc._append_automation_execution_log(
            source_type="mt_indicator",
            source_name="kforex Scalping",
            trigger="indicator_signal",
            status="opened",
            symbol="BTCUSDM",
            timeframe="M1",
            direction="SELL",
            lot=0.10,
            stop_loss=77531.78,
            final_tp=77281.03,
            stages_total=5,
            stages_opened=5,
            ticket=int(ticket),
            message="order_opened",
            profile="kforex",
            indicator="kforex Scalping",
            source_tag=str(source_tag),
            opened_at=str(opened_at),
            execution_mode="advanced",
            stage="entry",
            stage_status="success",
            stage_payload={
                "stage_lots": [0.04, 0.03, 0.01, 0.01, 0.01],
                "active_tps": [
                    {"index": 1, "price": 77481.03},
                    {"index": 2, "price": 77431.03},
                    {"index": 3, "price": 77381.03},
                    {"index": 4, "price": 77331.03},
                    {"index": 5, "price": 77281.03},
                ],
            },
        )

        def _fake_deals(*, position_ticket, days=14, symbol=None):
            assert int(position_ticket) == int(ticket)
            return [
                {
                    "entry_code": 1,
                    "profit": 4.37,
                    "commission": 0.0,
                    "swap": 0.0,
                    "time": "2026-04-25T19:29:12+00:00",
                    "order": 1393642347,
                    "ticket": 1393642347,
                    "comment": "[tp 77281.03000]",
                    "price": 77281.03,
                }
            ]

        monkeypatch.setattr(broker, "get_position_deals", _fake_deals, raising=False)
        with broker._lock:
            broker._positions.pop(int(ticket), None)

        svc._reconcile_execution_ticket_state(force=True)

        logs = svc.get_automation_execution_logs(limit=200)
        close_rows = [
            r
            for r in logs
            if int(r.get("ticket") or 0) == int(ticket)
            and str(r.get("status") or "").lower() == "closed"
            and str(r.get("trigger") or "") == "position_closed"
        ]
        assert close_rows
        row = close_rows[-1]
        assert str(row.get("source_type") or "") == "mt_indicator"
        assert str(row.get("message") or "") == "reconciled_closed_after_restart"
        assert abs(float(row.get("realized_pnl") or 0.0) - 4.37) < 1e-9
        assert abs(float(row.get("close_price") or 0.0) - 77281.03) < 1e-9
        assert int(row.get("deal_number") or 0) == 1393642347
    finally:
        _cleanup_execution_logs_for_tickets(int(expected_ticket))
        svc.stop()


def test_indicator_bridge_reconcile_does_not_close_when_open_snapshot_empty_without_deal(monkeypatch):
    svc, broker = _build_service(monkeypatch, mode_advanced=True, mode_normal=False, signal_confirm_sec=0.0)
    expected_ticket = 0
    try:
        monkeypatch.setattr(svc, "_execution_reconcile_interval_sec", lambda: 0.0)
        monkeypatch.setattr(broker, "get_live_status", lambda: {"mt5_available": True}, raising=False)
        monkeypatch.setattr(broker, "get_position_deals", lambda **kwargs: [], raising=False)

        expected_ticket = 989000000 + int(time.time_ns() % 1000000)
        source_tag = "mt4|kforex|kforex scalping|BTCUSDM|M5|advanced"
        svc._append_automation_execution_log(
            source_type="mt_indicator",
            source_name="kforex Scalping",
            trigger="indicator_signal",
            status="opened",
            symbol="BTCUSDM",
            timeframe="M5",
            direction="BUY",
            lot=0.10,
            ticket=int(expected_ticket),
            message="order_opened",
            profile="kforex",
            indicator="kforex Scalping",
            source_tag=str(source_tag),
            opened_at=svc._now_iso(),
            execution_mode="advanced",
        )

        svc._reconcile_execution_ticket_state(force=True)

        logs = svc.get_automation_execution_logs(limit=200)
        close_rows = [
            r
            for r in logs
            if int(r.get("ticket") or 0) == int(expected_ticket)
            and str(r.get("status") or "").lower() == "closed"
            and str(r.get("trigger") or "") == "position_closed"
        ]
        assert close_rows == []
    finally:
        _cleanup_execution_logs_for_tickets(int(expected_ticket))
        svc.stop()


def test_smoke_mt4_recent_open_debounce_blocks_duplicate_open_when_broker_visibility_lags(monkeypatch):
    svc, broker = _build_service(
        monkeypatch,
        terminal_family="mt4",
        mode_advanced=True,
        mode_normal=False,
    )
    try:
        monkeypatch.setattr(svc, "_indicator_open_debounce_sec", lambda: 5.0)
        broker.hide_positions_once(count=25)

        out1 = svc.ingest_indicator_bridge_signal(
            terminal_family="mt4",
            payload=_payload(hint="SELL", message="DEBOUNCE SELL 1"),
        )
        out2 = svc.ingest_indicator_bridge_signal(
            terminal_family="mt4",
            payload=_payload(hint="SELL", message="DEBOUNCE SELL 2"),
        )
        out3 = svc.ingest_indicator_bridge_signal(
            terminal_family="mt4",
            payload=_payload(hint="SELL", message="DEBOUNCE SELL 3"),
        )
        assert out1.get("ok") is True
        assert out1.get("executed") is True
        assert out2.get("ok") is True
        assert out3.get("ok") is True
        assert out2.get("executed") is False
        assert out3.get("executed") is False
        assert (
            str(out2.get("reason") or "") == "recent_open_debounce"
            or any(str((x or {}).get("reason") or "") == "recent_open_debounce" for x in (out2.get("mode_results") or []))
        )
        assert (
            str(out3.get("reason") or "") == "recent_open_debounce"
            or any(str((x or {}).get("reason") or "") == "recent_open_debounce" for x in (out3.get("mode_results") or []))
        )
        with broker._lock:
            assert len(broker._positions) == 1
    finally:
        svc.stop()


def test_smoke_mt5_recent_open_debounce_blocks_duplicate_open_when_broker_visibility_lags(monkeypatch):
    svc, broker = _build_service(
        monkeypatch,
        terminal_family="mt5",
        mode_advanced=True,
        mode_normal=False,
    )
    try:
        monkeypatch.setattr(svc, "_indicator_open_debounce_sec", lambda: 5.0)
        broker.hide_positions_once(count=25)

        out1 = svc.ingest_indicator_bridge_signal(
            terminal_family="mt5",
            payload=_payload(hint="BUY", message="MT5 DEBOUNCE BUY 1"),
        )
        out2 = svc.ingest_indicator_bridge_signal(
            terminal_family="mt5",
            payload=_payload(hint="BUY", message="MT5 DEBOUNCE BUY 2"),
        )
        out3 = svc.ingest_indicator_bridge_signal(
            terminal_family="mt5",
            payload=_payload(hint="BUY", message="MT5 DEBOUNCE BUY 3"),
        )
        assert out1.get("ok") is True
        assert out1.get("executed") is True
        assert out2.get("ok") is True
        assert out3.get("ok") is True
        assert out2.get("executed") is False
        assert out3.get("executed") is False
        assert (
            str(out2.get("reason") or "") == "recent_open_debounce"
            or any(str((x or {}).get("reason") or "") == "recent_open_debounce" for x in (out2.get("mode_results") or []))
        )
        assert (
            str(out3.get("reason") or "") == "recent_open_debounce"
            or any(str((x or {}).get("reason") or "") == "recent_open_debounce" for x in (out3.get("mode_results") or []))
        )
        with broker._lock:
            assert len(broker._positions) == 1
    finally:
        svc.stop()


def test_smoke_rsi_telemetry_ingest_and_snapshot(monkeypatch):
    svc, _broker = _build_service(monkeypatch)
    try:
        out = svc.ingest_indicator_bridge_signal(
            terminal_family="mt4",
            payload={
                "indicator": "H1_RSI_Line_Cem",
                "signal_profile": "rsi_telemetry",
                "symbol": "BTCUSDm",
                "timeframe": "M1",
                "bridge_event_type": "rsi_telemetry",
                "rsi_value": 63.25,
                "indicator_tf": "H1",
                "rsi_period": 14,
                "ingest_source": "bridge",
            },
        )
        assert out.get("ok") is True
        assert out.get("executed") is False
        assert str(out.get("reason") or "") == "rsi_telemetry_recorded"
        snap = svc.get_indicator_rsi_telemetry(limit=20, terminal_family="mt4")
        assert snap.get("ok") is True
        assert int(snap.get("count") or 0) >= 1
        rows = list(snap.get("rows") or [])
        row = rows[0]
        assert str(row.get("terminal_family") or "").lower() == "mt4"
        assert str(row.get("symbol") or "").upper() == "BTCUSDM"
        assert str(row.get("timeframe") or "").upper() == "M1"
        assert abs(float(row.get("rsi_value") or 0.0) - 63.25) < 1e-9
    finally:
        svc.stop()


def test_smoke_monitor_rows_include_latest_rsi(monkeypatch):
    svc, _broker = _build_service(monkeypatch)
    try:
        reg = svc.ingest_indicator_bridge_signal(
            terminal_family="mt4",
            payload={
                "indicator": "Intrepid Trend Direction",
                "signal_profile": "intrepid",
                "symbol": "BTCUSDm",
                "timeframe": "M1",
                "bridge_event_type": "register",
                "ingest_source": "bridge",
            },
        )
        assert reg.get("ok") is True

        telem = svc.ingest_indicator_bridge_signal(
            terminal_family="mt4",
            payload={
                "indicator": "H1_RSI_Line_Cem",
                "signal_profile": "rsi_telemetry",
                "symbol": "BTCUSDm",
                "timeframe": "M1",
                "bridge_event_type": "rsi_telemetry",
                "rsi_value": 48.10,
                "indicator_tf": "H1",
                "rsi_period": 14,
                "ingest_source": "bridge",
            },
        )
        assert telem.get("ok") is True

        state = svc.get_indicator_bridge_state(limit=50)
        mt4_rows = list((((state or {}).get("mt4_monitor") or {}).get("bot_rows") or []))
        assert mt4_rows
        row = next(
            (
                r
                for r in mt4_rows
                if str(r.get("symbol") or "").upper() == "BTCUSDM"
                and str(r.get("timeframe") or "").upper() == "M1"
            ),
            None,
        )
        assert row is not None
        assert abs(float(row.get("rsi_value") or 0.0) - 48.10) < 1e-9
        assert str(row.get("rsi_indicator_tf") or "").upper() == "H1"
    finally:
        svc.stop()
