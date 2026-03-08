from datetime import date

from sqlalchemy import create_engine, inspect
from sqlalchemy.orm import sessionmaker

from dashboard.backend.core.options_edge.csp_models import (
    CSPCandidate,
    CSPTrade,
    RollEvent,
    candidate_to_dict,
    roll_event_to_dict,
)
from dashboard.backend.models.database import Base
from dashboard.backend.models.schemas import CSPBacktestRequest


def test_csp_domain_model_serialization():
    cand = CSPCandidate(
        symbol="AAPL",
        revenue_growth_pct=12.0,
        eps_growth_5y_pct=11.0,
        eps_growth_fwd_pct=6.0,
        profit_margin_pct=18.0,
        assets_to_liabilities=1.5,
        free_cash_flow=1_000_000.0,
        sector="Technology",
        industry="Electronic Computers",
        iv_rank=0.45,
        option_volume_30d=6_000_000.0,
        pe_current=28.0,
        pe_5y_avg=24.0,
        pe_10y_avg=22.0,
        price_vs_sma200=1.2,
        regime="normal",
    )
    row = candidate_to_dict(cand)
    assert row["symbol"] == "AAPL"
    assert row["regime"] == "normal"

    ev = RollEvent(
        roll_date=date(2026, 2, 20),
        roll_type="out",
        old_strike=180.0,
        old_expiry=date(2026, 3, 20),
        new_strike=180.0,
        new_expiry=date(2026, 4, 17),
        buyback_cost=0.8,
        new_premium=1.3,
        net_credit=0.5,
    )
    ev_row = roll_event_to_dict(ev)
    assert ev_row["net_credit"] == 0.5
    assert ev_row["roll_type"] == "out"

    trade = CSPTrade(
        symbol="AAPL",
        open_date=date(2026, 2, 20),
        expiry_date=date(2026, 3, 20),
        strike=180.0,
        premium_received=1.2,
        cash_secured=18_000.0,
        yield_pct=1.2 / 180.0,
        delta_at_open=-0.25,
        iv_at_open=0.35,
        regime="normal",
        pop_at_open=0.75,
        state="OPEN_CSP",
    )
    assert trade.rolls == []
    assert trade.shares_assigned == 0


def test_csp_tables_registered_in_metadata():
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    Base.metadata.create_all(bind=engine)
    inspector = inspect(engine)
    tables = set(inspector.get_table_names())

    assert "csp_screen_runs" in tables
    assert "csp_candidates" in tables
    assert "csp_trades" in tables
    assert "csp_backtest_runs" in tables

    SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)
    db = SessionLocal()
    db.close()


def test_csp_backtest_request_validators():
    req = CSPBacktestRequest(start_date=date(2025, 1, 1), end_date=date(2025, 12, 31))
    assert req.target_dte_max >= req.target_dte_min

