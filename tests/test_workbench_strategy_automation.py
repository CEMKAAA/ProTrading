from types import SimpleNamespace

import pandas as pd
import json
import pytest
from datetime import datetime, timezone

from dashboard.backend.api import simulation_routes as sim_routes


class _QueryNoOpen:
    def filter(self, *args, **kwargs):
        return self

    def order_by(self, *args, **kwargs):
        return self

    def first(self):
        return None


class _QueryHasOpen:
    def filter(self, *args, **kwargs):
        return self

    def order_by(self, *args, **kwargs):
        return self

    def first(self):
        return SimpleNamespace(id=42)


class _DbNoOpen:
    def query(self, *args, **kwargs):
        return _QueryNoOpen()


class _DbHasOpen:
    def query(self, *args, **kwargs):
        return _QueryHasOpen()


def test_strategy_automation_entry_plan_applies_risk_and_rr_overrides(monkeypatch):
    session = SimpleNamespace(
        id=101,
        symbol="XAUUSDm",
        current_balance=10000.0,
        initial_balance=10000.0,
    )
    db = _DbNoOpen()
    captured = {}

    monkeypatch.setattr(sim_routes, "_strategy_automation_fetch_entry_price", lambda **kwargs: 100.0)
    monkeypatch.setattr(
        sim_routes,
        "_session_trade_math_context",
        lambda **kwargs: {
            "min_lot": 0.01,
            "max_lot": 100.0,
            "lot_step": 0.01,
            "value_per_1lot": 10.0,
            "point": 0.01,
        },
    )
    monkeypatch.setattr(sim_routes, "_agent_validate_trade_geometry", lambda **kwargs: (True, None))

    def _fake_execute_trade(*, session_id, req, db):
        captured["session_id"] = session_id
        captured["req"] = req
        return {"ok": True, "trade_id": 1}

    monkeypatch.setattr(sim_routes, "execute_trade", _fake_execute_trade)

    out = sim_routes._strategy_automation_try_open_from_plan(
        session=session,
        db=db,
        plan={
            "direction": "BUY",
            "stop_loss": 99.0,
            "take_profit": 102.0,
            "lot_size": 1.0,
        },
        source="mt5",
        timeframe="M15",
        risk_percent_override=1.0,
        rr_target_override=3.0,
    )

    assert out["ok"] is True
    assert out["reason"] == "opened_from_entry_plan"
    assert float(out["entry_price"]) == 100.0
    assert round(float(captured["req"].lot_size), 2) == 10.0
    assert round(float(captured["req"].take_profit), 2) == 103.0
    assert out.get("applied_overrides", {}).get("risk_percent") == 1.0
    assert out.get("applied_overrides", {}).get("rr_target") == 3.0


def test_strategy_automation_entry_plan_skips_when_open_trade_exists(monkeypatch):
    session = SimpleNamespace(
        id=102,
        symbol="XAUUSDm",
        current_balance=10000.0,
        initial_balance=10000.0,
    )
    db = _DbHasOpen()

    def _should_not_execute(*args, **kwargs):
        raise AssertionError("execute_trade should not be called when an open trade exists")

    monkeypatch.setattr(sim_routes, "execute_trade", _should_not_execute)

    out = sim_routes._strategy_automation_try_open_from_plan(
        session=session,
        db=db,
        plan={
            "direction": "SELL",
            "stop_loss": 101.0,
            "take_profit": 98.0,
            "lot_size": 1.0,
        },
        source="mt5",
        timeframe="M15",
    )

    assert out["ok"] is False
    assert out["reason"] == "open_trade_exists"
    assert int(out["trade_id"]) == 42


def test_bars_df_to_payload_converts_valid_ohlcv_rows():
    idx = pd.date_range("2026-03-17 10:00:00", periods=3, freq="min", tz="UTC")
    df = pd.DataFrame(
        {
            "open": [100.0, 100.5, 101.0],
            "high": [101.0, 101.2, 101.4],
            "low": [99.8, 100.2, 100.7],
            "close": [100.6, 101.0, 101.3],
            "volume": [10.0, 12.0, 14.0],
        },
        index=idx,
    )
    out = sim_routes._bars_df_to_payload(df, max_rows=100, min_rows=1)
    assert isinstance(out, list)
    assert len(out) == 3
    assert all(isinstance(r.get("time"), int) and r["time"] > 0 for r in out)
    assert out[-1]["close"] == 101.3


def test_mt5_live_merge_tick_updates_inbar_close_and_extremes():
    bar = {
        "time": 1710000000,  # bucket start
        "open": 100.0,
        "high": 101.0,
        "low": 99.0,
        "close": 100.5,
        "volume": 10,
    }
    tick = {"time_unix": 1710000005, "bid": 102.2}
    out = sim_routes._mt5_live_merge_tick_into_bar(bar, tick, "M1")
    assert out["time"] == 1710000000
    assert out["close"] == 102.2
    assert out["high"] == 102.2
    assert out["low"] == 99.0


def test_mt5_live_merge_tick_rolls_to_next_bucket_when_tick_advances():
    bar = {
        "time": 1710000000,
        "open": 100.0,
        "high": 100.8,
        "low": 99.5,
        "close": 100.2,
        "volume": 11,
    }
    # Next M1 bucket
    tick = {"time_unix": 1710000062, "bid": 101.4}
    out = sim_routes._mt5_live_merge_tick_into_bar(bar, tick, "M1")
    assert out["time"] == 1710000060
    assert out["open"] == 100.2
    assert out["close"] == 101.4
    assert out["high"] == 101.4
    assert out["low"] == 100.2


def test_strategy_automation_mark_stopped_disables_enabled_job():
    session = SimpleNamespace(
        id=303,
        config_json=json.dumps(
            {
                "x": 1,
                "strategy_automation": {
                    "enabled": True,
                    "status": "running",
                    "last_action": "opened_trade",
                    "last_reason": "color_flip_entry_signal",
                },
            }
        ),
        updated_at=None,
    )

    class _Db:
        def __init__(self):
            self.added = []

        def add(self, obj):
            self.added.append(obj)

    db = _Db()
    changed = sim_routes._strategy_automation_mark_stopped(
        session=session,
        db=db,
        reason="manual_close_auto_stop",
        action="stopped_by_manual_close",
    )
    assert changed is True
    cfg = json.loads(session.config_json)
    auto = cfg["strategy_automation"]
    assert auto["enabled"] is False
    assert auto["status"] == "stopped"
    assert auto["last_action"] == "stopped_by_manual_close"
    assert auto["last_reason"] == "manual_close_auto_stop"
    assert len(db.added) == 1


@pytest.mark.parametrize("strategy_key", ["trendilo", "advanced_trendilo", "trendilo_lsma"])
def test_strategy_automation_color_from_bars_trendilo_family_uses_closed_bar(monkeypatch, strategy_key):
    idx = pd.date_range("2026-03-21 00:00:00", periods=3, freq="min", tz="UTC")
    bars_df = pd.DataFrame(
        {
            "open": [100.0, 101.0, 102.0],
            "high": [101.2, 102.2, 102.5],
            "low": [99.8, 100.8, 89.5],
            "close": [101.0, 102.0, 90.0],  # last bar is opposite/flicker bar
            "volume": [100.0, 200.0, 300.0],
        },
        index=idx,
    )

    def _dir_from_last_close(v):
        return "bullish" if float(v) >= 100.0 else "bearish"

    if strategy_key == "trendilo":
        def _fake_indicator_values_from_bars(bars_payload, **kwargs):
            last_close = float((bars_payload or [{}])[-1].get("close") or 0.0)
            d = _dir_from_last_close(last_close)
            return {"trendilo_direction": d, "trendilo_avpch": 1.0, "trendilo_rms": 1.0}

        monkeypatch.setattr(sim_routes, "_agent_indicator_values_from_bars", _fake_indicator_values_from_bars)
    elif strategy_key == "advanced_trendilo":
        def _fake_advanced(df, cfg=None):
            last_close = float(df["close"].astype(float).iloc[-1])
            d = _dir_from_last_close(last_close)
            return {"trendilo_direction": d, "trendilo_avpch": 1.0, "trendilo_rms": 1.0}

        monkeypatch.setattr(sim_routes, "_agent_advanced_trendilo_indicators_from_df", _fake_advanced)
    else:
        def _fake_lsma(df, cfg=None):
            last_close = float(df["close"].astype(float).iloc[-1])
            d = _dir_from_last_close(last_close)
            return {"direction": d, "signal": 1.0}

        monkeypatch.setattr(sim_routes, "_agent_trendilo_lsma_indicators_from_df", _fake_lsma)

    out_closed = sim_routes._strategy_automation_color_from_bars(
        bars_df=bars_df,
        strategy_key=strategy_key,
        preset_cfg={},
        volume_sma_period=20,
        closed_bar_only=True,
    )
    out_live = sim_routes._strategy_automation_color_from_bars(
        bars_df=bars_df,
        strategy_key=strategy_key,
        preset_cfg={},
        volume_sma_period=20,
        closed_bar_only=False,
    )

    assert out_closed["color"] == "green"
    assert out_live["color"] == "red"


@pytest.mark.parametrize(
    "strategy_key",
    ["trendilo", "advanced_trendilo", "trendilo_lsma", "alpha_wave", "orb_alpha_hybrid", "deadzone_pro"],
)
def test_strategy_automation_tick_closes_on_stop_loss_without_immediate_reentry(monkeypatch, strategy_key):
    session = SimpleNamespace(
        id=501,
        symbol="BTCUSDm",
        timeframe="M15",
        current_balance=1000.0,
        initial_balance=1000.0,
        config_json=json.dumps(
            {
                "strategy_automation": {
                    "enabled": True,
                    "strategy": str(strategy_key),
                    "symbol": "BTCUSDm",
                    "timeframe": "M15",
                    "source": "mt5",
                    "preset": "default",
                    "last_color": "green",
                    "first_run": False,
                    "force_first_entry": True,
                    "history_days": 1.0,
                }
            }
        ),
        updated_at=None,
    )
    open_trade = SimpleNamespace(
        id=17,
        direction="BUY",
        stop_loss=70298.3257,
        take_profit=None,
        status="open",
    )

    class _QueryOpenTrade:
        def __init__(self, trade):
            self.trade = trade

        def filter(self, *args, **kwargs):
            return self

        def order_by(self, *args, **kwargs):
            return self

        def first(self):
            return self.trade

    class _Db:
        def __init__(self, trade):
            self.trade = trade
            self.added = []

        def query(self, *args, **kwargs):
            return _QueryOpenTrade(self.trade)

        def add(self, obj):
            self.added.append(obj)

        def flush(self):
            return None

    db = _Db(open_trade)
    bars_df = pd.DataFrame(
        {
            "open": [71087.84, 70550.00],
            "high": [71120.00, 70610.00],
            "low": [70980.00, 69965.34],
            "close": [70520.00, 70039.00],
            "volume": [10.0, 11.0],
        },
        index=pd.date_range("2026-03-18 22:45:00", periods=2, freq="15min", tz="UTC"),
    )

    monkeypatch.setattr(sim_routes, "_agent_fetch_live_history_bars", lambda **kwargs: ([], None))
    monkeypatch.setattr(sim_routes, "_bars_payload_to_df", lambda *args, **kwargs: bars_df)
    monkeypatch.setattr(sim_routes.StrategyRegistry, "get_preset_config", lambda *args, **kwargs: {})
    monkeypatch.setattr(
        sim_routes,
        "_strategy_automation_color_from_bars",
        lambda **kwargs: {"color": "green", "direction": "bullish"},
    )

    captured = {}

    def _fake_close_trade(*, session_id, trade_id, req, db):
        captured["session_id"] = session_id
        captured["trade_id"] = trade_id
        captured["exit_price"] = req.exit_price
        return {"ok": True, "id": trade_id, "status": "closed"}

    monkeypatch.setattr(sim_routes, "close_trade", _fake_close_trade)

    def _should_not_execute_trade(*args, **kwargs):
        raise AssertionError("execute_trade should not run after SL close on same tick")

    monkeypatch.setattr(sim_routes, "execute_trade", _should_not_execute_trade)

    out = sim_routes._process_strategy_automation_tick_unlocked(
        session=session,
        db=db,
        live_bar=None,
    )

    assert out["ok"] is True
    assert out["action"] == "closed_trade"
    assert out["reason"] == "stop_loss_hit"
    assert int(captured["session_id"]) == 501
    assert int(captured["trade_id"]) == 17
    assert float(captured["exit_price"]) == float(open_trade.stop_loss)

    cfg = json.loads(session.config_json)
    auto = cfg["strategy_automation"]
    assert auto["last_action"] == "closed_trade"
    assert auto["last_reason"] == "stop_loss_hit"


def test_strategy_automation_orb_signal_locks_after_reentry_attempt_same_day():
    ny_idx = pd.date_range(
        "2026-03-19 09:30:00",
        "2026-03-19 09:56:00",
        freq="1min",
        tz="America/New_York",
    )
    utc_idx = ny_idx.tz_convert("UTC")

    opens = []
    highs = []
    lows = []
    closes = []
    vols = []
    for ts in ny_idx:
        h = 100.0
        l = 99.0
        c = 99.5
        o = 99.5
        if ts.hour == 9 and ts.minute in {45, 46}:
            # Clean bullish break + FVG proxy.
            o, h, l, c = 101.2, 102.0, 101.0, 101.6
        elif ts.hour == 9 and ts.minute in {47, 48}:
            o, h, l, c = 101.4, 101.9, 101.1, 101.5
        elif ts.hour == 9 and ts.minute == 49:
            # Back inside OR range => strict ORB locks out reentry.
            o, h, l, c = 99.7, 100.1, 99.2, 99.6
        elif ts.hour == 9 and ts.minute in {55, 56}:
            # Later clean bearish break + FVG proxy.
            o, h, l, c = 97.8, 98.0, 97.0, 97.4
        opens.append(o)
        highs.append(h)
        lows.append(l)
        closes.append(c)
        vols.append(10.0)

    bars_df = pd.DataFrame(
        {
            "open": opens,
            "high": highs,
            "low": lows,
            "close": closes,
            "volume": vols,
        },
        index=utc_idx,
    )

    out = sim_routes._strategy_automation_orb_signal_from_bars(bars_df=bars_df)
    assert out["color"] == "gray"
    assert out["dir"] == 0


@pytest.mark.parametrize("strategy_key", ["orb_alpha_hybrid"])
def test_orb_alpha_hybrid_waits_10m_then_exits_after_two_opposite_alpha_bars(monkeypatch, strategy_key):
    entry_ts = datetime(2026, 3, 19, 10, 0, 0, tzinfo=timezone.utc).isoformat()
    session = SimpleNamespace(
        id=902,
        symbol="BTCUSDm",
        timeframe="M15",
        current_balance=1000.0,
        initial_balance=1000.0,
        config_json=json.dumps(
            {
                "strategy_automation": {
                    "enabled": True,
                    "strategy": str(strategy_key),
                    "symbol": "BTCUSDm",
                    "timeframe": "M15",
                    "source": "mt5",
                    "preset": "default",
                    "last_color": "red",
                    "first_run": False,
                    "force_first_entry": True,
                    "history_days": 1.0,
                    "hybrid_entry_time_utc": entry_ts,
                    "hybrid_alpha_opp_count": 0,
                    "hybrid_alpha_last_bar_unix": 0,
                }
            }
        ),
        updated_at=None,
    )
    open_trade = SimpleNamespace(
        id=77,
        direction="SELL",
        stop_loss=None,
        take_profit=None,
        status="open",
        entry_time=entry_ts,
    )

    class _QueryOpenTrade:
        def __init__(self, trade):
            self.trade = trade

        def filter(self, *args, **kwargs):
            return self

        def order_by(self, *args, **kwargs):
            return self

        def first(self):
            return self.trade

    class _Db:
        def __init__(self, trade):
            self.trade = trade
            self.added = []

        def query(self, *args, **kwargs):
            return _QueryOpenTrade(self.trade)

        def add(self, obj):
            self.added.append(obj)

        def flush(self):
            return None

    db = _Db(open_trade)
    # Two bars after +11m and +12m from entry.
    bars_t1 = pd.DataFrame(
        {
            "open": [70000.0],
            "high": [70100.0],
            "low": [69900.0],
            "close": [70050.0],
            "volume": [10.0],
        },
        index=pd.DatetimeIndex([pd.Timestamp("2026-03-19T10:11:00Z")]),
    )
    bars_t2 = pd.DataFrame(
        {
            "open": [70060.0],
            "high": [70120.0],
            "low": [70010.0],
            "close": [70110.0],
            "volume": [11.0],
        },
        index=pd.DatetimeIndex([pd.Timestamp("2026-03-19T10:12:00Z")]),
    )
    bars_seq = [bars_t1, bars_t2]

    monkeypatch.setattr(sim_routes, "_agent_fetch_live_history_bars", lambda **kwargs: ([], None))
    monkeypatch.setattr(sim_routes, "_bars_payload_to_df", lambda *args, **kwargs: bars_seq.pop(0))
    monkeypatch.setattr(sim_routes.StrategyRegistry, "get_preset_config", lambda *args, **kwargs: {})
    monkeypatch.setattr(
        sim_routes,
        "_strategy_automation_color_from_bars",
        lambda **kwargs: {
            "color": "red",               # ORB side still short
            "direction": "bearish",
            "alpha_color": "green",       # opposite to SELL
            "alpha_direction": "bullish",
        },
    )

    close_calls = []

    def _fake_close_trade(*, session_id, trade_id, req, db):
        close_calls.append({"session_id": session_id, "trade_id": trade_id, "exit_price": req.exit_price})
        return {"ok": True, "id": trade_id, "status": "closed"}

    monkeypatch.setattr(sim_routes, "close_trade", _fake_close_trade)
    monkeypatch.setattr(sim_routes, "execute_trade", lambda *args, **kwargs: pytest.fail("execute_trade should not run in this scenario"))

    first = sim_routes._process_strategy_automation_tick_unlocked(session=session, db=db, live_bar=None)
    assert first["ok"] is True
    assert first["action"] == "noop"
    assert len(close_calls) == 0
    cfg1 = json.loads(session.config_json)["strategy_automation"]
    assert int(cfg1.get("hybrid_alpha_opp_count") or 0) == 1

    second = sim_routes._process_strategy_automation_tick_unlocked(session=session, db=db, live_bar=None)
    assert second["ok"] is True
    assert second["action"] == "closed_trade"
    assert second["reason"] == "alpha_opposite_2bar_exit_after_10m"
    assert len(close_calls) == 1
    cfg2 = json.loads(session.config_json)["strategy_automation"]
    assert int(cfg2.get("hybrid_alpha_opp_count") or 0) == 0


def test_strategy_automation_hybrid_alias_normalization():
    assert sim_routes._normalize_strategy_automation_strategy("orb") == "orb_alpha_hybrid"
    assert sim_routes._normalize_strategy_automation_strategy("orb_alpha") == "orb_alpha_hybrid"
    assert sim_routes._normalize_strategy_automation_strategy("deadzone") == "deadzone_pro"
    assert sim_routes._normalize_strategy_automation_strategy("deadzonepro") == "deadzone_pro"


def test_strategy_automation_color_from_bars_deadzone_pro_uses_hull_slope():
    up_idx = pd.date_range("2026-03-21 00:00:00", periods=80, freq="min", tz="UTC")
    up_close = [100.0 + (i * 0.1) for i in range(80)]
    up_df = pd.DataFrame(
        {
            "open": up_close,
            "high": [v + 0.2 for v in up_close],
            "low": [v - 0.2 for v in up_close],
            "close": up_close,
            "volume": [100.0 for _ in up_close],
        },
        index=up_idx,
    )
    down_df = up_df.copy()
    down_df["close"] = list(reversed(up_close))
    down_df["open"] = down_df["close"]
    down_df["high"] = down_df["close"] + 0.2
    down_df["low"] = down_df["close"] - 0.2

    out_up = sim_routes._strategy_automation_color_from_bars(
        bars_df=up_df,
        strategy_key="deadzone_pro",
        preset_cfg={},
        volume_sma_period=20,
        closed_bar_only=True,
    )
    out_down = sim_routes._strategy_automation_color_from_bars(
        bars_df=down_df,
        strategy_key="deadzone_pro",
        preset_cfg={},
        volume_sma_period=20,
        closed_bar_only=True,
    )

    assert out_up["color"] == "green"
    assert out_up["direction"] == "bullish"
    assert out_down["color"] == "red"
    assert out_down["direction"] == "bearish"


def test_close_trade_falls_back_to_entry_price_when_no_market_data(monkeypatch):
    session = SimpleNamespace(
        id=99,
        mode="replay",
        strategy_id="_workbench",
        symbol="AMZNM",
        timeframe="M15",
        current_bar=0,
        total_bars=0,
        current_balance=10000.0,
        initial_balance=10000.0,
        total_pnl=0.0,
        trades_count=3,
        wins=0,
        losses=0,
        status="active",
        config_json=json.dumps({}),
        updated_at=None,
    )
    trade = SimpleNamespace(
        id=4,
        session_id=99,
        status="open",
        direction="BUY",
        entry_price=100.25,
        entry_fill_price=None,
        stop_loss=99.0,
        take_profit=103.0,
        lot_size=0.01,
        spread_value=0.0,
        tc_rate=0.0,
        exit_price=None,
        exit_mid_price=None,
        exit_fill_price=None,
        exit_bar=None,
        exit_time=None,
        exit_reason=None,
        raw_pnl=None,
        pnl=None,
        spread_cost=0.0,
        turnover_cost=0.0,
        total_cost=0.0,
        cost_breakdown_json=None,
        r_multiple=None,
    )

    class _QueryById:
        def __init__(self, obj):
            self.obj = obj

        def get(self, _id):
            return self.obj

    class _Db:
        def __init__(self):
            self.added = []
            self.commits = 0
            self.flushes = 0

        def query(self, model):
            if model is sim_routes.SimulationSession:
                return _QueryById(session)
            if model is sim_routes.SimulationTrade:
                return _QueryById(trade)
            return _QueryById(None)

        def add(self, obj):
            self.added.append(obj)

        def commit(self):
            self.commits += 1

        def flush(self):
            self.flushes += 1

    class _Engine:
        def __init__(self):
            self.df = pd.DataFrame()
            self.current_bar = 0
            self.total_bars = 0
            self.open_positions = []
            self.closed_trades = []
            self.balance = 10000.0

        def close_position(self, *args, **kwargs):
            raise ValueError("Position 4 not found")

    db = _Db()
    monkeypatch.setattr(sim_routes, "_get_or_create_engine", lambda *args, **kwargs: _Engine())
    monkeypatch.setattr(sim_routes, "_is_live_mt5_execution_enabled", lambda *_args, **_kwargs: False)
    monkeypatch.setattr(sim_routes, "_is_cost_model_enabled", lambda *_args, **_kwargs: False)
    monkeypatch.setattr(sim_routes, "_sync_session_from_engine_no_commit", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(sim_routes, "_strategy_automation_mark_stopped", lambda **_kwargs: False)
    monkeypatch.setattr(sim_routes, "_record_external_copilot_event", lambda **_kwargs: None)
    monkeypatch.setattr(sim_routes, "_store_external_snapshot", lambda **_kwargs: None)

    out = sim_routes.close_trade(
        session_id=99,
        trade_id=4,
        req=sim_routes.CloseTradeRequest(),
        db=db,
    )

    assert out["status"] == "closed"
    assert float(out["exit_price"]) == 100.25
    assert str(trade.status) == "closed"
    assert int(session.trades_count) == 4


def test_close_trade_live_reconciles_when_mt5_position_not_found_and_no_symbol_positions(monkeypatch):
    session = SimpleNamespace(
        id=116,
        symbol="BTCUSDm",
        mode="live",
        current_balance=10000.0,
        initial_balance=10000.0,
        current_bar=0,
        trades_count=0,
        wins=0,
        losses=0,
        config_json=json.dumps({"live_control": {"require_confirmation_for_live_order": False}}),
        updated_at=None,
    )
    trade = sim_routes.SimulationTrade(
        id=16,
        session_id=116,
        direction="SELL",
        status="open",
        entry_price=71087.0,
        entry_fill_price=71087.0,
        stop_loss=72000.0,
        lot_size=0.01,
        cost_breakdown_json={"execution": {"position_ticket": 987654}},
    )

    class _QueryById:
        def __init__(self, obj):
            self.obj = obj

        def get(self, _id):
            return self.obj

    class _Db:
        def __init__(self):
            self.commits = 0

        def query(self, model):
            if model is sim_routes.SimulationSession:
                return _QueryById(session)
            if model is sim_routes.SimulationTrade:
                return _QueryById(trade)
            return _QueryById(None)

        def add(self, _obj):
            return None

        def commit(self):
            self.commits += 1

        def flush(self):
            return None

    class _Mt5:
        def close_position(self, **kwargs):
            return {"ok": False, "error": "position_not_found", "position_ticket": kwargs.get("position_ticket")}

        def get_open_positions(self, **kwargs):
            return []

    db = _Db()
    monkeypatch.setattr(sim_routes, "_is_live_mt5_execution_enabled", lambda *_args, **_kwargs: True)
    monkeypatch.setattr(sim_routes, "_session_sync_live_mt5_account", lambda **_kwargs: None)
    monkeypatch.setattr(sim_routes, "_strategy_automation_mark_stopped", lambda **_kwargs: False)
    monkeypatch.setattr(sim_routes, "_get_mt5_service_singleton", lambda: _Mt5())
    monkeypatch.setattr(
        sim_routes,
        "_session_trade_math_context",
        lambda **_kwargs: {"value_per_1lot": 1.0},
    )

    out = sim_routes.close_trade(
        session_id=116,
        trade_id=16,
        req=sim_routes.CloseTradeRequest(),
        db=db,
    )

    assert out["status"] == "closed"
    assert out["execution"]["close"]["reconciled_position_not_found"] is True
    assert str(trade.status) == "closed"
    assert str(trade.exit_reason) == "manual_live_reconciled"


def test_close_trade_live_retries_with_symbol_position_ticket_on_position_not_found(monkeypatch):
    session = SimpleNamespace(
        id=124,
        symbol="BTCUSDm",
        mode="live",
        current_balance=10000.0,
        initial_balance=10000.0,
        current_bar=0,
        trades_count=0,
        wins=0,
        losses=0,
        config_json=json.dumps({"live_control": {"require_confirmation_for_live_order": False}}),
        updated_at=None,
    )
    trade = sim_routes.SimulationTrade(
        id=12,
        session_id=124,
        direction="BUY",
        status="open",
        entry_price=70000.0,
        entry_fill_price=70000.0,
        stop_loss=69000.0,
        lot_size=0.02,
        cost_breakdown_json={"execution": {"position_ticket": 111}},
    )

    class _QueryById:
        def __init__(self, obj):
            self.obj = obj

        def get(self, _id):
            return self.obj

    class _Db:
        def query(self, model):
            if model is sim_routes.SimulationSession:
                return _QueryById(session)
            if model is sim_routes.SimulationTrade:
                return _QueryById(trade)
            return _QueryById(None)

        def add(self, _obj):
            return None

        def commit(self):
            return None

        def flush(self):
            return None

    class _Mt5:
        def __init__(self):
            self.calls = []

        def close_position(self, **kwargs):
            self.calls.append(int(kwargs.get("position_ticket") or 0))
            if len(self.calls) == 1:
                return {"ok": False, "error": "position_not_found", "position_ticket": kwargs.get("position_ticket")}
            return {"ok": True, "position_ticket": kwargs.get("position_ticket"), "price": 70100.0, "order": 1, "deal": 2}

        def get_open_positions(self, **kwargs):
            return [
                {"ticket": 222, "direction": "SELL", "lot_size": 0.02},
                {"ticket": 333, "direction": "BUY", "lot_size": 0.03},
                {"ticket": 444, "direction": "BUY", "lot_size": 0.02},
            ]

    mt5 = _Mt5()
    db = _Db()
    monkeypatch.setattr(sim_routes, "_is_live_mt5_execution_enabled", lambda *_args, **_kwargs: True)
    monkeypatch.setattr(sim_routes, "_session_sync_live_mt5_account", lambda **_kwargs: None)
    monkeypatch.setattr(sim_routes, "_strategy_automation_mark_stopped", lambda **_kwargs: False)
    monkeypatch.setattr(sim_routes, "_get_mt5_service_singleton", lambda: mt5)
    monkeypatch.setattr(
        sim_routes,
        "_session_trade_math_context",
        lambda **_kwargs: {"value_per_1lot": 1.0},
    )

    out = sim_routes.close_trade(
        session_id=124,
        trade_id=12,
        req=sim_routes.CloseTradeRequest(),
        db=db,
    )

    assert out["status"] == "closed"
    assert out["execution"]["close"]["position_ticket"] == 444
    assert mt5.calls == [111, 444]
