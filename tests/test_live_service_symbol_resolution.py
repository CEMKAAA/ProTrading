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
