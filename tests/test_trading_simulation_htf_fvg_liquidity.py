from dashboard.backend.core.trading_simulation import adapters
from dashboard.backend.core.trading_simulation.education import get_strategy_guide
from dashboard.backend.core.trading_simulation.playbooks import get_playbook


def test_liquidity_reclaim_guide_and_playbook_exist():
    guide = get_strategy_guide("htf_fvg_liquidity_reclaim_strategy")
    playbook = get_playbook("htf_fvg_liquidity_reclaim_strategy")
    assert guide.get("strategy_id") == "htf_fvg_liquidity_reclaim_strategy"
    assert "higher-timeframe fair value gaps" in str(guide.get("what_this_strategy_is") or "").lower()
    assert playbook.get("strategy_id") == "htf_fvg_liquidity_reclaim_strategy"
    steps = playbook.get("steps") if isinstance(playbook.get("steps"), list) else []
    assert len(steps) == 5
    assert str(steps[1].get("ready_signal") or "") == "fvg_detected"
    assert str(steps[2].get("ready_signal") or "") == "sweep_detected"
    assert str(steps[3].get("ready_signal") or "") == "rejection_confirmed"


def test_build_telemetry_maps_liquidity_reclaim_state(monkeypatch):
    monkeypatch.setattr(
        adapters,
        "load_strategy_state",
        lambda strategy_id: (
            {
                "is_connected": True,
                "bias": "bullish",
                "bias_strength": 72,
                "entry_price": 5154.37,
                "stop_loss": 5148.16,
                "take_profit": 5226.77,
                "rr": 3.2,
                "setup_detected": True,
                "sweep_detected": True,
                "rejection_confirmed": True,
                "sweep_quality": "strong",
                "liquidity_level": 5150.0,
                "fvg_detected": True,
                "fvg_quality": "strong",
                "htf_timeframe": "H4",
            },
            True,
        ),
    )
    telemetry = adapters.build_telemetry(
        "htf_fvg_liquidity_reclaim_strategy",
        "XAUUSD",
        "M15",
        mode="live",
    )
    step_inputs = telemetry.get("step_inputs") if isinstance(telemetry.get("step_inputs"), dict) else {}
    signals = telemetry.get("signals") if isinstance(telemetry.get("signals"), dict) else {}
    assert step_inputs.get("fvg_quality") == "strong"
    assert step_inputs.get("htf_timeframe") == "H4"
    assert signals.get("fvg_detected") is True
    assert signals.get("sweep_detected") is True
    assert signals.get("rejection_confirmed") is True
    assert signals.get("risk_defined") is True
