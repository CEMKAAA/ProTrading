#!/usr/bin/env python3
"""Walk-forward ORB candidate and two-channel portfolio research."""

from __future__ import annotations

import argparse
import csv
import itertools
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd


REGIME_NAMES = {
    0: "TREND_LOW_VOL",
    1: "TREND_HIGH_VOL",
    2: "RANGE_LOW_VOL",
    3: "RANGE_HIGH_VOL",
    4: "TRANSITION_PENDING",
    5: "TRANSITION_FRESH",
}


@dataclass(frozen=True)
class Rule:
    regimes: tuple[int, ...]
    blocked_rf: tuple[str, ...]


def read_event(path: Path) -> pd.DataFrame:
    frame = pd.read_csv(path, encoding="utf-16")
    frame["signal_time"] = pd.to_datetime(frame["signal_time"])
    frame["r"] = pd.to_numeric(frame["net_r"], errors="coerce").fillna(0.0)
    frame["rf"] = frame["rf_rule"].fillna("NONE").astype(str)
    frame["year"] = frame["year"].astype(int)
    return frame.sort_values("signal_time").reset_index(drop=True)


def selected(frame: pd.DataFrame, rule: Rule) -> pd.DataFrame:
    keep = frame["regime_bucket"].isin(rule.regimes) & ~frame["rf"].isin(rule.blocked_rf)
    return frame.loc[keep].copy()


def stats(frame: pd.DataFrame) -> dict[str, float]:
    r = frame["r"].to_numpy(dtype=float)
    if not len(r):
        return {"trades": 0, "wins": 0, "losses": 0, "wr": 0.0, "net_r": 0.0,
                "avg_r": 0.0, "pf": 0.0, "min_cum_r": 0.0, "max_dd_r": 0.0}
    eq = np.cumsum(r)
    peak = np.maximum.accumulate(np.maximum(eq, 0.0))
    won = r[r > 0].sum()
    lost = abs(r[r < 0].sum())
    resolved = np.count_nonzero(r)
    return {
        "trades": int(len(r)),
        "wins": int((r > 0).sum()),
        "losses": int((r < 0).sum()),
        "wr": float(100.0 * (r > 0).sum() / max(1, resolved)),
        "net_r": float(r.sum()),
        "avg_r": float(r.mean()),
        "pf": float(won / lost) if lost else (99.0 if won else 0.0),
        "min_cum_r": float(eq.min()),
        "max_dd_r": float((eq - peak).min()),
    }


def find_rule(frame: pd.DataFrame) -> Rule:
    """Discover on 2021-23, select among finalists on 2024 only."""
    train = frame[frame["year"] <= 2023].reset_index(drop=True)
    valid = frame[frame["year"] == 2024].reset_index(drop=True)
    train_r = train["r"].to_numpy(float)
    train_reg = train["regime_bucket"].to_numpy(int)
    train_rf = train["rf"].to_numpy(str)
    years = train["year"].to_numpy(int)
    unique_years = sorted(set(years))
    rf_names = sorted(x for x in set(frame["rf"].astype(str)) if x != "NONE")
    finalists: list[tuple[float, Rule]] = []

    for regime_count in range(2, 7):
        for regimes in itertools.combinations(range(6), regime_count):
            regime_keep = np.isin(train_reg, regimes)
            for blocked_count in range(4):
                for blocked in itertools.combinations(rf_names, blocked_count):
                    keep = regime_keep if not blocked else regime_keep & ~np.isin(train_rf, blocked)
                    count = int(keep.sum())
                    if count < 0.35 * len(train):
                        continue
                    yearly_net = []
                    enough = True
                    for year in unique_years:
                        ykeep = keep & (years == year)
                        if int(ykeep.sum()) < 8:
                            enough = False
                            break
                        yearly_net.append(float(train_r[ykeep].sum()))
                    if not enough:
                        continue
                    rr = train_r[keep]
                    eq = np.cumsum(rr)
                    peak = np.maximum.accumulate(np.maximum(eq, 0.0))
                    max_dd = float((eq - peak).min())
                    score = min(yearly_net) + 0.08 * float(rr.sum()) + 0.03 * max_dd
                    finalists.append((score, Rule(tuple(regimes), tuple(blocked))))

    finalists.sort(key=lambda item: item[0], reverse=True)
    shortlist = finalists[:30]
    if not shortlist:
        return Rule(tuple(range(6)), tuple())

    ranked = []
    for discovery_score, rule in shortlist:
        val = selected(valid, rule)
        if len(val) < 8:
            continue
        val_net = float(val["r"].sum())
        ranked.append((val_net > 0.0, float(val["r"].mean()), val_net, discovery_score, rule))
    if not ranked:
        return shortlist[0][1]
    ranked.sort(key=lambda item: item[:4], reverse=True)
    return ranked[0][-1]


def daily_series(frame: pd.DataFrame, rule: Rule) -> pd.Series:
    data = selected(frame, rule).copy()
    if data.empty:
        return pd.Series(dtype=float)
    data["date"] = data["signal_time"].dt.date
    return data.groupby("date")["r"].sum().sort_index()


def pair_stats(a: pd.Series, b: pd.Series) -> dict[str, float]:
    joined = pd.concat([a.rename("a"), b.rename("b")], axis=1).fillna(0.0).sort_index()
    # Equal capital allocation: one portfolio R is the sum of two half-risk legs.
    portfolio = 0.5 * joined["a"] + 0.5 * joined["b"]
    eq = portfolio.cumsum()
    peak = eq.cummax().clip(lower=0.0)
    overlap = (joined["a"] != 0) & (joined["b"] != 0)
    joint_loss = (joined["a"] < 0) & (joined["b"] < 0)
    active = (joined["a"] != 0) | (joined["b"] != 0)
    corr = joined.loc[active, ["a", "b"]].corr().iloc[0, 1] if active.sum() > 2 else np.nan
    return {
        "days": int(active.sum()),
        "overlap_days": int(overlap.sum()),
        "joint_loss_days": int(joint_loss.sum()),
        "joint_loss_pct_active": float(100.0 * joint_loss.sum() / max(1, active.sum())),
        "daily_corr": float(corr) if np.isfinite(corr) else 0.0,
        "net_portfolio_r": float(portfolio.sum()),
        "max_dd_portfolio_r": float((eq - peak).min()) if len(eq) else 0.0,
    }


def fmt_rule(rule: Rule) -> str:
    regimes = "+".join(REGIME_NAMES[i] for i in rule.regimes)
    blocked = "+".join(rule.blocked_rf) if rule.blocked_rf else "NONE"
    return f"allow={regimes}; block_rf={blocked}"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--events", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)

    frames = {}
    rules = {}
    summary_rows = []
    yearly_rows = []
    for path in sorted(args.events.glob("ORB_RegimeMatrix_Events_*.csv")):
        frame = read_event(path)
        job = str(frame["job_id"].iloc[0])
        rule = find_rule(frame)
        frames[job] = frame
        rules[job] = rule
        for split, subset in (
            ("all", frame),
            ("discovery_2021_2023", frame[frame.year <= 2023]),
            ("validation_2024", frame[frame.year == 2024]),
            ("test_2025_2026", frame[frame.year >= 2025]),
        ):
            row = {"job": job, "split": split, "rule": fmt_rule(rule), **stats(selected(subset, rule))}
            summary_rows.append(row)
        kept = selected(frame, rule)
        for year, group in kept.groupby("year"):
            yearly_rows.append({"job": job, "year": int(year), "rule": fmt_rule(rule), **stats(group)})

    pair_rows = []
    for left, right in itertools.combinations(sorted(frames), 2):
        row = {"left": left, "right": right, **pair_stats(
            daily_series(frames[left], rules[left]), daily_series(frames[right], rules[right]))}
        pair_rows.append(row)

    summary = pd.DataFrame(summary_rows)
    yearly = pd.DataFrame(yearly_rows)
    pairs = pd.DataFrame(pair_rows).sort_values(
        ["net_portfolio_r", "max_dd_portfolio_r"], ascending=[False, False]
    )
    summary.to_csv(args.out / "candidate_walk_forward_summary.csv", index=False)
    yearly.to_csv(args.out / "candidate_yearly.csv", index=False)
    pairs.to_csv(args.out / "pair_summary.csv", index=False)

    lines = ["# ORB JP225 Two-Channel Research", "", "## Method", "",
             "- Events: MT5 ORB v6.27 native-parity matrix exports.",
             "- Discovery: 2021-2023; validation: 2024; untouched test: 2025-2026.",
             "- Constraints: at least two regimes, at most three blocked RF classes, >=35% discovery retention.",
             "- Pair results use equal capital allocation (0.5 portfolio-risk weight per channel).", "",
             "## Candidate Rules", ""]
    for job in sorted(frames):
        all_row = summary[(summary.job == job) & (summary.split == "all")].iloc[0]
        test_row = summary[(summary.job == job) & (summary.split == "test_2025_2026")].iloc[0]
        lines += [f"- `{job}`: {fmt_rule(rules[job])}",
                  f"  - All: {int(all_row.trades)} trades, {all_row.wr:.2f}% WR, {all_row.net_r:+.2f}R, DD {all_row.max_dd_r:.2f}R",
                  f"  - Test: {int(test_row.trades)} trades, {test_row.wr:.2f}% WR, {test_row.net_r:+.2f}R, DD {test_row.max_dd_r:.2f}R"]
    lines += ["", "## Top Pairs", ""]
    for _, row in pairs.head(10).iterrows():
        lines.append(
            f"- `{row.left}` + `{row.right}`: net {row.net_portfolio_r:+.2f}R, "
            f"DD {row.max_dd_portfolio_r:.2f}R, corr {row.daily_corr:.3f}, "
            f"joint-loss {int(row.joint_loss_days)}/{int(row.days)} active days"
        )
    (args.out / "REPORT.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(summary.to_string(index=False))
    print("\nTOP PAIRS\n", pairs.head(10).to_string(index=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
