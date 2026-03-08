import asyncio

import pandas as pd
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from dashboard.backend.api import routes as api_routes
from dashboard.backend.api.routes import (
    get_options_edge_scan_report,
    get_options_edge_polygon_status,
    probe_options_edge_polygon_entitlements,
    run_options_edge_scan_live,
)
from dashboard.backend.core.options_edge.connectors import LiveOptionsDataset
from dashboard.backend.models.database import Base
from dashboard.backend.models.schemas import OptionsEdgeLiveScanRequest


def test_polygon_status_endpoint_masked(monkeypatch):
    class _FakeConnector:
        def __init__(self, *args, **kwargs):
            pass

        def status(self):
            return {
                "provider": "polygon",
                "configured": True,
                "api_key_masked": "abcd...1234",
                "base_url": "https://api.polygon.io",
                "warnings": [],
            }

    monkeypatch.setattr(api_routes, "PolygonOptionsConnector", _FakeConnector)
    resp = asyncio.run(get_options_edge_polygon_status())
    assert resp.provider == "polygon"
    assert resp.configured is True
    assert resp.api_key_masked == "abcd...1234"


def test_polygon_probe_endpoint(monkeypatch):
    class _FakeConnector:
        def __init__(self, *args, **kwargs):
            pass

        def probe_entitlements(self, symbol="AAPL"):
            return {
                "provider": "polygon",
                "symbol": symbol,
                "configured": True,
                "api_key_masked": "abcd...1234",
                "results": [
                    {
                        "name": "stock_snapshot",
                        "path": f"/v2/snapshot/locale/us/markets/stocks/tickers/{symbol}",
                        "ok": True,
                        "status_code": 200,
                        "access": "ok",
                        "message": "OK",
                    },
                    {
                        "name": "options_chain_snapshot",
                        "path": f"/v3/snapshot/options/{symbol}",
                        "ok": False,
                        "status_code": 403,
                        "access": "not_entitled",
                        "message": "NOT_AUTHORIZED",
                    },
                ],
            }

    monkeypatch.setattr(api_routes, "PolygonOptionsConnector", _FakeConnector)
    resp = asyncio.run(probe_options_edge_polygon_entitlements(symbol="AAPL"))
    assert resp.provider == "polygon"
    assert resp.symbol == "AAPL"
    assert len(resp.results) == 2
    assert resp.results[0].name == "stock_snapshot"
    assert resp.results[1].access == "not_entitled"


def test_run_live_scan_uses_connector_and_persists(monkeypatch):
    class _FakeConnector:
        def __init__(self, *args, **kwargs):
            pass

        def status(self):
            return {
                "provider": "polygon",
                "configured": True,
                "api_key_masked": "abcd...1234",
                "base_url": "https://api.polygon.io",
                "warnings": [],
            }

        def get_sp500_symbols(self, limit=475):
            return ["AAPL", "MSFT"][:limit]

        def build_live_dataset(
            self,
            symbols,
            min_dte,
            max_dte,
            lookback_days,
            default_days_to_earnings,
            include_news=False,
            include_analyst=False,
            news_limit=3,
        ):
            universe = pd.DataFrame(
                [
                    {
                        "symbol": "AAPL",
                        "sector": "Technology",
                        "price": 190.0,
                        "iv30": 0.45,
                        "hv30": 0.22,
                        "iv_rank_252": 0.70,
                        "avg_opt_volume_30d": 30000.0,
                        "avg_oi_30d": 100000.0,
                        "avg_bid_ask_pct": 0.01,
                        "days_to_earnings": 20.0,
                        "borrow_rate": 0.01,
                        "trend_20d_return": 0.01,
                        "put_call_skew": 0.05,
                    }
                ]
            )
            chain = pd.DataFrame(
                [
                    {
                        "symbol": "AAPL",
                        "expiry_date": "2026-03-20",
                        "option_type": "P",
                        "strike": 185.0,
                        "bid": 3.4,
                        "ask": 3.8,
                        "delta": -0.25,
                        "theta": -0.08,
                        "vega": 0.12,
                        "volume": 500,
                        "oi": 2000,
                    },
                    {
                        "symbol": "AAPL",
                        "expiry_date": "2026-03-20",
                        "option_type": "P",
                        "strike": 180.0,
                        "bid": 1.6,
                        "ask": 1.9,
                        "delta": -0.12,
                        "theta": -0.04,
                        "vega": 0.07,
                        "volume": 400,
                        "oi": 1800,
                    },
                    {
                        "symbol": "AAPL",
                        "expiry_date": "2026-03-20",
                        "option_type": "C",
                        "strike": 195.0,
                        "bid": 3.3,
                        "ask": 3.7,
                        "delta": 0.24,
                        "theta": -0.08,
                        "vega": 0.12,
                        "volume": 480,
                        "oi": 1900,
                    },
                    {
                        "symbol": "AAPL",
                        "expiry_date": "2026-03-20",
                        "option_type": "C",
                        "strike": 200.0,
                        "bid": 1.5,
                        "ask": 1.8,
                        "delta": 0.12,
                        "theta": -0.04,
                        "vega": 0.07,
                        "volume": 420,
                        "oi": 1700,
                    },
                ]
            )
            return LiveOptionsDataset(
                universe_df=universe,
                chain_df=chain,
                metadata={
                    "provider": "polygon",
                    "requested_symbols": symbols,
                    "failed_symbols": {},
                    "symbol_insights": {"AAPL": {"news": [{"title": "Test headline"}]}},
                },
            )

    monkeypatch.setattr(api_routes, "PolygonOptionsConnector", _FakeConnector)

    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    Base.metadata.create_all(bind=engine)
    SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)
    db = SessionLocal()
    try:
        req = OptionsEdgeLiveScanRequest(
            provider="polygon",
            symbols=["AAPL"],
            build_strategies=True,
            top_n=1,
            max_sector_fraction=1.0,
        )
        resp = asyncio.run(run_options_edge_scan_live(req, db))
        report = asyncio.run(get_options_edge_scan_report(resp.scan_id, None, db))
    finally:
        db.close()

    assert resp.status == "COMPLETED"
    assert resp.summary.get("live_provider") == "polygon"
    assert resp.summary.get("trade_candidates_built", 0) >= 1
    assert resp.selected_symbols == ["AAPL"]
    assert "market_summary" in report.model_dump()


def test_run_live_scan_with_sp500_autoload(monkeypatch):
    class _FakeConnector:
        def __init__(self, *args, **kwargs):
            pass

        def status(self):
            return {"provider": "polygon", "configured": True, "api_key_masked": "abcd...1234", "base_url": "https://api.polygon.io", "warnings": []}

        def get_sp500_symbols(self, limit=475):
            return ["AAPL", "MSFT", "NVDA"][:limit]

        def build_live_dataset(
            self,
            symbols,
            min_dte,
            max_dte,
            lookback_days,
            default_days_to_earnings,
            include_news=False,
            include_analyst=False,
            news_limit=3,
        ):
            universe = pd.DataFrame(
                [
                    {
                        "symbol": s,
                        "sector": "Technology",
                        "price": 100.0,
                        "iv30": 0.40,
                        "hv30": 0.20,
                        "iv_rank_252": 0.70,
                        "avg_opt_volume_30d": 10000.0,
                        "avg_oi_30d": 30000.0,
                        "avg_bid_ask_pct": 0.01,
                        "days_to_earnings": 20.0,
                        "borrow_rate": 0.01,
                    }
                    for s in symbols
                ]
            )
            chain = pd.DataFrame(
                [
                    {
                        "symbol": symbols[0],
                        "expiry_date": "2026-03-20",
                        "option_type": "P",
                        "strike": 95.0,
                        "bid": 3.0,
                        "ask": 3.4,
                        "delta": -0.22,
                        "theta": -0.08,
                        "vega": 0.12,
                        "volume": 500,
                        "oi": 2000,
                    },
                    {
                        "symbol": symbols[0],
                        "expiry_date": "2026-03-20",
                        "option_type": "P",
                        "strike": 90.0,
                        "bid": 1.4,
                        "ask": 1.8,
                        "delta": -0.12,
                        "theta": -0.04,
                        "vega": 0.07,
                        "volume": 300,
                        "oi": 1500,
                    },
                    {
                        "symbol": symbols[0],
                        "expiry_date": "2026-03-20",
                        "option_type": "C",
                        "strike": 105.0,
                        "bid": 2.8,
                        "ask": 3.2,
                        "delta": 0.22,
                        "theta": -0.08,
                        "vega": 0.12,
                        "volume": 500,
                        "oi": 2000,
                    },
                    {
                        "symbol": symbols[0],
                        "expiry_date": "2026-03-20",
                        "option_type": "C",
                        "strike": 110.0,
                        "bid": 1.2,
                        "ask": 1.6,
                        "delta": 0.12,
                        "theta": -0.04,
                        "vega": 0.07,
                        "volume": 300,
                        "oi": 1500,
                    },
                ]
            )
            return LiveOptionsDataset(universe_df=universe, chain_df=chain, metadata={"provider": "polygon", "requested_symbols": symbols})

    monkeypatch.setattr(api_routes, "PolygonOptionsConnector", _FakeConnector)
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    Base.metadata.create_all(bind=engine)
    SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)
    db = SessionLocal()
    try:
        req = OptionsEdgeLiveScanRequest(
            provider="polygon",
            symbols=[],
            use_sp500=True,
            sp500_limit=2,
            build_strategies=True,
            top_n=1,
            max_sector_fraction=1.0,
        )
        resp = asyncio.run(run_options_edge_scan_live(req, db))
    finally:
        db.close()

    assert resp.status == "COMPLETED"
    assert resp.summary.get("requested_symbol_count") == 2
