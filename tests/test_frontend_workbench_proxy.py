from __future__ import annotations

from dashboard.frontend import app as frontend_app_module


def test_sim_mt5_symbols_proxy_forwards_to_backend(monkeypatch):
    app = frontend_app_module.app
    app.config["TESTING"] = True

    seen = {}

    def _fake_api_request(method, path, params=None, **kwargs):
        seen["method"] = method
        seen["path"] = path
        seen["params"] = dict(params or {})
        return {
            "ok": True,
            "count": 1,
            "symbols": [{"name": "XAUUSDm", "description": "Gold", "visible": True}],
        }, None

    monkeypatch.setattr(frontend_app_module, "api_request", _fake_api_request)

    client = app.test_client()
    resp = client.get("/api/simulation/mt5/symbols?search=XAU&limit=25&include_hidden=true")

    assert resp.status_code == 200
    data = resp.get_json()
    assert data["ok"] is True
    assert data["count"] == 1
    assert seen["method"] == "GET"
    assert seen["path"] == "/api/v1/simulation/mt5/symbols"
    assert seen["params"] == {"search": "XAU", "limit": "25", "include_hidden": "true"}


def test_sim_sessions_list_proxy_forwards_to_backend(monkeypatch):
    app = frontend_app_module.app
    app.config["TESTING"] = True

    seen = {}

    def _fake_api_request(method, path, params=None, **kwargs):
        seen["method"] = method
        seen["path"] = path
        seen["params"] = dict(params or {})
        return {"ok": True, "sessions": []}, None

    monkeypatch.setattr(frontend_app_module, "api_request", _fake_api_request)

    client = app.test_client()
    resp = client.get("/api/simulation/sessions?strategy_id=_workbench&limit=200")

    assert resp.status_code == 200
    data = resp.get_json()
    assert data["ok"] is True
    assert seen["method"] == "GET"
    assert seen["path"] == "/api/v1/simulation/sessions"
    assert seen["params"] == {"strategy_id": "_workbench", "limit": "200"}


def test_sim_agent_admin_proxy_forwards_to_backend(monkeypatch):
    app = frontend_app_module.app
    app.config["TESTING"] = True

    seen = {}

    def _fake_api_request(method, path, params=None, **kwargs):
        seen["method"] = method
        seen["path"] = path
        return {"ok": True, "health": {"provider_ready": True}}, None

    monkeypatch.setattr(frontend_app_module, "api_request", _fake_api_request)

    client = app.test_client()
    resp = client.get("/api/simulation/sessions/125/agent/admin")

    assert resp.status_code == 200
    data = resp.get_json()
    assert data["ok"] is True
    assert seen["method"] == "GET"
    assert seen["path"] == "/api/v1/simulation/sessions/125/agent/admin"


def test_sim_agent_trendilo_opportunities_proxy_forwards_to_backend(monkeypatch):
    app = frontend_app_module.app
    app.config["TESTING"] = True

    seen = {}

    def _fake_api_request(method, path, data=None, **kwargs):
        seen["method"] = method
        seen["path"] = path
        seen["data"] = dict(data or {})
        return {"ok": True, "session_id": 45, "data": {"scan_type": "trendilo_tradeable_scan"}}, None

    monkeypatch.setattr(frontend_app_module, "api_request", _fake_api_request)

    client = app.test_client()
    payload = {"timeframe": "M5", "lookback_bars": 120, "summary_only": True}
    resp = client.post("/api/simulation/sessions/45/agent/trendilo-opportunities", json=payload)

    assert resp.status_code == 200
    data = resp.get_json()
    assert data["ok"] is True
    assert seen["method"] == "POST"
    assert seen["path"] == "/api/v1/simulation/sessions/45/agent/trendilo-opportunities"
    assert seen["data"] == payload


def test_sim_agent_strategy_opportunities_proxy_forwards_to_backend(monkeypatch):
    app = frontend_app_module.app
    app.config["TESTING"] = True

    seen = {}

    def _fake_api_request(method, path, data=None, **kwargs):
        seen["method"] = method
        seen["path"] = path
        seen["data"] = dict(data or {})
        return {"ok": True, "session_id": 45, "data": {"scan_type": "strategy_tradeable_scan"}}, None

    monkeypatch.setattr(frontend_app_module, "api_request", _fake_api_request)

    client = app.test_client()
    payload = {"strategy": "mtf", "timeframe": "M15", "summary_only": True}
    resp = client.post("/api/simulation/sessions/45/agent/strategy-opportunities", json=payload)

    assert resp.status_code == 200
    data = resp.get_json()
    assert data["ok"] is True
    assert seen["method"] == "POST"
    assert seen["path"] == "/api/v1/simulation/sessions/45/agent/strategy-opportunities"
    assert seen["data"] == payload
