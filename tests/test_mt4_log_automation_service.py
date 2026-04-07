import shutil
import uuid
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
