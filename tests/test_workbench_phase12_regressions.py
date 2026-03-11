import json
import types
from datetime import datetime

import pandas as pd
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from dashboard.backend.api import simulation_routes as sim_routes
from dashboard.backend.core.workbench.mean_rev_tool import MeanRevTool
from dashboard.backend.models.database import (
    Base,
    SimulationSession,
    SimulationTrade,
    WorkbenchCopilotAdviceModel,
    WorkbenchCopilotSessionModel,
)


def _db_session():
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    Base.metadata.create_all(bind=engine)
    SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)
    return SessionLocal()


class _ZeroBarsEngine:
    def __init__(self):
        self.total_bars = 0
        self.current_bar = 0
        self.df = pd.DataFrame()


def _make_mean_rev_df() -> pd.DataFrame:
    idx = pd.date_range("2026-01-01", periods=120, freq="5min", tz="UTC")
    vals = []
    for i in range(120):
        base = 100.0 + (i * 0.02)
        if 40 <= i <= 45:
            base -= 4.0
        if 70 <= i <= 74:
            base += 4.5
        vals.append(base)
    close = pd.Series(vals, index=idx)
    return pd.DataFrame(
        {
            "open": close.shift(1).fillna(close),
            "high": close + 0.2,
            "low": close - 0.2,
            "close": close,
            "volume": 1.0,
        },
        index=idx,
    )


def test_mean_rev_signal_sequence_and_no_same_bar_conflicts():
    tool = MeanRevTool()
    df = _make_mean_rev_df()
    zones = tool.scan(
        df,
        {
            "sma_period": 20,
            "deviation": 2.0,
            "show_exit_signals": True,
            "strictness": 3,
        },
    )
    types = [z["type"] for z in zones]
    assert types == ["buy_zone", "mean_cross", "sell_zone", "mean_cross"]

    bar_to_types = {}
    for z in zones:
        bar_to_types.setdefault(int(z["bar_index"]), []).append(str(z["type"]))
    assert not any(len(v) > 1 for v in bar_to_types.values())


def test_create_session_allows_empty_replay_when_live_bootstrap_enabled(monkeypatch):
    db = _db_session()
    try:
        monkeypatch.setattr(sim_routes, "_get_or_create_engine", lambda session, db_sess: _ZeroBarsEngine())
        monkeypatch.setattr(sim_routes, "_clear_cached_engine", lambda _sid: None)
        req = sim_routes.CreateSessionRequest(
            strategy_id=sim_routes.WORKBENCH_ID,
            symbol="XAUUSD",
            timeframe="M15",
            initial_balance=10000.0,
            allow_empty_replay=True,
        )
        out = sim_routes.create_session(req, db)
        assert int(out.get("id") or 0) > 0
        assert int(out.get("total_bars") or 0) == 0
        row = db.query(SimulationSession).get(int(out["id"]))
        assert row is not None
        assert int(row.total_bars or 0) == 0
    finally:
        db.close()


def test_create_session_still_rejects_empty_replay_without_live_bootstrap(monkeypatch):
    db = _db_session()
    try:
        monkeypatch.setattr(sim_routes, "_get_or_create_engine", lambda session, db_sess: _ZeroBarsEngine())
        monkeypatch.setattr(sim_routes, "_clear_cached_engine", lambda _sid: None)
        req = sim_routes.CreateSessionRequest(
            strategy_id=sim_routes.WORKBENCH_ID,
            symbol="XAUUSD",
            timeframe="M15",
            initial_balance=10000.0,
            allow_empty_replay=False,
        )
        try:
            sim_routes.create_session(req, db)
            assert False, "Expected HTTPException for empty replay data"
        except HTTPException as exc:
            assert int(exc.status_code) == 400
            assert "No replay data loaded" in str(exc.detail or "")
        # Session row is rolled back/deleted on create failure.
        rows = db.query(SimulationSession).all()
        assert len(rows) == 0
    finally:
        db.close()


def test_list_sessions_filters_workbench_and_sorts_recent_first():
    db = _db_session()
    try:
        older = datetime(2026, 3, 1, 12, 0, 0)
        newer = datetime(2026, 3, 2, 12, 0, 0)
        s1 = SimulationSession(
            strategy_id="_workbench",
            symbol="XAUUSD",
            timeframe="M15",
            status="active",
            current_balance=10010.0,
            total_pnl=10.0,
            updated_at=older,
            created_at=older,
        )
        s2 = SimulationSession(
            strategy_id="_workbench",
            symbol="NAS100",
            timeframe="M5",
            status="active",
            current_balance=9990.0,
            total_pnl=-10.0,
            updated_at=newer,
            created_at=newer,
        )
        s3 = SimulationSession(
            strategy_id="some_other_strategy",
            symbol="EURUSD",
            timeframe="M15",
            status="active",
            updated_at=newer,
            created_at=newer,
        )
        db.add_all([s1, s2, s3])
        db.commit()

        out = sim_routes.list_sessions(strategy_id="_workbench", status=None, limit=10, db=db)
        assert out.get("ok") is True
        rows = out.get("sessions") if isinstance(out.get("sessions"), list) else []
        assert len(rows) == 2
        assert int(rows[0].get("id") or 0) == int(s2.id)
        assert int(rows[1].get("id") or 0) == int(s1.id)
    finally:
        db.close()


def test_mt5_symbols_endpoint_returns_service_catalog(monkeypatch):
    fake_rows = [
        {"name": "XAUUSDm", "description": "Gold", "visible": True},
        {"name": "US500m", "description": "S&P 500", "visible": True},
    ]

    class _FakeService:
        def list_symbols(self, search="", limit=500, include_hidden=True):
            return fake_rows[: int(limit)]

    monkeypatch.setattr(sim_routes, "_get_mt5_service_singleton", lambda: _FakeService())
    out = sim_routes.simulation_mt5_symbols(search="", limit=5, include_hidden=True)
    assert out.get("ok") is True
    assert int(out.get("count") or 0) == 2
    rows = out.get("symbols") if isinstance(out.get("symbols"), list) else []
    assert str(rows[0].get("name") or "") == "XAUUSDm"


def test_mean_rev_compute_current_state_handles_duplicate_index():
    tool = MeanRevTool()
    df = _make_mean_rev_df().copy()
    # Create duplicate timestamps intentionally.
    duplicated = pd.concat([df.iloc[:80], df.iloc[79:]], axis=0)
    state = tool.compute_current_state(
        duplicated,
        {"sma_period": 20, "deviation": 2.0, "strictness": 3},
    )
    assert isinstance(state, dict)
    assert "state" in state
    assert "z_score" in state or state.get("reason") == "insufficient_bars"


class _FakeEngine:
    def __init__(self, entry_price: float = 100.0):
        self.current_bar = 0
        self.total_bars = 10
        idx = pd.date_range("2026-01-01", periods=10, freq="5min", tz="UTC")
        self.df = pd.DataFrame({"close": [entry_price] * 10}, index=idx)
        self.balance = 10000.0
        self.closed_trades = []
        self.open_positions = []

    def execute_trade(self, direction, sl, tp, lot_size, entry_price_override=None):
        px = float(entry_price_override if entry_price_override is not None else self.df.iloc[self.current_bar]["close"])
        self.open_positions.append({"id": None, "direction": direction, "entry_price": px})
        return {
            "entry_price": px,
            "entry_bar": int(self.current_bar),
            "entry_time": self.df.index[self.current_bar].isoformat(),
        }


def _run_auto_paper_entry_with_zone(monkeypatch, zone_type: str, sl: float, tp: float, expected_dir: str):
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
            config_json=json.dumps({"cost_model": {"enabled": False}}),
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(sim)
        db.flush()

        copilot = WorkbenchCopilotSessionModel(
            simulation_session_id=int(sim.id),
            mode="AUTO_PAPER",
            status="ACTIVE",
            provider="deterministic",
            config_json={},
            last_snapshot_json={},
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        db.add(copilot)
        db.flush()

        advice = WorkbenchCopilotAdviceModel(
            copilot_session_id=int(copilot.id),
            advice_type="SUGGEST_ENTRY",
            summary="test entry",
            confidence=0.99,
            source_event_priority=100,
            delivery="ACTIONABLE",
            evidence_json={"zones_preview": [{"type": zone_type}]},
            action_json={
                "action_type": "SUGGEST_ENTRY",
                "stop_loss": sl,
                "take_profit": tp,
                "lot_size": 0.01,
            },
            status="NEW",
            created_at=datetime.utcnow(),
        )
        db.add(advice)
        db.commit()

        fake_engine = _FakeEngine(entry_price=100.0)
        monkeypatch.setattr(sim_routes, "_get_or_create_engine", lambda session, db_sess: fake_engine)
        monkeypatch.setattr(sim_routes, "_emit_copilot_event", lambda *args, **kwargs: None)
        monkeypatch.setattr(sim_routes, "_is_cost_model_enabled", lambda session: False)

        executed = sim_routes._maybe_apply_auto_paper_actions(
            copilot=copilot,
            session=sim,
            db=db,
            max_actions=1,
        )
        db.flush()
        db.refresh(advice)

        trade = db.query(SimulationTrade).filter(SimulationTrade.session_id == int(sim.id)).first()
        assert executed == 1
        assert advice.status == "EXECUTED"
        assert trade is not None
        assert trade.direction == expected_dir
    finally:
        db.close()


def test_auto_paper_direction_fallback_from_buy_zone(monkeypatch):
    _run_auto_paper_entry_with_zone(
        monkeypatch=monkeypatch,
        zone_type="buy_zone",
        sl=99.0,
        tp=102.0,
        expected_dir="BUY",
    )


def test_auto_paper_direction_fallback_from_sell_zone(monkeypatch):
    _run_auto_paper_entry_with_zone(
        monkeypatch=monkeypatch,
        zone_type="sell_zone",
        sl=101.0,
        tp=98.0,
        expected_dir="SELL",
    )


def test_session_cost_model_spread_source_resolution(monkeypatch):
    session = SimulationSession(
        strategy_id="_workbench",
        symbol="XAUUSD",
        timeframe="M5",
        config_json=json.dumps({"cost_model": {"enabled": True, "spread": 0.4, "tc_rate": 0.0002, "spread_source": "manual"}}),
    )

    manual_model = sim_routes._session_cost_model(session=session, spread_source_override="manual")
    assert manual_model.spread == 0.4
    assert manual_model.tc_rate == 0.0002
    assert manual_model.spread_source == "manual"

    class _SvcNone:
        def get_live_spread(self, symbol: str):
            return None

    monkeypatch.setattr(sim_routes, "_get_mt5_service_singleton", lambda: _SvcNone())
    fallback_model = sim_routes._session_cost_model(session=session, spread_source_override="mt5_live")
    assert fallback_model.spread == 0.4
    assert fallback_model.spread_source == "manual_fallback"

    class _SvcLive:
        def get_live_spread(self, symbol: str):
            return 0.55

    monkeypatch.setattr(sim_routes, "_get_mt5_service_singleton", lambda: _SvcLive())
    mt5_model = sim_routes._session_cost_model(session=session, spread_source_override="mt5_live")
    assert mt5_model.spread == 0.55
    assert mt5_model.spread_source == "mt5_live"


def test_strategy_tool_access_mode_normalization():
    assert sim_routes._normalize_strategy_tool_access_mode("all") == "all"
    assert sim_routes._normalize_strategy_tool_access_mode("parent") == "parent"
    assert sim_routes._normalize_strategy_tool_access_mode("child") == "child"
    assert sim_routes._normalize_strategy_tool_access_mode("collected") == "parent"
    assert sim_routes._normalize_strategy_tool_access_mode("children") == "child"
    assert sim_routes._normalize_strategy_tool_access_mode("unknown_mode") == "all"


def test_tool_selection_mode_normalization():
    assert sim_routes._normalize_tool_selection_mode("autonomous") == "autonomous"
    assert sim_routes._normalize_tool_selection_mode("guided") == "guided"
    assert sim_routes._normalize_tool_selection_mode("minimal") == "minimal"
    assert sim_routes._normalize_tool_selection_mode("auto") == "autonomous"
    assert sim_routes._normalize_tool_selection_mode("strict") == "minimal"
    assert sim_routes._normalize_tool_selection_mode("unknown_mode") == "autonomous"


def test_agent_select_allowed_tool_names_modes():
    msg = "can you explain why you entered that position?"
    hist = [{"role": "user", "content": "run_mtf_analysis schedule_trade_entry get_scheduled_triggers"}]

    guided = sim_routes._agent_select_allowed_tool_names(
        message=msg,
        conversation_history=hist,
        cfg={"tool_selection_mode": "guided", "strategy_tool_access_mode": "all"},
    )
    minimal = sim_routes._agent_select_allowed_tool_names(
        message=msg,
        conversation_history=hist,
        cfg={"tool_selection_mode": "minimal", "strategy_tool_access_mode": "all"},
    )
    autonomous = sim_routes._agent_select_allowed_tool_names(
        message=msg,
        conversation_history=hist,
        cfg={"tool_selection_mode": "autonomous", "strategy_tool_access_mode": "all"},
    )

    assert "run_mtf_analysis" in guided
    assert "schedule_trade_entry" in guided
    assert "run_mtf_analysis" not in minimal
    assert "schedule_trade_entry" not in minimal
    assert "run_mtf_analysis" in autonomous
    assert "scan_tool" in autonomous


def test_strategy_tool_access_mode_filters_parent_and_child_tools():
    base = [
        "get_positions_detail",
        "get_market_snapshot",
        "set_market_context",
        "scan_tool",
        "run_mtf_analysis",
        "schedule_trade_entry",
    ]
    parent_only = sim_routes._agent_apply_strategy_tool_access_mode(
        base,
        {"strategy_tool_access_mode": "parent"},
    )
    child_only = sim_routes._agent_apply_strategy_tool_access_mode(
        base,
        {"strategy_tool_access_mode": "child"},
    )
    assert "run_mtf_analysis" in parent_only
    assert "scan_tool" not in parent_only
    assert "set_market_context" in parent_only
    assert "get_market_snapshot" in parent_only
    assert "schedule_trade_entry" in parent_only

    assert "run_mtf_analysis" not in child_only
    assert "scan_tool" in child_only
    assert "set_market_context" in child_only
    assert "get_market_snapshot" in child_only
    assert "schedule_trade_entry" in child_only


def test_strategy_tool_access_mode_allows_non_strategy_tools():
    cfg_parent = {"strategy_tool_access_mode": "parent"}
    assert sim_routes._agent_tool_allowed_by_access_mode("get_positions_detail", cfg_parent) is True
    assert sim_routes._agent_tool_allowed_by_access_mode("schedule_trade_entry", cfg_parent) is True
    assert sim_routes._agent_tool_allowed_by_access_mode("scan_tool", cfg_parent) is False
    assert sim_routes._agent_tool_allowed_by_access_mode("run_mtf_analysis", cfg_parent) is True


def test_strategy_tool_access_mode_injects_parent_when_children_requested():
    out = sim_routes._agent_apply_strategy_tool_access_mode(
        ["scan_tool", "get_positions_detail"],
        {"strategy_tool_access_mode": "parent"},
    )
    assert "scan_tool" not in out
    assert "run_mtf_analysis" in out
    assert "get_positions_detail" in out


def test_execute_tool_blocks_strategy_child_in_parent_mode(monkeypatch):
    monkeypatch.setattr(
        sim_routes,
        "_agent_effective_tool_config",
        lambda **kwargs: {"strategy_tool_access_mode": "parent"},
    )
    res = sim_routes._agent_execute_tool(
        session=types.SimpleNamespace(id=1, symbol="XAUUSD", timeframe="M15"),
        db=None,
        permissions={},
        context_snapshot={},
        tool_name="scan_tool",
        args={},
        atomic=False,
    )
    assert bool(res.get("ok")) is False
    assert str(res.get("error") or "").startswith("tool_blocked_by_access_mode:parent:scan_tool")
