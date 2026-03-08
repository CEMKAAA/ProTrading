import pandas as pd

from dashboard.backend.core.options_edge.csp_screener import CSPScreener, detect_regime
from dashboard.backend.core.options_edge.csp_models import CSPScreenConfig


def _row(**overrides):
    base = {
        "symbol": "AAPL",
        "sector": "Technology",
        "industry": "Electronic Computers",
        "revenue_growth_pct": 14.0,
        "eps_growth_5y_pct": 13.0,
        "eps_growth_fwd_pct": 8.0,
        "profit_margin_pct": 21.0,
        "total_assets": 300.0,
        "total_liabilities": 180.0,
        "free_cash_flow": 50.0,
        "iv_rank_252": 0.42,
        "avg_opt_volume_30d": 7_000_000.0,
        "pe_current": 24.0,
        "pe_5y_avg": 23.0,
        "pe_10y_avg": 21.0,
        "price_vs_sma200": 1.5,
    }
    base.update(overrides)
    return base


def test_detect_regime_by_vix_or_sma_touch():
    assert detect_regime(vix_value=35.0, sma200_distance_pct=10.0) == "aggressive"
    assert detect_regime(vix_value=15.0, sma200_distance_pct=1.0) == "aggressive"
    assert detect_regime(vix_value=15.0, sma200_distance_pct=5.0) == "normal"


def test_csp_screener_passes_valid_row():
    df = pd.DataFrame([_row()])
    screener = CSPScreener()
    out = screener.screen_dataframe(df, vix_value=16.0)
    assert out.total_symbols_screened == 1
    assert out.candidates_passed == 1
    assert out.candidates[0].symbol == "AAPL"
    assert out.candidates[0].regime == "aggressive"  # near SMA200 touch


def test_csp_screener_rejects_low_revenue_growth():
    df = pd.DataFrame([_row(revenue_growth_pct=5.0)])
    screener = CSPScreener()
    out = screener.screen_dataframe(df, vix_value=16.0)
    assert out.candidates_passed == 0
    assert out.rejected[0]["symbol"] == "AAPL"
    assert "revenue_growth_fail" in out.rejected[0]["reasons"]


def test_csp_screener_respects_industry_exclusion():
    cfg = CSPScreenConfig(excluded_industries=["drug"])
    df = pd.DataFrame([_row(industry="Drug Manufacturing")])
    screener = CSPScreener(config=cfg)
    out = screener.screen_dataframe(df, vix_value=16.0)
    assert out.candidates_passed == 0
    assert "industry_excluded" in out.rejected[0]["reasons"]

