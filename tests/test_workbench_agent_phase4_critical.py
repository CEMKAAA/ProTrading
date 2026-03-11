import json
from datetime import datetime, timedelta, timezone

from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from dashboard.backend.api import simulation_routes as sim_routes
from dashboard.backend.core.workbench.agent import WorkbenchAgent
from dashboard.backend.services.agent_watchdog_service import AgentWatchdogService
from dashboard.backend.models.database import (
    Base,
    SimulationSession,
    WorkbenchCopilotSessionModel,
    WorkbenchAgentSessionModel,
    WorkbenchAgentEventModel,
)


def _db_session():
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    Base.metadata.create_all(bind=engine)
    SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)
    return SessionLocal()


def test_claude_tool_specs_use_input_schema():
    specs = WorkbenchAgent._claude_tool_specs()
    assert isinstance(specs, list) and len(specs) > 0
    for row in specs:
        assert "input_schema" in row
        assert "parameters" not in row


def test_tool_specs_include_submit_proposed_actions_with_enum():
    specs = WorkbenchAgent._tool_specs()
    submit = None
    for row in specs:
        if isinstance(row, dict) and str(row.get("name") or "") == "submit_proposed_actions":
            submit = row
            break
    assert isinstance(submit, dict)
    params = submit.get("parameters") if isinstance(submit.get("parameters"), dict) else {}
    props = params.get("properties") if isinstance(params.get("properties"), dict) else {}
    pa = props.get("proposed_actions") if isinstance(props.get("proposed_actions"), dict) else {}
    items = pa.get("items") if isinstance(pa.get("items"), dict) else {}
    item_props = items.get("properties") if isinstance(items.get("properties"), dict) else {}
    action_type = item_props.get("action_type") if isinstance(item_props.get("action_type"), dict) else {}
    enum_vals = action_type.get("enum") if isinstance(action_type.get("enum"), list) else []
    assert "REVIEW_NOTE" in enum_vals
    assert "PROPOSE_TRADE_ENTRY" in enum_vals


def test_tool_specs_include_run_mtf_analysis():
    specs = WorkbenchAgent._tool_specs()
    names = {str(row.get("name") or "") for row in specs if isinstance(row, dict)}
    assert "run_mtf_analysis" in names


def test_schedule_trade_entry_tool_spec_does_not_expose_proposal_bypass_flag():
    specs = WorkbenchAgent._tool_specs()
    schedule = None
    for row in specs:
        if isinstance(row, dict) and str(row.get("name") or "") == "schedule_trade_entry":
            schedule = row
            break
    assert isinstance(schedule, dict)
    params = schedule.get("parameters") if isinstance(schedule.get("parameters"), dict) else {}
    props = params.get("properties") if isinstance(params.get("properties"), dict) else {}
    assert "allow_proposal_mismatch" not in props


def test_agent_user_allows_auto_schedule_requires_explicit_schedule_request():
    assert sim_routes._agent_user_allows_auto_schedule(
        "waiting for close above 5154.37"
    ) is False
    assert sim_routes._agent_user_allows_auto_schedule(
        "schedule trigger: wait for close above 5154.37 then buy"
    ) is True


def test_agent_user_allows_auto_schedule_respects_do_not_schedule_guard():
    assert sim_routes._agent_user_allows_auto_schedule(
        "do not schedule anything yet, print report sections first then we decide"
    ) is False
    assert sim_routes._agent_user_allows_auto_schedule(
        "do not arm now; analysis first"
    ) is False


def test_tool_call_log_uses_tool_id_key():
    agent = WorkbenchAgent()

    def _exec(name, args):
        return {"ok": True, "count": 1, "name": name, "args": args}

    out = agent.chat(
        message="scan fvg please",
        context={"bars": []},
        conversation_history=[],
        provider="deterministic",
        model_label=None,
        llm_url=None,
        api_key=None,
        timeout_sec=30,
        permissions={"can_scan_tools": True},
        tool_executor=_exec,
        allow_tools=True,
        max_tool_steps=2,
        objective="chat",
    )
    assert out.get("ok") is True
    calls = out.get("tool_calls") if isinstance(out.get("tool_calls"), list) else []
    assert len(calls) >= 1
    assert "tool_id" in calls[0]
    assert "tool_name" not in calls[0]


def test_normalize_tool_calls_supports_name_and_tool_id():
    rows = WorkbenchAgent._normalize_tool_calls(
        [
            {"name": "scan_tool", "args": {"tool_id": "fvg"}},
            {"tool_id": "set_indicator_visibility", "arguments": {"visibility": {"rsi": True}}},
            {"name": "", "args": {}},
        ]
    )
    assert len(rows) == 2
    assert rows[0]["name"] == "scan_tool"
    assert rows[0]["args"]["tool_id"] == "fvg"
    assert rows[1]["name"] == "set_indicator_visibility"
    assert isinstance(rows[1]["args"], dict)


def test_run_mtf_analysis_builds_trigger_candidate_from_deterministic_scans(monkeypatch):
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M15",
            mode="live",
            current_bar=0,
            total_bars=1,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        def _mk_bars(count=320, start=1700000000, step=900, base=120.0):
            rows = []
            px = float(base)
            for i in range(count):
                px = px + (0.03 if (i % 3) else -0.01)
                rows.append(
                    {
                        "time": int(start + (i * step)),
                        "open": round(px - 0.05, 5),
                        "high": round(px + 0.20, 5),
                        "low": round(px - 0.20, 5),
                        "close": round(px, 5),
                        "volume": 100.0 + i,
                    }
                )
            return rows

        monkeypatch.setattr(
            sim_routes,
            "_agent_fetch_live_history_bars",
            lambda **kwargs: (_mk_bars(), None),
        )

        def _fake_scan_tool_from_bars(**kwargs):
            tf = str(kwargs.get("timeframe") or "").upper()
            zones = []
            if tf == "D1":
                zones = [
                    {
                        "type": "bullish_fvg",
                        "top": 124.5,
                        "bottom": 123.0,
                        "gap_size": 1.5,
                        "current_gap_size": 1.5,
                        "mitigations": 0,
                        "filled": False,
                    }
                ]
            elif tf == "H4":
                zones = [
                    {
                        "type": "bullish_fvg",
                        "top": 125.0,
                        "bottom": 124.0,
                        "gap_size": 1.0,
                        "current_gap_size": 1.0,
                        "mitigations": 1,
                        "filled": False,
                    }
                ]
            elif tf == "M15":
                zones = [
                    {
                        "type": "bullish_fvg",
                        "top": 125.2,
                        "bottom": 124.8,
                        "gap_size": 0.4,
                        "current_gap_size": 0.4,
                        "mitigations": 0,
                        "filled": False,
                    }
                ]
            return {
                "ok": True,
                "data": {
                    "tool_id": "fvg",
                    "zones": zones,
                    "count": len(zones),
                    "scan_source": "agent_live_fetch",
                    "scan_timeframe": tf,
                    "trend": {"direction": "bullish"},
                    "movement_strength": {"score": 68.0, "state": "steady", "gas_low": False},
                    "current_state": {},
                },
            }

        monkeypatch.setattr(sim_routes, "_agent_scan_tool_from_bars", _fake_scan_tool_from_bars)

        out = sim_routes._agent_execute_tool(
            session=sim,
            db=db,
            permissions={"can_scan_tools": True, "can_chat": True},
            context_snapshot={"tool_state": {"market_context": {"symbol": "XAUUSD", "timeframe": "M15", "source": "mt5"}}},
            tool_name="run_mtf_analysis",
            args={
                "htf_timeframes": ["D1", "H4"],
                "execution_timeframe": "M15",
                "risk_percent": 0.5,
                "rr_target": 2.0,
                "include_news": False,
            },
            atomic=False,
        )
        assert out.get("ok") is True
        data = out.get("data") if isinstance(out.get("data"), dict) else {}
        assert data.get("trigger_ready") is True
        setup = data.get("best_setup") if isinstance(data.get("best_setup"), dict) else {}
        assert str(setup.get("direction") or "") == "BUY"
        assert str((setup.get("precondition") or {}).get("condition") or "") == "close_below"
        assert str((setup.get("condition") or {}).get("condition") or "") == "close_above"
        assert str((setup.get("cancel_rule") or {}).get("condition") or "") == "close_below"
        assert float(setup.get("rr") or 0.0) >= 1.9
        assert float(setup.get("lot_size") or 0.0) > 0.0
    finally:
        db.close()


def test_run_mtf_analysis_does_not_hard_block_on_unknown_htf_bias(monkeypatch):
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M15",
            mode="live",
            current_bar=0,
            total_bars=1,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        def _mk_bars(count=260, start=1700100000, step=900, base=118.0):
            rows = []
            px = float(base)
            for i in range(count):
                px = px + (0.02 if (i % 2) else -0.01)
                rows.append(
                    {
                        "time": int(start + (i * step)),
                        "open": round(px - 0.04, 5),
                        "high": round(px + 0.18, 5),
                        "low": round(px - 0.18, 5),
                        "close": round(px, 5),
                        "volume": 120.0 + i,
                    }
                )
            return rows

        monkeypatch.setattr(sim_routes, "_agent_fetch_live_history_bars", lambda **kwargs: (_mk_bars(), None))

        def _fake_scan_unknown_bias(**kwargs):
            tf = str(kwargs.get("timeframe") or "").upper()
            zones = []
            if tf in {"D1", "H4"}:
                zones = [
                    {
                        "type": "bullish_fvg",
                        "top": 119.0,
                        "bottom": 118.0,
                        "gap_size": 1.0,
                        "current_gap_size": 1.0,
                        "mitigations": 0,
                        "filled": False,
                    }
                ]
            return {
                "ok": True,
                "data": {
                    "tool_id": "fvg",
                    "zones": zones,
                    "count": len(zones),
                    "scan_source": "agent_live_fetch",
                    "scan_timeframe": tf,
                    "trend": {"direction": "unknown"},
                    "movement_strength": {"score": 50.0, "state": "no_impulse", "gas_low": False},
                    "current_state": {},
                },
            }

        monkeypatch.setattr(sim_routes, "_agent_scan_tool_from_bars", _fake_scan_unknown_bias)

        out = sim_routes._agent_execute_tool(
            session=sim,
            db=db,
            permissions={"can_scan_tools": True, "can_chat": True},
            context_snapshot={"tool_state": {"market_context": {"symbol": "XAUUSD", "timeframe": "M15", "source": "mt5"}}},
            tool_name="run_mtf_analysis",
            args={"htf_timeframes": ["D1", "H4"], "execution_timeframe": "M15", "include_news": False},
            atomic=False,
        )
        assert out.get("ok") is True
        data = out.get("data") if isinstance(out.get("data"), dict) else {}
        assert data.get("trigger_ready") is True
        assert "htf_bias_unknown" in (data.get("confidence_warnings") if isinstance(data.get("confidence_warnings"), list) else [])
        setup = data.get("best_setup") if isinstance(data.get("best_setup"), dict) else {}
        assert str(setup.get("direction") or "") == "BUY"
    finally:
        db.close()


def test_run_mtf_analysis_blocks_when_all_htf_anchors_are_too_distant(monkeypatch):
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M15",
            mode="live",
            current_bar=0,
            total_bars=1,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        def _mk_bars(count=280, start=1700200000, step=900, base=120.0):
            rows = []
            px = float(base)
            for i in range(count):
                px = px + (0.025 if (i % 2) else -0.01)
                rows.append(
                    {
                        "time": int(start + (i * step)),
                        "open": round(px - 0.04, 5),
                        "high": round(px + 0.20, 5),
                        "low": round(px - 0.20, 5),
                        "close": round(px, 5),
                        "volume": 100.0 + i,
                    }
                )
            return rows

        monkeypatch.setattr(sim_routes, "_agent_fetch_live_history_bars", lambda **kwargs: (_mk_bars(), None))

        def _fake_scan_far(**kwargs):
            tf = str(kwargs.get("timeframe") or "").upper()
            zones = []
            if tf in {"D1", "H4"}:
                zones = [
                    {
                        "type": "bullish_fvg",
                        "top": 103.0,
                        "bottom": 102.0,
                        "gap_size": 1.0,
                        "current_gap_size": 1.0,
                        "mitigations": 0,
                        "filled": False,
                    }
                ]
            return {
                "ok": True,
                "data": {
                    "tool_id": "fvg",
                    "zones": zones,
                    "count": len(zones),
                    "scan_source": "agent_live_fetch",
                    "scan_timeframe": tf,
                    "trend": {"direction": "bullish"},
                    "movement_strength": {"score": 62.0, "state": "steady", "gas_low": False},
                    "current_state": {},
                },
            }

        monkeypatch.setattr(sim_routes, "_agent_scan_tool_from_bars", _fake_scan_far)

        out = sim_routes._agent_execute_tool(
            session=sim,
            db=db,
            permissions={"can_scan_tools": True, "can_chat": True},
            context_snapshot={"tool_state": {"market_context": {"symbol": "XAUUSD", "timeframe": "M15", "source": "mt5"}}},
            tool_name="run_mtf_analysis",
            args={"htf_timeframes": ["D1", "H4"], "execution_timeframe": "M15", "include_news": False},
            atomic=False,
        )
        assert out.get("ok") is True
        data = out.get("data") if isinstance(out.get("data"), dict) else {}
        assert data.get("trigger_ready") is True
        assert data.get("manual_confirmation_required") is True
        assert "no_execution_relevant_anchor" in (data.get("soft_blockers") if isinstance(data.get("soft_blockers"), list) else [])
        assert len(data.get("htf_anchors") if isinstance(data.get("htf_anchors"), list) else []) >= 1
        assert len(data.get("htf_context_only_anchors") if isinstance(data.get("htf_context_only_anchors"), list) else []) >= 1
    finally:
        db.close()


def test_run_mtf_analysis_derates_risk_when_ltf_is_exhausted(monkeypatch):
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M15",
            mode="live",
            current_bar=0,
            total_bars=1,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        def _mk_bars(count=320, start=1700300000, step=900, base=120.0):
            rows = []
            px = float(base)
            for i in range(count):
                px = px + (0.03 if (i % 3) else -0.01)
                rows.append(
                    {
                        "time": int(start + (i * step)),
                        "open": round(px - 0.05, 5),
                        "high": round(px + 0.20, 5),
                        "low": round(px - 0.20, 5),
                        "close": round(px, 5),
                        "volume": 100.0 + i,
                    }
                )
            return rows

        monkeypatch.setattr(sim_routes, "_agent_fetch_live_history_bars", lambda **kwargs: (_mk_bars(), None))

        def _fake_scan_exhausted(**kwargs):
            tf = str(kwargs.get("timeframe") or "").upper()
            zones = []
            if tf == "D1":
                zones = [{"type": "bullish_fvg", "top": 124.6, "bottom": 123.6, "gap_size": 1.0, "current_gap_size": 1.0, "mitigations": 0, "filled": False}]
            elif tf == "H4":
                zones = [{"type": "bullish_fvg", "top": 125.1, "bottom": 124.2, "gap_size": 0.9, "current_gap_size": 0.9, "mitigations": 0, "filled": False}]
            elif tf == "M15":
                zones = [{"type": "bullish_fvg", "top": 125.3, "bottom": 124.9, "gap_size": 0.4, "current_gap_size": 0.4, "mitigations": 0, "filled": False}]
            movement = {"score": 15.0, "state": "exhausted", "gas_low": True} if tf == "M15" else {"score": 58.0, "state": "steady", "gas_low": False}
            return {
                "ok": True,
                "data": {
                    "tool_id": "fvg",
                    "zones": zones,
                    "count": len(zones),
                    "scan_source": "agent_live_fetch",
                    "scan_timeframe": tf,
                    "trend": {"direction": "bullish"},
                    "movement_strength": movement,
                    "current_state": {},
                },
            }

        monkeypatch.setattr(sim_routes, "_agent_scan_tool_from_bars", _fake_scan_exhausted)

        out = sim_routes._agent_execute_tool(
            session=sim,
            db=db,
            permissions={"can_scan_tools": True, "can_chat": True},
            context_snapshot={"tool_state": {"market_context": {"symbol": "XAUUSD", "timeframe": "M15", "source": "mt5"}}},
            tool_name="run_mtf_analysis",
            args={"htf_timeframes": ["D1", "H4"], "execution_timeframe": "M15", "risk_percent": 0.5, "include_news": False},
            atomic=False,
        )
        assert out.get("ok") is True
        data = out.get("data") if isinstance(out.get("data"), dict) else {}
        assert data.get("trigger_ready") is True
        setup = data.get("best_setup") if isinstance(data.get("best_setup"), dict) else {}
        assert bool(setup.get("risk_derated")) is True
        assert float(setup.get("requested_risk_percent") or 0.0) == 0.5
        assert float(setup.get("risk_percent") or 0.0) <= 0.25
        calc_trace = setup.get("calc_trace") if isinstance(setup.get("calc_trace"), dict) else {}
        assert "price_increment" in calc_trace
        assert "money_per_price_unit_per_1lot" in calc_trace
        warnings = setup.get("warnings") if isinstance(setup.get("warnings"), list) else []
        assert any("Risk derated for exhausted movement" in str(w) for w in warnings)
    finally:
        db.close()


def test_run_mtf_analysis_uses_atr_proxy_when_indicators_unavailable(monkeypatch):
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M15",
            mode="live",
            current_bar=0,
            total_bars=1,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        def _mk_bars(count=25, start=1700400000, step=900, base=120.0):
            rows = []
            px = float(base)
            for i in range(count):
                px = px + (0.02 if (i % 2) else -0.01)
                rows.append(
                    {
                        "time": int(start + (i * step)),
                        "open": round(px - 0.03, 5),
                        "high": round(px + 0.18, 5),
                        "low": round(px - 0.18, 5),
                        "close": round(px, 5),
                        "volume": 80.0 + i,
                    }
                )
            return rows

        monkeypatch.setattr(sim_routes, "_agent_fetch_live_history_bars", lambda **kwargs: (_mk_bars(), None))

        def _fake_scan_far_no_ind(**kwargs):
            tf = str(kwargs.get("timeframe") or "").upper()
            zones = []
            if tf in {"D1", "H4"}:
                zones = [{"type": "bullish_fvg", "top": 104.0, "bottom": 103.0, "gap_size": 1.0, "current_gap_size": 1.0, "mitigations": 0, "filled": False}]
            return {
                "ok": True,
                "data": {
                    "tool_id": "fvg",
                    "zones": zones,
                    "count": len(zones),
                    "scan_source": "agent_live_fetch",
                    "scan_timeframe": tf,
                    "trend": {"direction": "bullish"},
                    "movement_strength": {"score": 55.0, "state": "steady", "gas_low": False},
                    "current_state": {},
                },
            }

        monkeypatch.setattr(sim_routes, "_agent_scan_tool_from_bars", _fake_scan_far_no_ind)

        out = sim_routes._agent_execute_tool(
            session=sim,
            db=db,
            permissions={"can_scan_tools": True, "can_chat": True},
            context_snapshot={"tool_state": {"market_context": {"symbol": "XAUUSD", "timeframe": "M15", "source": "mt5"}}},
            tool_name="run_mtf_analysis",
            args={"htf_timeframes": ["D1", "H4"], "execution_timeframe": "M15", "include_news": False},
            atomic=False,
        )
        assert out.get("ok") is True
        data = out.get("data") if isinstance(out.get("data"), dict) else {}
        assert data.get("trigger_ready") is True
        assert data.get("auto_schedule_allowed") is False
        assert data.get("manual_confirmation_required") is True
        soft_blockers = data.get("soft_blockers") if isinstance(data.get("soft_blockers"), list) else []
        assert "no_execution_relevant_anchor" in soft_blockers
    finally:
        db.close()


def test_proposed_actions_unknown_types_are_normalized():
    rows = WorkbenchAgent._normalize_proposed_actions(
        [
            {"action_type": "MONITOR", "summary": "Keep watching", "payload": {}, "confidence": 0.7},
            {"action_type": "TRADE_SETUP", "summary": "Potential long setup", "payload": {}, "confidence": 0.8},
            {"action_type": "RESEARCH", "summary": "Run optimizer", "payload": {}, "confidence": 0.6},
            {"action_type": "GARBAGE", "summary": "Bad label", "payload": {}, "confidence": 0.5},
        ]
    )
    assert len(rows) == 4
    assert rows[0]["action_type"] == "REVIEW_NOTE"
    assert rows[1]["action_type"] == "PROPOSE_TRADE_ENTRY"
    assert rows[2]["action_type"] == "RUN_RESEARCH_OPTIMIZER"
    assert rows[3]["action_type"] == "REVIEW_NOTE"


def test_route_level_action_normalization_is_safe():
    rows = sim_routes._normalize_agent_proposed_actions(
        [
            {"action_type": "MONITOR", "summary": "watch", "payload": {}, "confidence": 0.6},
            {"action_type": "TRADE_SETUP", "summary": "setup", "payload": {}, "confidence": 0.6},
            {"action_type": "WEIRD_ACTION", "summary": "fallback", "payload": {}, "confidence": 0.6},
        ]
    )
    assert [r["action_type"] for r in rows] == [
        "REVIEW_NOTE",
        "PROPOSE_TRADE_ENTRY",
        "REVIEW_NOTE",
    ]


def test_local_gptoss_two_pass_tool_flow_executes_requested_tools():
    agent = WorkbenchAgent()
    calls = []
    responses = [
        json.dumps(
            {
                "reply": "Need scan first",
                "tool_calls": [
                    {"name": "scan_tool", "args": {"tool_id": "fvg", "config": {"timeframe": "M15"}}}
                ],
                "proposed_actions": [],
            }
        ),
        json.dumps(
            {
                "reply": "Completed after scan",
                "proposed_actions": [
                    {
                        "action_type": "REVIEW_NOTE",
                        "summary": "Observed one bullish zone",
                        "payload": {},
                        "confidence": 0.8,
                    }
                ],
            }
        ),
    ]

    def _fake_local_call(*, message, system_prompt, model_label, llm_url, timeout_sec):
        _ = (message, system_prompt, model_label, llm_url, timeout_sec)
        if responses:
            return responses.pop(0)
        return json.dumps({"reply": "fallback", "proposed_actions": []})

    def _exec(name, args):
        calls.append((name, args))
        return {"ok": True, "data": {"tool_id": "fvg", "count": 1, "zones": []}}

    # Monkeypatch method on instance for deterministic testing without HTTP.
    agent._chat_local_gptoss = _fake_local_call  # type: ignore[attr-defined]

    out = agent.chat(
        message="scan fvg please",
        context={"bars": []},
        conversation_history=[],
        provider="local_gptoss_http",
        model_label="gpt-oss-20b",
        llm_url="http://127.0.0.1:8012",
        api_key=None,
        timeout_sec=30,
        permissions={"can_scan_tools": True},
        tool_executor=_exec,
        allow_tools=True,
        max_tool_steps=3,
        objective="chat",
    )
    assert out.get("ok") is True
    assert str(out.get("reply") or "").startswith("Completed")
    tool_calls = out.get("tool_calls") if isinstance(out.get("tool_calls"), list) else []
    assert len(tool_calls) == 1
    assert tool_calls[0].get("tool_id") == "scan_tool"
    assert len(calls) == 1
    assert calls[0][0] == "scan_tool"


def test_local_gptoss_submit_actions_tool_is_authoritative():
    agent = WorkbenchAgent()
    calls = []

    def _fake_local_call(*, message, system_prompt, model_label, llm_url, timeout_sec):
        _ = (message, system_prompt, model_label, llm_url, timeout_sec)
        return json.dumps(
            {
                "reply": "Using structured action submit",
                "tool_calls": [
                    {
                        "name": "submit_proposed_actions",
                        "args": {
                            "proposed_actions": [
                                {
                                    "action_type": "PROPOSE_TRADE_ENTRY",
                                    "summary": "Potential long setup near bullish FVG.",
                                    "payload": {"direction": "BUY"},
                                    "confidence": 0.71,
                                }
                            ]
                        },
                    }
                ],
            }
        )

    def _exec(name, args):
        calls.append((name, args))
        return {"ok": True}

    agent._chat_local_gptoss = _fake_local_call  # type: ignore[attr-defined]

    out = agent.chat(
        message="Propose next action",
        context={"bars": []},
        conversation_history=[],
        provider="local_gptoss_http",
        model_label="gpt-oss-20b",
        llm_url="http://127.0.0.1:8012",
        api_key=None,
        timeout_sec=30,
        permissions={"can_scan_tools": True},
        tool_executor=_exec,
        allow_tools=True,
        max_tool_steps=3,
        objective="chat",
    )
    assert out.get("ok") is True
    assert len(calls) == 0
    actions = out.get("proposed_actions") if isinstance(out.get("proposed_actions"), list) else []
    assert len(actions) == 1
    assert actions[0].get("action_type") == "PROPOSE_TRADE_ENTRY"


def test_agent_tool_call_schema_keeps_result_payload():
    tc = sim_routes.AgentToolCall(
        tool_id="scan_tool",
        args={"tool_id": "fvg"},
        result={"ok": True, "data": {"tool_id": "fvg", "count": 2}},
    )
    assert tc.tool_id == "scan_tool"
    assert isinstance(tc.result, dict)
    assert tc.result.get("ok") is True


def test_agent_context_snapshot_sanitizes_inbound_payload():
    bars = [{"time": i, "open": 1, "high": 2, "low": 0.5, "close": 1.5, "volume": 10} for i in range(1, 5000)]
    bars.append({"time": "bad", "open": "x"})  # invalid row should be dropped
    snap = sim_routes.AgentContextSnapshot(
        bars=bars,
        open_positions=[{"id": i} for i in range(800)],
        recent_trades=[{"id": i} for i in range(800)],
        tool_state={"blob": "x" * (300 * 1024)},  # force compaction
    )
    assert len(snap.bars) <= int(sim_routes._AGENT_CONTEXT_BARS_MAX_INBOUND)
    assert all(isinstance(row, dict) and int(row.get("time") or 0) > 0 for row in snap.bars)
    assert len(snap.open_positions) <= int(sim_routes._AGENT_CONTEXT_ITEMS_MAX_INBOUND)
    assert len(snap.recent_trades) <= int(sim_routes._AGENT_CONTEXT_ITEMS_MAX_INBOUND)
    assert isinstance(snap.tool_state, dict)


def test_agent_chat_request_max_tool_steps_guard():
    try:
        sim_routes.AgentChatRequest(
            message="x",
            max_tool_steps=99,
        )
        assert False, "Expected validation error for max_tool_steps"
    except Exception:
        pass


def test_agent_tool_state_route_rejects_oversized_payload():
    db = _db_session()
    try:
        req = sim_routes.CopilotToolStateRequest(
            tool_state={"blob": "x" * (300 * 1024)},
            event_type="TOOL_SIGNAL_CHANGED",
            severity="info",
        )
        try:
            sim_routes.workbench_agent_tool_state(session_id=1, req=req, db=db)
            assert False, "Expected HTTPException for oversized payload"
        except HTTPException as exc:
            assert int(exc.status_code) == 413
    finally:
        db.close()


def test_schedule_trade_entry_accepts_cancel_rule_fields():
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M15",
            mode="replay",
            current_bar=0,
            total_bars=100,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        agent_row = sim_routes._ensure_agent_session(
            simulation_session_id=int(sim.id),
            db=db,
            mode="LOOP",
            provider="deterministic",
            model_label=None,
            permissions={"can_place_trades": True},
            config={},
            runtime={},
            copilot_session_id=None,
        )
        db.flush()

        out = sim_routes._agent_execute_tool(
            session=sim,
            db=db,
            permissions={"can_place_trades": True},
            context_snapshot={},
            tool_name="schedule_trade_entry",
            args={
                "condition": "close_above",
                "trigger_price": 5105.97,
                "direction": "BUY",
                "stop_loss": 5092.80,
                "take_profit": 5134.00,
                "lot_size": 0.1,
                "timeframe": "M15",
                "cancel_condition": "close_below",
                "cancel_trigger_price": 5093.30,
            },
            atomic=True,
        )
        assert out.get("ok") is True
        trigger = (out.get("data") or {}).get("trigger") if isinstance(out.get("data"), dict) else None
        assert isinstance(trigger, dict)
        cancel_rule = trigger.get("cancel_rule") if isinstance(trigger.get("cancel_rule"), dict) else {}
        assert str(cancel_rule.get("condition") or "") == "close_below"
        assert abs(float(cancel_rule.get("trigger_price")) - 5093.30) < 1e-9

        rows = sim_routes._agent_trigger_rows_from_agent(agent_row)
        assert len(rows) >= 1
        row_cancel = rows[0].get("cancel_rule") if isinstance(rows[0].get("cancel_rule"), dict) else {}
        assert str(row_cancel.get("condition") or "") == "close_below"
        assert abs(float(row_cancel.get("trigger_price")) - 5093.30) < 1e-9
    finally:
        db.close()


def test_schedule_trade_entry_rejects_cancel_rule_equal_to_entry():
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M15",
            mode="replay",
            current_bar=0,
            total_bars=100,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        sim_routes._ensure_agent_session(
            simulation_session_id=int(sim.id),
            db=db,
            mode="LOOP",
            provider="deterministic",
            model_label=None,
            permissions={"can_place_trades": True},
            config={},
            runtime={},
            copilot_session_id=None,
        )
        db.flush()

        out = sim_routes._agent_execute_tool(
            session=sim,
            db=db,
            permissions={"can_place_trades": True},
            context_snapshot={},
            tool_name="schedule_trade_entry",
            args={
                "condition": "close_above",
                "trigger_price": 5105.97,
                "direction": "BUY",
                "stop_loss": 5092.80,
                "cancel_condition": "close_above",
                "cancel_trigger_price": 5105.97,
            },
            atomic=True,
        )
        assert out.get("ok") is False
        assert str(out.get("error") or "") == "cancel_rule_must_differ_from_entry_condition"
    finally:
        db.close()


def test_watchdog_cancels_trigger_when_cancel_rule_hits_before_entry():
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M15",
            mode="replay",
            current_bar=0,
            total_bars=100,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        agent_row = sim_routes._ensure_agent_session(
            simulation_session_id=int(sim.id),
            db=db,
            mode="LOOP",
            provider="deterministic",
            model_label=None,
            permissions={"can_place_trades": True, "requires_user_confirm_for_trade": False},
            config={"agent_permissions": {"can_place_trades": True, "requires_user_confirm_for_trade": False}},
            runtime={},
            copilot_session_id=None,
        )
        db.flush()

        out = sim_routes._agent_execute_tool(
            session=sim,
            db=db,
            permissions={"can_place_trades": True},
            context_snapshot={},
            tool_name="schedule_trade_entry",
            args={
                "condition": "close_above",
                "trigger_price": 5105.97,
                "direction": "BUY",
                "stop_loss": 5092.80,
                "take_profit": 5134.00,
                "lot_size": 0.1,
                "timeframe": "M15",
                "cancel_rule": {"condition": "price_below", "trigger_price": 5093.30},
            },
            atomic=True,
        )
        assert out.get("ok") is True

        svc = AgentWatchdogService()
        events = svc._process_entry_triggers(
            db=db,
            agent=agent_row,
            session=sim,
            now=datetime.now(timezone.utc),
            current_price=5092.0,
            closed_bar={"time": 1772520000, "close": 5092.0},
        )
        assert isinstance(events, list)
        assert any(str(getattr(e, "event_type", "")).upper() == "WATCHDOG_ENTRY_CANCELED" for e in events)

        rows = sim_routes._agent_trigger_rows_from_agent(agent_row)
        assert len(rows) >= 1
        first = rows[0]
        assert str(first.get("status") or "").lower() == "canceled"
        assert str(first.get("cancel_reason") or "") == "cancel_rule_hit"
    finally:
        db.close()


def test_watchdog_close_based_cancel_uses_closed_bar_not_tick():
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M15",
            mode="replay",
            current_bar=0,
            total_bars=100,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        agent_row = sim_routes._ensure_agent_session(
            simulation_session_id=int(sim.id),
            db=db,
            mode="LOOP",
            provider="deterministic",
            model_label=None,
            permissions={"can_place_trades": True, "requires_user_confirm_for_trade": False},
            config={"agent_permissions": {"can_place_trades": True, "requires_user_confirm_for_trade": False}},
            runtime={},
            copilot_session_id=None,
        )
        db.flush()

        out = sim_routes._agent_execute_tool(
            session=sim,
            db=db,
            permissions={"can_place_trades": True},
            context_snapshot={},
            tool_name="schedule_trade_entry",
            args={
                "condition": "close_above",
                "trigger_price": 5200.0,
                "direction": "BUY",
                "stop_loss": 5180.0,
                "take_profit": 5240.0,
                "lot_size": 0.1,
                "timeframe": "M15",
                "cancel_rule": {"condition": "close_below", "trigger_price": 5093.30},
            },
            atomic=True,
        )
        assert out.get("ok") is True

        svc = AgentWatchdogService()
        events = svc._process_entry_triggers(
            db=db,
            agent=agent_row,
            session=sim,
            now=datetime.now(timezone.utc),
            current_price=5088.0,  # tick below cancel level
            closed_bar={"time": 1772520600, "close": 5100.0},  # close is above cancel level -> should NOT cancel
        )
        assert isinstance(events, list)
        assert not any(str(getattr(e, "event_type", "")).upper() == "WATCHDOG_ENTRY_CANCELED" for e in events)

        rows = sim_routes._agent_trigger_rows_from_agent(agent_row)
        assert len(rows) >= 1
        assert str(rows[0].get("status") or "").lower() == "pending"
    finally:
        db.close()


def test_watchdog_cancel_miss_keeps_trigger_pending():
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M15",
            mode="replay",
            current_bar=0,
            total_bars=100,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        agent_row = sim_routes._ensure_agent_session(
            simulation_session_id=int(sim.id),
            db=db,
            mode="LOOP",
            provider="deterministic",
            model_label=None,
            permissions={"can_place_trades": True, "requires_user_confirm_for_trade": False},
            config={"agent_permissions": {"can_place_trades": True, "requires_user_confirm_for_trade": False}},
            runtime={},
            copilot_session_id=None,
        )
        db.flush()

        out = sim_routes._agent_execute_tool(
            session=sim,
            db=db,
            permissions={"can_place_trades": True},
            context_snapshot={},
            tool_name="schedule_trade_entry",
            args={
                "condition": "close_above",
                "trigger_price": 5200.0,
                "direction": "BUY",
                "stop_loss": 5180.0,
                "take_profit": 5240.0,
                "lot_size": 0.1,
                "timeframe": "M15",
                "cancel_rule": {"condition": "price_below", "trigger_price": 5093.30},
            },
            atomic=True,
        )
        assert out.get("ok") is True

        svc = AgentWatchdogService()
        events = svc._process_entry_triggers(
            db=db,
            agent=agent_row,
            session=sim,
            now=datetime.now(timezone.utc),
            current_price=5100.0,  # does not hit price_below 5093.30
            closed_bar={"time": 1772521200, "close": 5100.0},
        )
        assert isinstance(events, list)
        assert not any(str(getattr(e, "event_type", "")).upper() == "WATCHDOG_ENTRY_CANCELED" for e in events)
        rows = sim_routes._agent_trigger_rows_from_agent(agent_row)
        assert str(rows[0].get("status") or "").lower() == "pending"
    finally:
        db.close()


def test_watchdog_cancel_applies_during_waiting_precondition_state():
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M15",
            mode="replay",
            current_bar=0,
            total_bars=100,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        agent_row = sim_routes._ensure_agent_session(
            simulation_session_id=int(sim.id),
            db=db,
            mode="LOOP",
            provider="deterministic",
            model_label=None,
            permissions={"can_place_trades": True, "requires_user_confirm_for_trade": False},
            config={"agent_permissions": {"can_place_trades": True, "requires_user_confirm_for_trade": False}},
            runtime={},
            copilot_session_id=None,
        )
        db.flush()

        out = sim_routes._agent_execute_tool(
            session=sim,
            db=db,
            permissions={"can_place_trades": True},
            context_snapshot={},
            tool_name="schedule_trade_entry",
            args={
                "condition": "close_above",
                "trigger_price": 5310.0,
                "precondition": {"condition": "close_above", "trigger_price": 5300.0},
                "direction": "BUY",
                "stop_loss": 5280.0,
                "take_profit": 5350.0,
                "lot_size": 0.1,
                "timeframe": "M15",
                "cancel_rule": {"condition": "price_below", "trigger_price": 5093.30},
            },
            atomic=True,
        )
        assert out.get("ok") is True

        svc = AgentWatchdogService()
        events = svc._process_entry_triggers(
            db=db,
            agent=agent_row,
            session=sim,
            now=datetime.now(timezone.utc),
            current_price=5090.0,  # cancel hits before precondition can arm
            closed_bar={"time": 1772521800, "close": 5090.0},
        )
        assert isinstance(events, list)
        assert any(str(getattr(e, "event_type", "")).upper() == "WATCHDOG_ENTRY_CANCELED" for e in events)
        rows = sim_routes._agent_trigger_rows_from_agent(agent_row)
        assert str(rows[0].get("status") or "").lower() == "canceled"
    finally:
        db.close()


def test_watchdog_price_below_precondition_uses_live_low_touch():
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M15",
            mode="replay",
            current_bar=0,
            total_bars=100,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        agent_row = sim_routes._ensure_agent_session(
            simulation_session_id=int(sim.id),
            db=db,
            mode="LOOP",
            provider="deterministic",
            model_label=None,
            permissions={"can_place_trades": True, "requires_user_confirm_for_trade": False},
            config={"agent_permissions": {"can_place_trades": True, "requires_user_confirm_for_trade": False}},
            runtime={},
            copilot_session_id=None,
        )
        db.flush()

        out = sim_routes._agent_execute_tool(
            session=sim,
            db=db,
            permissions={"can_place_trades": True},
            context_snapshot={},
            tool_name="schedule_trade_entry",
            args={
                "condition": "close_above",
                "trigger_price": 5186.83,
                "precondition": {"condition": "price_below", "trigger_price": 5186.83},
                "direction": "BUY",
                "stop_loss": 5148.16,
                "take_profit": 5226.77,
                "lot_size": 0.01,
                "timeframe": "M15",
            },
            atomic=True,
        )
        assert out.get("ok") is True

        svc = AgentWatchdogService()
        now_utc = datetime.now(timezone.utc)
        fresh_ts = int(now_utc.timestamp())
        events = svc._process_entry_triggers(
            db=db,
            agent=agent_row,
            session=sim,
            now=now_utc,
            current_price=5189.35,  # sampled price is above level
            closed_bar={"time": fresh_ts - 60, "close": 5189.35},
            current_live_bar={"time": fresh_ts, "low": 5184.58, "high": 5190.10, "close": 5189.35},
        )
        assert isinstance(events, list)
        assert any(str(getattr(e, "event_type", "")).upper() == "WATCHDOG_ENTRY_STAGE_ADVANCED" for e in events)

        rows = sim_routes._agent_trigger_rows_from_agent(agent_row)
        assert len(rows) >= 1
        first = rows[0]
        assert str(first.get("status") or "").lower() == "pending"
        assert str(first.get("state") or "").lower() == "waiting_entry"
        pre = first.get("precondition") if isinstance(first.get("precondition"), dict) else {}
        assert abs(float(pre.get("hit_price")) - 5184.58) < 1e-9
    finally:
        db.close()


def test_watchdog_does_not_arm_price_precondition_from_stale_live_bar():
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M15",
            mode="replay",
            current_bar=0,
            total_bars=100,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        agent_row = sim_routes._ensure_agent_session(
            simulation_session_id=int(sim.id),
            db=db,
            mode="LOOP",
            provider="deterministic",
            model_label=None,
            permissions={"can_place_trades": True, "requires_user_confirm_for_trade": False},
            config={"agent_permissions": {"can_place_trades": True, "requires_user_confirm_for_trade": False}},
            runtime={},
            copilot_session_id=None,
        )
        db.flush()

        out = sim_routes._agent_execute_tool(
            session=sim,
            db=db,
            permissions={"can_place_trades": True},
            context_snapshot={},
            tool_name="schedule_trade_entry",
            args={
                "condition": "close_above",
                "trigger_price": 5186.83,
                "precondition": {"condition": "price_below", "trigger_price": 5186.83},
                "direction": "BUY",
                "stop_loss": 5148.16,
                "take_profit": 5226.77,
                "lot_size": 0.01,
                "timeframe": "M15",
            },
            atomic=True,
        )
        assert out.get("ok") is True

        stale_bar_ts = int((datetime.now(timezone.utc) - timedelta(minutes=30)).timestamp())
        svc = AgentWatchdogService()
        events = svc._process_entry_triggers(
            db=db,
            agent=agent_row,
            session=sim,
            now=datetime.now(timezone.utc),
            current_price=5189.35,
            closed_bar={"time": stale_bar_ts - 60, "close": 5189.35},
            current_live_bar={"time": stale_bar_ts, "low": 5184.58, "high": 5190.10, "close": 5189.35},
            live_bar_max_age_sec=120.0,
        )
        assert isinstance(events, list)
        assert not any(str(getattr(e, "event_type", "")).upper() == "WATCHDOG_ENTRY_STAGE_ADVANCED" for e in events)

        rows = sim_routes._agent_trigger_rows_from_agent(agent_row)
        assert len(rows) >= 1
        first = rows[0]
        assert str(first.get("status") or "").lower() == "pending"
        assert str(first.get("state") or "").lower() == "waiting_precondition"
    finally:
        db.close()


def test_watchdog_close_condition_recovers_after_restart_from_trigger_last_live_bar():
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M15",
            mode="replay",
            current_bar=0,
            total_bars=100,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        agent_row = sim_routes._ensure_agent_session(
            simulation_session_id=int(sim.id),
            db=db,
            mode="LOOP",
            provider="deterministic",
            model_label=None,
            permissions={"can_place_trades": True, "requires_user_confirm_for_trade": False},
            config={"agent_permissions": {"can_place_trades": True, "requires_user_confirm_for_trade": False}},
            runtime={},
            copilot_session_id=None,
        )
        db.flush()

        out = sim_routes._agent_execute_tool(
            session=sim,
            db=db,
            permissions={"can_place_trades": True},
            context_snapshot={},
            tool_name="schedule_trade_entry",
            args={
                "condition": "close_above",
                "trigger_price": 5200.0,
                "direction": "BUY",
                "stop_loss": 5190.0,
                "take_profit": 5230.0,
                "lot_size": 0.01,
                "timeframe": "M15",
            },
            atomic=True,
        )
        assert out.get("ok") is True

        snap = agent_row.last_snapshot_json if isinstance(agent_row.last_snapshot_json, dict) else {}
        tr = snap.get("agent_trade_triggers") if isinstance(snap.get("agent_trade_triggers"), list) else []
        assert len(tr) >= 1
        now_utc = datetime.now(timezone.utc)
        prev_ts = int(now_utc.timestamp()) - 60
        tr[0]["_last_live_bar"] = {"time": int(prev_ts), "close": 5205.0}
        snap["agent_trade_triggers"] = tr
        agent_row.last_snapshot_json = snap
        db.add(agent_row)
        db.flush()

        svc = AgentWatchdogService()
        events = svc._process_entry_triggers(
            db=db,
            agent=agent_row,
            session=sim,
            now=now_utc,
            current_price=5210.0,
            closed_bar=None,  # simulates restart: in-memory previous bar cache empty
            current_live_bar={"time": int(prev_ts + 60), "low": 5208.0, "high": 5212.0, "close": 5210.0},
            live_bar_max_age_sec=120.0,
        )
        assert isinstance(events, list)
        assert any(str(getattr(e, "event_type", "")).upper() == "WATCHDOG_ENTRY_EXECUTED" for e in events)

        rows = sim_routes._agent_trigger_rows_from_agent(agent_row)
        assert len(rows) >= 1
        first = rows[0]
        assert str(first.get("status") or "").lower() == "executed"
    finally:
        db.close()


def test_schedule_trade_entry_rejects_incomplete_cancel_fields():
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M15",
            mode="replay",
            current_bar=0,
            total_bars=100,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        sim_routes._ensure_agent_session(
            simulation_session_id=int(sim.id),
            db=db,
            mode="LOOP",
            provider="deterministic",
            model_label=None,
            permissions={"can_place_trades": True},
            config={},
            runtime={},
            copilot_session_id=None,
        )
        db.flush()

        out = sim_routes._agent_execute_tool(
            session=sim,
            db=db,
            permissions={"can_place_trades": True},
            context_snapshot={},
            tool_name="schedule_trade_entry",
            args={
                "condition": "close_above",
                "trigger_price": 5105.97,
                "direction": "BUY",
                "stop_loss": 5092.80,
                "cancel_condition": "close_below",
            },
            atomic=True,
        )
        assert out.get("ok") is False
        assert str(out.get("error") or "") == "cancel_rule_incomplete:provide_condition_and_trigger_price"
    finally:
        db.close()


def test_schedule_trade_entry_empty_cancel_rule_is_ignored():
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M15",
            mode="replay",
            current_bar=0,
            total_bars=100,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        sim_routes._ensure_agent_session(
            simulation_session_id=int(sim.id),
            db=db,
            mode="LOOP",
            provider="deterministic",
            model_label=None,
            permissions={"can_place_trades": True},
            config={},
            runtime={},
            copilot_session_id=None,
        )
        db.flush()

        out = sim_routes._agent_execute_tool(
            session=sim,
            db=db,
            permissions={"can_place_trades": True},
            context_snapshot={},
            tool_name="schedule_trade_entry",
            args={
                "condition": "close_above",
                "trigger_price": 5105.97,
                "direction": "BUY",
                "stop_loss": 5092.80,
                "take_profit": 5134.00,
                "lot_size": 0.1,
                "cancel_rule": {},
            },
            atomic=True,
        )
        assert out.get("ok") is True
        trigger = (out.get("data") or {}).get("trigger") if isinstance(out.get("data"), dict) else {}
        assert "cancel_rule" not in trigger
    finally:
        db.close()


def test_schedule_trade_entry_rejects_rr_mismatch_when_expected_rr_supplied():
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M15",
            mode="replay",
            current_bar=0,
            total_bars=100,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        sim_routes._ensure_agent_session(
            simulation_session_id=int(sim.id),
            db=db,
            mode="LOOP",
            provider="deterministic",
            model_label=None,
            permissions={"can_place_trades": True},
            config={},
            runtime={},
            copilot_session_id=None,
        )
        db.flush()

        out = sim_routes._agent_execute_tool(
            session=sim,
            db=db,
            permissions={"can_place_trades": True},
            context_snapshot={},
            tool_name="schedule_trade_entry",
            args={
                "condition": "close_above",
                "trigger_price": 5105.97,
                "direction": "BUY",
                "stop_loss": 5092.80,
                "take_profit": 5134.00,
                "lot_size": 0.10,
                "expected_rr": 3.50,  # mismatched on purpose
            },
            atomic=True,
        )
        assert out.get("ok") is False
        assert str(out.get("error") or "") == "rr_mismatch"
    finally:
        db.close()


def test_schedule_trade_entry_rejects_lot_size_mismatch_with_risk_model():
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M15",
            mode="replay",
            current_bar=0,
            total_bars=100,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        sim_routes._ensure_agent_session(
            simulation_session_id=int(sim.id),
            db=db,
            mode="LOOP",
            provider="deterministic",
            model_label=None,
            permissions={"can_place_trades": True},
            config={},
            runtime={},
            copilot_session_id=None,
        )
        db.flush()

        out = sim_routes._agent_execute_tool(
            session=sim,
            db=db,
            permissions={"can_place_trades": True},
            context_snapshot={},
            tool_name="schedule_trade_entry",
            args={
                "condition": "close_above",
                "trigger_price": 5105.97,
                "direction": "BUY",
                "stop_loss": 5092.80,
                "take_profit": 5134.00,
                "lot_size": 1.00,  # intentionally too large for risk model below
                "risk_amount": 50.0,
            },
            atomic=True,
        )
        assert out.get("ok") is False
        assert str(out.get("error") or "") == "lot_size_mismatch_with_risk_model"
    finally:
        db.close()


def test_schedule_trade_entry_rejects_when_payload_differs_from_recent_mtf_proposal():
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M15",
            mode="replay",
            current_bar=0,
            total_bars=100,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        sim_routes._ensure_agent_session(
            simulation_session_id=int(sim.id),
            db=db,
            mode="LOOP",
            provider="deterministic",
            model_label=None,
            permissions={"can_place_trades": True},
            config={},
            runtime={},
            copilot_session_id=None,
        )
        db.flush()

        mtf_best_setup = {
            "direction": "BUY",
            "condition": {"condition": "close_above", "trigger_price": 5154.37},
            "precondition": {"condition": "close_below", "trigger_price": 5154.37},
            "cancel_rule": {"condition": "close_below", "trigger_price": 5148.16},
            "stop_loss": 5144.293,
            "take_profit": 5271.904,
            "lot_size": 0.01,
            "timeframe": "M15",
            "expires_sec": 21600,
        }
        ctx = {
            "tool_state": {
                "mtf_analysis": {
                    "generated_at": datetime.now(timezone.utc).isoformat(),
                    "best_setup": mtf_best_setup,
                }
            }
        }

        out = sim_routes._agent_execute_tool(
            session=sim,
            db=db,
            permissions={"can_place_trades": True},
            context_snapshot=ctx,
            tool_name="schedule_trade_entry",
            args={
                "condition": "close_above",
                "trigger_price": 5154.37,
                "direction": "BUY",
                "stop_loss": 5144.293,
                "take_profit": 5200.00,  # intentionally mismatched vs proposal
                "lot_size": 0.01,
                "timeframe": "M15",
                "expires_sec": 21600,
                "precondition": {"condition": "close_below", "trigger_price": 5154.37},
                "cancel_rule": {"condition": "close_below", "trigger_price": 5148.16},
            },
            atomic=True,
        )
        assert out.get("ok") is False
        assert str(out.get("error") or "") == "scheduled_trigger_mismatch_with_proposal"
        details = out.get("details") if isinstance(out.get("details"), dict) else {}
        mm = details.get("mismatches") if isinstance(details.get("mismatches"), list) else []
        assert any(str(r.get("field") or "") == "take_profit" for r in mm if isinstance(r, dict))
    finally:
        db.close()


def test_schedule_trade_entry_ignores_payload_allow_proposal_mismatch_flag():
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M15",
            mode="replay",
            current_bar=0,
            total_bars=100,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        sim_routes._ensure_agent_session(
            simulation_session_id=int(sim.id),
            db=db,
            mode="LOOP",
            provider="deterministic",
            model_label=None,
            permissions={"can_place_trades": True},
            config={},
            runtime={},
            copilot_session_id=None,
        )
        db.flush()

        mtf_best_setup = {
            "direction": "BUY",
            "condition": {"condition": "close_above", "trigger_price": 5154.37},
            "precondition": {"condition": "close_below", "trigger_price": 5154.37},
            "cancel_rule": {"condition": "close_below", "trigger_price": 5148.16},
            "stop_loss": 5144.293,
            "take_profit": 5271.904,
            "lot_size": 0.01,
            "timeframe": "M15",
            "expires_sec": 21600,
        }
        ctx = {
            "tool_state": {
                "mtf_analysis": {
                    "generated_at": datetime.now(timezone.utc).isoformat(),
                    "best_setup": mtf_best_setup,
                }
            }
        }

        out = sim_routes._agent_execute_tool(
            session=sim,
            db=db,
            permissions={"can_place_trades": True},
            context_snapshot=ctx,
            tool_name="schedule_trade_entry",
            args={
                "condition": "close_above",
                "trigger_price": 5154.37,
                "direction": "BUY",
                "stop_loss": 5144.293,
                "take_profit": 5200.00,  # intentionally mismatched vs proposal
                "lot_size": 0.01,
                "timeframe": "M15",
                "expires_sec": 21600,
                "precondition": {"condition": "close_below", "trigger_price": 5154.37},
                "cancel_rule": {"condition": "close_below", "trigger_price": 5148.16},
                "allow_proposal_mismatch": True,  # must be ignored
            },
            atomic=True,
        )
        assert out.get("ok") is False
        assert str(out.get("error") or "") == "scheduled_trigger_mismatch_with_proposal"
    finally:
        db.close()


def test_schedule_trade_entry_accepts_when_payload_matches_recent_mtf_proposal():
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M15",
            mode="replay",
            current_bar=0,
            total_bars=100,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        sim_routes._ensure_agent_session(
            simulation_session_id=int(sim.id),
            db=db,
            mode="LOOP",
            provider="deterministic",
            model_label=None,
            permissions={"can_place_trades": True},
            config={},
            runtime={},
            copilot_session_id=None,
        )
        db.flush()

        mtf_best_setup = {
            "direction": "BUY",
            "condition": {"condition": "close_above", "trigger_price": 5154.37},
            "precondition": {"condition": "close_below", "trigger_price": 5154.37},
            "cancel_rule": {"condition": "close_below", "trigger_price": 5148.16},
            "stop_loss": 5144.293,
            "take_profit": 5271.904,
            "lot_size": 0.01,
            "timeframe": "M15",
            "expires_sec": 21600,
        }
        ctx = {
            "tool_state": {
                "mtf_analysis": {
                    "generated_at": datetime.now(timezone.utc).isoformat(),
                    "best_setup": mtf_best_setup,
                }
            }
        }

        out = sim_routes._agent_execute_tool(
            session=sim,
            db=db,
            permissions={"can_place_trades": True},
            context_snapshot=ctx,
            tool_name="schedule_trade_entry",
            args={
                "condition": "close_above",
                "trigger_price": 5154.37,
                "direction": "BUY",
                "stop_loss": 5144.293,
                "take_profit": 5271.904,
                "lot_size": 0.01,
                "timeframe": "M15",
                "expires_sec": 21600,
                "precondition": {"condition": "close_below", "trigger_price": 5154.37},
                "cancel_rule": {"condition": "close_below", "trigger_price": 5148.16},
            },
            atomic=True,
        )
        assert out.get("ok") is True
    finally:
        db.close()


def test_schedule_trade_entry_dedup_semantics_include_expiry():
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M15",
            mode="replay",
            current_bar=0,
            total_bars=100,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        sim_routes._ensure_agent_session(
            simulation_session_id=int(sim.id),
            db=db,
            mode="LOOP",
            provider="deterministic",
            model_label=None,
            permissions={"can_place_trades": True},
            config={},
            runtime={},
            copilot_session_id=None,
        )
        db.flush()

        base_args = {
            "condition": "close_above",
            "trigger_price": 5154.37,
            "precondition": {"condition": "close_below", "trigger_price": 5154.37},
            "cancel_rule": {"condition": "close_below", "trigger_price": 5148.16},
            "direction": "BUY",
            "stop_loss": 5144.293,
            "take_profit": 5271.904,
            "lot_size": 0.01,
            "timeframe": "M15",
        }
        out1 = sim_routes._agent_execute_tool(
            session=sim,
            db=db,
            permissions={"can_place_trades": True},
            context_snapshot={},
            tool_name="schedule_trade_entry",
            args={**base_args, "expires_sec": 21600},
            atomic=True,
        )
        assert out1.get("ok") is True
        d1 = out1.get("data") if isinstance(out1.get("data"), dict) else {}
        assert bool(d1.get("deduped")) is False
        assert int(d1.get("pending_count") or 0) == 1

        out2 = sim_routes._agent_execute_tool(
            session=sim,
            db=db,
            permissions={"can_place_trades": True},
            context_snapshot={},
            tool_name="schedule_trade_entry",
            args={**base_args, "expires_sec": 43200},  # changed expiry only
            atomic=True,
        )
        assert out2.get("ok") is True
        d2 = out2.get("data") if isinstance(out2.get("data"), dict) else {}
        assert bool(d2.get("deduped")) is False
        assert int(d2.get("pending_count") or 0) == 2
    finally:
        db.close()


def test_schedule_trade_entry_can_require_recent_mtf_proposal(monkeypatch):
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M15",
            mode="replay",
            current_bar=0,
            total_bars=100,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        sim_routes._ensure_agent_session(
            simulation_session_id=int(sim.id),
            db=db,
            mode="LOOP",
            provider="deterministic",
            model_label=None,
            permissions={"can_place_trades": True},
            config={},
            runtime={},
            copilot_session_id=None,
        )
        db.flush()

        out = sim_routes._agent_execute_tool(
            session=sim,
            db=db,
            permissions={"can_place_trades": True},
            context_snapshot={},
            tool_name="schedule_trade_entry",
            args={
                "condition": "close_above",
                "trigger_price": 5154.37,
                "direction": "BUY",
                "stop_loss": 5144.293,
                "take_profit": 5271.904,
                "lot_size": 0.01,
                "timeframe": "M15",
                "expires_sec": 21600,
                "precondition": {"condition": "close_below", "trigger_price": 5154.37},
                "cancel_rule": {"condition": "close_below", "trigger_price": 5148.16},
            },
            tool_config={"require_mtf_proposal_before_schedule": True},
            atomic=True,
        )
        assert out.get("ok") is False
        assert str(out.get("error") or "") == "missing_mtf_proposal_for_schedule"
    finally:
        db.close()


def test_agent_tool_state_patch_from_tool_calls_includes_draw_selection():
    zones = [
        {
            "type": "bullish_fvg",
            "top": 2901.0,
            "bottom": 2899.0,
            "start_time_unix": 1700000000,
            "end_time_unix": 1700000300,
            "bar_index": 42,
            "gap_size": 2.0,
        }
    ]
    patch = sim_routes._agent_tool_state_from_tool_calls(
        [
            {
                "tool_id": "scan_draw_fvg_range",
                "args": {"config": {"timeframe": "M15"}},
                "result": {
                    "ok": True,
                    "selection": {"start_index": 10, "end_index": 30, "bars": 21},
                    "data": {
                        "tool_id": "fvg",
                        "zones": zones,
                        "count": 1,
                        "scan_timeframe": "M15",
                        "scan_source": "client_live",
                    },
                },
            }
        ]
    )
    assert isinstance(patch, dict)
    assert int(patch.get("fvg_last_zone_count") or 0) == 1
    assert isinstance(patch.get("fvg_zones_preview"), list)
    assert isinstance(patch.get("draw_fvg_selection"), dict)
    assert int(patch["draw_fvg_selection"].get("bars") or 0) == 21


def test_scan_draw_fvg_range_blocked_for_telegram_bridge():
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M15",
            mode="live",
            current_bar=0,
            total_bars=1,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        out = sim_routes._agent_execute_tool(
            session=sim,
            db=db,
            permissions={"can_scan_tools": True},
            context_snapshot={
                "bars": [
                    {"time": 1, "open": 1.0, "high": 1.1, "low": 0.9, "close": 1.05, "volume": 10},
                    {"time": 2, "open": 1.05, "high": 1.2, "low": 1.0, "close": 1.1, "volume": 12},
                    {"time": 3, "open": 1.1, "high": 1.3, "low": 1.05, "close": 1.2, "volume": 11},
                ]
            },
            tool_name="scan_draw_fvg_range",
            args={"start_index": 0, "end_index": 2},
            tool_config={"telegram_bridge": True},
            atomic=False,
        )
        assert out.get("ok") is False
        assert str(out.get("error") or "") == "unsupported_in_telegram:no_chart_selection"
    finally:
        db.close()


def test_scan_tool_returns_live_history_unavailable_when_context_thin_and_fetch_fails(monkeypatch):
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M15",
            mode="live",
            current_bar=0,
            total_bars=1,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        monkeypatch.setattr(
            sim_routes,
            "_agent_fetch_live_history_bars",
            lambda **kwargs: ([], "live_history_unavailable:mock_source_down"),
        )
        out = sim_routes._agent_execute_tool(
            session=sim,
            db=db,
            permissions={"can_scan_tools": True},
            context_snapshot={},
            tool_name="scan_tool",
            args={"tool_id": "fvg", "timeframe": "H4"},
            atomic=False,
        )
        assert out.get("ok") is False
        assert str(out.get("error") or "").startswith("live_history_unavailable:")
    finally:
        db.close()


def test_scan_tool_ignores_context_bars_when_timeframe_mismatch_and_fetch_fails(monkeypatch):
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M15",
            mode="live",
            current_bar=0,
            total_bars=1,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        called = {"n": 0}

        def _fake_fetch(**kwargs):
            _ = kwargs
            called["n"] += 1
            return [], "live_history_unavailable:mock_tf_mismatch"

        monkeypatch.setattr(sim_routes, "_agent_fetch_live_history_bars", _fake_fetch)

        ctx_bars = []
        for i in range(1, 41):
            ctx_bars.append(
                {
                    "time": i,
                    "open": 100.0 + i,
                    "high": 100.2 + i,
                    "low": 99.8 + i,
                    "close": 100.1 + i,
                    "volume": 10,
                }
            )

        out = sim_routes._agent_execute_tool(
            session=sim,
            db=db,
            permissions={"can_scan_tools": True},
            context_snapshot={
                "bars": ctx_bars,
                "tool_state": {"market_context": {"symbol": "XAUUSD", "timeframe": "M15", "source": "mt5", "history_days": 2}},
            },
            tool_name="scan_tool",
            args={"tool_id": "fvg", "timeframe": "H4"},
            atomic=False,
        )
        assert called["n"] >= 1, "Expected live-history fetch when scan timeframe differs from context timeframe"
        assert out.get("ok") is False
        assert str(out.get("error") or "").startswith("live_history_unavailable:")
    finally:
        db.close()


def test_agent_permission_validator_rejects_contradictory_auto_execute():
    # can_auto_execute=True requires both trade permissions and no user-confirm gate.
    try:
        sim_routes.AgentPermissionConfig(
            can_auto_execute=True,
            can_place_trades=False,
            can_close_trades=True,
            requires_user_confirm_for_trade=False,
        )
        assert False, "Expected validation error"
    except Exception:
        pass

    try:
        sim_routes.AgentPermissionConfig(
            can_auto_execute=True,
            can_place_trades=True,
            can_close_trades=True,
            requires_user_confirm_for_trade=True,
        )
        assert False, "Expected validation error"
    except Exception:
        pass


def test_agent_start_does_not_persist_api_key():
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M5",
            mode="replay",
            current_bar=0,
            total_bars=10,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.commit()
        db.refresh(sim)

        req = sim_routes.AgentLoopStartRequest(
            provider=sim_routes.AgentProviderConfig(
                provider="claude",
                model_label="claude-3-5-sonnet-latest",
                llm_url="https://api.anthropic.com",
                api_key="TOP_SECRET",
                timeout_sec=45,
            ),
            permissions=sim_routes.AgentPermissionConfig(
                can_place_trades=False,
                can_close_trades=False,
                can_auto_execute=False,
                requires_user_confirm_for_trade=True,
            ),
            loop_interval_sec=5.0,
            mode="LOOP",
            config={},
            runtime={},
        )
        out = sim_routes.workbench_agent_start(session_id=int(sim.id), req=req, db=db)
        assert out.get("ok") is True

        agent_row = (
            db.query(WorkbenchAgentSessionModel)
            .filter(WorkbenchAgentSessionModel.simulation_session_id == int(sim.id))
            .order_by(WorkbenchAgentSessionModel.id.desc())
            .first()
        )
        assert agent_row is not None
        runtime_json = agent_row.runtime_json if isinstance(agent_row.runtime_json, dict) else {}
        assert "api_key" not in runtime_json
        assert "TOP_SECRET" not in json.dumps(runtime_json, ensure_ascii=True)
    finally:
        db.close()


def test_agent_snapshot_pruning():
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M5",
            mode="replay",
            current_bar=0,
            total_bars=500,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        agent_row = sim_routes._ensure_agent_session(
            simulation_session_id=int(sim.id),
            db=db,
            mode="LOOP",
            provider="deterministic",
            model_label=None,
            permissions={},
            config={},
            runtime={},
            copilot_session_id=None,
        )
        old_max = sim_routes._AGENT_SNAPSHOT_MAX_PER_SESSION
        sim_routes._AGENT_SNAPSHOT_MAX_PER_SESSION = 25
        try:
            for i in range(60):
                sim.current_bar = i
                sim_routes._agent_store_snapshot(
                    agent=agent_row,
                    simulation_session=sim,
                    db=db,
                    source="state",
                    patch={"i": i},
                )
            db.commit()
        finally:
            sim_routes._AGENT_SNAPSHOT_MAX_PER_SESSION = old_max

        count = (
            db.query(sim_routes.WorkbenchAgentSnapshotModel)
            .filter(sim_routes.WorkbenchAgentSnapshotModel.agent_session_id == int(agent_row.id))
            .count()
        )
        assert count <= 25
    finally:
        db.close()


def test_ensure_agent_session_dedupes_multiple_active_rows():
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M5",
            mode="replay",
            current_bar=0,
            total_bars=10,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()
        older = WorkbenchAgentSessionModel(
            simulation_session_id=int(sim.id),
            mode="LOOP",
            status="ACTIVE",
            provider="deterministic",
            model_label=None,
            permissions_json={},
            config_json={},
            runtime_json={},
            last_snapshot_json={},
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        newer = WorkbenchAgentSessionModel(
            simulation_session_id=int(sim.id),
            mode="LOOP",
            status="ACTIVE",
            provider="deterministic",
            model_label=None,
            permissions_json={},
            config_json={},
            runtime_json={},
            last_snapshot_json={},
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(older)
        db.add(newer)
        db.commit()

        row = sim_routes._ensure_agent_session(
            simulation_session_id=int(sim.id),
            db=db,
            mode="LOOP",
            provider="deterministic",
            model_label=None,
            permissions={},
            config={},
            runtime={},
            copilot_session_id=None,
        )
        assert row is not None
        active = (
            db.query(WorkbenchAgentSessionModel)
            .filter(WorkbenchAgentSessionModel.simulation_session_id == int(sim.id))
            .filter(WorkbenchAgentSessionModel.status == "ACTIVE")
            .count()
        )
        assert int(active) == 1
    finally:
        db.close()


def test_agent_event_payload_is_capped_when_too_large():
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M5",
            mode="replay",
            current_bar=0,
            total_bars=10,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()
        agent = sim_routes._ensure_agent_session(
            simulation_session_id=int(sim.id),
            db=db,
            mode="CHAT",
            provider="deterministic",
            model_label=None,
            permissions={},
            config={},
            runtime={},
            copilot_session_id=None,
        )
        huge = {"blob": "x" * 200000}
        sim_routes._agent_emit_event(
            agent=agent,
            event_type="AGENT_CHAT",
            db=db,
            payload=huge,
            severity="info",
        )
        db.commit()
        ev = (
            db.query(WorkbenchAgentEventModel)
            .filter(WorkbenchAgentEventModel.agent_session_id == int(agent.id))
            .order_by(WorkbenchAgentEventModel.id.desc())
            .first()
        )
        assert ev is not None
        payload = ev.payload_json if isinstance(ev.payload_json, dict) else {}
        assert payload.get("_truncated") is True
        assert payload.get("_reason") == "payload_too_large"
    finally:
        db.close()


def test_agent_stop_commits_copilot_when_no_agent_row():
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M5",
            mode="replay",
            current_bar=0,
            total_bars=10,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()
        cop = WorkbenchCopilotSessionModel(
            simulation_session_id=int(sim.id),
            mode="ADVISE",
            status="ACTIVE",
            provider="deterministic",
            model_label=None,
            config_json={},
            last_snapshot_json={},
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(cop)
        db.commit()

        out = sim_routes.workbench_agent_stop(session_id=int(sim.id), db=db)
        assert out.get("ok") is True
        db.refresh(cop)
        assert str(cop.status) == "STOPPED"
    finally:
        db.close()


def test_heuristic_plan_covers_research_ml_and_indicator_visibility():
    context = {
        "bars": [{"time": 1, "open": 1, "high": 2, "low": 0.5, "close": 1.2, "volume": 1}] * 50,
        "indicators": {"enabled": {"smaEma": True, "adx": True, "rsi": True, "stoch": True, "bollinger": True, "goldenCross": True}},
    }
    permissions = {
        "can_scan_tools": True,
        "can_use_research": True,
        "can_manage_indicators": True,
    }
    msg = "Optimize mean reversion, run ML diagnostic, and hide RSI indicator."
    plan = WorkbenchAgent._heuristic_tool_plan(message=msg, context=context, permissions=permissions)
    names = [str(r.get("name")) for r in plan]
    assert "run_research_optimize" in names
    assert "run_ml_diagnostic" in names
    assert "set_indicator_visibility" in names
    vis_rows = [r for r in plan if str(r.get("name")) == "set_indicator_visibility"]
    assert vis_rows and isinstance(vis_rows[0].get("args"), dict)
    vis = vis_rows[0]["args"].get("visibility")
    assert isinstance(vis, dict)
    assert vis.get("rsi") is False


def test_heuristic_plan_covers_draw_range_and_trade_entry_exit():
    context = {
        "bars": [{"time": i, "open": 1, "high": 2, "low": 0.5, "close": 1.2, "volume": 1} for i in range(200)],
        "tool_state": {"draw_fvg": {"picks": [20, 35]}},
        "open_positions": [{"id": 77}],
    }
    permissions = {
        "can_scan_tools": True,
        "can_place_trades": True,
        "can_close_trades": True,
        "requires_user_confirm_for_trade": False,
    }
    msg = "Use selected bars to scan draw fvg, buy with SL 99 TP 105 lot 0.02, then close position."
    plan = WorkbenchAgent._heuristic_tool_plan(message=msg, context=context, permissions=permissions)
    names = [str(r.get("name")) for r in plan]
    assert "scan_draw_fvg_range" in names
    assert "place_trade" in names
    assert "close_trade" in names

    place_rows = [r for r in plan if str(r.get("name")) == "place_trade"]
    assert place_rows
    pargs = place_rows[0].get("args") if isinstance(place_rows[0].get("args"), dict) else {}
    assert pargs.get("direction") == "BUY"
    assert float(pargs.get("stop_loss")) == 99.0
    assert float(pargs.get("take_profit")) == 105.0


def test_schedule_trade_entry_persists_trigger_requires_approval_policy():
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M15",
            mode="replay",
            current_bar=0,
            total_bars=100,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        sim_routes._ensure_agent_session(
            simulation_session_id=int(sim.id),
            db=db,
            mode="LOOP",
            provider="deterministic",
            model_label=None,
            permissions={"can_place_trades": True},
            config={"watchdog_trigger_requires_approval": True},
            runtime={},
            copilot_session_id=None,
        )
        db.flush()

        out = sim_routes._agent_execute_tool(
            session=sim,
            db=db,
            permissions={"can_place_trades": True},
            context_snapshot={},
            tool_name="schedule_trade_entry",
            args={
                "condition": "close_above",
                "trigger_price": 5105.97,
                "direction": "BUY",
                "stop_loss": 5092.80,
                "take_profit": 5134.00,
                "lot_size": 0.1,
                "timeframe": "M15",
            },
            atomic=True,
        )
        assert out.get("ok") is True
        trigger = (out.get("data") or {}).get("trigger") if isinstance(out.get("data"), dict) else {}
        guardrails = trigger.get("guardrails") if isinstance(trigger, dict) and isinstance(trigger.get("guardrails"), dict) else {}
        assert bool(guardrails.get("trigger_requires_approval")) is True
    finally:
        db.close()


def test_watchdog_uses_trigger_level_requires_approval_override():
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M15",
            mode="replay",
            current_bar=0,
            total_bars=100,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        agent_row = sim_routes._ensure_agent_session(
            simulation_session_id=int(sim.id),
            db=db,
            mode="LOOP",
            provider="deterministic",
            model_label=None,
            permissions={"can_place_trades": True, "requires_user_confirm_for_trade": True},
            config={
                "watchdog_trigger_requires_approval": True,
                "agent_permissions": {"can_place_trades": True, "requires_user_confirm_for_trade": True},
            },
            runtime={},
            copilot_session_id=None,
        )
        agent_row.last_snapshot_json = {
            "agent_trade_triggers": [
                {
                    "id": "trg_override",
                    "status": "pending",
                    "state": "waiting_entry",
                    "created_at": datetime.utcnow().isoformat(),
                    "expires_at": (datetime.now(timezone.utc).replace(microsecond=0) + timedelta(hours=1)).isoformat(),
                    "condition": "price_above",
                    "trigger_price": 5000.0,
                    "timeframe": "M15",
                    "trade_args": {
                        "direction": "BUY",
                        "stop_loss": 4990.0,
                        "take_profit": 5030.0,
                        "lot_size": 0.1,
                        "entry_price": None,
                    },
                    "guardrails": {
                        "trigger_requires_approval": False,
                        "guardrail_enabled": False,
                        "session_filter_enabled": True,
                        "news_filter_enabled": True,
                        "news_lookback_min": 90,
                    },
                }
            ]
        }
        db.add(agent_row)
        db.flush()

        captured_permissions = []
        captured_tool_configs = []
        orig_exec = sim_routes._agent_execute_tool

        def _fake_exec(*, session, db, permissions, context_snapshot, tool_name, args, atomic=True, tool_config=None):
            _ = (session, db, context_snapshot, tool_name, args, atomic, tool_config)
            captured_permissions.append(dict(permissions or {}))
            captured_tool_configs.append(dict(tool_config or {}))
            return {"ok": True, "data": {"id": 1}}

        sim_routes._agent_execute_tool = _fake_exec  # type: ignore[assignment]
        try:
            svc = AgentWatchdogService()
            events = svc._process_entry_triggers(
                db=db,
                agent=agent_row,
                session=sim,
                now=datetime.now(timezone.utc),
                current_price=5100.0,
                closed_bar={"time": 1772522400, "close": 5100.0},
            )
            assert isinstance(events, list)
            assert len(captured_permissions) == 1
            assert bool(captured_permissions[0].get("requires_user_confirm_for_trade")) is False
            assert len(captured_tool_configs) == 1
            assert bool(captured_tool_configs[0].get("guardrail_enabled", True)) is False
            assert bool(captured_tool_configs[0].get("guardrail_session_filter_enabled", False)) is True
            assert bool(captured_tool_configs[0].get("guardrail_news_filter_enabled", False)) is True
            assert int(captured_tool_configs[0].get("guardrail_news_lookback_min", 0)) == 90
        finally:
            sim_routes._agent_execute_tool = orig_exec  # type: ignore[assignment]
    finally:
        db.close()


def test_agent_execute_tool_get_market_news_delegates_to_fetcher():
    db = _db_session()
    try:
        sim = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M15",
            mode="replay",
            current_bar=0,
            total_bars=100,
            initial_balance=10000.0,
            current_balance=10000.0,
            total_pnl=0.0,
            trades_count=0,
            wins=0,
            losses=0,
            status="active",
            config_json=json.dumps({}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        orig = sim_routes._agent_fetch_market_news

        def _fake_fetch(
            *,
            symbol,
            limit=5,
            lookback_min=180,
            provider="polygon",
            include_summary=False,
            summary_model="",
            summary_timeout_sec=8,
            ibkr_host="127.0.0.1",
            ibkr_port=7497,
        ):
            _ = (provider, include_summary, summary_model, summary_timeout_sec, ibkr_host, ibkr_port)
            return {
                "ok": True,
                "provider": "test",
                "symbol": str(symbol),
                "items": [{"title": "Test headline", "impact": "normal"}],
                "limit": int(limit),
                "lookback_min": int(lookback_min),
            }

        sim_routes._agent_fetch_market_news = _fake_fetch  # type: ignore[assignment]
        try:
            out = sim_routes._agent_execute_tool(
                session=sim,
                db=db,
                permissions={"can_chat": True},
                context_snapshot={},
                tool_name="get_market_news",
                args={"limit": 3, "lookback_min": 60},
                atomic=True,
            )
        finally:
            sim_routes._agent_fetch_market_news = orig  # type: ignore[assignment]

        assert out.get("ok") is True
        data = out.get("data") if isinstance(out.get("data"), dict) else {}
        assert data.get("ok") is True
        items = data.get("items") if isinstance(data.get("items"), list) else []
        assert len(items) == 1
    finally:
        db.close()
