"""Core CSP domain models.

Internal dataclasses used by screener/engine before API-level schemas
are added to `dashboard/backend/models/schemas.py`.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from typing import Any, Dict, List, Optional


@dataclass
class RollEvent:
    roll_date: date
    roll_type: str  # out | up | down
    old_strike: float
    old_expiry: date
    new_strike: float
    new_expiry: date
    buyback_cost: float
    new_premium: float
    net_credit: float


@dataclass
class CSPCandidate:
    symbol: str
    revenue_growth_pct: float
    eps_growth_5y_pct: float
    eps_growth_fwd_pct: float
    profit_margin_pct: float
    assets_to_liabilities: float
    free_cash_flow: float
    sector: str
    industry: str
    iv_rank: float
    option_volume_30d: float
    pe_current: float
    pe_5y_avg: float
    pe_10y_avg: float
    price_vs_sma200: float
    regime: str  # normal | aggressive


@dataclass
class CSPTrade:
    symbol: str
    open_date: date
    expiry_date: date
    strike: float
    premium_received: float
    cash_secured: float
    yield_pct: float
    delta_at_open: float
    iv_at_open: float
    regime: str
    pop_at_open: float
    state: str  # OPEN_CSP | ROLLING | EXPIRED_OTM | ASSIGNED | CLOSED
    rolls: List[RollEvent] = field(default_factory=list)
    current_value: float = 0.0
    shares_assigned: int = 0
    assignment_cost: float = 0.0


@dataclass
class CSPScreenConfig:
    min_revenue_growth_pct: float = 5.0
    min_eps_growth_5y_pct: float = 5.0
    min_eps_growth_fwd_pct: float = 0.0
    min_profit_margin_pct: float = 10.0
    min_iv_rank: float = 0.30
    min_option_volume_30d: float = 5_000_000.0
    excluded_industries: List[str] = field(default_factory=list)


@dataclass
class CSPBacktestConfig:
    initial_capital: float = 100_000.0
    max_concurrent_csps: int = 5
    max_portfolio_allocation_pct: float = 20.0
    max_sector_concentration: int = 2
    max_single_stock_pct: float = 5.0
    target_dte_min: int = 30
    target_dte_max: int = 45
    normal_pop_min: float = 0.70
    normal_pop_max: float = 0.80
    normal_yield_min_pct: float = 1.5
    normal_yield_max_pct: float = 3.0
    hard_min_yield_pct: float = 1.0
    aggressive_yield_min_pct: float = 4.0
    aggressive_yield_max_pct: float = 6.0
    vix_aggressive_threshold: float = 30.0
    sma200_touch_pct: float = 2.0
    iv_premium_factor: float = 1.2
    iv_floor: float = 0.40
    risk_free_rate: float = 0.03


def roll_event_to_dict(ev: RollEvent) -> Dict[str, Any]:
    return {
        "roll_date": ev.roll_date.isoformat(),
        "roll_type": ev.roll_type,
        "old_strike": float(ev.old_strike),
        "old_expiry": ev.old_expiry.isoformat(),
        "new_strike": float(ev.new_strike),
        "new_expiry": ev.new_expiry.isoformat(),
        "buyback_cost": float(ev.buyback_cost),
        "new_premium": float(ev.new_premium),
        "net_credit": float(ev.net_credit),
    }


def candidate_to_dict(c: CSPCandidate) -> Dict[str, Any]:
    return {
        "symbol": c.symbol,
        "revenue_growth_pct": float(c.revenue_growth_pct),
        "eps_growth_5y_pct": float(c.eps_growth_5y_pct),
        "eps_growth_fwd_pct": float(c.eps_growth_fwd_pct),
        "profit_margin_pct": float(c.profit_margin_pct),
        "assets_to_liabilities": float(c.assets_to_liabilities),
        "free_cash_flow": float(c.free_cash_flow),
        "sector": c.sector,
        "industry": c.industry,
        "iv_rank": float(c.iv_rank),
        "option_volume_30d": float(c.option_volume_30d),
        "pe_current": float(c.pe_current),
        "pe_5y_avg": float(c.pe_5y_avg),
        "pe_10y_avg": float(c.pe_10y_avg),
        "price_vs_sma200": float(c.price_vs_sma200),
        "regime": c.regime,
    }
