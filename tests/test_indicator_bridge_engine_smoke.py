from __future__ import annotations

import threading
import time
from datetime import datetime, timezone
from typing import Any, Dict, List

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

        broker.hide_positions_once(count=1)
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

        broker.hide_positions_once(count=1)
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
