from __future__ import annotations

import types
from datetime import datetime, timezone

from dashboard.backend.services import telegram_bridge_service as tbs


def test_send_text_uses_post(monkeypatch):
    svc = tbs.TelegramBridgeService()
    seen = []

    def _fake_tg_request(method, *, params=None, timeout_sec=0, http_method="GET"):
        seen.append(
            {
                "method": method,
                "params": dict(params or {}),
                "timeout_sec": timeout_sec,
                "http_method": http_method,
            }
        )
        return {"ok": True}

    monkeypatch.setattr(svc, "_tg_request", _fake_tg_request)
    svc._send_text(7119946313, "hello")
    assert seen, "sendMessage call was not made"
    assert seen[0]["method"] == "sendMessage"
    assert seen[0]["http_method"] == "POST"


def test_start_prepares_polling_with_delete_webhook(monkeypatch):
    svc = tbs.TelegramBridgeService()
    seen = []

    class _FakeThread:
        def __init__(self, *args, **kwargs):
            self._alive = False

        def start(self):
            self._alive = True

        def is_alive(self):
            return self._alive

        def join(self, timeout=None):
            self._alive = False

    def _fake_tg_request(method, *, params=None, timeout_sec=0, http_method="GET"):
        seen.append(
            {
                "method": method,
                "params": dict(params or {}),
                "timeout_sec": timeout_sec,
                "http_method": http_method,
            }
        )
        if method == "getMe":
            return {"ok": True, "result": {"id": 123, "username": "prod_optimizer_bot"}}
        return {"ok": True}

    monkeypatch.setattr(svc, "_enabled", lambda: True)
    monkeypatch.setattr(svc, "_token", lambda: "dummy")
    monkeypatch.setattr(svc, "_allowed_chat_id", lambda: 7119946313)
    monkeypatch.setattr(svc, "_tg_request", _fake_tg_request)
    monkeypatch.setattr(tbs.threading, "Thread", _FakeThread)

    svc.start()
    assert len(seen) >= 2
    assert seen[0]["method"] == "deleteWebhook"
    assert seen[0]["http_method"] == "POST"
    assert seen[1]["method"] == "getMe"
    svc.stop()


def test_approve_uses_agent_execute_tool_with_confirm_off(monkeypatch):
    svc = tbs.TelegramBridgeService()
    chat_id = 7119946313
    svc._set_pending(
        chat_id,
        [
            {
                "id": 1,
                "session_id": 77,
                "tool": "place_trade",
                "args": {
                    "direction": "BUY",
                    "stop_loss": 5155.5,
                    "take_profit": 5177.73,
                    "lot_size": 1.34,
                },
            }
        ],
    )

    class _FakeQuery:
        def __init__(self, row):
            self._row = row

        def get(self, _sid):
            return self._row

    class _FakeDB:
        def __init__(self, row):
            self._row = row

        def query(self, _model):
            return _FakeQuery(self._row)

        def close(self):
            return None

    session_row = types.SimpleNamespace(id=77, strategy_id="_workbench", symbol="XAUUSD", timeframe="M15")
    monkeypatch.setattr(tbs, "SessionLocal", lambda: _FakeDB(session_row))
    monkeypatch.setattr(
        svc,
        "_resolve_provider_and_permissions",
        lambda _sid: (
            {"provider": "deterministic"},
            {
                "can_place_trades": True,
                "can_close_trades": True,
                "requires_user_confirm_for_trade": True,
            },
            {},
        ),
    )

    from dashboard.backend.api import simulation_routes as sim_routes

    calls = {}

    def _fake_agent_default_context(*, session, db):
        return {"session_id": getattr(session, "id", None)}

    def _fake_agent_execute_tool(*, session, db, permissions, context_snapshot, tool_name, args, atomic):
        calls["tool_name"] = tool_name
        calls["permissions"] = dict(permissions or {})
        calls["atomic"] = atomic
        return {"ok": True, "data": {"id": 999, "direction": "BUY"}}

    def _fail_execute_trade(*args, **kwargs):
        raise AssertionError("execute_trade must not be called directly in approval path")

    monkeypatch.setattr(sim_routes, "_agent_default_context", _fake_agent_default_context)
    monkeypatch.setattr(sim_routes, "_agent_execute_tool", _fake_agent_execute_tool)
    monkeypatch.setattr(sim_routes, "execute_trade", _fail_execute_trade)

    msg = svc._execute_pending_approval(chat_id, 1)
    assert "Approved and executed" in msg
    assert calls.get("tool_name") == "place_trade"
    assert calls.get("permissions", {}).get("requires_user_confirm_for_trade") is False
    assert calls.get("permissions", {}).get("can_place_trades") is True
    assert svc._get_pending(chat_id) == []


def test_summary_command_is_distinct(monkeypatch):
    svc = tbs.TelegramBridgeService()
    chat_id = 7119946313
    monkeypatch.setattr(svc, "_resolve_default_session_id", lambda _chat: 92)
    monkeypatch.setattr(svc, "_format_status", lambda _sid: "STATUS_PAYLOAD")
    monkeypatch.setattr(svc, "_format_summary", lambda _sid: "SUMMARY_PAYLOAD")
    assert svc._handle_text(chat_id, "/status") == "STATUS_PAYLOAD"
    assert svc._handle_text(chat_id, "/summary") == "SUMMARY_PAYLOAD"


def test_allowed_chat_id_reads_env_file_fallback(monkeypatch):
    monkeypatch.delenv("TELEGRAM_ALLOWED_CHAT_ID", raising=False)
    monkeypatch.setattr(
        tbs.TelegramBridgeService,
        "_read_env_file_value",
        staticmethod(lambda key: "7119946313" if str(key) == "TELEGRAM_ALLOWED_CHAT_ID" else None),
    )
    assert tbs.TelegramBridgeService._allowed_chat_id() == 7119946313


def test_agent_max_tool_steps_from_env(monkeypatch):
    monkeypatch.setenv("TELEGRAM_AGENT_MAX_TOOL_STEPS", "8")
    assert tbs.TelegramBridgeService._agent_max_tool_steps() == 8


def test_format_watchdog_event_contains_key_fields():
    svc = tbs.TelegramBridgeService()
    session = types.SimpleNamespace(id=92, symbol="XAUUSD", timeframe="M15")
    ev = types.SimpleNamespace(
        event_type="WATCHDOG_ENTRY_EXECUTED",
        severity="info",
        payload_json={
            "trigger_id": "trg_abc",
            "trade": {"id": 12},
            "condition": "close_below",
            "trigger_price": 5313.48,
            "hit_price": 5312.90,
            "message": "Entry executed",
        },
        created_at=datetime(2026, 3, 7, 10, 0, tzinfo=timezone.utc),
    )
    out = svc._format_watchdog_event(session, ev)
    assert "WATCHDOG_ENTRY_EXECUTED" in out
    assert "Session #92 XAUUSD M15" in out
    assert "Trigger: trg_abc" in out
    assert "Trade: #12" in out
    assert "Trigger price: 5313.48" in out
    assert "Hit price: 5312.9" in out


def test_push_watchdog_alerts_skips_backlog_then_sends_new(monkeypatch):
    svc = tbs.TelegramBridgeService()
    chat_id = 7119946313
    session_id = 92
    sent = []

    session_row = types.SimpleNamespace(id=session_id, strategy_id="_workbench", symbol="XAUUSD", timeframe="M15")
    agent_row = types.SimpleNamespace(id=501, simulation_session_id=session_id, status="ACTIVE")
    ev5 = types.SimpleNamespace(
        id=5,
        event_type="WATCHDOG_ENTRY_EXECUTED",
        severity="info",
        payload_json={"trigger_id": "trg_old"},
        created_at=datetime(2026, 3, 7, 10, 0, tzinfo=timezone.utc),
    )
    ev6 = types.SimpleNamespace(
        id=6,
        event_type="WATCHDOG_ENTRY_EXECUTED",
        severity="info",
        payload_json={"trigger_id": "trg_new"},
        created_at=datetime(2026, 3, 7, 10, 1, tzinfo=timezone.utc),
    )

    class _FakeQuery:
        def __init__(self, db, model):
            self.db = db
            self.model = model

        def filter(self, *args, **kwargs):
            return self

        def order_by(self, *args, **kwargs):
            return self

        def limit(self, _n):
            return self

        def get(self, _id):
            if self.model is tbs.SimulationSession:
                return self.db.session_row
            return None

        def first(self):
            if self.model is tbs.WorkbenchAgentSessionModel:
                return self.db.agent_row
            if self.model is tbs.WorkbenchAgentEventModel:
                if self.db.max_rows:
                    return self.db.max_rows.pop(0)
                return None
            return None

        def all(self):
            if self.model is tbs.WorkbenchAgentEventModel:
                if self.db.event_batches:
                    return self.db.event_batches.pop(0)
            return []

    class _FakeDB:
        def __init__(self):
            self.session_row = session_row
            self.agent_row = agent_row
            self.max_rows = [ev5, ev6]
            self.event_batches = [[ev6]]

        def query(self, model):
            return _FakeQuery(self, model)

        def close(self):
            return None

    fake_db = _FakeDB()
    monkeypatch.setattr(tbs, "SessionLocal", lambda: fake_db)
    monkeypatch.setattr(svc, "_allowed_chat_id", lambda: chat_id)
    monkeypatch.setattr(svc, "_resolve_default_session_id", lambda _chat: session_id)
    monkeypatch.setattr(svc, "_watchdog_should_check_now", lambda _chat, _sid: True)
    monkeypatch.setattr(svc, "_send_text", lambda _chat, text: sent.append(text))

    # First run initializes cursor to latest event and sends nothing.
    svc._push_watchdog_alerts()
    assert sent == []
    assert svc._watchdog_cursor_get(chat_id, session_id) == 5

    # Second run sends only newly appeared event(s).
    svc._push_watchdog_alerts()
    assert len(sent) == 1
    assert "trg_new" in sent[0]
    assert svc._watchdog_cursor_get(chat_id, session_id) == 6


def test_resolve_provider_prefers_agent_session_over_copilot(monkeypatch):
    svc = tbs.TelegramBridgeService()
    session_id = 92
    agent_row = types.SimpleNamespace(
        simulation_session_id=session_id,
        status="ACTIVE",
        provider="claude",
        model_label="claude-haiku-4-5-20251001",
        permissions_json={"can_chat": True, "can_scan_tools": True},
        config_json={"agent_permissions": {"can_chat": False}},
        runtime_json={"claude_base_url": "https://api.anthropic.com", "anthropic_api_key": "k", "llm_timeout_sec": 75},
        updated_at=None,
    )
    cop_row = types.SimpleNamespace(
        simulation_session_id=session_id,
        provider="deterministic",
        model_label=None,
        config_json={"agent_permissions": {"can_chat": False}},
        created_at=None,
    )

    class _FakeQuery:
        def __init__(self, db, model):
            self.db = db
            self.model = model

        def filter(self, *args, **kwargs):
            return self

        def order_by(self, *args, **kwargs):
            return self

        def first(self):
            if self.model is tbs.WorkbenchAgentSessionModel:
                return self.db.agent_row
            if self.model is tbs.WorkbenchCopilotSessionModel:
                return self.db.cop_row
            return None

    class _FakeDB:
        def __init__(self):
            self.agent_row = agent_row
            self.cop_row = cop_row

        def query(self, model):
            return _FakeQuery(self, model)

        def close(self):
            return None

    monkeypatch.setattr(tbs, "SessionLocal", lambda: _FakeDB())
    provider, perms, cfg = svc._resolve_provider_and_permissions(session_id)
    assert provider.get("provider") == "claude"
    assert provider.get("model_label") == "claude-haiku-4-5-20251001"
    assert provider.get("llm_url") == "https://api.anthropic.com"
    assert provider.get("api_key") == "k"
    assert provider.get("timeout_sec") == 75
    assert perms.get("can_chat") is True
    assert cfg.get("agent_permissions") is not None


def test_resolve_provider_falls_back_to_env_api_key_when_runtime_has_none(monkeypatch):
    """When runtime_json has no API key, Telegram should fall back to env vars."""
    svc = tbs.TelegramBridgeService()
    session_id = 92
    agent_row = types.SimpleNamespace(
        simulation_session_id=session_id,
        status="ACTIVE",
        provider="claude",
        model_label="claude-haiku-4-5-20251001",
        permissions_json={"can_chat": True},
        config_json={},
        # runtime_json has llm_url and timeout but NO api_key — this is
        # what happens after a normal Workbench chat (key sent per-request).
        runtime_json={"llm_url": "https://api.anthropic.com", "timeout_sec": 60},
        updated_at=None,
    )

    class _FakeQuery:
        def __init__(self, db, model):
            self.db = db
            self.model = model

        def filter(self, *args, **kwargs):
            return self

        def order_by(self, *args, **kwargs):
            return self

        def first(self):
            if self.model is tbs.WorkbenchAgentSessionModel:
                return self.db.agent_row
            return None

    class _FakeDB:
        def __init__(self):
            self.agent_row = agent_row

        def query(self, model):
            return _FakeQuery(self, model)

        def close(self):
            return None

    monkeypatch.setattr(tbs, "SessionLocal", lambda: _FakeDB())
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-test-from-env")
    provider, perms, cfg = svc._resolve_provider_and_permissions(session_id)
    assert provider.get("provider") == "claude"
    assert provider.get("api_key") == "sk-test-from-env", (
        "API key should fall back to ANTHROPIC_API_KEY env var"
    )


def test_toolmode_command_show_and_set(monkeypatch):
    svc = tbs.TelegramBridgeService()
    chat_id = 7119946313
    monkeypatch.setattr(svc, "_resolve_default_session_id", lambda _chat: 97)
    monkeypatch.setattr(
        svc,
        "_resolve_provider_and_permissions",
        lambda _sid: ({"provider": "claude"}, {}, {"strategy_tool_access_mode": "parent"}),
    )
    out_show = svc._handle_text(chat_id, "/toolmode")
    assert "strategy tool mode: parent" in out_show.lower()

    seen = {}
    def _fake_set_mode(sid, mode):
        seen["value"] = (sid, mode)
        return "ok"

    monkeypatch.setattr(svc, "_set_tool_access_mode", _fake_set_mode)
    svc._handle_text(chat_id, "/toolmode child")
    assert seen.get("value") == (97, "child")


def test_toolmode_command_usage_on_invalid_mode(monkeypatch):
    svc = tbs.TelegramBridgeService()
    assert "Usage: /toolmode <all|parent|child> [session_id]" == svc._set_tool_access_mode(1, "invalid_mode")


def test_toolselect_command_show_and_set(monkeypatch):
    svc = tbs.TelegramBridgeService()
    chat_id = 7119946313
    monkeypatch.setattr(svc, "_resolve_default_session_id", lambda _chat: 97)
    monkeypatch.setattr(
        svc,
        "_resolve_provider_and_permissions",
        lambda _sid: ({"provider": "claude"}, {}, {"tool_selection_mode": "guided"}),
    )
    out_show = svc._handle_text(chat_id, "/toolselect")
    assert "tool selection mode: guided" in out_show.lower()

    seen = {}

    def _fake_set_mode(sid, mode):
        seen["value"] = (sid, mode)
        return "ok"

    monkeypatch.setattr(svc, "_set_tool_selection_mode", _fake_set_mode)
    out_set = svc._handle_text(chat_id, "/toolselect minimal")
    assert out_set == "ok"
    assert seen.get("value") == (97, "minimal")


def test_toolselect_command_usage_on_invalid_mode(monkeypatch):
    svc = tbs.TelegramBridgeService()
    assert "Usage: /toolselect <autonomous|guided|minimal> [session_id]" == svc._set_tool_selection_mode(1, "invalid_mode")


def test_help_includes_tool_modes():
    svc = tbs.TelegramBridgeService()
    out = svc._handle_text(7119946313, "/help")
    assert "/toolmode [all|parent|child] [session_id]" in out
    assert "/toolselect [autonomous|guided|minimal] [session_id]" in out


def test_resolve_provider_falls_back_to_claude_alias_env_key(monkeypatch):
    svc = tbs.TelegramBridgeService()
    session_id = 92
    agent_row = types.SimpleNamespace(
        simulation_session_id=session_id,
        status="ACTIVE",
        provider="claude",
        model_label="claude-haiku-4-5-20251001",
        permissions_json={"can_chat": True},
        config_json={},
        runtime_json={"llm_url": "https://api.anthropic.com", "timeout_sec": 60},
        updated_at=None,
    )

    class _FakeQuery:
        def __init__(self, db, model):
            self.db = db
            self.model = model

        def filter(self, *args, **kwargs):
            return self

        def order_by(self, *args, **kwargs):
            return self

        def first(self):
            if self.model is tbs.WorkbenchAgentSessionModel:
                return self.db.agent_row
            return None

    class _FakeDB:
        def __init__(self):
            self.agent_row = agent_row

        def query(self, model):
            return _FakeQuery(self, model)

        def close(self):
            return None

    monkeypatch.setattr(tbs, "SessionLocal", lambda: _FakeDB())
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    monkeypatch.setenv("CLAUDE_API_KEY", "sk-test-claude-alias")
    provider, _perms, _cfg = svc._resolve_provider_and_permissions(session_id)
    assert provider.get("api_key") == "sk-test-claude-alias"


def test_identity_command_routes_to_profile_setter(monkeypatch):
    svc = tbs.TelegramBridgeService()
    chat_id = 7119946313
    monkeypatch.setattr(svc, "_resolve_default_session_id", lambda _chat: 97)
    seen = {}

    def _fake_set_identity_profile(sid, profile):
        seen["sid"] = int(sid)
        seen["profile"] = str(profile)
        return "ok"

    monkeypatch.setattr(svc, "_set_identity_profile", _fake_set_identity_profile)
    out = svc._handle_text(chat_id, "/identity master")
    assert out == "ok"
    assert seen.get("sid") == 97
    assert seen.get("profile") == "master"


def test_convo_switch_isolates_history():
    svc = tbs.TelegramBridgeService()
    chat_id = 7119946313
    session_id = 97

    svc._conversation_set_active(chat_id, session_id, "default")
    svc._history_append(chat_id, session_id, "user", "hello default")
    assert len(svc._history_get(chat_id, session_id)) == 1

    svc._conversation_set_active(chat_id, session_id, "fvg_plan")
    assert svc._history_get(chat_id, session_id) == []
    svc._history_append(chat_id, session_id, "user", "hello fvg")
    assert len(svc._history_get(chat_id, session_id)) == 1

    svc._conversation_set_active(chat_id, session_id, "default")
    rows = svc._history_get(chat_id, session_id)
    assert len(rows) == 1
    assert "default" in str(rows[0].get("content") or "")

    names = svc._conversation_list(chat_id, session_id)
    assert "default" in names
    assert "fvg_plan" in names


def test_runtime_identity_detects_master_from_json_string(monkeypatch):
    svc = tbs.TelegramBridgeService()
    session_id = 97
    session_row = types.SimpleNamespace(
        id=session_id,
        symbol="XAUUSD",
        timeframe="M15",
        config_json=(
            '{"agent_identity":{"enabled":true,"version":1,'
            '"persona":"Master trader and quantitative risk manager for paper simulation.",'
            '"tone":"Decisive"}}'
        ),
    )

    class _FakeQuery:
        def __init__(self, row):
            self._row = row

        def get(self, _sid):
            return self._row

    class _FakeDB:
        def query(self, _model):
            return _FakeQuery(session_row)

        def close(self):
            return None

    monkeypatch.setattr(tbs, "SessionLocal", lambda: _FakeDB())
    monkeypatch.setattr(
        svc,
        "_resolve_provider_and_permissions",
        lambda _sid: ({"provider": "claude", "model_label": "claude-haiku-4-5-20251001"}, {"can_chat": True}, {}),
    )
    out = svc._format_runtime(session_id)
    assert "Identity: master_quant" in out


def test_latest_command_formats_latest_active_session(monkeypatch):
    svc = tbs.TelegramBridgeService()
    chat_id = 7119946313
    row = types.SimpleNamespace(
        id=123,
        strategy_id="_workbench",
        status="active",
        symbol="XAUUSD",
        timeframe="M15",
        updated_at=datetime(2026, 3, 8, 10, 30, tzinfo=timezone.utc),
    )

    class _FakeQuery:
        def filter(self, *args, **kwargs):
            return self

        def order_by(self, *args, **kwargs):
            return self

        def first(self):
            return row

    class _FakeDB:
        def query(self, _model):
            return _FakeQuery()

        def close(self):
            return None

    monkeypatch.setattr(tbs, "SessionLocal", lambda: _FakeDB())
    monkeypatch.setattr(svc, "_resolve_default_session_id", lambda _chat: 99)
    out = svc._handle_text(chat_id, "/latest")
    assert "Latest Workbench session: #123" in out
    assert "Use it: /use 123" in out


def test_provider_set_command_routes_to_provider_setter(monkeypatch):
    svc = tbs.TelegramBridgeService()
    chat_id = 7119946313
    monkeypatch.setattr(svc, "_resolve_default_session_id", lambda _chat: 97)
    seen = {}

    def _fake_set_provider_profile(session_id, provider_raw, model_label=None, llm_url=None, api_key=None):
        seen["session_id"] = int(session_id)
        seen["provider_raw"] = str(provider_raw)
        seen["model_label"] = model_label
        seen["llm_url"] = llm_url
        seen["api_key"] = api_key
        return "ok"

    monkeypatch.setattr(svc, "_set_provider_profile", _fake_set_provider_profile)
    out = svc._handle_text(
        chat_id,
        "/provider set claude claude-haiku-4-5-20251001 https://api.anthropic.com - 97",
    )
    assert out == "ok"
    assert seen.get("session_id") == 97
    assert seen.get("provider_raw") == "claude"
    assert seen.get("model_label") == "claude-haiku-4-5-20251001"
    assert seen.get("llm_url") == "https://api.anthropic.com"
    assert seen.get("api_key") is None


def test_provider_set_clears_stale_cross_provider_keys(monkeypatch):
    svc = tbs.TelegramBridgeService()
    session_id = 97
    session_row = types.SimpleNamespace(id=session_id, strategy_id="_workbench")
    agent_row = types.SimpleNamespace(
        id=7,
        simulation_session_id=session_id,
        status="ACTIVE",
        provider="openai_compat",
        model_label="gpt-4.1-mini",
        runtime_json={
            "openai_base_url": "https://api.openai.com/v1",
            "openai_api_key": "old-openai-key",
            "api_key": "old-generic-key",
            "llm_url": "https://api.openai.com/v1",
        },
        updated_at=None,
    )

    class _FakeQuery:
        def __init__(self, db, model):
            self.db = db
            self.model = model

        def filter(self, *args, **kwargs):
            return self

        def order_by(self, *args, **kwargs):
            return self

        def first(self):
            if self.model is tbs.WorkbenchAgentSessionModel:
                return self.db.agent_row
            return None

        def get(self, _sid):
            if self.model is tbs.SimulationSession:
                return self.db.session_row
            return None

    class _FakeDB:
        def __init__(self):
            self.session_row = session_row
            self.agent_row = agent_row
            self.did_commit = False

        def query(self, model):
            return _FakeQuery(self, model)

        def add(self, _row):
            return None

        def flush(self):
            return None

        def commit(self):
            self.did_commit = True

        def rollback(self):
            return None

        def close(self):
            return None

    fake_db = _FakeDB()
    monkeypatch.setattr(tbs, "SessionLocal", lambda: fake_db)
    out = svc._set_provider_profile(session_id, "claude", model_label=None, llm_url=None, api_key=None)
    assert "Provider set for session" in out
    rt = fake_db.agent_row.runtime_json if isinstance(fake_db.agent_row.runtime_json, dict) else {}
    assert "openai_api_key" not in rt
    assert "api_key" not in rt
    assert rt.get("claude_base_url") == "https://api.anthropic.com"
