from __future__ import annotations

import types

from dashboard.backend.services import live_service as ls


def _sym(name: str, *, visible: bool = True, description: str = ""):
    return types.SimpleNamespace(
        name=name,
        visible=visible,
        description=description,
        path="Forex",
        digits=2,
        point=0.01,
        trade_mode=4,
        spread=12,
    )


def test_resolve_symbol_prefers_visible_suffix_variant(monkeypatch):
    service = ls.LiveTradingService()
    service._mt5_initialized = True

    selected = []
    symbols = [
        _sym("XAUUSD.pro", visible=False, description="Gold Pro"),
        _sym("XAUUSDm", visible=True, description="Gold Micro"),
        _sym("EURUSD", visible=True),
    ]

    monkeypatch.setattr(ls.mt5, "symbols_get", lambda: symbols, raising=False)
    monkeypatch.setattr(ls.mt5, "symbol_select", lambda name, _on: selected.append(str(name)), raising=False)
    monkeypatch.setattr(ls.mt5, "terminal_info", lambda: types.SimpleNamespace(connected=True), raising=False)

    out = service.resolve_symbol_name("XAUUSD")
    assert out == "XAUUSDm"
    assert "XAUUSDm" in selected


def test_resolve_symbol_uses_short_ttl_cache(monkeypatch):
    service = ls.LiveTradingService()
    service._mt5_initialized = True
    service._resolved_symbol_cache_ttl_sec = 60.0

    calls = {"list": 0}

    def _fake_list_symbols(*args, **kwargs):
        calls["list"] += 1
        return [{"name": "XAUUSDm", "visible": True, "description": "Gold Micro"}]

    monkeypatch.setattr(service, "list_symbols", _fake_list_symbols)
    monkeypatch.setattr(ls.mt5, "symbol_select", lambda *_args, **_kwargs: True, raising=False)

    r1 = service.resolve_symbol_name("XAUUSD")
    r2 = service.resolve_symbol_name("XAUUSD")
    assert r1 == "XAUUSDm"
    assert r2 == "XAUUSDm"
    assert calls["list"] == 1, "second resolve should hit in-memory alias cache"


def test_get_recent_candles_preserves_symbol_case_when_resolution_disabled(monkeypatch):
    service = ls.LiveTradingService()
    service._mt5_initialized = True

    seen = {}

    monkeypatch.setattr(ls.mt5, "TIMEFRAME_M15", 15, raising=False)
    monkeypatch.setattr(ls.mt5, "terminal_info", lambda: types.SimpleNamespace(connected=True), raising=False)

    def _fake_copy_rates_from_pos(symbol, timeframe, start_pos, count):
        seen["symbol"] = symbol
        seen["timeframe"] = timeframe
        seen["count"] = count
        return [
            {
                "time": 1773234000,
                "open": 1.0,
                "high": 2.0,
                "low": 0.5,
                "close": 1.5,
                "tick_volume": 42,
            }
        ]

    monkeypatch.setattr(ls.mt5, "copy_rates_from_pos", _fake_copy_rates_from_pos, raising=False)

    bars = service.get_recent_candles(symbol="XAUUSDm", timeframe="M15", count=2, resolve_symbol=False)
    assert len(bars) == 1
    assert seen.get("symbol") == "XAUUSDm"
    assert bars[0]["symbol"] == "XAUUSDm"


def test_list_symbols_reinitializes_when_mt5_handle_is_stale(monkeypatch):
    service = ls.LiveTradingService()
    service._mt5_initialized = True

    calls = {"initialize": 0, "shutdown": 0, "symbols_get": 0, "terminal_info": 0}

    def _fake_terminal_info():
        calls["terminal_info"] += 1
        if calls["terminal_info"] == 1:
            return None
        return types.SimpleNamespace(connected=True)

    def _fake_initialize():
        calls["initialize"] += 1
        return True

    def _fake_shutdown():
        calls["shutdown"] += 1
        return True

    def _fake_symbols_get():
        calls["symbols_get"] += 1
        return [_sym("XAUUSDm", visible=True, description="Gold")]

    monkeypatch.setattr(ls.mt5, "terminal_info", _fake_terminal_info, raising=False)
    monkeypatch.setattr(ls.mt5, "initialize", _fake_initialize, raising=False)
    monkeypatch.setattr(ls.mt5, "shutdown", _fake_shutdown, raising=False)
    monkeypatch.setattr(ls.mt5, "symbols_get", _fake_symbols_get, raising=False)

    rows = service.list_symbols(limit=10, include_hidden=True)
    assert len(rows) == 1
    assert rows[0]["name"] == "XAUUSDm"
    assert calls["shutdown"] >= 1
    assert calls["initialize"] >= 1
    assert calls["symbols_get"] >= 1
