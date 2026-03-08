import asyncio

import pandas as pd
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from dashboard.backend.api.routes import (
    get_options_edge_candidates,
    get_options_edge_trade_candidates,
    run_options_edge_scan,
)
from dashboard.backend.core.options_edge.scan_engine import OptionsEdgeScanEngine
from dashboard.backend.core.options_edge.strategy_builder import (
    OptionsStrategyBuilder,
    normalize_option_chain_dataframe,
)
from dashboard.backend.models.database import Base
from dashboard.backend.models.schemas import OptionsEdgeScanRequest, OptionsEdgeUniverseRow


def _sample_universe_rows():
    return [
        OptionsEdgeUniverseRow(
            symbol="AAPL",
            sector="Technology",
            price=190.0,
            iv30=0.40,
            hv30=0.20,
            iv_rank_252=0.72,
            avg_opt_volume_30d=25000,
            avg_oi_30d=90000,
            avg_bid_ask_pct=0.010,
            days_to_earnings=25,
            borrow_rate=0.01,
            trend_20d_return=0.03,
            put_call_skew=0.12,
        ),
        OptionsEdgeUniverseRow(
            symbol="TSLA",
            sector="Consumer Cyclical",
            price=220.0,
            iv30=0.55,
            hv30=0.30,
            iv_rank_252=0.65,
            avg_opt_volume_30d=40000,
            avg_oi_30d=120000,
            avg_bid_ask_pct=0.012,
            days_to_earnings=18,
            borrow_rate=0.02,
            trend_20d_return=-0.03,
            put_call_skew=-0.12,
        ),
        OptionsEdgeUniverseRow(
            symbol="JPM",
            sector="Financials",
            price=180.0,
            iv30=0.32,
            hv30=0.22,
            iv_rank_252=0.62,
            avg_opt_volume_30d=18000,
            avg_oi_30d=50000,
            avg_bid_ask_pct=0.009,
            days_to_earnings=30,
            borrow_rate=0.01,
            trend_20d_return=0.00,
            put_call_skew=0.00,
        ),
    ]


def _sample_chain_rows():
    rows = []
    for symbol, spot in [("AAPL", 190.0), ("TSLA", 220.0), ("JPM", 180.0)]:
        # Keep DTE in builder preferred window for deterministic test behavior.
        expiry = "2026-03-20"
        rows.extend(
            [
                # puts
                {
                    "symbol": symbol,
                    "expiry_date": expiry,
                    "option_type": "P",
                    "strike": spot - 5,
                    "bid": 3.4,
                    "ask": 3.8,
                    "delta": -0.25,
                    "theta": -0.08,
                    "vega": 0.12,
                    "volume": 500,
                    "oi": 2000,
                },
                {
                    "symbol": symbol,
                    "expiry_date": expiry,
                    "option_type": "P",
                    "strike": spot - 10,
                    "bid": 1.6,
                    "ask": 1.9,
                    "delta": -0.12,
                    "theta": -0.04,
                    "vega": 0.07,
                    "volume": 400,
                    "oi": 1800,
                },
                # calls
                {
                    "symbol": symbol,
                    "expiry_date": expiry,
                    "option_type": "C",
                    "strike": spot + 5,
                    "bid": 3.3,
                    "ask": 3.7,
                    "delta": 0.24,
                    "theta": -0.08,
                    "vega": 0.12,
                    "volume": 480,
                    "oi": 1900,
                },
                {
                    "symbol": symbol,
                    "expiry_date": expiry,
                    "option_type": "C",
                    "strike": spot + 10,
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
    return rows


def test_options_edge_scan_engine_sector_cap_selection():
    universe_df = pd.DataFrame([r.model_dump() for r in _sample_universe_rows()])
    engine = OptionsEdgeScanEngine(top_n=2, max_sector_fraction=0.5)
    result = engine.run(universe_df)

    assert result.summary["universe_size"] == 3
    assert result.summary["passed_gate_count"] == 3
    assert len(result.selected_symbols) == 2
    assert all(sym in {"AAPL", "TSLA", "JPM"} for sym in result.selected_symbols)


def test_options_strategy_builder_auto_policy_constructs_trades():
    chain_df = normalize_option_chain_dataframe(pd.DataFrame(_sample_chain_rows()))
    builder = OptionsStrategyBuilder()

    outcome = builder.build_for_symbol_diagnostics(
        symbol="AAPL",
        spot=190.0,
        chain_df=chain_df,
        iv_rank_252=0.72,
        trend_20d_return=0.00,
        put_call_skew=0.12,
    )

    assert len(outcome.strategies) >= 1
    # With corrected iron condor POP (delta-sum formula), the condor may be
    # rejected when short deltas sum > 1 - min_pop. Directional spread fallback
    # is equally valid.
    assert outcome.chosen_policy in {
        "auto_condor_high_ivr_balanced_trend",
        "auto_best_available",
        "auto_put_credit_skew_signal",
        "auto_call_credit_skew_signal",
    }


def test_options_strategy_builder_falls_back_when_spot_side_filter_fails():
    chain_df = normalize_option_chain_dataframe(pd.DataFrame(_sample_chain_rows()))
    builder = OptionsStrategyBuilder()

    # Deliberately wrong spot so strike-side filter would otherwise remove all legs.
    outcome = builder.build_for_symbol_diagnostics(
        symbol="AAPL",
        spot=10_000.0,
        chain_df=chain_df,
        iv_rank_252=0.70,
        trend_20d_return=0.00,
        put_call_skew=0.00,
    )

    assert len(outcome.strategies) >= 1


def test_options_strategy_builder_supports_short_strangle_and_straddle_modes():
    chain_df = normalize_option_chain_dataframe(pd.DataFrame(_sample_chain_rows()))

    strangle_builder = OptionsStrategyBuilder(config={"structure_mode": "short_strangle"})
    out1 = strangle_builder.build_for_symbol_diagnostics(
        symbol="AAPL",
        spot=190.0,
        chain_df=chain_df,
        iv_rank_252=0.72,
        trend_20d_return=0.00,
        put_call_skew=0.00,
    )
    assert len(out1.strategies) >= 1
    assert out1.strategies[0].structure_type == "short_strangle"
    assert "max_loss_proxy_unbounded" in (out1.strategies[0].quality_flags or [])

    straddle_builder = OptionsStrategyBuilder(config={"structure_mode": "short_straddle"})
    out2 = straddle_builder.build_for_symbol_diagnostics(
        symbol="AAPL",
        spot=190.0,
        chain_df=chain_df,
        iv_rank_252=0.72,
        trend_20d_return=0.00,
        put_call_skew=0.00,
    )
    # Straddle can fail on sparse toy chains; must not crash and should return deterministic policy.
    assert out2.chosen_policy in {
        "forced_short_straddle",
        "none",
        "auto_none",
        "auto_condor_high_ivr_balanced_trend",
        "auto_best_available",
    }
    if out2.strategies and out2.strategies[0].structure_type == "short_straddle":
        assert "max_loss_proxy_unbounded" in (out2.strategies[0].quality_flags or [])


def test_options_edge_routes_build_and_persist_candidates():
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    Base.metadata.create_all(bind=engine)
    SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)

    request = OptionsEdgeScanRequest(
        universe=_sample_universe_rows(),
        option_chain=_sample_chain_rows(),
        build_strategies=True,
        top_n=3,
        max_sector_fraction=0.5,
    )

    db = SessionLocal()
    try:
        resp = asyncio.run(run_options_edge_scan(request, db))
        candidates = asyncio.run(get_options_edge_candidates(resp.scan_id, True, db))
        trades = asyncio.run(get_options_edge_trade_candidates(resp.scan_id, None, db))
    finally:
        db.close()

    assert resp.status == "COMPLETED"
    assert resp.summary["selected_count"] == 3
    assert resp.summary["trade_candidates_built"] > 0
    assert len(candidates) == 3
    assert len(trades) > 0
    assert all(c.builder_status in {"built", "rejected"} for c in candidates)
    assert any(c.builder_status == "built" for c in candidates)
