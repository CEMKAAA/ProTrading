import asyncio
from datetime import date

import pandas as pd
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from dashboard.backend.api import routes as api_routes
from dashboard.backend.core.options_edge.connectors import LiveOptionsDataset
from dashboard.backend.models.database import Base, CSPTradeModel
from dashboard.backend.models.schemas import CSPScreenRequest, CSPBacktestRequest


def test_csp_screen_and_backtest_routes_with_mock_connector(monkeypatch):
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
            news_limit=0,
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
                        "avg_opt_volume_30d": 8_000_000.0,
                        "avg_oi_30d": 100_000.0,
                        "avg_bid_ask_pct": 0.01,
                        "days_to_earnings": 20.0,
                        "borrow_rate": 0.01,
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
                    }
                ]
            )
            return LiveOptionsDataset(
                universe_df=universe,
                chain_df=chain,
                metadata={"provider": "polygon", "requested_symbols": symbols, "failed_symbols": {}},
            )

        def get_daily_bars(self, symbol, start_date, end_date):
            idx = pd.date_range("2025-01-01", periods=120, freq="D")
            return pd.DataFrame(
                {
                    "date": idx.date,
                    "open": 100.0,
                    "high": 101.0,
                    "low": 99.0,
                    "close": pd.Series(range(120)).astype(float) * 0.1 + 100.0,
                    "volume": 1_000_000.0,
                }
            )

    monkeypatch.setattr(api_routes, "PolygonOptionsConnector", _FakeConnector)

    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    Base.metadata.create_all(bind=engine)
    SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)
    db = SessionLocal()
    try:
        screen_req = CSPScreenRequest(
            provider="polygon",
            symbols=["AAPL"],
            use_sp500=False,
            fundamentals_overrides={
                "AAPL": {
                    "industry": "Electronic Computers",
                    "revenue_growth_pct": 12.0,
                    "eps_growth_5y_pct": 11.0,
                    "eps_growth_fwd_pct": 6.0,
                    "profit_margin_pct": 20.0,
                    "total_assets": 300.0,
                    "total_liabilities": 180.0,
                    "free_cash_flow": 50.0,
                    "pe_current": 25.0,
                    "pe_5y_avg": 23.0,
                    "pe_10y_avg": 22.0,
                    "price_vs_sma200": 1.5,
                }
            },
        )
        screen_resp = asyncio.run(api_routes.run_csp_screen(screen_req, db))
        assert screen_resp.candidates_passed == 1
        assert len(screen_resp.candidates) == 1

        list_resp = asyncio.run(api_routes.list_csp_screens(20, db))
        assert len(list_resp) == 1
        detail_resp = asyncio.run(api_routes.get_csp_screen(screen_resp.id, db))
        assert detail_resp.id == screen_resp.id

        bt_req = CSPBacktestRequest(
            symbol="AAPL",
            start_date=date(2025, 1, 1),
            end_date=date(2025, 5, 1),
            initial_capital=100000.0,
        )
        bt_resp = asyncio.run(api_routes.run_csp_backtest(bt_req, db))
        assert bt_resp.status == "COMPLETED"
        assert bt_resp.results.get("total_events", 0) >= 1
        assert db.query(CSPTradeModel).filter(CSPTradeModel.backtest_run_id == bt_resp.id).count() >= 1

        bt_detail = asyncio.run(api_routes.get_csp_backtest(bt_resp.id, db))
        assert bt_detail.id == bt_resp.id
        bt_list = asyncio.run(api_routes.list_csp_backtests(20, db))
        assert len(bt_list) == 1
    finally:
        db.close()
