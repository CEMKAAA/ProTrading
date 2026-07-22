#!/usr/bin/env python3
"""Evaluate the frozen Liq Narrative V3 regime filter on NAS trades.

The regime state uses completed H1/H2/H4/D1 bars only. Outcomes are attached
strictly afterwards. This script does not alter NAS signal generation.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import pandas as pd

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
from research_sol_market_regimes_v2 import build_daily_features
from research_sol_market_regimes_v3 import confirmed_state_machine_v3

TIMEFRAMES = ("H1", "H2", "H4", "D1")
AUDIT_COLUMNS = [
    "server_time", "gmt_time", "symbol", "tf", "deal", "position_id",
    "entry_type", "deal_type", "reason", "price", "volume", "request_sl",
    "request_tp", "profit", "swap", "commission", "fee", "retcode", "comment",
]


def load_rates(rate_dir: Path, symbol: str) -> dict[str, pd.DataFrame]:
    rates = {}
    for timeframe in TIMEFRAMES:
        frame = pd.read_parquet(rate_dir / f"{symbol}_{timeframe}.parquet")
        frame = frame.sort_values("time").reset_index(drop=True)
        frame["time"] = pd.to_datetime(frame["time"], utc=True)
        rates[timeframe] = frame
    return rates


def load_deals(path: Path) -> pd.DataFrame:
    raw_prefix = path.read_bytes()[:2]
    encoding = "utf-16" if raw_prefix in (b"\xff\xfe", b"\xfe\xff") else "utf-8-sig"
    probe = path.open("r", encoding=encoding, errors="replace").readline().strip()
    header = 0 if probe.startswith("server_time,") else None
    frame = pd.read_csv(path, header=header, names=None if header == 0 else AUDIT_COLUMNS, encoding=encoding)
    for column in ("entry_type", "deal_type"):
        frame[column] = pd.to_numeric(frame[column], errors="coerce")
    for column in ("price", "profit", "swap", "commission", "fee"):
        frame[column] = pd.to_numeric(frame[column], errors="coerce").fillna(0.0)
    frame["available"] = pd.to_datetime(frame["gmt_time"], utc=True, errors="coerce")
    return frame.dropna(subset=["available", "position_id"]).sort_values(["available", "deal"])


def reconstruct_trades(deals: pd.DataFrame, risk_price: float) -> pd.DataFrame:
    rows = []
    for position_id, part in deals.groupby("position_id", sort=False):
        entries = part[part["entry_type"].eq(0)]
        exits = part[part["entry_type"].isin([1, 2, 3])]
        if entries.empty or exits.empty:
            continue
        entry = entries.iloc[0]
        exit_row = exits.iloc[-1]
        direction = 1 if int(entry["deal_type"]) == 0 else -1
        entry_price = float(entry["price"])
        exit_price = float(exit_row["price"])
        pnl_r = direction * (exit_price - entry_price) / risk_price
        net_money = float(exits[["profit", "swap", "commission", "fee"]].sum().sum())
        rows.append({
            "position_id": str(position_id),
            "available": entry["available"],
            "exit_time": exit_row["available"],
            "direction": direction,
            "entry": entry_price,
            "exit": exit_price,
            "pnl_r": pnl_r,
            "won": pnl_r > 1e-9,
            "lost": pnl_r < -1e-9,
            "net_money": net_money,
            "exit_reason": int(exit_row["reason"]),
        })
    return pd.DataFrame(rows).sort_values("available").reset_index(drop=True)


def frozen_liq_rule(row: object) -> str:
    continuation = bool(row.continuation_route)
    reversal = not continuation
    if row.core_regime_v3 == "RANGE_LOW_VOL" and row.regime_age_bucket == "MATURE" and row.transition_status == "STABLE" and continuation:
        return "RF01_RLV_MATURE_STABLE_CONT"
    if row.core_regime_v3 == "TREND_LOW_VOL" and row.h1_h2_phase == "NEUTRAL_ROTATION" and row.macro_direction_v3 == "UP":
        return "RF02_TLV_ROTATION_UP"
    if row.h1_h2_phase == "ALIGNED_IMPULSE" and row.macro_direction_v3 == "DOWN" and continuation:
        return "RF03_IMPULSE_DOWN_CONT"
    if row.core_regime_v3 == "RANGE_HIGH_VOL" and row.transition_status == "DEVELOPING":
        return "RF04_RHV_DEVELOPING"
    if row.core_regime_v3 == "RANGE_LOW_VOL" and row.h1_h2_phase == "DEEP_REBOUND" and row.volatility_depth == "NORMAL":
        return "RF05_RLV_DEEP_REBOUND_NORMAL"
    if row.core_regime_v3 == "RANGE_LOW_VOL" and row.h1_h2_phase == "SHALLOW_REBOUND":
        return "RF06_RLV_SHALLOW_REBOUND"
    if row.h1_h2_phase == "ALIGNED" and row.regime_age_bucket == "FRESH" and row.transition_status == "STABLE":
        return "RF07_ALIGNED_FRESH_STABLE"
    if row.h1_h2_phase == "SHALLOW_PULLBACK" and row.regime_age_bucket == "MATURE" and row.transition_status == "STABLE":
        return "RF08_SHALLOW_PULLBACK_MATURE"
    if row.core_regime_v3 == "RANGE_HIGH_VOL" and row.h1_h2_phase == "ALIGNED_IMPULSE":
        return "RF09_RHV_ALIGNED_IMPULSE"
    if row.core_regime_v3 == "RANGE_LOW_VOL" and row.volatility_depth == "COMPRESSED" and row.macro_direction_v3 == "DOWN" and reversal:
        return "RF10_RLV_COMPRESSED_DOWN_REV"
    if row.h1_h2_phase == "ALIGNED_IMPULSE" and row.volatility_depth == "NORMAL" and reversal:
        return "RF11_IMPULSE_NORMAL_REV"
    if row.h1_h2_phase == "SHALLOW_PULLBACK" and row.volatility_depth == "NORMAL":
        return "RF12_SHALLOW_PULLBACK_NORMAL"
    return ""


def summarize(frame: pd.DataFrame) -> dict:
    closed = frame[frame["won"] | frame["lost"]]
    wins = int(closed["won"].sum())
    losses = int(closed["lost"].sum())
    return {
        "trades": int(len(closed)),
        "wins": wins,
        "losses": losses,
        "wr_pct": round(100.0 * wins / len(closed), 3) if len(closed) else None,
        "net_r": round(float(closed["pnl_r"].sum()), 3),
        "avg_r": round(float(closed["pnl_r"].mean()), 4) if len(closed) else None,
    }


def segment_report(frame: pd.DataFrame) -> dict:
    kept = frame[frame["reject_rule"].eq("")]
    rejected = frame[frame["reject_rule"].ne("")]
    result = {
        "baseline": summarize(frame),
        "frozen_filter_kept": summarize(kept),
        "frozen_filter_rejected": summarize(rejected),
        "retention_pct": round(100.0 * len(kept) / len(frame), 3) if len(frame) else None,
    }
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--audit", type=Path, required=True)
    parser.add_argument("--rates", type=Path, default=Path("logs/nas_de30_rates"))
    parser.add_argument("--symbol", default="DE30m")
    parser.add_argument("--risk-price", type=float, default=40.0)
    parser.add_argument("--forward-start", default="2025-04-01")
    parser.add_argument("--out-prefix", type=Path, default=Path("logs/nas_de30_regime_transfer"))
    args = parser.parse_args()

    trades = reconstruct_trades(load_deals(args.audit), args.risk_price)
    state_cache = args.rates / f"{args.symbol}_RegimeV3States.csv"
    if state_cache.exists():
        states = pd.read_csv(state_cache, parse_dates=["regime_available"])
        states["regime_available"] = pd.to_datetime(states["regime_available"], utc=True)
    else:
        states, _ = confirmed_state_machine_v3(build_daily_features(load_rates(args.rates, args.symbol)))
        states.to_csv(state_cache, index=False)
    regime_columns = [
        "regime_available", "core_regime_v3", "regime_age_bucket", "transition_status",
        "macro_direction_v3", "h1_h2_phase", "volatility_depth", "structural_hint",
    ]
    attached = pd.merge_asof(
        trades.sort_values("available"),
        states[regime_columns].sort_values("regime_available"),
        left_on="available", right_on="regime_available", direction="backward",
        tolerance=pd.Timedelta("36h"),
    ).dropna(subset=["core_regime_v3"]).copy()
    attached["continuation_route"] = (
        ((attached["direction"] > 0) & attached["macro_direction_v3"].eq("UP"))
        | ((attached["direction"] < 0) & attached["macro_direction_v3"].eq("DOWN"))
    )
    attached["reject_rule"] = [frozen_liq_rule(row) for row in attached.itertuples(index=False)]
    forward_start = pd.Timestamp(args.forward_start, tz="UTC")
    development = attached[attached["available"] < forward_start]
    forward = attached[attached["available"] >= forward_start]

    by_rule = {}
    for rule, part in attached[attached["reject_rule"].ne("")].groupby("reject_rule"):
        by_rule[rule] = summarize(part)
    monthly = {
        str(month): segment_report(part)
        for month, part in attached.groupby(attached["available"].dt.to_period("M"))
    }
    payload = {
        "status": "EXTERNAL_FROZEN_LIQ_RULE_TRANSFER_NO_FITTING",
        "audit": str(args.audit),
        "risk_price": args.risk_price,
        "route_mapping": "NAS direction equals causal macro direction => continuation; otherwise reversal",
        "covered_from": attached["available"].min().isoformat() if len(attached) else None,
        "covered_to": attached["available"].max().isoformat() if len(attached) else None,
        "overall": segment_report(attached),
        "development": segment_report(development),
        "forward": segment_report(forward),
        "rejected_by_rule": by_rule,
        "monthly": monthly,
    }
    args.out_prefix.parent.mkdir(parents=True, exist_ok=True)
    attached.to_csv(args.out_prefix.with_suffix(".trades.csv"), index=False)
    args.out_prefix.with_suffix(".json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(json.dumps(payload, indent=2))


if __name__ == "__main__":
    main()
