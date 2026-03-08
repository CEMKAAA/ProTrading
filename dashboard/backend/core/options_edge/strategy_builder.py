"""
Deterministic options strategy constructor (Phase 2).

Builds:
- put credit spread
- call credit spread
- iron condor
- short strangle
- short straddle
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime, timezone
from typing import Any, Dict, List, Optional

import numpy as np
import pandas as pd


DEFAULT_BUILDER_CONFIG: Dict[str, Any] = {
    "structure_mode": "auto",  # auto / put_credit_spread / call_credit_spread / iron_condor / short_strangle / short_straddle
    "target_delta_abs": 0.25,
    "strangle_target_delta_abs": 0.18,
    "straddle_max_atm_distance_pct": 0.02,
    "preferred_dte_min": 30,
    "preferred_dte_max": 45,
    "fallback_dte_min": 21,
    "fallback_dte_max": 55,
    "min_width": 1.0,
    "max_width": 20.0,
    "min_credit_width_ratio": 0.12,
    "min_pop": 0.55,
    "min_pop_unbounded": 0.15,  # Lower POP gate for straddle/strangle (unbounded risk)
    "max_leg_bid_ask_pct": 0.25,
    "min_leg_oi": 50,
    "min_leg_volume": 5,
    "contract_multiplier": 100.0,
    "max_structures_per_symbol": 2,
    "auto_condor_ivr_min": 0.60,
    "auto_condor_trend_abs_max": 0.03,
    "auto_directional_trend_threshold": 0.015,
    "auto_skew_put_threshold": 0.10,
    "auto_skew_call_threshold": -0.10,
    "allow_unbounded_structures": True,
}

CHAIN_REQUIRED_COLUMNS: List[str] = [
    "symbol",
    "expiry_date",
    "option_type",
    "strike",
    "bid",
    "ask",
]


def _safe_float(v: Any, default: float = np.nan) -> float:
    try:
        if v is None:
            return float(default)
        f = float(v)
        if np.isnan(f) or np.isinf(f):
            return float(default)
        return f
    except Exception:
        return float(default)


def _clamp(v: float, lo: float, hi: float) -> float:
    return float(max(lo, min(hi, v)))


def normalize_option_chain_dataframe(df: pd.DataFrame, asof_date: Optional[date] = None) -> pd.DataFrame:
    """
    Normalize option chain rows into builder schema.
    """
    if df is None or df.empty:
        return pd.DataFrame(columns=CHAIN_REQUIRED_COLUMNS + ["dte", "delta", "theta", "vega", "volume", "oi", "mid"])

    out = df.copy()
    out.columns = [str(c).strip().lower() for c in out.columns]
    aliases = {
        "ticker": "symbol",
        "expiration": "expiry_date",
        "expiry": "expiry_date",
        "type": "option_type",
        "right": "option_type",
        "open_interest": "oi",
        "ivol": "iv",
    }
    for src, dst in aliases.items():
        if src in out.columns and dst not in out.columns:
            out[dst] = out[src]

    for c in ["symbol", "expiry_date", "option_type", "strike", "bid", "ask"]:
        if c not in out.columns:
            out[c] = np.nan

    out["symbol"] = out["symbol"].astype(str).str.upper().str.strip()
    out["option_type"] = out["option_type"].astype(str).str.upper().str.strip()
    out["option_type"] = out["option_type"].replace({
        "CALL": "C", "PUT": "P", "C": "C", "P": "P",
    })
    out = out[out["option_type"].isin(["C", "P"])]

    out["expiry_date"] = pd.to_datetime(out["expiry_date"], errors="coerce").dt.date
    for c in ["strike", "bid", "ask", "delta", "theta", "vega", "volume", "oi", "dte"]:
        if c not in out.columns:
            out[c] = np.nan
        out[c] = pd.to_numeric(out[c], errors="coerce")

    out["mid"] = (out["bid"] + out["ask"]) / 2.0
    out = out.dropna(subset=["symbol", "expiry_date", "strike", "bid", "ask"])
    out = out[(out["ask"] >= out["bid"]) & (out["bid"] >= 0)]

    if asof_date is None:
        asof_date = datetime.now(timezone.utc).date()
    out["dte"] = out["dte"].where(out["dte"].notna(), (pd.to_datetime(out["expiry_date"]) - pd.Timestamp(asof_date)).dt.days)
    out = out[out["dte"] >= 0]

    return out[
        ["symbol", "expiry_date", "dte", "option_type", "strike", "bid", "ask", "mid", "delta", "theta", "vega", "volume", "oi"]
    ].copy()


@dataclass
class BuiltStrategy:
    structure_type: str
    symbol: str
    expiry_date: str
    dte: int
    legs: List[Dict[str, Any]]
    net_credit: float
    max_profit: float
    max_loss: float
    pop_est: float
    delta_net: float
    theta_net: float
    vega_net: float
    breakeven_low: Optional[float]
    breakeven_high: Optional[float]
    quality_flags: List[str]
    builder_score: float


@dataclass
class BuildOutcome:
    strategies: List[BuiltStrategy]
    rejection_reasons: List[str]
    chosen_policy: str


class OptionsStrategyBuilder:
    def __init__(self, config: Optional[Dict[str, Any]] = None):
        self.cfg = dict(DEFAULT_BUILDER_CONFIG)
        if config:
            self.cfg.update(config)

    def _pick_expiry(self, chain: pd.DataFrame) -> Optional[int]:
        pref = chain[(chain["dte"] >= int(self.cfg["preferred_dte_min"])) & (chain["dte"] <= int(self.cfg["preferred_dte_max"]))]
        if not pref.empty:
            return int(pref["dte"].value_counts().idxmax())
        fb = chain[(chain["dte"] >= int(self.cfg["fallback_dte_min"])) & (chain["dte"] <= int(self.cfg["fallback_dte_max"]))]
        if fb.empty:
            return None
        return int(fb["dte"].value_counts().idxmax())

    def _liq_flags(self, leg: pd.Series) -> List[str]:
        flags: List[str] = []
        mid = _safe_float(leg.get("mid"), np.nan)
        bid = _safe_float(leg.get("bid"), np.nan)
        ask = _safe_float(leg.get("ask"), np.nan)
        if np.isfinite(mid) and mid > 0 and np.isfinite(bid) and np.isfinite(ask):
            pct = (ask - bid) / mid
            if pct > float(self.cfg["max_leg_bid_ask_pct"]):
                flags.append("wide_leg_spread")
        oi = _safe_float(leg.get("oi"), 0.0)
        vol = _safe_float(leg.get("volume"), 0.0)
        if oi < float(self.cfg["min_leg_oi"]):
            flags.append("thin_oi")
        if vol < float(self.cfg["min_leg_volume"]):
            flags.append("thin_volume")
        return flags

    def _pick_short_leg(self, sub: pd.DataFrame, option_type: str, spot: float) -> Optional[pd.Series]:
        t = float(self.cfg["target_delta_abs"])
        z = sub[sub["option_type"] == option_type].copy()
        if z.empty:
            return None
        z = z[z["mid"] > 0]
        if z.empty:
            return None
        z_all = z.copy()
        if option_type == "P":
            z = z[z["strike"] < spot]
        else:
            z = z[z["strike"] > spot]
        if z.empty:
            # Spot can be noisy/unavailable for some providers/plans.
            # Fallback: choose from full side by delta/strike proximity.
            z = z_all

        if z["delta"].notna().any():
            z["delta_dist"] = (z["delta"].abs() - t).abs()
            z = z.sort_values(by=["delta_dist", "mid"], ascending=[True, False])
        else:
            z["dist"] = (z["strike"] - spot).abs()
            z = z.sort_values(by=["dist", "mid"], ascending=[True, False])
        return z.iloc[0]

    def _build_credit_spread_diagnostic(
        self,
        symbol: str,
        expiry_df: pd.DataFrame,
        spot: float,
        side: str,  # "put" or "call"
    ) -> tuple[Optional[BuiltStrategy], List[str]]:
        reasons: List[str] = []
        option_type = "P" if side == "put" else "C"
        short = self._pick_short_leg(expiry_df, option_type, spot)
        if short is None:
            return None, [f"{side}_short_leg_not_found"]

        if option_type == "P":
            longs = expiry_df[(expiry_df["option_type"] == "P") & (expiry_df["strike"] < float(short["strike"]))].copy()
        else:
            longs = expiry_df[(expiry_df["option_type"] == "C") & (expiry_df["strike"] > float(short["strike"]))].copy()
        if longs.empty:
            return None, [f"{side}_no_hedge_candidates"]

        widths = (float(short["strike"]) - longs["strike"]) if option_type == "P" else (longs["strike"] - float(short["strike"]))
        longs = longs[(widths >= float(self.cfg["min_width"])) & (widths <= float(self.cfg["max_width"]))].copy()
        if longs.empty:
            return None, [f"{side}_width_constraints_failed"]

        longs["width"] = (float(short["strike"]) - longs["strike"]) if option_type == "P" else (longs["strike"] - float(short["strike"]))
        longs["credit"] = float(short["mid"]) - longs["mid"]
        longs = longs[(longs["credit"] > 0) & longs["width"].notna()]
        if longs.empty:
            return None, [f"{side}_non_positive_credit"]
        longs["cw_ratio"] = longs["credit"] / longs["width"]
        longs = longs[longs["cw_ratio"] >= float(self.cfg["min_credit_width_ratio"])]
        if longs.empty:
            return None, [f"{side}_credit_width_ratio_too_low"]

        long_leg = longs.sort_values(by=["cw_ratio", "credit"], ascending=[False, False]).iloc[0]

        credit = float(long_leg["credit"])
        width = float(long_leg["width"])
        cm = float(self.cfg["contract_multiplier"])
        max_profit = credit * cm
        max_loss = max((width - credit) * cm, 0.0)
        if max_loss <= 0:
            return None, [f"{side}_invalid_max_loss"]

        short_delta = _safe_float(short.get("delta"), np.nan)
        pop = _clamp(1.0 - abs(short_delta), 0.01, 0.99) if np.isfinite(short_delta) else 0.60
        if pop < float(self.cfg["min_pop"]):
            return None, [f"{side}_pop_below_min"]

        # Net Greeks: portfolio is -1 short + 1 long, so net = long - short
        delta_net = (_safe_float(long_leg.get("delta"), 0.0) - _safe_float(short.get("delta"), 0.0)) * cm
        theta_net = (_safe_float(long_leg.get("theta"), 0.0) - _safe_float(short.get("theta"), 0.0)) * cm
        vega_net = (_safe_float(long_leg.get("vega"), 0.0) - _safe_float(short.get("vega"), 0.0)) * cm

        if side == "put":
            be_low = float(short["strike"]) - credit
            be_high = None
        else:
            be_low = None
            be_high = float(short["strike"]) + credit

        flags = []
        flags.extend(self._liq_flags(short))
        flags.extend(self._liq_flags(long_leg))

        liq_pen = 0.08 * len(flags)
        score = _clamp(0.45 * pop + 0.35 * _clamp(float(long_leg["cw_ratio"]) / 0.5, 0.0, 1.0) + 0.20 * _clamp(1.0 - liq_pen, 0.0, 1.0), 0.0, 1.0)

        legs = [
            {
                "action": "SELL",
                "option_type": option_type,
                "strike": float(short["strike"]),
                "bid": _safe_float(short["bid"], 0.0),
                "ask": _safe_float(short["ask"], 0.0),
                "mid": _safe_float(short["mid"], 0.0),
                "delta": _safe_float(short.get("delta"), np.nan),
                "theta": _safe_float(short.get("theta"), np.nan),
                "vega": _safe_float(short.get("vega"), np.nan),
                "oi": _safe_float(short.get("oi"), 0.0),
                "volume": _safe_float(short.get("volume"), 0.0),
            },
            {
                "action": "BUY",
                "option_type": option_type,
                "strike": float(long_leg["strike"]),
                "bid": _safe_float(long_leg["bid"], 0.0),
                "ask": _safe_float(long_leg["ask"], 0.0),
                "mid": _safe_float(long_leg["mid"], 0.0),
                "delta": _safe_float(long_leg.get("delta"), np.nan),
                "theta": _safe_float(long_leg.get("theta"), np.nan),
                "vega": _safe_float(long_leg.get("vega"), np.nan),
                "oi": _safe_float(long_leg.get("oi"), 0.0),
                "volume": _safe_float(long_leg.get("volume"), 0.0),
            },
        ]

        return BuiltStrategy(
            structure_type=f"{side}_credit_spread",
            symbol=symbol,
            expiry_date=str(short["expiry_date"]),
            dte=int(_safe_float(short["dte"], 0)),
            legs=legs,
            net_credit=float(round(credit, 6)),
            max_profit=float(round(max_profit, 6)),
            max_loss=float(round(max_loss, 6)),
            pop_est=float(round(pop, 6)),
            delta_net=float(round(delta_net, 6)),
            theta_net=float(round(theta_net, 6)),
            vega_net=float(round(vega_net, 6)),
            breakeven_low=None if be_low is None else float(round(be_low, 6)),
            breakeven_high=None if be_high is None else float(round(be_high, 6)),
            quality_flags=sorted(list(set(flags))),
            builder_score=float(round(score, 6)),
        ), reasons

    def _build_credit_spread(
        self,
        symbol: str,
        expiry_df: pd.DataFrame,
        spot: float,
        side: str,
    ) -> Optional[BuiltStrategy]:
        built, _ = self._build_credit_spread_diagnostic(symbol, expiry_df, spot, side)
        return built

    def _build_iron_condor(self, put_spread: BuiltStrategy, call_spread: BuiltStrategy) -> Optional[BuiltStrategy]:
        if put_spread.expiry_date != call_spread.expiry_date:
            return None
        if put_spread.dte != call_spread.dte:
            return None
        put_short = next((l for l in put_spread.legs if l["action"] == "SELL"), None)
        call_short = next((l for l in call_spread.legs if l["action"] == "SELL"), None)
        if put_short is None or call_short is None:
            return None
        if float(put_short["strike"]) >= float(call_short["strike"]):
            return None

        credit = put_spread.net_credit + call_spread.net_credit
        put_width = abs(float(put_spread.legs[0]["strike"]) - float(put_spread.legs[1]["strike"]))
        call_width = abs(float(call_spread.legs[0]["strike"]) - float(call_spread.legs[1]["strike"]))
        width = max(put_width, call_width)
        cm = float(self.cfg["contract_multiplier"])
        max_profit = credit * cm
        max_loss = max((width - credit) * cm, 0.0)
        if max_loss <= 0:
            return None

        # Iron condor POP: use delta-sum formula (not min of spreads).
        # POP ~ 1 - |put_short_delta| - |call_short_delta|
        put_d = abs(_safe_float(put_short.get("delta"), 0.0))
        call_d = abs(_safe_float(call_short.get("delta"), 0.0))
        if put_d + call_d > 0:
            pop = _clamp(1.0 - put_d - call_d, 0.05, 0.95)
        else:
            # Fallback if delta data missing: conservative estimate from spread POPs
            pop = _clamp(put_spread.pop_est * call_spread.pop_est, 0.05, 0.95)
        if pop < float(self.cfg["min_pop"]):
            return None

        flags = sorted(list(set((put_spread.quality_flags or []) + (call_spread.quality_flags or []))))
        score = _clamp(0.5 * pop + 0.3 * _clamp((credit / max(width, 1e-6)) / 0.5, 0.0, 1.0) + 0.2 * _clamp(1.0 - 0.08 * len(flags), 0.0, 1.0), 0.0, 1.0)

        return BuiltStrategy(
            structure_type="iron_condor",
            symbol=put_spread.symbol,
            expiry_date=put_spread.expiry_date,
            dte=put_spread.dte,
            legs=put_spread.legs + call_spread.legs,
            net_credit=float(round(credit, 6)),
            max_profit=float(round(max_profit, 6)),
            max_loss=float(round(max_loss, 6)),
            pop_est=float(round(pop, 6)),
            delta_net=float(round(put_spread.delta_net + call_spread.delta_net, 6)),
            theta_net=float(round(put_spread.theta_net + call_spread.theta_net, 6)),
            vega_net=float(round(put_spread.vega_net + call_spread.vega_net, 6)),
            breakeven_low=float(round(float(put_short["strike"]) - credit, 6)),
            breakeven_high=float(round(float(call_short["strike"]) + credit, 6)),
            quality_flags=flags,
            builder_score=float(round(score, 6)),
        )

    def _pick_atm_leg(self, sub: pd.DataFrame, option_type: str, spot: float) -> Optional[pd.Series]:
        z = sub[sub["option_type"] == option_type].copy()
        if z.empty:
            return None
        z = z[z["mid"] > 0]
        if z.empty:
            return None
        z["atm_dist"] = (z["strike"] - spot).abs()
        z = z.sort_values(by=["atm_dist", "mid"], ascending=[True, False])
        return z.iloc[0]

    def _build_short_straddle(self, symbol: str, expiry_df: pd.DataFrame, spot: float) -> Optional[BuiltStrategy]:
        put_leg = self._pick_atm_leg(expiry_df, "P", spot)
        call_leg = self._pick_atm_leg(expiry_df, "C", spot)
        if put_leg is None or call_leg is None:
            return None

        strike_mid = 0.5 * (float(put_leg["strike"]) + float(call_leg["strike"]))
        strike_gap = abs(float(put_leg["strike"]) - float(call_leg["strike"]))
        max_atm_gap = max(spot * float(self.cfg.get("straddle_max_atm_distance_pct", 0.02)), 1.0)
        if strike_gap > max_atm_gap:
            return None

        credit = float(put_leg["mid"]) + float(call_leg["mid"])
        if credit <= 0:
            return None

        cm = float(self.cfg["contract_multiplier"])
        max_profit = credit * cm
        # Unbounded in theory; use deterministic risk proxy for ranking/backtest compatibility.
        max_loss = max(max_profit * 2.5, 1.0)
        # Straddle POP: delta-sum gives ~0 for ATM. Use breakeven-range proxy instead:
        # POP ~ credit / spot (fraction of spot price that stock can move before loss)
        put_d = abs(_safe_float(put_leg.get("delta"), 0.50))
        call_d = abs(_safe_float(call_leg.get("delta"), 0.50))
        delta_pop = 1.0 - put_d - call_d  # often ~0 for ATM
        be_range_pop = _clamp(credit / max(spot * 0.01, 1e-6) * 0.10, 0.05, 0.65)  # breakeven width proxy
        pop = _clamp(max(delta_pop, be_range_pop), 0.05, 0.95)
        if pop < float(self.cfg.get("min_pop_unbounded", 0.15)):
            return None

        be_low = strike_mid - credit
        be_high = strike_mid + credit
        flags = sorted(list(set(self._liq_flags(put_leg) + self._liq_flags(call_leg) + ["max_loss_proxy_unbounded"])))
        liq_pen = 0.08 * len(flags)
        score = _clamp(0.45 * pop + 0.35 * _clamp(credit / max(spot * 0.08, 1e-6), 0.0, 1.0) + 0.20 * _clamp(1.0 - liq_pen, 0.0, 1.0), 0.0, 1.0)

        legs = [
            {
                "action": "SELL",
                "option_type": "P",
                "strike": float(put_leg["strike"]),
                "bid": _safe_float(put_leg.get("bid"), 0.0),
                "ask": _safe_float(put_leg.get("ask"), 0.0),
                "mid": _safe_float(put_leg.get("mid"), 0.0),
                "delta": _safe_float(put_leg.get("delta"), np.nan),
                "theta": _safe_float(put_leg.get("theta"), np.nan),
                "vega": _safe_float(put_leg.get("vega"), np.nan),
                "oi": _safe_float(put_leg.get("oi"), 0.0),
                "volume": _safe_float(put_leg.get("volume"), 0.0),
            },
            {
                "action": "SELL",
                "option_type": "C",
                "strike": float(call_leg["strike"]),
                "bid": _safe_float(call_leg.get("bid"), 0.0),
                "ask": _safe_float(call_leg.get("ask"), 0.0),
                "mid": _safe_float(call_leg.get("mid"), 0.0),
                "delta": _safe_float(call_leg.get("delta"), np.nan),
                "theta": _safe_float(call_leg.get("theta"), np.nan),
                "vega": _safe_float(call_leg.get("vega"), np.nan),
                "oi": _safe_float(call_leg.get("oi"), 0.0),
                "volume": _safe_float(call_leg.get("volume"), 0.0),
            },
        ]
        return BuiltStrategy(
            structure_type="short_straddle",
            symbol=symbol,
            expiry_date=str(put_leg["expiry_date"]),
            dte=int(_safe_float(put_leg["dte"], 0)),
            legs=legs,
            net_credit=float(round(credit, 6)),
            max_profit=float(round(max_profit, 6)),
            max_loss=float(round(max_loss, 6)),
            pop_est=float(round(pop, 6)),
            delta_net=float(round((_safe_float(put_leg.get("delta"), 0.0) + _safe_float(call_leg.get("delta"), 0.0)) * cm, 6)),
            theta_net=float(round((_safe_float(put_leg.get("theta"), 0.0) + _safe_float(call_leg.get("theta"), 0.0)) * cm, 6)),
            vega_net=float(round((_safe_float(put_leg.get("vega"), 0.0) + _safe_float(call_leg.get("vega"), 0.0)) * cm, 6)),
            breakeven_low=float(round(be_low, 6)),
            breakeven_high=float(round(be_high, 6)),
            quality_flags=flags,
            builder_score=float(round(score, 6)),
        )

    def _build_short_strangle(self, symbol: str, expiry_df: pd.DataFrame, spot: float) -> Optional[BuiltStrategy]:
        put_pool = expiry_df[expiry_df["option_type"] == "P"].copy()
        call_pool = expiry_df[expiry_df["option_type"] == "C"].copy()
        if put_pool.empty or call_pool.empty:
            return None
        put_pool = put_pool[put_pool["strike"] < spot]
        call_pool = call_pool[call_pool["strike"] > spot]
        if put_pool.empty or call_pool.empty:
            return None

        td = float(self.cfg.get("strangle_target_delta_abs", self.cfg.get("target_delta_abs", 0.18)))
        if put_pool["delta"].notna().any():
            put_pool["delta_dist"] = (put_pool["delta"].abs() - td).abs()
            put_pool = put_pool.sort_values(by=["delta_dist", "mid"], ascending=[True, False])
        else:
            put_pool["dist"] = (put_pool["strike"] - spot).abs()
            put_pool = put_pool.sort_values(by=["dist", "mid"], ascending=[False, False])
        if call_pool["delta"].notna().any():
            call_pool["delta_dist"] = (call_pool["delta"].abs() - td).abs()
            call_pool = call_pool.sort_values(by=["delta_dist", "mid"], ascending=[True, False])
        else:
            call_pool["dist"] = (call_pool["strike"] - spot).abs()
            call_pool = call_pool.sort_values(by=["dist", "mid"], ascending=[False, False])

        put_leg = put_pool.iloc[0]
        call_leg = call_pool.iloc[0]

        if float(put_leg["strike"]) >= float(call_leg["strike"]):
            return None
        credit = float(_safe_float(put_leg.get("mid"), 0.0) + _safe_float(call_leg.get("mid"), 0.0))
        if credit <= 0:
            return None

        cm = float(self.cfg["contract_multiplier"])
        max_profit = credit * cm
        max_loss = max(max_profit * 2.0, 1.0)
        pop = _clamp(
            1.0 - (abs(_safe_float(put_leg.get("delta"), 0.0)) + abs(_safe_float(call_leg.get("delta"), 0.0))),
            0.05,
            0.98,
        )
        if pop < float(self.cfg.get("min_pop_unbounded", 0.15)):
            return None

        be_low = float(put_leg["strike"]) - credit
        be_high = float(call_leg["strike"]) + credit
        flags = sorted(list(set(self._liq_flags(put_leg) + self._liq_flags(call_leg) + ["max_loss_proxy_unbounded"])))
        liq_pen = 0.08 * len(flags)
        score = _clamp(0.45 * pop + 0.35 * _clamp(credit / max(spot * 0.06, 1e-6), 0.0, 1.0) + 0.20 * _clamp(1.0 - liq_pen, 0.0, 1.0), 0.0, 1.0)

        legs = [
            {
                "action": "SELL",
                "option_type": "P",
                "strike": float(put_leg["strike"]),
                "bid": _safe_float(put_leg.get("bid"), 0.0),
                "ask": _safe_float(put_leg.get("ask"), 0.0),
                "mid": _safe_float(put_leg.get("mid"), 0.0),
                "delta": _safe_float(put_leg.get("delta"), np.nan),
                "theta": _safe_float(put_leg.get("theta"), np.nan),
                "vega": _safe_float(put_leg.get("vega"), np.nan),
                "oi": _safe_float(put_leg.get("oi"), 0.0),
                "volume": _safe_float(put_leg.get("volume"), 0.0),
            },
            {
                "action": "SELL",
                "option_type": "C",
                "strike": float(call_leg["strike"]),
                "bid": _safe_float(call_leg.get("bid"), 0.0),
                "ask": _safe_float(call_leg.get("ask"), 0.0),
                "mid": _safe_float(call_leg.get("mid"), 0.0),
                "delta": _safe_float(call_leg.get("delta"), np.nan),
                "theta": _safe_float(call_leg.get("theta"), np.nan),
                "vega": _safe_float(call_leg.get("vega"), np.nan),
                "oi": _safe_float(call_leg.get("oi"), 0.0),
                "volume": _safe_float(call_leg.get("volume"), 0.0),
            },
        ]
        return BuiltStrategy(
            structure_type="short_strangle",
            symbol=symbol,
            expiry_date=str(put_leg["expiry_date"]),
            dte=int(_safe_float(put_leg["dte"], 0)),
            legs=legs,
            net_credit=float(round(credit, 6)),
            max_profit=float(round(max_profit, 6)),
            max_loss=float(round(max_loss, 6)),
            pop_est=float(round(pop, 6)),
            delta_net=float(round((_safe_float(put_leg.get("delta"), 0.0) + _safe_float(call_leg.get("delta"), 0.0)) * cm, 6)),
            theta_net=float(round((_safe_float(put_leg.get("theta"), 0.0) + _safe_float(call_leg.get("theta"), 0.0)) * cm, 6)),
            vega_net=float(round((_safe_float(put_leg.get("vega"), 0.0) + _safe_float(call_leg.get("vega"), 0.0)) * cm, 6)),
            breakeven_low=float(round(be_low, 6)),
            breakeven_high=float(round(be_high, 6)),
            quality_flags=flags,
            builder_score=float(round(score, 6)),
        )

    def build_for_symbol_diagnostics(
        self,
        symbol: str,
        spot: float,
        chain_df: pd.DataFrame,
        iv_rank_252: Optional[float] = None,
        trend_20d_return: Optional[float] = None,
        put_call_skew: Optional[float] = None,
    ) -> BuildOutcome:
        reasons: List[str] = []
        chosen_policy = "none"
        sym_df = chain_df[chain_df["symbol"] == symbol].copy()
        if sym_df.empty or not np.isfinite(spot) or spot <= 0:
            return BuildOutcome(strategies=[], rejection_reasons=["symbol_chain_missing_or_invalid_spot"], chosen_policy=chosen_policy)
        dte = self._pick_expiry(sym_df)
        if dte is None:
            return BuildOutcome(strategies=[], rejection_reasons=["no_valid_expiry_in_dte_window"], chosen_policy=chosen_policy)
        exp_df = sym_df[sym_df["dte"] == dte].copy()
        if exp_df.empty:
            return BuildOutcome(strategies=[], rejection_reasons=["empty_chain_after_expiry_filter"], chosen_policy=chosen_policy)

        put_spread, put_reasons = self._build_credit_spread_diagnostic(symbol, exp_df, spot, "put")
        call_spread, call_reasons = self._build_credit_spread_diagnostic(symbol, exp_df, spot, "call")
        reasons.extend(put_reasons)
        reasons.extend(call_reasons)
        condor = self._build_iron_condor(put_spread, call_spread) if (put_spread and call_spread) else None
        allow_unbounded = bool(self.cfg.get("allow_unbounded_structures", True))
        short_strangle = self._build_short_strangle(symbol, exp_df, spot) if allow_unbounded else None
        short_straddle = self._build_short_straddle(symbol, exp_df, spot) if allow_unbounded else None
        if condor is None:
            reasons.append("iron_condor_unavailable")
        if short_strangle is None:
            reasons.append("short_strangle_unavailable")
        if short_straddle is None:
            reasons.append("short_straddle_unavailable")
        if not allow_unbounded:
            reasons.append("unbounded_structures_disabled")

        mode = str(self.cfg.get("structure_mode", "auto")).lower()
        out: List[BuiltStrategy] = []
        if mode == "put_credit_spread" and put_spread:
            chosen_policy = "forced_put_credit_spread"
            out = [put_spread]
        elif mode == "call_credit_spread" and call_spread:
            chosen_policy = "forced_call_credit_spread"
            out = [call_spread]
        elif mode == "iron_condor" and condor:
            chosen_policy = "forced_iron_condor"
            out = [condor]
        elif mode == "short_strangle" and short_strangle:
            chosen_policy = "forced_short_strangle"
            out = [short_strangle]
        elif mode == "short_straddle" and short_straddle:
            chosen_policy = "forced_short_straddle"
            out = [short_straddle]
        else:
            ivr = _safe_float(iv_rank_252, np.nan)
            tr = _safe_float(trend_20d_return, np.nan)
            skew = _safe_float(put_call_skew, np.nan)
            condor_ivr_min = float(self.cfg.get("auto_condor_ivr_min", 0.60))
            condor_trend_abs_max = float(self.cfg.get("auto_condor_trend_abs_max", 0.03))
            directional_thr = float(self.cfg.get("auto_directional_trend_threshold", 0.015))
            skew_put_thr = float(self.cfg.get("auto_skew_put_threshold", 0.10))
            skew_call_thr = float(self.cfg.get("auto_skew_call_threshold", -0.10))

            condor_preferred = bool(
                condor is not None
                and np.isfinite(ivr)
                and ivr >= condor_ivr_min
                and (not np.isfinite(tr) or abs(tr) <= condor_trend_abs_max)
            )

            if condor_preferred and condor is not None:
                chosen_policy = "auto_condor_high_ivr_balanced_trend"
                out.append(condor)
                # optional backup directional spread
                if put_spread and call_spread:
                    out.append(put_spread if put_spread.builder_score >= call_spread.builder_score else call_spread)
                if short_strangle is not None:
                    out.append(short_strangle)
            else:
                if np.isfinite(tr) and tr >= directional_thr and put_spread is not None:
                    chosen_policy = "auto_put_credit_positive_trend"
                    out.append(put_spread)
                elif np.isfinite(tr) and tr <= -directional_thr and call_spread is not None:
                    chosen_policy = "auto_call_credit_negative_trend"
                    out.append(call_spread)
                elif np.isfinite(skew) and skew >= skew_put_thr and put_spread is not None:
                    chosen_policy = "auto_put_credit_skew_signal"
                    out.append(put_spread)
                elif np.isfinite(skew) and skew <= skew_call_thr and call_spread is not None:
                    chosen_policy = "auto_call_credit_skew_signal"
                    out.append(call_spread)
                else:
                    chosen_policy = "auto_best_available"
                    candidates = [x for x in [put_spread, call_spread, condor, short_strangle, short_straddle] if x is not None]
                    candidates = sorted(candidates, key=lambda x: x.builder_score, reverse=True)
                    out.extend(candidates)

        out = sorted(out, key=lambda x: x.builder_score, reverse=True)
        out = out[: max(1, int(self.cfg.get("max_structures_per_symbol", 2)))]
        if not out:
            if not reasons:
                reasons = ["no_strategy_constructed"]
            return BuildOutcome(strategies=[], rejection_reasons=sorted(list(set(reasons))), chosen_policy=chosen_policy or "auto_none")
        return BuildOutcome(
            strategies=out,
            rejection_reasons=sorted(list(set(reasons))),
            chosen_policy=chosen_policy or "auto_best_available",
        )

    def build_for_symbol(
        self,
        symbol: str,
        spot: float,
        chain_df: pd.DataFrame,
        iv_rank_252: Optional[float] = None,
        trend_20d_return: Optional[float] = None,
        put_call_skew: Optional[float] = None,
    ) -> List[BuiltStrategy]:
        outcome = self.build_for_symbol_diagnostics(
            symbol=symbol,
            spot=spot,
            chain_df=chain_df,
            iv_rank_252=iv_rank_252,
            trend_20d_return=trend_20d_return,
            put_call_skew=put_call_skew,
        )
        return outcome.strategies
