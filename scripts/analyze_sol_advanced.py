#!/usr/bin/env python3
"""Walk-forward research harness for LiqNarrativeSol_Advanced.

The script consumes MT5 tester journal blocks emitted by the Advanced EA. It
pairs all-reversal and all-continuation runs by signal timestamp, then evaluates
causal routing models without changing the production SolVersion EA.
"""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.base import clone
from sklearn.ensemble import ExtraTreesClassifier, RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, balanced_accuracy_score
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler


SUMMARY_RE = re.compile(
    r"SOL_INTERNAL_AUDIT build=(?P<build>\S+).*?total=(?P<total>\d+).*?"
    r"wins=(?P<wins>\d+).*?losses=(?P<losses>\d+).*?wr=(?P<wr>[\d.]+)"
)
ROW_RE = re.compile(
    r"SOL_INTERNAL_AUDIT_ROW index=(?P<index>\d+) available=(?P<available>\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}) "
    r"dir=(?P<dir>BUY|SELL) result=(?P<result>WIN|LOSS|OPEN|INVALID) r=(?P<r>-?[\d.]+) "
    r"entry=(?P<entry>-?[\d.]+) sl=(?P<sl>-?[\d.]+) reason=(?P<reason>.*?)(?: id=|$)"
)
FEATURE_RE = re.compile(r"\|adv_(?P<name>[a-z0-9]+)=(?P<value>-?[\d.]+)")
FEATURE_ROW_RE = re.compile(r"SOL_ADV_FEATURE_ROW index=(?P<index>\d+) part=(?P<part>\d+) data=(?P<data>.*)$")


@dataclass
class Run:
    build: str
    total: int
    wins: int
    losses: int
    wr: float
    mode: str
    rows: list[dict]


def parse_journal(path: Path) -> list[Run]:
    runs: list[Run] = []
    active: Run | None = None
    with path.open("r", encoding="utf-16", errors="replace") as handle:
        for raw in handle:
            summary = SUMMARY_RE.search(raw)
            if summary and "sol-advanced" in summary.group("build"):
                active = Run(
                    build=summary.group("build"),
                    total=int(summary.group("total")),
                    wins=int(summary.group("wins")),
                    losses=int(summary.group("losses")),
                    wr=float(summary.group("wr")),
                    mode="unknown",
                    rows=[],
                )
                runs.append(active)
                continue
            if active is None:
                continue
            feature_row = FEATURE_ROW_RE.search(raw)
            if feature_row and active.rows:
                row_index = int(feature_row.group("index"))
                if active.rows[-1]["index"] == row_index:
                    payload = feature_row.group("data")
                    active.rows[-1].update({
                        match.group("name"): float(match.group("value"))
                        for match in FEATURE_RE.finditer(payload)
                    })
                    if "sol_session_continuation" in payload:
                        active.mode = "continuation"
                    elif "sol_session_reversal" in payload:
                        active.mode = "reversal"
                continue
            if len(active.rows) >= active.total:
                continue
            match = ROW_RE.search(raw)
            if not match:
                continue
            reason = match.group("reason")
            if "sol_session_continuation" in reason:
                active.mode = "continuation"
            elif "sol_session_reversal" in reason:
                active.mode = "reversal"
            row = {
                "index": int(match.group("index")),
                "available": pd.Timestamp(match.group("available"), tz="UTC"),
                "dir": match.group("dir"),
                "result": match.group("result"),
                "r": float(match.group("r")),
                "entry": float(match.group("entry")),
                "sl": float(match.group("sl")),
            }
            row.update({m.group("name"): float(m.group("value")) for m in FEATURE_RE.finditer(reason)})
            active.rows.append(row)
    complete = [run for run in runs if len(run.rows) == run.total]
    for run in complete:
        if run.mode != "unknown" or not run.rows:
            continue
        first = run.rows[0]
        source_dir = int(first.get("src", 0))
        output_dir = 1 if first["dir"] == "BUY" else -1
        if source_dir:
            run.mode = "reversal" if output_dir == source_dir else "continuation"
    return complete


def best_run(runs: list[Run], mode: str) -> Run:
    candidates = [run for run in runs if run.mode == mode]
    if not candidates:
        raise RuntimeError(f"No complete {mode} run found")
    # Later runs contain the longest feature payload after logger refinements.
    return max(candidates, key=lambda run: (len(pd.DataFrame(run.rows).columns), runs.index(run)))


def paired_frame(reversal: Run, continuation: Run) -> pd.DataFrame:
    rev = pd.DataFrame(reversal.rows).add_suffix("_rev")
    cont = pd.DataFrame(continuation.rows).add_suffix("_cont")
    frame = rev.merge(
        cont,
        left_on=["index_rev", "available_rev"],
        right_on=["index_cont", "available_cont"],
        how="inner",
        validate="one_to_one",
    )
    frame["available"] = frame["available_rev"]
    frame = frame.sort_values("available").reset_index(drop=True)
    frame["year"] = frame["available"].dt.year
    if "h_rev" in frame:
        angle = 2.0 * np.pi * frame["h_rev"] / 24.0
        frame["hour_sin_rev"] = np.sin(angle)
        frame["hour_cos_rev"] = np.cos(angle)
    source = frame["src_rev"]
    prior_source = source.shift(1)
    prior_time = frame["available"].shift(1)
    prior_entry = frame["entry_rev"].shift(1)
    frame["seq_same_prev_rev"] = (source == prior_source).astype(float)
    frame["seq_age_hours_rev"] = (frame["available"] - prior_time).dt.total_seconds() / 3600.0
    frame["seq_prev_move_r_rev"] = prior_source * (frame["entry_rev"] - prior_entry) / 400.0
    frame["seq_current_move_r_rev"] = source * (frame["entry_rev"] - prior_entry) / 400.0
    frame["seq_source_sum3_rev"] = source.shift(1).rolling(3, min_periods=1).sum()
    frame["seq_source_sum5_rev"] = source.shift(1).rolling(5, min_periods=1).sum()
    frame["seq_quality_mean3_rev"] = frame["q_rev"].shift(1).rolling(3, min_periods=1).mean()
    frame["seq_quality_delta_rev"] = frame["q_rev"] - frame["q_rev"].shift(1)
    direction_flip = source.ne(prior_source).astype(float)
    frame["seq_flips3_rev"] = direction_flip.shift(1).rolling(3, min_periods=1).sum()
    frame["seq_flips5_rev"] = direction_flip.shift(1).rolling(5, min_periods=1).sum()
    times = frame["available"].astype("int64").to_numpy() / 1e9
    frame["seq_count24h_rev"] = [int(np.searchsorted(times, t, side="left") - np.searchsorted(times, t - 86400, side="left")) for t in times]
    frame["seq_count72h_rev"] = [int(np.searchsorted(times, t, side="left") - np.searchsorted(times, t - 259200, side="left")) for t in times]
    frame["rev_win"] = frame["result_rev"].eq("WIN")
    frame["cont_win"] = frame["result_cont"].eq("WIN")
    frame["oracle_win"] = frame["rev_win"] | frame["cont_win"]
    frame["target_cont"] = np.where(
        frame["cont_win"] & ~frame["rev_win"], 1,
        np.where(frame["rev_win"] & ~frame["cont_win"], 0, np.nan),
    )
    return frame.sort_values("available").reset_index(drop=True)


def feature_columns(frame: pd.DataFrame) -> list[str]:
    excluded = {"dw", "h"}  # No weekday/session memorization in the learned model.
    columns = []
    for column in frame.columns:
        if not column.endswith("_rev"):
            continue
        base = column[:-4]
        if base in excluded or base in {"index", "r", "entry", "sl"}:
            continue
        if base in {"available", "dir", "result"}:
            continue
        if pd.api.types.is_numeric_dtype(frame[column]):
            columns.append(column)
    return columns


def routed_win(frame: pd.DataFrame, pred_cont: np.ndarray) -> np.ndarray:
    return np.where(pred_cont.astype(bool), frame["cont_win"], frame["rev_win"]).astype(bool)


def expanding_walk_forward(frame: pd.DataFrame, columns: list[str]) -> tuple[pd.DataFrame, pd.DataFrame]:
    models = {
        "logistic": make_pipeline(
            SimpleImputer(strategy="median"), StandardScaler(),
            LogisticRegression(C=0.15, max_iter=3000, class_weight="balanced"),
        ),

        "random_forest": make_pipeline(
            SimpleImputer(strategy="median"),
            RandomForestClassifier(n_estimators=500, max_depth=4, min_samples_leaf=30,
                                   max_features=0.55, class_weight="balanced", random_state=17),
        ),
        "extra_trees": make_pipeline(
            SimpleImputer(strategy="median"),
            ExtraTreesClassifier(n_estimators=500, max_depth=5, min_samples_leaf=25,
                                 max_features=0.65, class_weight="balanced", random_state=17),
        ),
    }
    labeled = frame[frame["target_cont"].notna()].copy()
    years = sorted(frame["year"].unique())
    predictions: list[pd.DataFrame] = []
    metrics: list[dict] = []
    for test_year in years[2:]:
        train = labeled[labeled["year"] < test_year]
        test_all = frame[frame["year"] == test_year]
        test_labeled = labeled[labeled["year"] == test_year]
        if len(train) < 150 or test_all.empty:
            continue
        for name, estimator in models.items():
            fitted = clone(estimator).fit(train[columns], train["target_cont"].astype(int))
            pred = fitted.predict(test_all[columns]).astype(int)
            wins = routed_win(test_all, pred)
            row = test_all[["available", "year", "rev_win", "cont_win"]].copy()
            row["model"] = name
            row["pred_cont"] = pred
            row["win"] = wins
            predictions.append(row)
            metric = {
                "model": name,
                "test_year": int(test_year),
                "train_rows": int(len(train)),
                "trades": int(len(test_all)),
                "wins": int(wins.sum()),
                "wr": float(wins.mean()),
            }
            if not test_labeled.empty:
                labeled_pred = fitted.predict(test_labeled[columns]).astype(int)
                metric["route_accuracy"] = float(accuracy_score(test_labeled["target_cont"], labeled_pred))
                metric["route_balanced_accuracy"] = float(
                    balanced_accuracy_score(test_labeled["target_cont"], labeled_pred)
                )
            metrics.append(metric)
    return pd.DataFrame(metrics), pd.concat(predictions, ignore_index=True) if predictions else pd.DataFrame()


def summarize(frame: pd.DataFrame, metrics: pd.DataFrame, predictions: pd.DataFrame) -> dict:
    by_year = frame.groupby("year").agg(
        trades=("year", "size"), rev_wins=("rev_win", "sum"), cont_wins=("cont_win", "sum"),
        oracle_wins=("oracle_win", "sum"),
    )
    by_year["rev_wr"] = by_year["rev_wins"] / by_year["trades"]
    by_year["cont_wr"] = by_year["cont_wins"] / by_year["trades"]
    by_year["oracle_wr"] = by_year["oracle_wins"] / by_year["trades"]
    model_summary = []
    if not predictions.empty:
        for model, group in predictions.groupby("model"):
            model_summary.append({
                "model": model,
                "oos_trades": int(len(group)),
                "oos_wins": int(group["win"].sum()),
                "oos_wr": float(group["win"].mean()),
                "min_year_wr": float(group.groupby("year")["win"].mean().min()),
            })
    return {
        "period": [str(frame["available"].min()), str(frame["available"].max())],
        "trades": int(len(frame)),
        "reversal_wr": float(frame["rev_win"].mean()),
        "continuation_wr": float(frame["cont_win"].mean()),
        "oracle_wr": float(frame["oracle_win"].mean()),
        "ambiguous_both_win": int((frame["rev_win"] & frame["cont_win"]).sum()),
        "ambiguous_both_loss": int((~frame["rev_win"] & ~frame["cont_win"]).sum()),
        "feature_count": len(feature_columns(frame)),
        "features": feature_columns(frame),
        "by_year": by_year.reset_index().to_dict(orient="records"),
        "walk_forward": model_summary,
        "folds": metrics.to_dict(orient="records"),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("journal", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    runs = parse_journal(args.journal)
    reversal = best_run(runs, "reversal")
    continuation = best_run(runs, "continuation")
    frame = paired_frame(reversal, continuation)
    columns = feature_columns(frame)
    metrics, predictions = expanding_walk_forward(frame, columns)
    report = summarize(frame, metrics, predictions)
    payload = json.dumps(report, indent=2, default=str)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(payload + "\n", encoding="utf-8")
        frame.to_csv(args.out.with_suffix(".dataset.csv"), index=False)
        if not predictions.empty:
            predictions.to_csv(args.out.with_suffix(".oos.csv"), index=False)
    print(payload)


if __name__ == "__main__":
    main()
