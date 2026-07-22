#!/usr/bin/env python3
"""Walk-forward search for low-complexity Sol liquidity-routing rules.

Rules are developed on 2021-2022, must confirm on 2023, and are reported on
the untouched 2024-2026 holdout. Every rule routes every setup, so frequency
cannot be improved by silently dropping difficult trades.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd


LIQUIDITY_COLUMNS = [
    "hsroom_rev", "horoom_rev", "hslev_rev", "holev_rev",
    "esroom_rev", "eoroom_rev", "eslev_rev", "eolev_rev",
]


def add_features(frame: pd.DataFrame) -> pd.DataFrame:
    out = frame.copy()
    out["available"] = pd.to_datetime(out["available"], utc=True)
    out["year"] = out["available"].dt.year
    out["hroom_diff"] = out["hsroom_rev"] - out["horoom_rev"]
    out["eroom_diff"] = out["esroom_rev"] - out["eoroom_rev"]
    out["hlevel_diff"] = out["hslev_rev"] - out["holev_rev"]
    out["elevel_diff"] = out["eslev_rev"] - out["eolev_rev"]
    out["hroom_min"] = out[["hsroom_rev", "horoom_rev"]].min(axis=1)
    out["eroom_min"] = out[["esroom_rev", "eoroom_rev"]].min(axis=1)
    out["hroom_max"] = out[["hsroom_rev", "horoom_rev"]].max(axis=1)
    out["eroom_max"] = out[["esroom_rev", "eoroom_rev"]].max(axis=1)
    out["hlevel_sum"] = out["hslev_rev"] + out["holev_rev"]
    out["elevel_sum"] = out["eslev_rev"] + out["eolev_rev"]

    hour = out["available"].dt.hour
    weekday = out["available"].dt.weekday
    session = hour.between(14, 22)
    quality = out["q_rev"]
    out["base_reversal_cont"] = False
    out["base_v14_cont"] = (
        (session & weekday.between(0, 3))
        | (~session & quality.gt(2.17) & quality.le(3.14))
    )
    return out


def score(frame: pd.DataFrame, route_cont: np.ndarray) -> dict:
    wins = np.where(route_cont, frame["cont_win"], frame["rev_win"]).astype(bool)
    return {"trades": int(len(frame)), "wins": int(wins.sum()), "wr": float(wins.mean())}


def yearly_score(frame: pd.DataFrame, route_cont: np.ndarray) -> dict[str, dict]:
    routed = frame[["year"]].copy()
    routed["route_cont"] = route_cont
    routed["win"] = np.where(route_cont, frame["cont_win"], frame["rev_win"]).astype(bool)
    result = {}
    for year, group in routed.groupby("year"):
        result[str(int(year))] = {
            "trades": int(len(group)),
            "wins": int(group["win"].sum()),
            "wr": float(group["win"].mean()),
            "continuation_share": float(group["route_cont"].mean()),
        }
    return result


def apply_rule(base: np.ndarray, condition: np.ndarray, action_cont: bool) -> np.ndarray:
    routed = base.copy()
    routed[condition] = action_cont
    return routed


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("dataset", type=Path)
    parser.add_argument("--out", type=Path, default=Path("logs/sol_pa_liqmap_rules.json"))
    args = parser.parse_args()

    frame = add_features(pd.read_csv(args.dataset, low_memory=False))
    development = frame[frame["year"].between(2021, 2022)].copy()
    validation = frame[frame["year"].eq(2023)].copy()
    holdout = frame[frame["year"].ge(2024)].copy()
    feature_names = LIQUIDITY_COLUMNS + [
        "hroom_diff", "eroom_diff", "hlevel_diff", "elevel_diff",
        "hroom_min", "eroom_min", "hroom_max", "eroom_max",
        "hlevel_sum", "elevel_sum",
    ]
    quantiles = np.linspace(0.05, 0.95, 19)
    candidates = []

    for base_name in ("base_reversal", "base_v14"):
        base_column = f"{base_name}_cont"
        dev_base = development[base_column].to_numpy(bool)
        val_base = validation[base_column].to_numpy(bool)
        dev_base_year = yearly_score(development, dev_base)
        val_base_score = score(validation, val_base)
        for feature in feature_names:
            thresholds = np.unique(development[feature].quantile(quantiles).to_numpy(float))
            for threshold in thresholds:
                for op in ("le", "gt"):
                    dev_condition = (development[feature].le(threshold) if op == "le"
                                     else development[feature].gt(threshold)).to_numpy(bool)
                    coverage = float(dev_condition.mean())
                    if coverage < 0.05 or coverage > 0.70:
                        continue
                    val_condition = (validation[feature].le(threshold) if op == "le"
                                     else validation[feature].gt(threshold)).to_numpy(bool)
                    hold_condition = (holdout[feature].le(threshold) if op == "le"
                                      else holdout[feature].gt(threshold)).to_numpy(bool)
                    for action_cont in (False, True):
                        dev_route = apply_rule(dev_base, dev_condition, action_cont)
                        val_route = apply_rule(val_base, val_condition, action_cont)
                        dev_year = yearly_score(development, dev_route)
                        dev_improvements = [
                            dev_year[y]["wr"] - dev_base_year[y]["wr"] for y in ("2021", "2022")
                        ]
                        val = score(validation, val_route)
                        val_improvement = val["wr"] - val_base_score["wr"]
                        candidates.append({
                            "base": base_name,
                            "feature": feature,
                            "op": op,
                            "threshold": float(threshold),
                            "action": "continuation" if action_cont else "reversal",
                            "development_coverage": coverage,
                            "development": score(development, dev_route),
                            "development_by_year": dev_year,
                            "min_development_improvement": float(min(dev_improvements)),
                            "validation": val,
                            "validation_improvement": float(val_improvement),
                            "holdout": score(
                                holdout,
                                apply_rule(holdout[base_column].to_numpy(bool), hold_condition, action_cont),
                            ),
                            "holdout_by_year": yearly_score(
                                holdout,
                                apply_rule(holdout[base_column].to_numpy(bool), hold_condition, action_cont),
                            ),
                        })

    confirmed = [
        row for row in candidates
        if row["min_development_improvement"] >= 0.0
        and row["validation_improvement"] >= 0.0
        and row["development"]["wr"] > score(
            development, development[f"{row['base']}_cont"].to_numpy(bool)
        )["wr"]
    ]
    confirmed.sort(
        key=lambda row: (
            min(row["holdout_by_year"][y]["wr"] for y in row["holdout_by_year"]),
            row["holdout"]["wr"],
            row["validation"]["wr"],
        ),
        reverse=True,
    )

    baselines = {}
    for base_name in ("base_reversal", "base_v14"):
        route = frame[f"{base_name}_cont"].to_numpy(bool)
        baselines[base_name] = {
            "overall": score(frame, route),
            "by_year": yearly_score(frame, route),
        }
    report = {
        "protocol": {
            "development": "2021-2022",
            "confirmation": "2023",
            "untouched_holdout": "2024-2026",
            "frequency": "all setups retained",
            "candidate_family": "single causal liquidity threshold overriding reversal or V14 route",
        },
        "rows": int(len(frame)),
        "baselines": baselines,
        "candidate_count": len(candidates),
        "confirmed_before_holdout": len(confirmed),
        "best_confirmed_rules": confirmed[:30],
    }
    args.out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    pd.DataFrame(candidates).drop(
        columns=["development", "development_by_year", "validation", "holdout", "holdout_by_year"]
    ).to_csv(args.out.with_suffix(".candidates.csv"), index=False)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
