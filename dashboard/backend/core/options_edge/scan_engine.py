"""
Deterministic scanner for options-volatility edge candidates.

Phase 1 scope:
- hard gates
- score computation
- sector-balanced top-N selection
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, List, Tuple

import numpy as np
import pandas as pd


DEFAULT_GATE_CONFIG: Dict[str, float] = {
    "min_iv_rank": 0.40,
    "min_iv_hv_spread": 0.03,
    "min_option_volume_30d": 1000.0,
    "min_option_oi_30d": 2000.0,
    "max_bid_ask_pct": 0.015,
    "min_days_to_earnings": 10.0,
    "max_borrow_rate": 0.08,
}

DEFAULT_SCORE_WEIGHTS: Dict[str, float] = {
    "vol_edge": 0.40,
    "liquidity": 0.30,
    "event_timing": 0.15,
    "risk": 0.15,
}

REQUIRED_COLUMNS: List[str] = [
    "symbol",
    "sector",
    "price",
    "iv30",
    "hv30",
    "iv_rank_252",
    "avg_opt_volume_30d",
    "avg_oi_30d",
    "avg_bid_ask_pct",
    "days_to_earnings",
    "borrow_rate",
]

OPTIONAL_COLUMNS: List[str] = [
    "trend_20d_return",
    "put_call_skew",
]


def _clamp(v: float, lo: float, hi: float) -> float:
    return float(max(lo, min(hi, v)))


def _safe_float(v: Any, default: float = 0.0) -> float:
    try:
        if v is None:
            return float(default)
        f = float(v)
        if np.isnan(f) or np.isinf(f):
            return float(default)
        return f
    except Exception:
        return float(default)


def normalize_universe_dataframe(df: pd.DataFrame) -> pd.DataFrame:
    """
    Normalize incoming universe rows to deterministic schema.

    Accepts common aliases and coerces numerics.
    """
    if df is None or df.empty:
        return pd.DataFrame(columns=REQUIRED_COLUMNS + ["earnings_date"])

    out = df.copy()
    out.columns = [str(c).strip().lower() for c in out.columns]

    aliases = {
        "ticker": "symbol",
        "sec": "sector",
        "close": "price",
        "last": "price",
        "iv": "iv30",
        "hv": "hv30",
        "ivr": "iv_rank_252",
        "iv_rank": "iv_rank_252",
        "avg_option_volume_30d": "avg_opt_volume_30d",
        "option_volume_30d": "avg_opt_volume_30d",
        "option_oi_30d": "avg_oi_30d",
        "avg_option_oi_30d": "avg_oi_30d",
        "bid_ask_pct": "avg_bid_ask_pct",
        "spread_pct": "avg_bid_ask_pct",
        "dte_earnings": "days_to_earnings",
        "days_until_earnings": "days_to_earnings",
    }
    for src, dst in aliases.items():
        if src in out.columns and dst not in out.columns:
            out[dst] = out[src]

    if "symbol" in out.columns:
        out["symbol"] = out["symbol"].astype(str).str.upper().str.strip()
    else:
        out["symbol"] = ""
    out["sector"] = out.get("sector", "UNKNOWN").fillna("UNKNOWN").astype(str)

    numeric_cols = [
        "price",
        "iv30",
        "hv30",
        "iv_rank_252",
        "avg_opt_volume_30d",
        "avg_oi_30d",
        "avg_bid_ask_pct",
        "days_to_earnings",
        "borrow_rate",
        "trend_20d_return",
        "put_call_skew",
    ]
    for c in numeric_cols:
        if c not in out.columns:
            out[c] = np.nan
        out[c] = pd.to_numeric(out[c], errors="coerce")

    if "earnings_date" not in out.columns:
        out["earnings_date"] = None

    out = out.drop_duplicates(subset=["symbol"], keep="last")
    out = out[out["symbol"].str.len() > 0]

    for c in OPTIONAL_COLUMNS:
        if c not in out.columns:
            out[c] = np.nan

    base_cols = [
        "symbol", "sector", "price", "iv30", "hv30", "iv_rank_252",
        "avg_opt_volume_30d", "avg_oi_30d", "avg_bid_ask_pct",
        "earnings_date", "days_to_earnings", "borrow_rate",
        "trend_20d_return", "put_call_skew",
    ]
    # Preserve any extra provider-specific columns for downstream modules
    # (e.g., CSP liquidity/fundamental enrichments) while keeping deterministic
    # base schema first.
    extra_cols = [c for c in out.columns if c not in base_cols]
    return out[base_cols + extra_cols]


@dataclass
class ScanResult:
    summary: Dict[str, Any]
    snapshots: List[Dict[str, Any]]
    scores: List[Dict[str, Any]]
    selected_symbols: List[str]


class OptionsEdgeScanEngine:
    """Deterministic gate + score + selection pipeline."""

    def __init__(
        self,
        gate_config: Dict[str, float] | None = None,
        score_weights: Dict[str, float] | None = None,
        top_n: int = 8,
        max_sector_fraction: float = 0.35,
    ):
        self.gate = dict(DEFAULT_GATE_CONFIG)
        if gate_config:
            self.gate.update(gate_config)

        self.weights = dict(DEFAULT_SCORE_WEIGHTS)
        if score_weights:
            self.weights.update(score_weights)
        w_sum = sum(max(0.0, float(v)) for v in self.weights.values())
        if w_sum <= 0:
            self.weights = dict(DEFAULT_SCORE_WEIGHTS)
            w_sum = sum(self.weights.values())
        for k in list(self.weights.keys()):
            self.weights[k] = float(self.weights[k]) / w_sum

        self.top_n = max(1, int(top_n))
        self.max_sector_fraction = _clamp(float(max_sector_fraction), 0.1, 1.0)

    def _gate_row(self, row: pd.Series) -> Tuple[bool, List[str], float]:
        reasons: List[str] = []
        iv30 = _safe_float(row.get("iv30"), np.nan)
        hv30 = _safe_float(row.get("hv30"), np.nan)
        ivr = _safe_float(row.get("iv_rank_252"), np.nan)
        vol = _safe_float(row.get("avg_opt_volume_30d"), np.nan)
        oi = _safe_float(row.get("avg_oi_30d"), np.nan)
        spread = _safe_float(row.get("avg_bid_ask_pct"), np.nan)
        dte = _safe_float(row.get("days_to_earnings"), np.nan)
        borrow = _safe_float(row.get("borrow_rate"), np.nan)

        if not np.isfinite(iv30) or not np.isfinite(hv30):
            reasons.append("missing_iv_hv")
            spread_raw = np.nan
        else:
            spread_raw = iv30 - hv30
            if spread_raw < float(self.gate["min_iv_hv_spread"]):
                reasons.append("iv_hv_edge_too_low")

        if not np.isfinite(ivr) or ivr < float(self.gate["min_iv_rank"]):
            reasons.append("iv_rank_too_low")
        if not np.isfinite(vol) or vol < float(self.gate["min_option_volume_30d"]):
            reasons.append("option_volume_too_low")
        if not np.isfinite(oi) or oi < float(self.gate["min_option_oi_30d"]):
            reasons.append("oi_too_low")
        if not np.isfinite(spread) or spread > float(self.gate["max_bid_ask_pct"]):
            reasons.append("bid_ask_too_wide")
        if not np.isfinite(dte) or dte < float(self.gate["min_days_to_earnings"]):
            reasons.append("earnings_too_close")
        if np.isfinite(borrow) and borrow > float(self.gate["max_borrow_rate"]):
            reasons.append("borrow_rate_too_high")

        return len(reasons) == 0, reasons, float(spread_raw) if np.isfinite(spread_raw) else np.nan

    def _score_components(self, row: pd.Series) -> Dict[str, float]:
        iv30 = _safe_float(row.get("iv30"), 0.0)
        hv30 = _safe_float(row.get("hv30"), 1e-6)
        spread_pct = _safe_float(row.get("avg_bid_ask_pct"), 1.0)
        vol = _safe_float(row.get("avg_opt_volume_30d"), 0.0)
        oi = _safe_float(row.get("avg_oi_30d"), 0.0)
        dte = _safe_float(row.get("days_to_earnings"), 0.0)
        borrow = _safe_float(row.get("borrow_rate"), np.nan)

        vol_edge_raw = (iv30 - hv30) / max(abs(hv30), 1e-6)
        vol_edge = _clamp((vol_edge_raw + 1.0) / 4.0, 0.0, 1.0)

        spread_score = _clamp(1.0 - (spread_pct / max(float(self.gate["max_bid_ask_pct"]), 1e-6)), 0.0, 1.0)
        vol_score = _clamp(vol / max(float(self.gate["min_option_volume_30d"]) * 2.0, 1.0), 0.0, 1.0)
        oi_score = _clamp(oi / max(float(self.gate["min_option_oi_30d"]) * 2.0, 1.0), 0.0, 1.0)
        liquidity = 0.40 * spread_score + 0.30 * vol_score + 0.30 * oi_score

        min_dte = float(self.gate["min_days_to_earnings"])
        event_timing = _clamp((dte - min_dte) / max(35.0 - min_dte, 1.0), 0.0, 1.0)

        # Unknown borrow is treated as mild penalty instead of best-case zero.
        if np.isfinite(borrow):
            borrow_pen = _clamp(borrow / max(float(self.gate["max_borrow_rate"]), 1e-6), 0.0, 1.0)
        else:
            borrow_pen = 0.25
        risk = 1.0 - borrow_pen

        return {
            "score_vol_edge": float(vol_edge),
            "score_liquidity": float(liquidity),
            "score_event_timing": float(event_timing),
            "score_risk": float(risk),
        }

    def run(self, universe_df: pd.DataFrame) -> ScanResult:
        df = normalize_universe_dataframe(universe_df)
        if df.empty:
            return ScanResult(
                summary={
                    "universe_size": 0,
                    "passed_gate_count": 0,
                    "selected_count": 0,
                    "top_n": self.top_n,
                    "max_sector_fraction": self.max_sector_fraction,
                },
                snapshots=[],
                scores=[],
                selected_symbols=[],
            )

        snapshots: List[Dict[str, Any]] = []
        score_rows: List[Dict[str, Any]] = []
        pass_symbols: List[str] = []

        for _, row in df.iterrows():
            passed, reasons, iv_hv_spread = self._gate_row(row)
            symbol = str(row["symbol"])
            sector = str(row.get("sector") or "UNKNOWN")

            snapshots.append({
                "symbol": symbol,
                "sector": sector,
                "price": _safe_float(row.get("price"), np.nan),
                "iv30": _safe_float(row.get("iv30"), np.nan),
                "hv30": _safe_float(row.get("hv30"), np.nan),
                "iv_rank_252": _safe_float(row.get("iv_rank_252"), np.nan),
                "iv_hv_spread": float(iv_hv_spread) if np.isfinite(iv_hv_spread) else None,
                "avg_opt_volume_30d": _safe_float(row.get("avg_opt_volume_30d"), np.nan),
                "avg_oi_30d": _safe_float(row.get("avg_oi_30d"), np.nan),
                "avg_bid_ask_pct": _safe_float(row.get("avg_bid_ask_pct"), np.nan),
                "earnings_date": row.get("earnings_date"),
                "days_to_earnings": _safe_float(row.get("days_to_earnings"), np.nan),
                "borrow_rate": _safe_float(row.get("borrow_rate"), np.nan),
                "trend_20d_return": _safe_float(row.get("trend_20d_return"), np.nan),
                "put_call_skew": _safe_float(row.get("put_call_skew"), np.nan),
                "gate_pass": bool(passed),
                "gate_reasons": reasons,
            })

            comps = self._score_components(row) if passed else {
                "score_vol_edge": 0.0,
                "score_liquidity": 0.0,
                "score_event_timing": 0.0,
                "score_risk": 0.0,
            }
            total = 100.0 * (
                self.weights["vol_edge"] * comps["score_vol_edge"] +
                self.weights["liquidity"] * comps["score_liquidity"] +
                self.weights["event_timing"] * comps["score_event_timing"] +
                self.weights["risk"] * comps["score_risk"]
            )

            score_rows.append({
                "symbol": symbol,
                "sector": sector,
                "score_total": float(round(total, 4)),
                "score_vol_edge": float(round(comps["score_vol_edge"] * 100.0, 4)),
                "score_liquidity": float(round(comps["score_liquidity"] * 100.0, 4)),
                "score_event_timing": float(round(comps["score_event_timing"] * 100.0, 4)),
                "score_risk": float(round(comps["score_risk"] * 100.0, 4)),
                "penalty_sector_concentration": 0.0,
                "rank_global": None,
                "rank_in_sector": None,
                "selected": False,
            })
            if passed:
                pass_symbols.append(symbol)

        score_df = pd.DataFrame(score_rows)
        eligible = score_df[score_df["symbol"].isin(pass_symbols)].sort_values(
            by=["score_total", "symbol"], ascending=[False, True]
        )

        max_per_sector = max(1, int(np.floor(self.top_n * self.max_sector_fraction)))
        sector_counts: Dict[str, int] = {}
        selected: List[str] = []
        sector_rank: Dict[str, int] = {}

        for idx, row in eligible.iterrows():
            if len(selected) >= self.top_n:
                break
            sec = str(row["sector"])
            cur = sector_counts.get(sec, 0)
            if cur >= max_per_sector:
                penalty = 100.0 * (float(cur + 1) / max(float(self.top_n), 1.0) - self.max_sector_fraction)
                score_df.at[idx, "penalty_sector_concentration"] = float(max(0.0, penalty))
                continue

            selected.append(str(row["symbol"]))
            sector_counts[sec] = cur + 1
            sector_rank[sec] = sector_rank.get(sec, 0) + 1
            score_df.at[idx, "selected"] = True
            score_df.at[idx, "rank_global"] = len(selected)
            score_df.at[idx, "rank_in_sector"] = sector_rank[sec]

        summary = {
            "universe_size": int(len(df)),
            "passed_gate_count": int(len(pass_symbols)),
            "selected_count": int(len(selected)),
            "top_n": int(self.top_n),
            "max_sector_fraction": float(self.max_sector_fraction),
            "sector_counts": {k: int(v) for k, v in sector_counts.items()},
            "selected_symbols": selected,
        }

        return ScanResult(
            summary=summary,
            snapshots=snapshots,
            scores=score_df.to_dict(orient="records"),
            selected_symbols=selected,
        )
