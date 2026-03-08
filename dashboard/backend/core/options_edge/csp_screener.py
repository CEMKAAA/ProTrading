"""CSP fundamental + liquidity screening module."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple

import numpy as np
import pandas as pd

from .csp_models import CSPCandidate, CSPScreenConfig


def _safe_float(v: Any, default: float = 0.0) -> float:
    try:
        if v is None:
            return float(default)
        f = float(v)
        if np.isnan(f) or np.isinf(f):
            return float(default)
        return float(f)
    except Exception:
        return float(default)


def detect_regime(
    *,
    vix_value: Optional[float],
    sma200_distance_pct: Optional[float],
    vix_aggressive_threshold: float = 30.0,
    sma200_touch_pct: float = 2.0,
) -> str:
    """Return market mode for CSP strike aggressiveness."""
    vix = _safe_float(vix_value, np.nan)
    sma_dist = abs(_safe_float(sma200_distance_pct, np.nan))
    if np.isfinite(vix) and vix >= float(vix_aggressive_threshold):
        return "aggressive"
    if np.isfinite(sma_dist) and sma_dist <= float(sma200_touch_pct):
        return "aggressive"
    return "normal"


@dataclass
class CSPScreenResult:
    total_symbols_screened: int
    candidates_passed: int
    candidates: List[CSPCandidate] = field(default_factory=list)
    rejected: List[Dict[str, Any]] = field(default_factory=list)
    summary: Dict[str, Any] = field(default_factory=dict)


class CSPScreener:
    """Apply CSP hard gates over a pre-built symbol dataframe."""

    def __init__(self, config: Optional[CSPScreenConfig] = None):
        self.config = config or CSPScreenConfig()

    def _excluded_industry(self, industry: str) -> bool:
        ind = str(industry or "").lower().strip()
        for rule in (self.config.excluded_industries or []):
            rule_s = str(rule or "").lower().strip()
            if rule_s and rule_s in ind:
                return True
        return False

    def _evaluate_row(
        self,
        row: pd.Series,
        *,
        vix_value: Optional[float],
        vix_aggressive_threshold: float,
        sma200_touch_pct: float,
    ) -> Tuple[Optional[CSPCandidate], List[str]]:
        reasons: List[str] = []
        symbol = str(row.get("symbol") or "").upper().strip()
        if not symbol:
            reasons.append("missing_symbol")
            return None, reasons

        revenue_growth = _safe_float(row.get("revenue_growth_pct"), np.nan)
        eps_growth_5y = _safe_float(row.get("eps_growth_5y_pct"), np.nan)
        eps_growth_fwd = _safe_float(row.get("eps_growth_fwd_pct"), np.nan)
        profit_margin = _safe_float(row.get("profit_margin_pct"), np.nan)
        total_assets = _safe_float(row.get("total_assets"), np.nan)
        total_liabilities = _safe_float(row.get("total_liabilities"), np.nan)
        free_cash_flow = _safe_float(row.get("free_cash_flow"), np.nan)
        industry = str(row.get("industry") or "")
        sector = str(row.get("sector") or "UNKNOWN")
        iv_rank = _safe_float(row.get("iv_rank"), _safe_float(row.get("iv_rank_252"), np.nan))
        option_volume = _safe_float(row.get("option_volume_30d"), _safe_float(row.get("avg_opt_volume_30d"), np.nan))
        pe_current = _safe_float(row.get("pe_current"), np.nan)
        pe_5y = _safe_float(row.get("pe_5y_avg"), np.nan)
        pe_10y = _safe_float(row.get("pe_10y_avg"), np.nan)
        price_vs_sma200 = _safe_float(row.get("price_vs_sma200"), np.nan)

        if not np.isfinite(revenue_growth) or revenue_growth <= self.config.min_revenue_growth_pct:
            reasons.append("revenue_growth_fail")
        if not np.isfinite(eps_growth_5y) or eps_growth_5y <= self.config.min_eps_growth_5y_pct:
            reasons.append("eps_growth_5y_fail")
        if not np.isfinite(eps_growth_fwd) or eps_growth_fwd <= self.config.min_eps_growth_fwd_pct:
            reasons.append("eps_growth_fwd_fail")
        if not np.isfinite(profit_margin) or profit_margin <= self.config.min_profit_margin_pct:
            reasons.append("profit_margin_fail")
        if not np.isfinite(total_assets) or not np.isfinite(total_liabilities) or total_assets <= total_liabilities:
            reasons.append("balance_sheet_fail")
        if not np.isfinite(free_cash_flow) or free_cash_flow <= 0.0:
            reasons.append("free_cash_flow_fail")
        if self._excluded_industry(industry):
            reasons.append("industry_excluded")
        if not np.isfinite(iv_rank) or iv_rank < self.config.min_iv_rank:
            reasons.append("iv_rank_fail")
        if not np.isfinite(option_volume) or option_volume < self.config.min_option_volume_30d:
            reasons.append("option_volume_fail")
        # Soft valuation guard elevated to hard gate for now.
        if np.isfinite(pe_current):
            pe_ref = np.nan
            if np.isfinite(pe_5y) and pe_5y > 0:
                pe_ref = pe_5y
            elif np.isfinite(pe_10y) and pe_10y > 0:
                pe_ref = pe_10y
            if np.isfinite(pe_ref) and pe_current > 1.35 * pe_ref:
                reasons.append("pe_overvalued_fail")

        if reasons:
            return None, reasons

        regime = detect_regime(
            vix_value=vix_value,
            sma200_distance_pct=price_vs_sma200,
            vix_aggressive_threshold=vix_aggressive_threshold,
            sma200_touch_pct=sma200_touch_pct,
        )
        candidate = CSPCandidate(
            symbol=symbol,
            revenue_growth_pct=float(revenue_growth),
            eps_growth_5y_pct=float(eps_growth_5y),
            eps_growth_fwd_pct=float(eps_growth_fwd),
            profit_margin_pct=float(profit_margin),
            assets_to_liabilities=float(total_assets / max(total_liabilities, 1e-9)),
            free_cash_flow=float(free_cash_flow),
            sector=sector,
            industry=industry,
            iv_rank=float(iv_rank),
            option_volume_30d=float(option_volume),
            pe_current=float(pe_current) if np.isfinite(pe_current) else 0.0,
            pe_5y_avg=float(pe_5y) if np.isfinite(pe_5y) else 0.0,
            pe_10y_avg=float(pe_10y) if np.isfinite(pe_10y) else 0.0,
            price_vs_sma200=float(price_vs_sma200) if np.isfinite(price_vs_sma200) else 0.0,
            regime=regime,
        )
        return candidate, []

    def screen_dataframe(
        self,
        df: pd.DataFrame,
        *,
        vix_value: Optional[float] = None,
        vix_aggressive_threshold: float = 30.0,
        sma200_touch_pct: float = 2.0,
    ) -> CSPScreenResult:
        if df is None or df.empty:
            return CSPScreenResult(
                total_symbols_screened=0,
                candidates_passed=0,
                candidates=[],
                rejected=[],
                summary={"reason": "empty_universe"},
            )

        candidates: List[CSPCandidate] = []
        rejected: List[Dict[str, Any]] = []

        for _, row in df.iterrows():
            cand, reasons = self._evaluate_row(
                row,
                vix_value=vix_value,
                vix_aggressive_threshold=vix_aggressive_threshold,
                sma200_touch_pct=sma200_touch_pct,
            )
            if cand is not None:
                candidates.append(cand)
            else:
                rejected.append(
                    {
                        "symbol": str(row.get("symbol") or "").upper().strip(),
                        "sector": str(row.get("sector") or "UNKNOWN"),
                        "industry": str(row.get("industry") or ""),
                        "iv_rank": _safe_float(row.get("iv_rank"), _safe_float(row.get("iv_rank_252"), np.nan)),
                        "option_volume_30d": _safe_float(row.get("option_volume_30d"), _safe_float(row.get("avg_opt_volume_30d"), np.nan)),
                        "reasons": reasons,
                    }
                )

        reg_counts: Dict[str, int] = {"normal": 0, "aggressive": 0}
        for c in candidates:
            reg_counts[c.regime] = reg_counts.get(c.regime, 0) + 1

        return CSPScreenResult(
            total_symbols_screened=int(len(df)),
            candidates_passed=int(len(candidates)),
            candidates=candidates,
            rejected=rejected,
            summary={
                "rejected_count": int(len(rejected)),
                "regime_counts": reg_counts,
                "vix_value": None if vix_value is None else float(vix_value),
            },
        )
