#!/usr/bin/env python3
"""Compare consecutive Sol internal-audit runs from an MT5 agent journal."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

import pandas as pd


SUMMARY_RE = re.compile(
    r"SOL_INTERNAL_AUDIT build=(?P<build>\S+) window=(?P<window>\S+) "
    r"total=(?P<total>\d+) wins=(?P<wins>\d+) losses=(?P<losses>\d+) "
    r"open=(?P<open>\d+) invalid=(?P<invalid>\d+) wr=(?P<wr>-?[\d.]+) "
    r"netR=(?P<net_r>-?[\d.]+)"
)
ROW_RE = re.compile(
    r"SOL_INTERNAL_AUDIT_ROW index=(?P<index>\d+) "
    r"available=(?P<available>\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}) "
    r"dir=(?P<direction>BUY|SELL) result=(?P<result>\S+) "
    r"r=(?P<r>-?[\d.]+) entry=(?P<entry>-?[\d.]+) "
    r"sl=(?P<sl>-?[\d.]+) reason=(?P<reason>.*?) id="
)


def parse_runs(path: Path, build: str) -> list[dict]:
    runs: list[dict] = []
    current: dict | None = None
    with path.open("r", encoding="utf-16", errors="replace") as handle:
        for line in handle:
            summary = SUMMARY_RE.search(line)
            if summary:
                if current is not None:
                    runs.append(current)
                values = summary.groupdict()
                current = {
                    "summary": {
                        **values,
                        **{key: int(values[key]) for key in ("total", "wins", "losses", "open", "invalid")},
                        "wr": float(values["wr"]),
                        "net_r": float(values["net_r"]),
                    },
                    "rows": [],
                } if values["build"] == build else None
                continue
            if current is None:
                continue
            row = ROW_RE.search(line)
            if row:
                values = row.groupdict()
                current["rows"].append(
                    {
                        **values,
                        "index": int(values["index"]),
                        "r": float(values["r"]),
                        "entry": float(values["entry"]),
                        "sl": float(values["sl"]),
                    }
                )
    if current is not None:
        runs.append(current)
    return [run for run in runs if len(run["rows"]) == run["summary"]["total"]]


def aggregate(rows: list[dict], columns: list[str]) -> list[dict]:
    frame = pd.DataFrame(rows)
    frame["available"] = pd.to_datetime(frame["available"], format="%Y.%m.%d %H:%M", utc=True)
    frame["won"] = frame["result"].eq("WIN").astype(int)
    frame["sl_distance"] = (frame["entry"] - frame["sl"]).abs()
    frame["year"] = frame["available"].dt.year
    frame["month"] = frame["available"].dt.month
    frame["season"] = pd.cut(
        frame["month"], bins=[0, 2, 5, 8, 11, 12],
        labels=["winter", "spring", "summer", "autumn", "winter2"], include_lowest=True,
    ).astype(str).replace("winter2", "winter")
    frame["route"] = frame["reason"].str.contains("sol_session_continuation").map(
        {True: "continuation", False: "reversal"}
    )
    grouped = frame.groupby(columns, dropna=False).agg(
        trades=("won", "size"), wins=("won", "sum"), net_r=("r", "sum"),
        median_entry=("entry", "median"), median_sl_distance=("sl_distance", "median"),
    ).reset_index()
    grouped["wr"] = grouped["wins"] / grouped["trades"]
    return grouped.to_dict(orient="records")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("journal", type=Path)
    parser.add_argument("--build", required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--labels", nargs="+")
    args = parser.parse_args()

    runs = parse_runs(args.journal, args.build)
    labels = tuple(args.labels or ("fixed_4000", "price_normalized_4000"))
    if len(runs) < len(labels):
        raise SystemExit(f"Expected at least {len(labels)} complete runs, found {len(runs)}")
    selected = runs[-len(labels):]
    report = {"build": args.build, "runs": {}}
    for label, run in zip(labels, selected):
        report["runs"][label] = {
            "summary": run["summary"],
            "by_year": aggregate(run["rows"], ["year"]),
            "by_season": aggregate(run["rows"], ["season"]),
            "by_route": aggregate(run["rows"], ["route"]),
            "by_year_route": aggregate(run["rows"], ["year", "route"]),
        }
        pd.DataFrame(run["rows"]).to_csv(args.out.with_name(f"{args.out.stem}.{label}.csv"), index=False)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
