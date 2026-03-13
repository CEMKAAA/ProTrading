from __future__ import annotations

import shutil
import uuid
from pathlib import Path

from Strategies.shared.bot_state import BotStateManager
from Strategies.strategy_manager import STRATEGY_PATHS
from Strategies.HTFFVGLiquidityReclaimStrategy.config import build_live_strategy_config
from dashboard.backend.services.live_service import BOT_STATE_FILES, LiveTradingService
from dashboard.backend.core.trading_simulation.session_service import capability_matrix


def test_live_config_preserves_broker_symbol_and_uses_base_preset():
    cfg = build_live_strategy_config(
        {
            "symbol": "XAUUSDm",
            "preset": "xauusd_m15",
            "timeframe": "M15",
            "initial_balance": 5000,
        }
    )

    assert cfg["symbol"] == "XAUUSDm"
    assert cfg["base_symbol"] == "XAUUSD"
    assert cfg["preset_id"] == "xauusd_m15"
    assert cfg["htf_timeframe"] == "H4"
    assert float(cfg["sweep_distance_atr"]) == 0.50
    assert float(cfg["initial_balance"]) == 5000.0


def test_bot_state_manager_accepts_extra_diagnostics():
    tmp_dir = Path("dashboard/data") / f"codex_reclaim_{uuid.uuid4().hex[:8]}"
    tmp_dir.mkdir(parents=True, exist_ok=True)
    try:
        state_file = tmp_dir / "reclaim_state.json"
        mgr = BotStateManager(str(state_file), "htf_fvg_liquidity_reclaim_strategy", "HTF FVG + Liquidity Reclaim")

        mgr.update_state(
            is_running=True,
            current_price=5154.37,
            sweep_quality="strong",
            fvg_quality="moderate",
            setup_detected=True,
        )

        state = mgr.read_state()
        assert state["current_price"] == 5154.37
        assert state["sweep_quality"] == "strong"
        assert state["fvg_quality"] == "moderate"
        assert state["setup_detected"] is True
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


def test_liquidity_reclaim_strategy_is_live_runnable():
    entry = STRATEGY_PATHS.get("htf_fvg_liquidity_reclaim_strategy")
    assert isinstance(entry, dict)
    assert Path(entry["main"]).name == "main.py"
    assert Path(entry["state"]).name == "htf_fvg_liquidity_reclaim_strategy_state.json"
    assert Path(BOT_STATE_FILES["htf_fvg_liquidity_reclaim_strategy"]).name == "htf_fvg_liquidity_reclaim_strategy_state.json"

    rows = capability_matrix()
    row = next(r for r in rows if r["strategy_id"] == "htf_fvg_liquidity_reclaim_strategy")
    assert row["listed"] is True
    assert row["runnable"] is True
    assert row["has_live_state"] is True
    assert row["status_label"] == "Live Runnable"


def test_live_status_exposes_liquidity_reclaim_diagnostics(monkeypatch):
    service = LiveTradingService()
    bot_state = {
        "is_connected": True,
        "is_running": True,
        "active_strategy": "htf_fvg_liquidity_reclaim_strategy",
        "symbol": "XAUUSDm",
        "base_symbol": "XAUUSD",
        "current_time_ny": "2026-03-12T10:15:00-04:00",
        "current_price": 5154.37,
        "spread": 0.42,
        "session_bias": "bullish",
        "is_trending": True,
        "daily_trades": 1,
        "daily_pnl": 42.5,
        "can_trade": True,
        "balance": 10042.5,
        "equity": 10040.0,
        "margin_level": 512.0,
        "strategy_preset": "xauusd_m15",
        "setup_detected": True,
        "fvg_detected": True,
        "fvg_quality": "strong",
        "sweep_detected": True,
        "sweep_quality": "moderate",
        "rejection_confirmed": True,
        "rr": 2.8,
    }
    monkeypatch.setattr(service, "_read_bot_state", lambda: dict(bot_state))
    monkeypatch.setattr(service, "get_all_running_strategies", lambda: [dict(bot_state, strategy_id="htf_fvg_liquidity_reclaim_strategy")])

    status = service.get_status(symbol="XAUUSDm")
    assert status["active_strategy"] == "htf_fvg_liquidity_reclaim_strategy"
    assert status["symbol_requested"] == "XAUUSDM"
    assert status["symbol_resolved"] == "XAUUSDm"
    assert status["strategy_diagnostics"]["fvg_quality"] == "strong"
    assert status["strategy_diagnostics"]["sweep_quality"] == "moderate"
    assert status["strategy_diagnostics"]["rr"] == 2.8
