#!/usr/bin/env python3
"""Causal regime-to-signal-family research for LiqNarrativeSol Advanced.

The script parses exact MT5 internal-audit runs, attaches the causal V3 regime
known at each signal, and evaluates mappings learned only from prior years.
Selecting a family is causal; whether that family later emits a signal is not
used while choosing it.
"""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path

import pandas as pd


SUMMARY_RE = re.compile(
    r"SOL_INTERNAL_AUDIT build=(?P<build>\S+).*?"
    r"total=(?P<total>\d+).*?wins=(?P<wins>\d+).*?losses=(?P<losses>\d+)"
)
JOB_INPUT_RE = re.compile(r"InpValidationJobId=(?P<job>\S+)")
ROW_RE = re.compile(
    r"SOL_INTERNAL_AUDIT_ROW index=(?P<index>\d+) "
    r"available=(?P<available>\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}) "
    r"dir=(?P<direction>BUY|SELL) result=(?P<result>WIN|LOSS|OPEN|INVALID) "
    r"r=(?P<r>-?[\d.]+) entry=(?P<entry>-?[\d.]+) "
    r"sl=(?P<sl>-?[\d.]+) reason=(?P<reason>.*?)(?: id=|$)"
)


@dataclass
class AuditRun:
    job: str
    build: str
    total: int
    rows: list[dict]


def parse_runs(path: Path) -> list[AuditRun]:
    runs: list[AuditRun] = []
    active: AuditRun | None = None
    pending_job = ""
    with path.open("r", encoding="utf-16", errors="replace") as handle:
        for line in handle:
            job_input = JOB_INPUT_RE.search(line)
            if job_input:
                pending_job = job_input.group("job")
                continue
            summary = SUMMARY_RE.search(line)
            if summary:
                if active is not None and len(active.rows) == active.total:
                    runs.append(active)
                if not pending_job:
                    active = None
                    continue
                active = AuditRun(
                    job=pending_job,
                    build=summary.group("build"),
                    total=int(summary.group("total")),
                    rows=[],
                )
                continue
            if active is None or len(active.rows) >= active.total:
                continue
            row = ROW_RE.search(line)
            if not row:
                continue
            values = row.groupdict()
            active.rows.append(
                {
                    "job": active.job,
                    "available": pd.Timestamp(values["available"], tz="UTC"),
                    "direction": values["direction"],
                    "result": values["result"],
                    "r": float(values["r"]),
                    "entry": float(values["entry"]),
                    "sl": float(values["sl"]),
                    "reason": values["reason"],
                }
            )
    if active is not None and len(active.rows) == active.total:
        runs.append(active)
    return runs

def family_name(job: str) -> str | None:
    aliases = {
        "sol_pa_confirm_baseline_10y": "h2_h1_sw5_base",
        "sol_pa_confirm_h1_next_10y": "h2_h1_sw5_h1_next",
        "sol_pa_confirm_h1_break_10y": "h2_h1_sw5_h1_break",
        "sol_pa_confirm_m15_next_10y": "h2_h1_sw5_m15_next",
        "sol_pa_confirm_m15_break_10y": "h2_h1_sw5_m15_break",
        "sol_pa_confirm_m15_disp25_10y": "h2_h1_sw5_m15_disp25",
        "sol_pa_pool_h2_m30_sw5_10y": "h2_m30_sw5",
        "sol_pa_pool_h1_m30_sw5_10y": "h1_m30_sw5",
        "sol_pa_pool_h2_m15_sw5_10y": "h2_m15_sw5",
    }
    if job in aliases:
        return aliases[job]
    match = re.fullmatch(r"sol_regime_family_h2_h1_sw([2-8])_rows", job)
    if match:
        return f"h2_h1_sw{match.group(1)}"
    match = re.fullmatch(r"sol_pa_pool_(h[24])_h1_sw([2-8])_10y", job)
    if match:
        return f"{match.group(1)}_h1_sw{match.group(2)}"
    return None


def latest_family_runs(runs: list[AuditRun]) -> dict[str, AuditRun]:
    selected: dict[str, AuditRun] = {}
    for run in runs:
        family = family_name(run.job)
        if family is not None:
            selected[family] = run
    return selected


def attach_regimes(rows: pd.DataFrame, regimes: pd.DataFrame) -> pd.DataFrame:
    regime_cols = [
        "available",
        "core_regime_v3",
        "h1_h2_phase_family",
        "volatility_depth",
        "regime_age_bucket",
        "transition_status",
        "macro_direction_v3",
    ]
    state = regimes[regime_cols].copy()
    state["available"] = pd.to_datetime(state["available"], utc=True)
    state = state.sort_values("available").drop_duplicates("available", keep="last")
    rows = rows.sort_values("available")
    return pd.merge_asof(rows, state, on="available", direction="backward", tolerance=pd.Timedelta("36h"))


def summarize(frame: pd.DataFrame) -> dict:
    closed = frame[frame["result"].isin(["WIN", "LOSS"])].copy()
    wins = int(closed["result"].eq("WIN").sum())
    trades = len(closed)
    return {
        "trades": trades,
        "wins": wins,
        "losses": trades - wins,
        "wr": wins / trades if trades else None,
        "net_r": float(closed["r"].sum()),
    }


def choose_mapping(train: pd.DataFrame, keys: list[str], min_group: int, min_family: int) -> dict[tuple, str]:
    mapping: dict[tuple, str] = {}
    global_stats = train.groupby("family").agg(trades=("won", "size"), wins=("won", "sum"), net_r=("r", "sum"))
    global_stats = global_stats[global_stats["trades"] >= min_family]
    if global_stats.empty:
        return mapping
    global_stats["score"] = (global_stats["wins"] + 2.0) / (global_stats["trades"] + 4.0)
    default_family = global_stats.sort_values(["score", "net_r", "trades"], ascending=False).index[0]

    for group_values, part in train.groupby(keys, dropna=False):
        if not isinstance(group_values, tuple):
            group_values = (group_values,)
        stats = part.groupby("family").agg(trades=("won", "size"), wins=("won", "sum"), net_r=("r", "sum"))
        stats = stats[stats["trades"] >= min_group]
        if stats.empty:
            mapping[group_values] = default_family
            continue
        # Beta(2,2) shrinkage prevents tiny groups from winning the selector.
        stats["score"] = (stats["wins"] + 2.0) / (stats["trades"] + 4.0)
        mapping[group_values] = stats.sort_values(["score", "net_r", "trades"], ascending=False).index[0]
    mapping[("__DEFAULT__",)] = default_family
    return mapping


def apply_mapping(frame: pd.DataFrame, keys: list[str], mapping: dict[tuple, str]) -> pd.DataFrame:
    default = mapping.get(("__DEFAULT__",))
    wanted = frame[keys].apply(lambda row: mapping.get(tuple(row), default), axis=1)
    return frame[frame["family"].eq(wanted)].copy()


def walk_forward(all_rows: pd.DataFrame, keys: list[str], min_group: int, min_family: int) -> dict:
    years = sorted(int(year) for year in all_rows["year"].unique())
    annual: list[dict] = []
    selected_rows: list[pd.DataFrame] = []
    for year in years:
        train = all_rows[all_rows["year"] < year]
        test = all_rows[all_rows["year"] == year]
        if train["year"].nunique() < 2 or test.empty:
            continue
        mapping = choose_mapping(train, keys, min_group, min_family)
        selected = apply_mapping(test, keys, mapping)
        selected_rows.append(selected)
        result = summarize(selected)
        result.update({"year": year, "available_family_rows": len(test), "mapping_groups": len(mapping) - 1})
        annual.append(result)
    combined = pd.concat(selected_rows, ignore_index=True) if selected_rows else all_rows.iloc[0:0]
    valid_wrs = [row["wr"] for row in annual if row["wr"] is not None and row["trades"] >= 20]
    return {
        "keys": keys,
        "min_group": min_group,
        "min_family": min_family,
        "overall": summarize(combined),
        "min_year_wr": min(valid_wrs) if valid_wrs else None,
        "annual": annual,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--journal", type=Path, required=True)
    parser.add_argument("--regimes", type=Path, default=Path("logs/sol_market_regimes_v3.trades.csv"))
    parser.add_argument("--out", type=Path, default=Path("logs/sol_regime_signal_families.json"))
    args = parser.parse_args()

    runs = latest_family_runs(parse_runs(args.journal))
    if not runs:
        raise SystemExit("No supported exact-audit family runs found")
    frames = []
    for family, run in runs.items():
        frame = pd.DataFrame(run.rows)
        frame["family"] = family
        frames.append(frame)
    all_rows = pd.concat(frames, ignore_index=True)
    all_rows["won"] = all_rows["result"].eq("WIN").astype(int)
    all_rows["year"] = all_rows["available"].dt.year
    all_rows = attach_regimes(all_rows, pd.read_csv(args.regimes))
    all_rows = all_rows.dropna(subset=["core_regime_v3"]).copy()

    key_sets = [
        ["core_regime_v3"],
        ["h1_h2_phase_family"],
        ["core_regime_v3", "h1_h2_phase_family"],
        ["core_regime_v3", "volatility_depth"],
        ["core_regime_v3", "h1_h2_phase_family", "volatility_depth"],
        ["core_regime_v3", "regime_age_bucket", "transition_status"],
    ]
    reports = []
    for keys in key_sets:
        for min_group in (8, 12, 20, 30):
            reports.append(walk_forward(all_rows, keys, min_group, 40))
    reports.sort(
        key=lambda row: (
            row["min_year_wr"] if row["min_year_wr"] is not None else -1.0,
            row["overall"]["wr"] if row["overall"]["wr"] is not None else -1.0,
            row["overall"]["trades"],
        ),
        reverse=True,
    )

    family_summary = {
        family: summarize(frame)
        for family, frame in all_rows.groupby("family", sort=True)
    }
    payload = {
        "status": "RESEARCH_ONLY_CAUSAL_EXPANDING_YEAR",
        "families": sorted(runs),
        "covered_rows": len(all_rows),
        "family_summary": family_summary,
        "best": reports[:12],
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2))


if __name__ == "__main__":
    main()
