import shutil
import uuid
import json
from datetime import datetime, timezone, timedelta
from pathlib import Path

from dashboard.backend.services.mt4_log_automation_service import MT4LogAutomationService


def _mk_workspace_tmp_dir() -> Path:
    root = Path("dashboard/data/test_tmp")
    root.mkdir(parents=True, exist_ok=True)
    d = root / f"mt4la_{uuid.uuid4().hex}"
    d.mkdir(parents=True, exist_ok=True)
    return d


def test_run_loop_does_not_restore_active_indicators_when_restore_disabled(monkeypatch):
    tmp_dir = _mk_workspace_tmp_dir()
    svc = MT4LogAutomationService()
    monkeypatch.setattr(svc, "_data_path", lambda: str(tmp_dir))
    monkeypatch.setattr(svc, "_restore_active_indicators_on_start", lambda: False)
    monkeypatch.setattr(svc, "_active_indicator_names", lambda: ["Hydra Signals Indicator"])
    monkeypatch.setattr(svc, "_discover_active_files", lambda _base: [])

    try:
        svc._run_loop()
        assert "hydra signals indicator" not in svc._indicator_stats
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


def test_run_loop_restores_active_indicators_only_when_enabled(monkeypatch):
    tmp_dir = _mk_workspace_tmp_dir()
    svc = MT4LogAutomationService()
    monkeypatch.setattr(svc, "_data_path", lambda: str(tmp_dir))
    monkeypatch.setattr(svc, "_restore_active_indicators_on_start", lambda: True)
    monkeypatch.setattr(svc, "_active_indicator_names", lambda: ["Hydra Signals Indicator"])
    monkeypatch.setattr(svc, "_discover_active_files", lambda _base: [])

    try:
        svc._run_loop()
        row = svc._indicator_stats.get("hydra signals indicator")
        assert isinstance(row, dict)
        assert bool(row.get("automation_enabled")) is True
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


def test_indicator_signal_forward_requires_automation_enabled():
    calls = {"n": 0}

    def _on_signal(**_kwargs):
        calls["n"] += 1

    svc = MT4LogAutomationService(on_indicator_signal=_on_signal)
    key = "hydra signals indicator"
    svc._indicator_stats[key] = {
        "indicator": "Hydra Signals Indicator",
        "key": key,
        "automation_enabled": False,
    }
    ev = {
        "indicator": "Hydra Signals Indicator",
        "signal_profile": "hydra",
        "signal_hint": "BUY",
        "symbol": "USDJPY",
        "timeframe": "M5",
        "message": "Hydra: BUY",
        "event_ts": "2026-04-07T10:00:00+00:00",
    }

    svc._maybe_forward_signal(dict(ev), from_backfill=False)
    assert calls["n"] == 0

    svc._indicator_stats[key]["automation_enabled"] = True
    svc._maybe_forward_signal(dict(ev), from_backfill=False)
    assert calls["n"] == 1


def test_discover_active_files_includes_mql5_logs():
    tmp_dir = _mk_workspace_tmp_dir()
    try:
        mql5_logs = tmp_dir / "MQL5" / "Logs"
        mql5_logs.mkdir(parents=True, exist_ok=True)
        p = mql5_logs / "20260407.log"
        p.write_text("0\t12:00:00.000\ttest\n", encoding="utf-8")

        svc = MT4LogAutomationService()
        files = svc._discover_active_files(tmp_dir)
        paths = {str(x).lower() for x in files}
        assert any("mql5" in x and x.endswith(".log") for x in paths)
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


def test_signal_hint_uranus_turned_up_down_are_mapped():
    svc = MT4LogAutomationService()
    buy = svc._signal_hint(
        indicator="Forex Uranus direction",
        message="Uranus : Turned Up XAUUSD 5 Minutes Ask Price = 4678.31",
    )
    sell = svc._signal_hint(
        indicator="Forex Uranus direction",
        message="Uranus : Turned Down XAUUSD 5 Minutes Bid Price = 4665.49",
    )
    assert buy == "BUY"
    assert sell == "SELL"


def test_signal_profile_alchemy_detected_from_indicator_name():
    svc = MT4LogAutomationService()
    profile = svc._signal_profile(
        indicator="Alchemy Pulse Indicator",
        message="loaded successfully",
    )
    assert profile == "alchemy"


def test_get_state_includes_active_indicator_even_without_events(monkeypatch):
    svc = MT4LogAutomationService()
    monkeypatch.setattr(svc, "_active_indicator_names", lambda: ["Alchemy Pulse Indicator"])
    state = svc.get_state(limit=200)
    rows = [dict(x) for x in (state.get("indicators") or [])]
    assert any(str(r.get("indicator") or "").strip().lower() == "alchemy pulse indicator" for r in rows)
    row = next(
        r for r in rows if str(r.get("indicator") or "").strip().lower() == "alchemy pulse indicator"
    )
    # Default must be OFF until user explicitly clicks Start Automation.
    assert bool(row.get("automation_enabled")) is False
    assert int(row.get("event_count") or 0) == 0


def test_parse_line_supports_mql5_alert_format():
    svc = MT4LogAutomationService()
    row = svc._parse_line(
        line="MH\t0\t12:33:02.585\tAlchemy Pulse Indicateor (USDJPYm,M1)\tAlert: AlchemyPulse | M1 USDJPYm | ▲ BUY — Trend Turned UP | 12:33:02",
        source_file="20260407.log",
        file_date="20260407",
    )
    assert isinstance(row, dict)
    assert str(row.get("indicator")) == "Alchemy Pulse Indicateor"
    assert str(row.get("symbol")) == "USDJPYM"
    assert str(row.get("timeframe")) == "M1"
    assert str(row.get("kind")) == "alert"
    assert str(row.get("signal_profile")) == "alchemy"
    assert str(row.get("signal_hint")) == "BUY"


def test_parse_line_sets_terminal_group_from_source_path():
    svc = MT4LogAutomationService()
    row = svc._parse_line(
        line="MH\t0\t12:33:02.585\tAlchemy Pulse Indicateor (USDJPYm,M1)\tAlert: AlchemyPulse | M1 USDJPYm | BUY",
        source_file="20260407.log",
        file_date="20260407",
        source_path=r"C:\MT5\DEMO\MQL5\Logs\20260407.log",
    )
    assert isinstance(row, dict)
    assert str(row.get("terminal_group") or "") == "mt5_demo"


def test_parse_line_supports_mt4_parenthesized_symbol_tf():
    svc = MT4LogAutomationService()
    row = svc._parse_line(
        line="0\t12:33:02.585\tAlchemy Pulse Indicateor (USDCADm,M1): Alert: SELL",
        source_file="20260407.log",
        file_date="20260407",
    )
    assert isinstance(row, dict)
    assert str(row.get("symbol") or "") == "USDCADM"
    assert str(row.get("timeframe") or "") == "M1"


def test_parse_line_mt5_indicators_source_extracts_custom_indicator_chart():
    svc = MT4LogAutomationService()
    row = svc._parse_line(
        line="MO\t0\t10:55:35.648\tIndicators\tcustom indicator Trend-Cross Alert (US500m,M15) removed",
        source_file="20260405.log",
        file_date="20260405",
    )
    assert isinstance(row, dict)
    assert str(row.get("indicator") or "") == "Trend-Cross Alert"
    assert str(row.get("symbol") or "") == "US500M"
    assert str(row.get("timeframe") or "") == "M15"


def test_enrich_event_for_view_repairs_generic_indicators_event():
    svc = MT4LogAutomationService()
    ev = {
        "indicator": "Indicators",
        "symbol": "",
        "timeframe": "",
        "message": "custom indicator Trend-Cross Alert (USDJPYm,M15) removed",
    }
    out = svc._enrich_event_for_view(ev)
    assert str(out.get("indicator") or "") == "Trend-Cross Alert"
    assert str(out.get("symbol") or "") == "USDJPYM"
    assert str(out.get("timeframe") or "") == "M15"
    assert str(out.get("instance_key") or "").endswith("|USDJPYM|M15")


def test_append_event_sets_instance_key():
    svc = MT4LogAutomationService()
    ev = {
        "event_ts": "2026-04-09T00:00:00+00:00",
        "source_file": "20260409.log",
        "indicator": "Alchemy Pulse Indicateor",
        "indicator_key": "alchemy pulse indicateor",
        "symbol": "USDJPYM",
        "timeframe": "M1",
        "kind": "alert",
        "signal_hint": "BUY",
        "signal_profile": "alchemy",
        "message": "BUY",
        "raw": "raw",
    }
    svc._append_event(ev)
    st = svc.get_state(limit=50)
    rows = st.get("events") or []
    assert rows and str(rows[-1].get("instance_key") or "").endswith("|USDJPYM|M1")


def test_append_event_dedupes_same_ingest_line(monkeypatch):
    svc = MT4LogAutomationService()
    monkeypatch.setattr(svc, "_ingest_dedupe_window_sec", lambda: 3600.0)
    ev = {
        "event_ts": "2026-04-09T00:00:00+00:00",
        "source_file": "20260409.log",
        "source_path": r"C:\MT5\DEMO\MQL5\Logs\20260409.log",
        "time": "12:00:00.123",
        "indicator": "Alchemy Pulse Indicateor",
        "indicator_key": "alchemy pulse indicateor",
        "symbol": "USDJPYM",
        "timeframe": "M1",
        "kind": "alert",
        "signal_hint": "BUY",
        "signal_profile": "alchemy",
        "message": "BUY",
        "raw": "MO\t0\t12:00:00.123\tAlchemy Pulse Indicateor (USDJPYm,M1)\tAlert BUY",
    }
    svc._append_event(dict(ev))
    svc._append_event(dict(ev))
    st = svc.get_state(limit=100)
    rows = st.get("events") or []
    assert len(rows) == 1


def test_indicator_last_symbol_timeframe_not_overwritten_by_empty_event():
    svc = MT4LogAutomationService()
    ev1 = {
        "event_ts": "2026-04-09T00:00:00+00:00",
        "source_file": "20260409.log",
        "indicator": "Alchemy Pulse Indicateor",
        "indicator_key": "alchemy pulse indicateor",
        "symbol": "USDJPYM",
        "timeframe": "M1",
        "kind": "alert",
        "signal_hint": "BUY",
        "signal_profile": "alchemy",
        "message": "BUY",
        "raw": "raw",
    }
    ev2 = {
        "event_ts": "2026-04-09T00:01:00+00:00",
        "source_file": "20260409.log",
        "indicator": "Alchemy Pulse Indicateor",
        "indicator_key": "alchemy pulse indicateor",
        "symbol": "",
        "timeframe": "",
        "kind": "log",
        "signal_hint": "",
        "signal_profile": "alchemy",
        "message": "heartbeat",
        "raw": "raw",
    }
    svc._append_event(ev1)
    svc._append_event(ev2)
    st = svc.get_state(limit=80)
    rows = [dict(x) for x in (st.get("indicators") or [])]
    alchemy = next((r for r in rows if str(r.get("indicator") or "").strip().lower() == "alchemy pulse indicateor"), None)
    assert isinstance(alchemy, dict)
    assert str(alchemy.get("last_symbol") or "") == "USDJPYM"
    assert str(alchemy.get("last_timeframe") or "") == "M1"


def test_get_state_includes_events_recent_24h():
    svc = MT4LogAutomationService()
    old_ev = {
        "event_ts": "2025-01-01T00:00:00+00:00",
        "source_file": "20250101.log",
        "source_path": r"C:\MT5\DEMO\MQL5\Logs\20250101.log",
        "time": "00:00:00.000",
        "indicator": "Alchemy Pulse Indicateor",
        "indicator_key": "alchemy pulse indicateor",
        "symbol": "USDJPYM",
        "timeframe": "M1",
        "kind": "alert",
        "signal_hint": "BUY",
        "signal_profile": "alchemy",
        "message": "BUY",
        "raw": "old",
    }
    new_ev = {
        "event_ts": datetime.now(timezone.utc).isoformat(),
        "source_file": "20260409.log",
        "source_path": r"C:\MT5\DEMO\MQL5\Logs\20260409.log",
        "time": "12:00:00.000",
        "indicator": "Alchemy Pulse Indicateor",
        "indicator_key": "alchemy pulse indicateor",
        "symbol": "USDJPYM",
        "timeframe": "M1",
        "kind": "alert",
        "signal_hint": "BUY",
        "signal_profile": "alchemy",
        "message": "BUY",
        "raw": "new",
    }
    svc._append_event(old_ev)
    svc._append_event(new_ev)
    st = svc.get_state(limit=200)
    recent = st.get("events_recent_24h") or []
    assert any(str(r.get("raw") or "") == "new" for r in recent)
    assert not any(str(r.get("raw") or "") == "old" for r in recent)


def test_realtime_log_callback_emits_only_non_backfill_alarm_like():
    calls = {"n": 0}

    def _on_log_event(**payload):
        if isinstance(payload.get("event"), dict):
            calls["n"] += 1

    svc = MT4LogAutomationService(on_log_event=_on_log_event)
    noisy_alert = {
        "event_ts": datetime.now(timezone.utc).isoformat(),
        "source_file": "20260409.log",
        "source_path": r"C:\MT5\DEMO\MQL5\Logs\20260409.log",
        "time": "12:00:00.000",
        "indicator": "Trend-Cross Alert",
        "symbol": "USDJPYM",
        "timeframe": "M1",
        "kind": "alert",
        "signal_hint": "",
        "signal_profile": "generic",
        "message": "custom indicator Trend-Cross Alert (USDJPYm,M1) removed",
        "raw": "removed",
    }
    live_signal = dict(noisy_alert)
    live_signal["signal_hint"] = "BUY"
    live_signal["message"] = "Alert: BUY"
    live_signal["raw"] = "buy"
    live_signal["time"] = "12:00:00.001"

    svc._append_event(noisy_alert, from_backfill=False)
    assert calls["n"] == 0

    svc._append_event(live_signal, from_backfill=True)
    assert calls["n"] == 0

    live_signal_2 = dict(live_signal)
    live_signal_2["time"] = "12:00:00.002"
    live_signal_2["raw"] = "buy2"
    svc._append_event(live_signal_2, from_backfill=False)
    assert calls["n"] == 1


def test_safe_decode_handles_utf16_mql5_rows():
    svc = MT4LogAutomationService()
    text = "MH\t0\t12:33:02.585\tAlchemy Pulse Indicateor (USDJPYm,M1)\tAlert: AlchemyPulse | M1 USDJPYm | BUY"
    raw = text.encode("utf-16")
    decoded = svc._safe_decode(raw)
    assert "Alchemy Pulse Indicateor" in decoded
    assert "\t" in decoded


def test_process_file_backfill_parses_utf16_mql5_alerts():
    tmp_dir = _mk_workspace_tmp_dir()
    try:
        mql5_logs = tmp_dir / "MQL5" / "Logs"
        mql5_logs.mkdir(parents=True, exist_ok=True)
        p = mql5_logs / "20260407.log"
        payload = (
            "MH\t0\t12:33:02.585\tAlchemy Pulse Indicateor (USDJPYm,M1)\tAlert: AlchemyPulse | M1 USDJPYm | ▲ BUY — Trend Turned UP | 12:33:02\r\n"
            "KD\t0\t14:45:01.692\tAlchemy Pulse Indicateor (USDJPYm,M1)\tAlert: AlchemyPulse | M1 USDJPYm | ▼ SELL — Trend Turned DOWN | 14:45:01\r\n"
        )
        p.write_bytes(payload.encode("utf-16"))

        svc = MT4LogAutomationService()
        svc._process_file_backfill(p, max_lines=200)
        st = svc.get_state(limit=200)
        rows = [dict(x) for x in (st.get("indicators") or [])]
        alchemy = next((r for r in rows if str(r.get("indicator") or "").strip().lower() == "alchemy pulse indicateor"), None)
        assert isinstance(alchemy, dict)
        assert int(alchemy.get("event_count") or 0) >= 2
        assert int(alchemy.get("signal_hint_count") or 0) >= 2
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


def test_update_indicator_settings_lot_override_without_auto_enable(monkeypatch):
    svc = MT4LogAutomationService()
    monkeypatch.setattr(svc, "_active_indicator_names", lambda: [])
    monkeypatch.setattr(svc, "_indicator_lot_overrides", lambda: {})
    monkeypatch.setattr(svc, "_default_indicator_lot", lambda: 0.05)
    monkeypatch.setattr(svc, "_upsert_env_values", lambda updates: (True, "ok"))

    out = svc.update_indicator_settings(indicator="Hydra Signals Indicator", lot_size=0.07)
    rows = [dict(x) for x in (out.get("indicators") or [])]
    hydra = next((r for r in rows if str(r.get("indicator") or "").strip().lower() == "hydra signals indicator"), None)
    assert isinstance(hydra, dict)
    assert bool(hydra.get("automation_enabled")) is False
    assert abs(float(hydra.get("lot_size") or 0.0) - 0.07) < 1e-9
    lots_json = str((out.get("updated") or {}).get("MT4_LOG_AUTOMATION_INDICATOR_LOTS") or "{}")
    parsed = json.loads(lots_json)
    assert float(parsed.get("hydra signals indicator") or 0.0) == 0.07


def test_update_indicator_settings_toggle_isolated_by_indicator(monkeypatch):
    svc = MT4LogAutomationService()
    monkeypatch.setattr(svc, "_active_indicator_names", lambda: ["Hydra Signals Indicator", "Alchemy Pulse Indicator"])
    monkeypatch.setattr(svc, "_indicator_lot_overrides", lambda: {})
    monkeypatch.setattr(svc, "_default_indicator_lot", lambda: 0.05)
    monkeypatch.setattr(svc, "_upsert_env_values", lambda updates: (True, "ok"))

    out = svc.update_indicator_settings(indicator="Hydra Signals Indicator", enabled=False)
    active_raw = str((out.get("updated") or {}).get("MT4_LOG_AUTOMATION_ACTIVE_INDICATORS") or "")
    active_names = [x.strip() for x in active_raw.split("|") if x.strip()]
    assert "Hydra Signals Indicator" not in active_names
    assert "Alchemy Pulse Indicator" in active_names


def test_runtime_new_file_backfill_forwards_recent_signal_when_enabled(monkeypatch):
    tmp_dir = _mk_workspace_tmp_dir()
    calls = {"n": 0}

    def _on_signal(**_kwargs):
        calls["n"] += 1

    try:
        p = tmp_dir / "20260408.log"
        p.write_text("dummy\n", encoding="utf-8")
        svc = MT4LogAutomationService(on_indicator_signal=_on_signal)
        key = "alchemy pulse indicateor"
        svc._indicator_stats[key] = {
            "indicator": "Alchemy Pulse Indicateor",
            "key": key,
            "automation_enabled": True,
            "lot_size": 0.05,
        }
        monkeypatch.setattr(svc, "_forward_new_file_grace_sec", lambda: 180.0)
        monkeypatch.setattr(
            svc,
            "_parse_line",
            lambda **_kwargs: {
                "event_ts": datetime.now(timezone.utc).isoformat(),
                "source_file": "20260408.log",
                "level": 0,
                "time": "12:00:00.000",
                "indicator": "Alchemy Pulse Indicateor",
                "indicator_key": key,
                "symbol": "USDJPYM",
                "timeframe": "M1",
                "kind": "alert",
                "signal_hint": "SELL",
                "signal_profile": "alchemy",
                "message": "SELL",
                "raw": "raw",
            },
        )

        svc._process_file_backfill(p, max_lines=50, allow_runtime_forward_recent=True)
        assert calls["n"] == 1
        assert int(svc.get_state(limit=120).get("forward_ok") or 0) >= 1
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


def test_runtime_new_file_backfill_skips_old_signal(monkeypatch):
    tmp_dir = _mk_workspace_tmp_dir()
    calls = {"n": 0}

    def _on_signal(**_kwargs):
        calls["n"] += 1

    try:
        p = tmp_dir / "20260408.log"
        p.write_text("dummy\n", encoding="utf-8")
        svc = MT4LogAutomationService(on_indicator_signal=_on_signal)
        key = "alchemy pulse indicateor"
        svc._indicator_stats[key] = {
            "indicator": "Alchemy Pulse Indicateor",
            "key": key,
            "automation_enabled": True,
            "lot_size": 0.05,
        }
        monkeypatch.setattr(svc, "_forward_new_file_grace_sec", lambda: 30.0)
        monkeypatch.setattr(
            svc,
            "_parse_line",
            lambda **_kwargs: {
                "event_ts": (datetime.now(timezone.utc) - timedelta(minutes=10)).isoformat(),
                "source_file": "20260408.log",
                "level": 0,
                "time": "12:00:00.000",
                "indicator": "Alchemy Pulse Indicateor",
                "indicator_key": key,
                "symbol": "USDJPYM",
                "timeframe": "M1",
                "kind": "alert",
                "signal_hint": "SELL",
                "signal_profile": "alchemy",
                "message": "SELL",
                "raw": "raw",
            },
        )

        svc._process_file_backfill(p, max_lines=50, allow_runtime_forward_recent=True)
        st = svc.get_state(limit=120)
        assert calls["n"] == 0
        assert int(st.get("forward_ok") or 0) == 0
        assert int(st.get("forward_skip_backfill") or 0) >= 1
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


def test_signal_profile_forexcyper_detected():
    svc = MT4LogAutomationService()
    profile = svc._signal_profile(
        indicator="ForexCyperSytem",
        message="Alert: ForexCyperSytem SELL signal",
    )
    hint = svc._signal_hint(
        indicator="ForexCyperSytem",
        message="Alert: ForexCyperSytem SELL signal",
    )
    assert profile == "forexcyper"
    assert hint == "SELL"


def test_instance_explicit_disable_blocks_forward_even_if_indicator_enabled():
    calls = {"n": 0}

    def _on_signal(**_kwargs):
        calls["n"] += 1

    svc = MT4LogAutomationService(on_indicator_signal=_on_signal)
    ind_key = "hydra signals indicator"
    inst_key = "hydra signals indicator|USDJPY|M5"
    svc._indicator_stats[ind_key] = {
        "indicator": "Hydra Signals Indicator",
        "key": ind_key,
        "automation_enabled": True,
        "lot_size": 0.05,
    }
    svc._instance_stats[inst_key] = {
        "instance_key": inst_key,
        "indicator": "Hydra Signals Indicator",
        "indicator_key": ind_key,
        "symbol": "USDJPY",
        "timeframe": "M5",
        "automation_mode": "explicit",
        "automation_enabled": False,
        "lot_size": 0.07,
    }
    ev = {
        "indicator": "Hydra Signals Indicator",
        "signal_profile": "hydra",
        "signal_hint": "BUY",
        "symbol": "USDJPY",
        "timeframe": "M5",
        "message": "Hydra: BUY",
        "event_ts": "2026-04-07T10:00:00+00:00",
    }

    svc._maybe_forward_signal(dict(ev), from_backfill=False)
    assert calls["n"] == 0


def test_instance_explicit_enable_forwards_even_if_indicator_disabled():
    calls = {"n": 0}

    def _on_signal(**_kwargs):
        calls["n"] += 1

    svc = MT4LogAutomationService(on_indicator_signal=_on_signal)
    ind_key = "hydra signals indicator"
    inst_key = "hydra signals indicator|USDJPY|M5"
    svc._indicator_stats[ind_key] = {
        "indicator": "Hydra Signals Indicator",
        "key": ind_key,
        "automation_enabled": False,
        "lot_size": 0.05,
    }
    svc._instance_stats[inst_key] = {
        "instance_key": inst_key,
        "indicator": "Hydra Signals Indicator",
        "indicator_key": ind_key,
        "symbol": "USDJPY",
        "timeframe": "M5",
        "automation_mode": "explicit",
        "automation_enabled": True,
        "lot_size": 0.07,
    }
    ev = {
        "indicator": "Hydra Signals Indicator",
        "signal_profile": "hydra",
        "signal_hint": "SELL",
        "symbol": "USDJPY",
        "timeframe": "M5",
        "message": "Hydra: SELL",
        "event_ts": "2026-04-07T10:00:00+00:00",
    }

    svc._maybe_forward_signal(dict(ev), from_backfill=False)
    assert calls["n"] == 1


def test_update_instance_settings_persists_explicit_false(monkeypatch):
    svc = MT4LogAutomationService()
    monkeypatch.setattr(svc, "_instance_automation_overrides", lambda: {})
    monkeypatch.setattr(svc, "_instance_lot_overrides", lambda: {})
    monkeypatch.setattr(svc, "_indicator_lot_for_key", lambda _k: 0.05)
    monkeypatch.setattr(svc, "_instance_lot_for_key", lambda _k: 0.05)
    monkeypatch.setattr(svc, "_upsert_env_values", lambda updates: (True, "ok"))

    out = svc.update_instance_settings(
        indicator="ForexCyperSytem",
        symbol="XAUUSD",
        timeframe="M5",
        enabled=False,
        lot_size=0.09,
    )
    updated = dict(out.get("updated") or {})
    automation_raw = str(updated.get("MT4_LOG_AUTOMATION_INSTANCE_AUTOMATION") or "{}")
    automation = json.loads(automation_raw)
    assert automation.get("forexcypersytem|XAUUSD|M5".lower()) is False


def test_update_indicator_settings_rejects_non_whitelisted_indicator():
    svc = MT4LogAutomationService()
    out = svc.update_indicator_settings(indicator="Random Noise Indicator", enabled=True)
    assert bool(out.get("ok")) is False
    assert str(out.get("error") or "") == "indicator_not_allowed_for_automation"


def test_get_state_filters_non_whitelisted_rows(monkeypatch):
    svc = MT4LogAutomationService()
    monkeypatch.setattr(svc, "_active_indicator_names", lambda: [])
    monkeypatch.setattr(svc, "_instance_automation_overrides", lambda: {})
    monkeypatch.setattr(svc, "_instance_lot_overrides", lambda: {})

    svc._indicator_stats = {
        "hydra signals indicator": {
            "indicator": "Hydra Signals Indicator",
            "indicator_key": "hydra signals indicator",
            "key": "hydra signals indicator",
            "event_count": 1,
            "automation_enabled": True,
            "lot_size": 0.05,
            "last_seen": "",
        },
        "totally custom indicator": {
            "indicator": "Totally Custom Indicator",
            "indicator_key": "totally custom indicator",
            "key": "totally custom indicator",
            "event_count": 1,
            "automation_enabled": True,
            "lot_size": 0.05,
            "last_seen": "",
        },
    }
    svc._instance_stats = {
        "hydra signals indicator|USDJPY|M5": {
            "instance_key": "hydra signals indicator|USDJPY|M5",
            "indicator": "Hydra Signals Indicator",
            "indicator_key": "hydra signals indicator",
            "symbol": "USDJPY",
            "timeframe": "M5",
            "automation_enabled": True,
            "automation_mode": "explicit",
            "lot_size": 0.05,
            "last_seen": "",
        },
        "totally custom indicator|USDJPY|M5": {
            "instance_key": "totally custom indicator|USDJPY|M5",
            "indicator": "Totally Custom Indicator",
            "indicator_key": "totally custom indicator",
            "symbol": "USDJPY",
            "timeframe": "M5",
            "automation_enabled": True,
            "automation_mode": "explicit",
            "lot_size": 0.05,
            "last_seen": "",
        },
    }

    out = svc.get_state(limit=200)
    indicators = [str((r or {}).get("indicator") or "") for r in (out.get("indicators") or [])]
    instances = [str((r or {}).get("indicator") or "") for r in (out.get("instances") or [])]
    assert "Hydra Signals Indicator" in indicators
    assert "Totally Custom Indicator" not in indicators
    assert "Hydra Signals Indicator" in instances
    assert "Totally Custom Indicator" not in instances
