from __future__ import annotations

from datetime import datetime, timezone
import sys
import types

from dashboard.backend.api import simulation_routes as sim_routes


def test_news_impact_uses_word_boundaries():
    assert sim_routes._agent_news_headline_impact("Warranty costs are rising") == "normal"
    assert sim_routes._agent_news_headline_impact("War risk rises in key region") == "high"
    assert sim_routes._agent_news_headline_impact("FOMC decision later today") == "high"


def test_news_symbol_mapping_handles_cfd_variants():
    assert sim_routes._agent_news_ticker_for_symbol("XAUUSD.m") == "GLD"
    assert sim_routes._agent_news_ticker_for_symbol("us500.cash") == "SPY"
    assert sim_routes._agent_news_ticker_for_symbol("NAS100_i") == "QQQ"
    assert sim_routes._agent_news_ticker_for_symbol("AAPL") == "AAPL"
    assert sim_routes._agent_news_ticker_for_symbol("UNKNOWNCFD123") == ""


def test_ibkr_proxy_mapping_does_not_map_xau_to_etf_proxy():
    assert sim_routes._agent_ibkr_news_proxy_ticker_for_symbol("XAUUSD") == ""
    assert sim_routes._agent_ibkr_news_proxy_ticker_for_symbol("XAUUSD.m") == ""
    assert sim_routes._agent_ibkr_news_proxy_ticker_for_symbol("US500.cash") == "SPY"


def test_news_fetch_uses_bearer_header_and_cache():
    calls = []
    now_utc = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

    class _FakeResponse:
        status_code = 200
        headers = {"content-type": "application/json"}

        def json(self):
            return {
                "results": [
                    {
                        "title": "FOMC outlook update",
                        "publisher": {"name": "wire"},
                        "published_utc": now_utc,
                        "article_url": "https://example.test/news/1",
                    }
                ]
            }

    class _FakeClient:
        def __init__(self, *args, **kwargs):
            _ = (args, kwargs)

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            _ = (exc_type, exc, tb)
            return False

        def get(self, url, params=None, headers=None):
            calls.append({"url": url, "params": dict(params or {}), "headers": dict(headers or {})})
            return _FakeResponse()

    orig_client = sim_routes.httpx.Client
    orig_getenv = sim_routes.os.getenv
    try:
        sim_routes.httpx.Client = _FakeClient  # type: ignore[assignment]
        sim_routes.os.getenv = lambda key, default=None: "test_key" if str(key) == "POLYGON_API_KEY" else orig_getenv(key, default)  # type: ignore[assignment]
        with sim_routes._AGENT_NEWS_CACHE_LOCK:
            sim_routes._AGENT_NEWS_CACHE.clear()

        out1 = sim_routes._agent_fetch_market_news(symbol="XAUUSD", limit=3, lookback_min=120)
        out2 = sim_routes._agent_fetch_market_news(symbol="XAUUSD", limit=3, lookback_min=120)

        assert out1.get("ok") is True
        assert out2.get("ok") is True
        assert len(calls) == 1
        req = calls[0]
        assert "apiKey" not in req["params"]
        auth = str(req["headers"].get("Authorization") or "")
        assert auth == "Bearer test_key"
    finally:
        sim_routes.httpx.Client = orig_client  # type: ignore[assignment]
        sim_routes.os.getenv = orig_getenv  # type: ignore[assignment]


def test_news_dispatch_uses_selected_provider():
    called = {"polygon": 0, "ibkr": 0}
    orig_polygon = sim_routes._agent_fetch_market_news_polygon
    orig_ibkr = sim_routes._agent_fetch_market_news_ibkr
    try:
        def _fake_polygon(*, symbol, limit=5, lookback_min=180):
            _ = (symbol, limit, lookback_min)
            called["polygon"] += 1
            return {"ok": True, "provider": "polygon", "items": []}

        def _fake_ibkr(*, symbol, limit=5, lookback_min=180, host="127.0.0.1", port=7497):
            _ = (symbol, limit, lookback_min, host, port)
            called["ibkr"] += 1
            return {"ok": True, "provider": "ibkr", "items": []}

        sim_routes._agent_fetch_market_news_polygon = _fake_polygon  # type: ignore[assignment]
        sim_routes._agent_fetch_market_news_ibkr = _fake_ibkr  # type: ignore[assignment]

        out_polygon = sim_routes._agent_fetch_market_news(symbol="XAUUSD", provider="polygon", include_summary=False)
        out_ibkr = sim_routes._agent_fetch_market_news(symbol="XAUUSD", provider="ibkr", include_summary=False)

        assert out_polygon.get("provider") == "polygon"
        assert out_ibkr.get("provider") == "ibkr"
        assert called["polygon"] == 1
        assert called["ibkr"] == 1
    finally:
        sim_routes._agent_fetch_market_news_polygon = orig_polygon  # type: ignore[assignment]
        sim_routes._agent_fetch_market_news_ibkr = orig_ibkr  # type: ignore[assignment]


def test_news_summary_cache_calls_llm_once_for_same_headlines():
    orig_polygon = sim_routes._agent_fetch_market_news_polygon
    orig_summarize = sim_routes._agent_llm_summarize_news
    calls = {"llm": 0}
    try:
        def _fake_polygon(*, symbol, limit=5, lookback_min=180):
            _ = (symbol, limit, lookback_min)
            return {
                "ok": True,
                "provider": "polygon",
                "symbol": "XAUUSD",
                "items": [
                    {
                        "title": "FOMC outlook update",
                        "published_utc": "2026-03-05T10:00:00Z",
                        "impact": "high",
                        "publisher": "wire",
                    }
                ],
                "error": None,
            }

        def _fake_sum(*, symbol, provider, items, model, timeout_sec=8):
            _ = (symbol, provider, items, model, timeout_sec)
            calls["llm"] += 1
            return {"ok": True, "summary": "High-impact macro risk.", "model": model}

        sim_routes._agent_fetch_market_news_polygon = _fake_polygon  # type: ignore[assignment]
        sim_routes._agent_llm_summarize_news = _fake_sum  # type: ignore[assignment]
        with sim_routes._AGENT_NEWS_SUMMARY_CACHE_LOCK:
            sim_routes._AGENT_NEWS_SUMMARY_CACHE.clear()

        out1 = sim_routes._agent_fetch_market_news(
            symbol="XAUUSD",
            provider="polygon",
            include_summary=True,
            summary_model="claude-haiku-4-5-20251001",
        )
        out2 = sim_routes._agent_fetch_market_news(
            symbol="XAUUSD",
            provider="polygon",
            include_summary=True,
            summary_model="claude-haiku-4-5-20251001",
        )

        assert calls["llm"] == 1
        assert out1.get("summary_cached") is False
        assert out2.get("summary_cached") is True
        assert str(out2.get("summary") or "") == "High-impact macro risk."
    finally:
        sim_routes._agent_fetch_market_news_polygon = orig_polygon  # type: ignore[assignment]
        sim_routes._agent_llm_summarize_news = orig_summarize  # type: ignore[assignment]


def test_ibkr_fetch_calls_start_loop_and_avoids_static_client_id():
    start_calls = {"n": 0}
    connected_client_ids = []

    class _FakeIB:
        def connect(self, host, port, clientId=0, timeout=10):
            _ = (host, port, timeout)
            connected_client_ids.append(int(clientId))

        def qualifyContracts(self, contract):
            return [contract]

        def reqNewsProviders(self):
            return [types.SimpleNamespace(code="BRFG")]

        def reqHistoricalNews(self, conid, provider_codes, start_str, end_str, limit):
            _ = (conid, provider_codes, start_str, end_str, limit)
            return [
                types.SimpleNamespace(
                    headline="Macro risk update",
                    time="20260305 10:00:00",
                    articleId="abc",
                    providerCode="BRFG",
                )
            ]

        def disconnect(self):
            return None

    class _FakeStock:
        def __init__(self, symbol, exchange, currency):
            _ = (exchange, currency)
            self.symbol = symbol
            self.conId = 12345

    fake_ib_async = types.SimpleNamespace(
        IB=_FakeIB,
        Stock=_FakeStock,
        util=types.SimpleNamespace(startLoop=lambda: start_calls.__setitem__("n", start_calls["n"] + 1)),
    )

    class _FakeResolver:
        @staticmethod
        def resolve_contract(ib, symbol):
            _ = (ib, symbol)
            raise RuntimeError("force_proxy_fallback")

    fake_resolver_mod = types.SimpleNamespace(IBKRContractResolver=_FakeResolver)
    orig_ib_async_mod = sys.modules.get("ib_async")
    orig_resolver_mod = sys.modules.get("dashboard.backend.core.ibkr_data_provider")
    try:
        sys.modules["ib_async"] = fake_ib_async  # type: ignore[assignment]
        sys.modules["dashboard.backend.core.ibkr_data_provider"] = fake_resolver_mod  # type: ignore[assignment]
        with sim_routes._AGENT_NEWS_CACHE_LOCK:
            sim_routes._AGENT_NEWS_CACHE.clear()

        out = sim_routes._agent_fetch_market_news_ibkr(
            symbol="US500",
            limit=3,
            lookback_min=120,
            host="127.0.0.1",
            port=7497,
        )
        assert out.get("ok") is True
        assert len(out.get("items") or []) == 1
        assert start_calls["n"] >= 1
        assert connected_client_ids
        assert connected_client_ids[0] != 97
    finally:
        if orig_ib_async_mod is None:
            sys.modules.pop("ib_async", None)
        else:
            sys.modules["ib_async"] = orig_ib_async_mod
        if orig_resolver_mod is None:
            sys.modules.pop("dashboard.backend.core.ibkr_data_provider", None)
        else:
            sys.modules["dashboard.backend.core.ibkr_data_provider"] = orig_resolver_mod
