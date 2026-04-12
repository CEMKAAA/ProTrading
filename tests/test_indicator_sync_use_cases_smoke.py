from datetime import datetime, timezone

from dashboard.backend.services.telegram_bridge_service import TelegramBridgeService


def _build_service():
    svc = TelegramBridgeService()
    observed = {"close_calls": 0, "open_calls": 0, "last_close_reason": "", "close_timeframes": []}

    def _fake_close(**kwargs):
        observed["close_calls"] += 1
        observed["last_close_reason"] = str(kwargs.get("close_reason") or "")
        observed["close_timeframes"].append(str(kwargs.get("timeframe") or ""))
        return {"ok": True, "closed_count": 0, "failed_count": 0}

    def _fake_guard(**kwargs):
        return {"ok": True, "ready": True, "reason": "reversal_guard_passed"}

    def _fake_has_open(**kwargs):
        return False

    def _fake_open(**kwargs):
        observed["open_calls"] += 1
        return "Normal mode order executed\nTicket: 1"

    svc._close_mt4_reverse_positions = _fake_close  # type: ignore[assignment]
    svc._check_indicator_reversal_stability = _fake_guard  # type: ignore[assignment]
    svc._has_live_open_for_source_tag_direction = _fake_has_open  # type: ignore[assignment]
    svc._execute_indicator_normal_signal = _fake_open  # type: ignore[assignment]
    return svc, observed


def _run_sync(
    svc: TelegramBridgeService,
    *,
    direction_tf: str,
    entry_tf: str,
    exit_tf: str,
    reentry_enabled: bool,
    current_tf: str,
    current_dir: str,
    direction_dir: str,
):
    family = "mt4"
    profile = "intrepid"
    indicator = "Intrepid Trend Direction"
    indicator_key = "intrepid trend direction"
    symbol = "BTCUSDM"
    mode_source_tag = svc._build_sync_mode_source_tag(
        family=family,
        profile=profile,
        indicator_key=indicator_key,
        symbol=symbol,
        direction_tf=direction_tf,
        entry_tf=entry_tf,
        exit_tf=exit_tf,
    )
    now_ts = 1_900_000_000.0

    base_key = svc._indicator_sync_base_key(
        family=family,
        profile=profile,
        indicator_key=indicator_key,
        symbol=symbol,
    )
    svc._record_indicator_sync_direction(
        base_key=base_key,
        timeframe=direction_tf,
        direction=direction_dir,
        now_ts=now_ts - 5.0,
        message="seed",
    )

    return svc._execute_indicator_sync_mode(
        family=family,
        profile=profile,
        indicator=indicator,
        indicator_key=indicator_key,
        symbol_exec_raw=symbol,
        timeframe=current_tf,
        incoming_direction=current_dir,
        lot=0.1,
        now_ts=now_ts,
        mode_source_tag=mode_source_tag,
        sync_cfg={
            "direction_tf": direction_tf,
            "entry_tf": entry_tf,
            "exit_tf": exit_tf,
            "reentry_enabled": reentry_enabled,
        },
        audit_event_ts=datetime.now(timezone.utc).isoformat(),
    )


def test_sync_use_case_1_m1_scalp_m5_filter_smoke():
    svc, observed = _build_service()
    out = _run_sync(
        svc,
        direction_tf="M5",
        entry_tf="M1",
        exit_tf="M1",
        reentry_enabled=True,
        current_tf="M1",
        current_dir="BUY",
        direction_dir="BUY",
    )
    assert out.get("ok") is True
    assert out.get("executed") is True
    assert observed["open_calls"] == 1


def test_sync_use_case_2_m1_scalp_m15_filter_smoke():
    svc, observed = _build_service()
    out = _run_sync(
        svc,
        direction_tf="M15",
        entry_tf="M1",
        exit_tf="M1",
        reentry_enabled=True,
        current_tf="M1",
        current_dir="SELL",
        direction_dir="SELL",
    )
    assert out.get("ok") is True
    assert out.get("executed") is True
    assert observed["open_calls"] == 1


def test_sync_use_case_3_m5_entry_m1_exit_smoke():
    svc, observed = _build_service()
    # Entry leg on M5.
    out_entry = _run_sync(
        svc,
        direction_tf="M5",
        entry_tf="M5",
        exit_tf="M1",
        reentry_enabled=True,
        current_tf="M5",
        current_dir="BUY",
        direction_dir="BUY",
    )
    assert out_entry.get("ok") is True
    assert out_entry.get("executed") is True
    # Exit-only signal on M1 in opposite direction must not open new trade.
    out_exit = _run_sync(
        svc,
        direction_tf="M5",
        entry_tf="M5",
        exit_tf="M1",
        reentry_enabled=True,
        current_tf="M1",
        current_dir="SELL",
        direction_dir="BUY",
    )
    assert out_exit.get("ok") is True
    assert out_exit.get("executed") is False
    assert str(out_exit.get("reason") or "").startswith("sync_exit_only")
    assert observed["close_calls"] >= 2
    # Cross-timeframe reverse close must not be constrained by current signal TF.
    assert all(str(x) == "" for x in (observed.get("close_timeframes") or []))


def test_sync_use_case_4_h1_direction_m15_entry_exit_smoke():
    svc, observed = _build_service()
    out = _run_sync(
        svc,
        direction_tf="H1",
        entry_tf="M15",
        exit_tf="M15",
        reentry_enabled=True,
        current_tf="M15",
        current_dir="BUY",
        direction_dir="BUY",
    )
    assert out.get("ok") is True
    assert out.get("executed") is True
    assert observed["open_calls"] == 1


def test_sync_use_case_5_single_try_mode_smoke():
    svc, observed = _build_service()
    out = _run_sync(
        svc,
        direction_tf="M5",
        entry_tf="M1",
        exit_tf="M1",
        reentry_enabled=False,
        current_tf="M1",
        current_dir="BUY",
        direction_dir="BUY",
    )
    assert out.get("ok") is True
    assert out.get("executed") is True
    assert observed["open_calls"] == 1


def test_sync_use_case_6_conservative_smoke():
    svc, observed = _build_service()
    out = _run_sync(
        svc,
        direction_tf="H1",
        entry_tf="M5",
        exit_tf="M5",
        reentry_enabled=False,
        current_tf="M5",
        current_dir="SELL",
        direction_dir="SELL",
    )
    assert out.get("ok") is True
    assert out.get("executed") is True
    assert observed["open_calls"] == 1


def test_reversal_pending_replay_triggers_after_wait(monkeypatch):
    svc = TelegramBridgeService()
    calls = []

    def _fake_ingest(*, terminal_family, payload):
        calls.append({"family": terminal_family, "payload": dict(payload or {})})
        return {"ok": True, "executed": False, "reason": "replay_probe"}

    monkeypatch.setattr(svc, "ingest_indicator_bridge_signal", _fake_ingest)

    now_ts = 1_900_000_500.0
    monkeypatch.setattr("time.time", lambda: now_ts)
    with svc._lock:
        svc._indicator_reversal_pending["mt4|intrepid|intrepid trend direction|BTCUSDM|M1|normal"] = {
            "direction": "BUY",
            "first_seen_ts": float(now_ts - 25.0),
            "last_seen_ts": float(now_ts - 2.0),
            "required_sec": 20.0,
            "replay_terminal_family": "mt4",
            "replay_payload": {
                "indicator": "Intrepid Trend Direction",
                "signal_profile": "intrepid",
                "signal_hint": "BUY",
                "symbol": "BTCUSDM",
                "timeframe": "M1",
                "message": "probe",
                "event_ts": datetime.now(timezone.utc).isoformat(),
            },
        }

    svc._process_indicator_reversal_pending_replays()
    assert len(calls) == 1
    assert str(calls[0]["family"]) == "mt4"
    assert bool(calls[0]["payload"].get("__guard_replay")) is True
