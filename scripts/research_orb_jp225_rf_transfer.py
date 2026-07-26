#!/usr/bin/env python3
"""Evaluate Liq Narrative RF01-RF12 as a frozen filter family on ORB events.

The MT5 exporter attaches causal RegimeV3 state before outcomes. This script
only evaluates post-hoc filter masks; it does not change ORB signal math.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd

RF_COUNT = 12


def summarize(frame: pd.DataFrame) -> dict:
    resolved = frame[frame["net_r"].abs() > 1e-9]
    wins = int((resolved["net_r"] > 0).sum())
    losses = int((resolved["net_r"] < 0).sum())
    won_r = float(resolved.loc[resolved["net_r"] > 0, "net_r"].sum())
    lost_r = abs(float(resolved.loc[resolved["net_r"] < 0, "net_r"].sum()))
    return {
        "trades": int(len(resolved)),
        "wins": wins,
        "losses": losses,
        "wr_pct": round(100.0 * wins / len(resolved), 4) if len(resolved) else None,
        "net_r": round(float(resolved["net_r"].sum()), 6),
        "profit_factor": round(won_r / lost_r, 6) if lost_r else (99.9 if won_r else 0.0),
        "avg_r": round(float(resolved["net_r"].mean()), 6) if len(resolved) else None,
    }


def rule_index(value: object) -> int:
    text = str(value or "")
    if len(text) < 4 or not text.startswith("RF"):
        return -1
    try:
        number = int(text[2:4])
    except ValueError:
        return -1
    return number - 1 if 1 <= number <= RF_COUNT else -1


def keep_mask(frame: pd.DataFrame, mask: int, column: str = "rf_rule") -> pd.DataFrame:
    indices = frame[column].map(rule_index)
    blocked = indices.map(lambda idx: idx >= 0 and bool(mask & (1 << idx)))
    return frame.loc[~blocked]


def segment(frame: pd.DataFrame, mask: int, column: str = "rf_rule") -> dict:
    kept = keep_mask(frame, mask, column)
    result = summarize(kept)
    result["retention_pct"] = round(100.0 * len(kept) / len(frame), 4) if len(frame) else None
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--events", type=Path, required=True)
    parser.add_argument("--split", default="2025-06-26")
    parser.add_argument("--min-retention", type=float, default=60.0)
    parser.add_argument("--out-prefix", type=Path, required=True)
    args = parser.parse_args()

    head = args.events.read_bytes()[:2]
    encoding = "utf-16" if head in (b"\xff\xfe", b"\xfe\xff") else "utf-8-sig"
    events = pd.read_csv(args.events, keep_default_na=False, encoding=encoding)
    events["signal_time"] = pd.to_datetime(events["signal_time"], errors="raise")
    events["net_r"] = pd.to_numeric(events["net_r"], errors="raise")
    events = events[events["sim_valid"].astype(str).eq("1")].sort_values("signal_time").reset_index(drop=True)
    split = pd.Timestamp(args.split)
    development = events[events["signal_time"] < split]
    forward = events[events["signal_time"] >= split]

    baseline = {
        "overall": summarize(events),
        "development": summarize(development),
        "forward": summarize(forward),
    }

    by_rule = []
    single_blocks = []
    for idx in range(RF_COUNT):
        code = f"RF{idx + 1:02d}"
        matched = events[events["rf_rule"].map(rule_index).eq(idx)]
        row = {"rule": code, "matched": summarize(matched)}
        by_rule.append(row)
        single_blocks.append({
            "rule": code,
            "mask": 1 << idx,
            "overall": segment(events, 1 << idx),
            "development": segment(development, 1 << idx),
            "forward": segment(forward, 1 << idx),
        })

    rows = []
    for mask in range(1 << RF_COUNT):
        overall = segment(events, mask)
        dev = segment(development, mask)
        fwd = segment(forward, mask)
        rows.append({
            "mask": mask,
            "blocked_rules": "+".join(f"RF{i + 1:02d}" for i in range(RF_COUNT) if mask & (1 << i)) or "NONE",
            **{f"overall_{k}": v for k, v in overall.items()},
            **{f"dev_{k}": v for k, v in dev.items()},
            **{f"fwd_{k}": v for k, v in fwd.items()},
        })
    masks = pd.DataFrame(rows)
    base_dev = baseline["development"]
    base_fwd = baseline["forward"]
    stable = masks[
        (masks["overall_retention_pct"] >= args.min_retention)
        & (masks["dev_wr_pct"] > base_dev["wr_pct"])
        & (masks["fwd_wr_pct"] > base_fwd["wr_pct"])
        & (masks["dev_net_r"] > base_dev["net_r"])
        & (masks["fwd_net_r"] > base_fwd["net_r"])
    ].copy()
    if not stable.empty:
        stable["min_split_wr"] = stable[["dev_wr_pct", "fwd_wr_pct"]].min(axis=1)
        stable["min_split_net_r"] = stable[["dev_net_r", "fwd_net_r"]].min(axis=1)
        stable = stable.sort_values(
            ["min_split_wr", "overall_wr_pct", "overall_net_r", "overall_retention_pct"],
            ascending=False,
        )

    all_mask = (1 << RF_COUNT) - 1
    route_sensitivity = {
        "macro_route": {
            "overall": segment(events, all_mask, "rf_rule"),
            "development": segment(development, all_mask, "rf_rule"),
            "forward": segment(forward, all_mask, "rf_rule"),
        },
        "force_continuation": {
            "overall": segment(events, all_mask, "rf_rule_if_cont"),
            "development": segment(development, all_mask, "rf_rule_if_cont"),
            "forward": segment(forward, all_mask, "rf_rule_if_cont"),
        },
        "force_reversal": {
            "overall": segment(events, all_mask, "rf_rule_if_rev"),
            "development": segment(development, all_mask, "rf_rule_if_rev"),
            "forward": segment(forward, all_mask, "rf_rule_if_rev"),
        },
    }

    payload = {
        "status": "ORB_RF_FROZEN_TRANSFER_AUDIT",
        "events": str(args.events),
        "covered_from": events["signal_time"].min().isoformat(),
        "covered_to": events["signal_time"].max().isoformat(),
        "split": str(split),
        "route_mapping": "ORB direction equals causal macro direction => continuation; route-dependent rules fail open if unknown",
        "baseline": baseline,
        "frozen_all_12_blocked": route_sensitivity["macro_route"],
        "route_sensitivity": route_sensitivity,
        "by_rule": by_rule,
        "single_rule_blocks": single_blocks,
        "stable_candidate_count": int(len(stable)),
        "best_stable_candidates": stable.head(20).to_dict(orient="records"),
    }
    args.out_prefix.parent.mkdir(parents=True, exist_ok=True)
    events.to_csv(args.out_prefix.with_suffix(".events.csv"), index=False)
    masks.to_csv(args.out_prefix.with_suffix(".masks.csv"), index=False)
    stable.to_csv(args.out_prefix.with_suffix(".stable.csv"), index=False)
    args.out_prefix.with_suffix(".json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(json.dumps(payload, indent=2))


if __name__ == "__main__":
    main()
