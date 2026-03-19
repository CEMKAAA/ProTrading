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


def test_sim_agent_strategy_automation_start_proxy_forwards_to_backend(monkeypatch):
    app = frontend_app_module.app
    app.config["TESTING"] = True

    seen = {}

    def _fake_api_request(method, path, data=None, **kwargs):
        seen["method"] = method
        seen["path"] = path
        seen["data"] = dict(data or {})
        return {"ok": True, "job_id": "auto_1"}, None

    monkeypatch.setattr(frontend_app_module, "api_request", _fake_api_request)

    client = app.test_client()
    payload = {"symbol": "XAUUSDm", "strategy": "trendilo", "timeframe": "M15"}
    resp = client.post("/api/simulation/sessions/45/agent/strategy-automation/start", json=payload)

    assert resp.status_code == 200
    data = resp.get_json()
    assert data["ok"] is True
    assert seen["method"] == "POST"
    assert seen["path"] == "/api/v1/simulation/sessions/45/agent/strategy-automation/start"
    assert seen["data"] == payload


def test_sim_agent_strategy_automation_stop_proxy_forwards_to_backend(monkeypatch):
    app = frontend_app_module.app
    app.config["TESTING"] = True

    seen = {}

    def _fake_api_request(method, path, data=None, **kwargs):
        seen["method"] = method
        seen["path"] = path
        seen["data"] = dict(data or {})
        return {"ok": True, "stopped": 1}, None

    monkeypatch.setattr(frontend_app_module, "api_request", _fake_api_request)

    client = app.test_client()
    payload = {"job_id": "auto_1"}
    resp = client.post("/api/simulation/sessions/45/agent/strategy-automation/stop", json=payload)

    assert resp.status_code == 200
    data = resp.get_json()
    assert data["ok"] is True
    assert seen["method"] == "POST"
    assert seen["path"] == "/api/v1/simulation/sessions/45/agent/strategy-automation/stop"
    assert seen["data"] == payload


def test_sim_agent_strategy_automation_jobs_proxy_forwards_query_params(monkeypatch):
    app = frontend_app_module.app
    app.config["TESTING"] = True

    seen = {}

    def _fake_api_request(method, path, params=None, **kwargs):
        seen["method"] = method
        seen["path"] = path
        seen["params"] = dict(params or {})
        return {"ok": True, "jobs": []}, None

    monkeypatch.setattr(frontend_app_module, "api_request", _fake_api_request)

    client = app.test_client()
    resp = client.get("/api/simulation/sessions/45/agent/strategy-automation/jobs?include_disabled=1")

    assert resp.status_code == 200
    data = resp.get_json()
    assert data["ok"] is True
    assert seen["method"] == "GET"
    assert seen["path"] == "/api/v1/simulation/sessions/45/agent/strategy-automation/jobs"
    assert seen["params"] == {"include_disabled": "1"}


def test_sim_live_control_proxy_forwards_to_backend(monkeypatch):
    app = frontend_app_module.app
    app.config["TESTING"] = True

    seen = {}

    def _fake_api_request(method, path, data=None, **kwargs):
        seen["method"] = method
        seen["path"] = path
        seen["data"] = dict(data or {})
        return {"ok": True, "session_id": 122, "live_control": {"execution_mode": "live_mt5"}}, None

    monkeypatch.setattr(frontend_app_module, "api_request", _fake_api_request)

    client = app.test_client()
    payload = {
        "execution_mode": "live_mt5",
        "max_risk_per_trade_usd": 50.0,
        "max_lot_per_trade": 0.25,
    }
    resp = client.post("/api/simulation/sessions/122/live-control", json=payload)

    assert resp.status_code == 200
    data = resp.get_json()
    assert data["ok"] is True
    assert seen["method"] == "POST"
    assert seen["path"] == "/api/v1/simulation/sessions/122/live-control"
    assert seen["data"] == payload


def test_sim_close_trade_proxy_preserves_upstream_400(monkeypatch):
    app = frontend_app_module.app
    app.config["TESTING"] = True

    def _fake_api_request(method, path, data=None, **kwargs):
        return None, "API error (400): No market data available for close exit price"

    monkeypatch.setattr(frontend_app_module, "api_request", _fake_api_request)

    client = app.test_client()
    resp = client.post("/api/simulation/sessions/99/close-trade/4", json={})

    assert resp.status_code == 400
    data = resp.get_json() or {}
    assert "No market data available for close exit price" in str(data.get("error") or "")
