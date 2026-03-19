from dashboard.backend.api.simulation_routes import _agent_guardrail_check_trade_risk


def test_trade_risk_cap_blocks_when_risk_exceeds_default_live_cap():
    out = _agent_guardrail_check_trade_risk(
        symbol="XAUUSD",
        entry_price=100.0,
        stop_loss=90.0,
        lot_size=1.0,
        cfg={},
        point_value_per_1lot=1.0,
        live_execution=True,
    )
    assert out["enabled"] is True
    assert out["ok"] is False
    assert out["error"] == "risk_cap_per_trade"
    assert float(out["cap_usd"]) == 5.0
    assert float(out["risk_usd"]) == 10.0


def test_trade_risk_cap_disabled_by_default_in_paper_mode():
    out = _agent_guardrail_check_trade_risk(
        symbol="XAUUSD",
        entry_price=100.0,
        stop_loss=90.0,
        lot_size=1.0,
        cfg={},
        point_value_per_1lot=1.0,
        live_execution=False,
    )
    assert out["enabled"] is False
    assert out["ok"] is True
    assert out["cap_usd"] is None


def test_trade_risk_cap_respects_configured_value():
    out = _agent_guardrail_check_trade_risk(
        symbol="XAUUSD",
        entry_price=100.0,
        stop_loss=90.0,
        lot_size=1.0,
        cfg={"guardrail_max_risk_per_trade_usd": 25.0},
        point_value_per_1lot=1.0,
    )
    assert out["enabled"] is True
    assert out["ok"] is True
    assert out["error"] is None
    assert float(out["cap_usd"]) == 25.0
    assert float(out["risk_usd"]) == 10.0


def test_trade_risk_cap_zero_disables_limit():
    out = _agent_guardrail_check_trade_risk(
        symbol="XAUUSD",
        entry_price=100.0,
        stop_loss=90.0,
        lot_size=1.0,
        cfg={"guardrail_max_risk_per_trade_usd": 0.0},
        point_value_per_1lot=1.0,
    )
    assert out["enabled"] is False
    assert out["ok"] is True
    assert out["cap_usd"] is None
