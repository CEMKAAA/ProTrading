from __future__ import annotations

import json
import sqlite3
import types
import shutil
import uuid
from pathlib import Path

from Strategies import strategy_manager as sm

_TEST_DATA_DIR = Path("dashboard/data")


def _make_temp_options_db(path, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(path))
    cur = conn.cursor()
    cur.execute(
        """
        CREATE TABLE options_trade_journal (
            id INTEGER PRIMARY KEY,
            status TEXT,
            max_loss REAL,
            contracts INTEGER,
            portfolio_scope_key TEXT
        )
        """
    )
    cur.executemany(
        """
        INSERT INTO options_trade_journal (status, max_loss, contracts, portfolio_scope_key)
        VALUES (?, ?, ?, ?)
        """,
        rows,
    )
    conn.commit()
    conn.close()


class _FakeMt5:
    def __init__(self, account):
        self._account = account

    def initialize(self):
        return True

    def account_info(self):
        return self._account

    def positions_get(self):
        return []


def _local_tmp_dir() -> Path:
    _TEST_DATA_DIR.mkdir(parents=True, exist_ok=True)
    path = _TEST_DATA_DIR / f"codex_gov_{uuid.uuid4().hex[:8]}"
    path.mkdir(parents=True, exist_ok=True)
    return path


def test_portfolio_governor_filters_options_risk_by_current_account_scope(monkeypatch):
    tmp_path = _local_tmp_dir()
    try:
        db_path = tmp_path / "trading.db"
        _make_temp_options_db(
            db_path,
            [
                ("OPEN", 409.0, 1, "profile:MAIN|login:old|server:MetaQuotes-Demo"),
                ("OPEN", 370.0, 1, "profile:MAIN|login:old|server:MetaQuotes-Demo"),
                ("OPEN", 2.0, 1, "profile:MAIN|login:123|server:Exness-MT5Real"),
            ],
        )
        state_path = tmp_path / "portfolio_state.json"
        cfg_path = tmp_path / "portfolio_cfg.json"

        account = types.SimpleNamespace(
            balance=50.0,
            equity=50.0,
            login=123,
            server="Exness-MT5Real",
            company="Exness",
        )

        monkeypatch.setattr(sm, "_DASHBOARD_DB_PATH", db_path)
        monkeypatch.setattr(sm, "PORTFOLIO_GOVERNOR_STATE_FILE", state_path)
        monkeypatch.setattr(sm, "PORTFOLIO_GOVERNOR_CONFIG_FILE", cfg_path)
        monkeypatch.setattr(sm, "HAS_MT5", True)
        monkeypatch.setattr(sm, "mt5", _FakeMt5(account))
        monkeypatch.setenv("PORTFOLIO_SCOPE_PROFILE", "MAIN")

        mgr = sm.StrategyManager()
        monkeypatch.setattr(mgr, "get_all_running", lambda: [])

        out = mgr.evaluate_portfolio_governor(enforce=False)
        snap = out.get("snapshot", {})

        assert out.get("status") == "ok"
        assert snap.get("options_open_risk_usd") == 2.0
        assert snap.get("portfolio_heat_usd") == 2.0
        assert snap.get("portfolio_heat_pct") == 4.0
        assert snap.get("scope", {}).get("account_server") == "Exness-MT5Real"
    finally:
        shutil.rmtree(tmp_path, ignore_errors=True)


def test_portfolio_governor_cooldown_is_isolated_by_scope(monkeypatch):
    tmp_path = _local_tmp_dir()
    try:
        db_path = tmp_path / "trading.db"
        _make_temp_options_db(db_path, [])
        state_path = tmp_path / "portfolio_state.json"
        cfg_path = tmp_path / "portfolio_cfg.json"
        state_path.write_text(
            json.dumps(
                {
                    "version": 2,
                    "by_scope": {
                        "profile:MAIN|login:other|server:MetaQuotes-Demo": {
                            "status": "breached",
                            "allow_new_starts": False,
                            "cooldown_until": "2099-01-01T00:00:00+00:00",
                            "last_breach_reasons": ["portfolio_heat_exceeded:999.00%"],
                        }
                    },
                }
            ),
            encoding="utf-8",
        )

        account = types.SimpleNamespace(
            balance=50.0,
            equity=50.0,
            login=555,
            server="Exness-MT5Real",
            company="Exness",
        )

        monkeypatch.setattr(sm, "_DASHBOARD_DB_PATH", db_path)
        monkeypatch.setattr(sm, "PORTFOLIO_GOVERNOR_STATE_FILE", state_path)
        monkeypatch.setattr(sm, "PORTFOLIO_GOVERNOR_CONFIG_FILE", cfg_path)
        monkeypatch.setattr(sm, "HAS_MT5", True)
        monkeypatch.setattr(sm, "mt5", _FakeMt5(account))
        monkeypatch.setenv("PORTFOLIO_SCOPE_PROFILE", "MAIN")

        mgr = sm.StrategyManager()
        monkeypatch.setattr(mgr, "get_all_running", lambda: [])

        out = mgr.evaluate_portfolio_governor(enforce=False)

        assert out.get("status") == "ok"
        assert "cooldown_active" not in (out.get("breaches") or [])
        assert out.get("state", {}).get("status") == "ok"
    finally:
        shutil.rmtree(tmp_path, ignore_errors=True)


def test_portfolio_governor_does_not_extend_cooldown_when_only_cooldown_active(monkeypatch):
    tmp_path = _local_tmp_dir()
    try:
        db_path = tmp_path / "trading.db"
        _make_temp_options_db(db_path, [])
        state_path = tmp_path / "portfolio_state.json"
        cfg_path = tmp_path / "portfolio_cfg.json"
        original_cooldown = "2099-01-01T00:05:00+00:00"
        state_path.write_text(
            json.dumps(
                {
                    "version": 2,
                    "by_scope": {
                        "profile:MAIN|login:555|server:Exness-MT5Real": {
                            "status": "breached",
                            "allow_new_starts": False,
                            "cooldown_until": original_cooldown,
                            "last_breach_reasons": ["portfolio_heat_exceeded:999.00%"],
                        }
                    },
                }
            ),
            encoding="utf-8",
        )

        account = types.SimpleNamespace(
            balance=50.0,
            equity=50.0,
            login=555,
            server="Exness-MT5Real",
            company="Exness",
        )

        monkeypatch.setattr(sm, "_DASHBOARD_DB_PATH", db_path)
        monkeypatch.setattr(sm, "PORTFOLIO_GOVERNOR_STATE_FILE", state_path)
        monkeypatch.setattr(sm, "PORTFOLIO_GOVERNOR_CONFIG_FILE", cfg_path)
        monkeypatch.setattr(sm, "HAS_MT5", True)
        monkeypatch.setattr(sm, "mt5", _FakeMt5(account))
        monkeypatch.setenv("PORTFOLIO_SCOPE_PROFILE", "MAIN")

        mgr = sm.StrategyManager()
        monkeypatch.setattr(mgr, "get_all_running", lambda: [])

        out = mgr.evaluate_portfolio_governor(enforce=False)

        assert out.get("breaches") == ["cooldown_active"]
        assert out.get("state", {}).get("cooldown_until") == original_cooldown
    finally:
        shutil.rmtree(tmp_path, ignore_errors=True)
