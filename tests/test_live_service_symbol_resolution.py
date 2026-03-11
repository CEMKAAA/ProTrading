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
