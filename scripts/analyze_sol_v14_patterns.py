#!/usr/bin/env python3
"""Causal pattern research for the JP225 LiqNarrativeSol V14 audit.

The script deliberately separates development, validation, and forward periods.
It never changes an EA and never uses future bars as model inputs.  The V14
trade outcome is joined to market-state features logged at the same signal time
by earlier controlled Advanced runs.
"""

from __future__ import annotations

import argparse
import json
import math
import re
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.base import clone
from sklearn.ensemble import ExtraTreesClassifier, RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler


SUMMARY_RE = re.compile(
    r"SOL_INTERNAL_AUDIT build=(?P<build>\S+).*?window=(?P<window>\S+) "
    r"total=(?P<total>\d+).*?wins=(?P<wins>\d+).*?losses=(?P<losses>\d+).*?"
    r"open=(?P<open>\d+).*?invalid=(?P<invalid>\d+).*?wr=(?P<wr>[\d.]+).*?netR=(?P<netr>-?[\d.]+)"
)
ROW_RE = re.compile(
    r"SOL_INTERNAL_AUDIT_ROW index=(?P<index>\d+) "
    r"available=(?P<available>\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}) "
    r"dir=(?P<dir>BUY|SELL) result=(?P<result>WIN|LOSS|OPEN|INVALID) "
    r"r=(?P<r>-?[\d.]+) entry=(?P<entry>-?[\d.]+) sl=(?P<sl>-?[\d.]+) "
    r"reason=(?P<reason>.*?)(?: id=|$)"
)
QUALITY_RE = re.compile(r"sol_frontier_q=(?P<quality>-?[\d.]+)")


@dataclass
class AuditRun:
    build: str
    window: str
    total: int
    wins: int
    losses: int
    open_count: int
    invalid: int
    wr: float
    net_r: float
    rows: list[dict]


def parse_v14_run(path: Path, build: str, expected_total: int) -> AuditRun:
    runs: list[AuditRun] = []
    active: AuditRun | None = None
    with path.open("r", encoding="utf-16", errors="replace") as handle:
        for raw in handle:
            summary = SUMMARY_RE.search(raw)
            if summary:
                active = None
                if summary.group("build") == build and int(summary.group("total")) == expected_total:
                    active = AuditRun(
                        build=summary.group("build"),
                        window=summary.group("window"),
                        total=int(summary.group("total")),
                        wins=int(summary.group("wins")),
                        losses=int(summary.group("losses")),
                        open_count=int(summary.group("open")),
                        invalid=int(summary.group("invalid")),
                        wr=float(summary.group("wr")),
                        net_r=float(summary.group("netr")),
                        rows=[],
                    )
                    runs.append(active)
                continue
            if active is None or len(active.rows) >= active.total:
                continue
            match = ROW_RE.search(raw)
            if not match:
                continue
            reason = match.group("reason")
            quality = QUALITY_RE.search(reason)
            route = "continuation" if "sol_session_continuation" in reason else "reversal"
            active.rows.append(
                {
                    "index": int(match.group("index")),
                    "available": pd.Timestamp(match.group("available"), tz="UTC"),
                    "dir": match.group("dir"),
                    "result": match.group("result"),
                    "r": float(match.group("r")),
                    "entry": float(match.group("entry")),
                    "sl": float(match.group("sl")),
                    "route": route,
                    "quality": float(quality.group("quality")) if quality else np.nan,
                    "reason": reason,
                }
            )
    complete = [run for run in runs if len(run.rows) == run.total]
    if not complete:
        sizes = [len(run.rows) for run in runs]
        raise RuntimeError(f"No complete {build} total={expected_total} run; row counts={sizes}")
    return complete[-1]


def wilson_lower(wins: int, total: int, z: float = 1.96) -> float:
    if total <= 0:
        return float("nan")
    p = wins / total
    den = 1.0 + z * z / total
    center = p + z * z / (2.0 * total)
    margin = z * math.sqrt((p * (1.0 - p) + z * z / (4.0 * total)) / total)
    return (center - margin) / den


def add_causal_calendar_features(frame: pd.DataFrame) -> pd.DataFrame:
    out = frame.sort_values("available").reset_index(drop=True).copy()
    ts = out["available"]
    out["year"] = ts.dt.year
    out["month"] = ts.dt.month
    out["quarter"] = ts.dt.quarter
    out["weekday"] = ts.dt.weekday
    out["weekday_name"] = ts.dt.day_name().str[:3]
    out["hour"] = ts.dt.hour
    out["session_2h"] = (out["hour"] // 2) * 2
    out["season"] = np.select(
        [out["month"].isin([12, 1, 2]), out["month"].isin([3, 4, 5]), out["month"].isin([6, 7, 8])],
        ["winter", "spring", "summer"],
        default="autumn",
    )
    out["is_buy"] = out["dir"].eq("BUY").astype(int)
    out["is_continuation"] = out["route"].eq("continuation").astype(int)
    out["won"] = out["result"].eq("WIN").astype(int)
    out["hour_sin"] = np.sin(2.0 * np.pi * out["hour"] / 24.0)
    out["hour_cos"] = np.cos(2.0 * np.pi * out["hour"] / 24.0)
    out["weekday_sin"] = np.sin(2.0 * np.pi * out["weekday"] / 7.0)
    out["weekday_cos"] = np.cos(2.0 * np.pi * out["weekday"] / 7.0)
    out["month_sin"] = np.sin(2.0 * np.pi * (out["month"] - 1) / 12.0)
    out["month_cos"] = np.cos(2.0 * np.pi * (out["month"] - 1) / 12.0)

    # These use only information known when the current signal becomes available.
    # Prior trade outcomes are deliberately excluded because same-direction trades
    # can still be open and their eventual result would leak future information.
    out["prev_same_dir"] = out["dir"].eq(out["dir"].shift(1)).astype(float)
    out["signal_age_h"] = ts.diff().dt.total_seconds() / 3600.0
    return out


def merge_market_features(v14: pd.DataFrame, feature_csv: Path) -> tuple[pd.DataFrame, dict]:
    features = pd.read_csv(feature_csv, low_memory=False)
    features["available"] = pd.to_datetime(features["available"], utc=True)
    keep = ["available"]
    for column in features.columns:
        if not column.endswith("_rev"):
            continue
        base = column[:-4]
        if base in {"index", "available", "dir", "result", "r", "entry", "sl", "dw", "h"}:
            continue
        if pd.api.types.is_numeric_dtype(features[column]):
            keep.append(column)
    slim = features[keep].drop_duplicates("available", keep="last")
    merged = v14.merge(slim, on="available", how="left", validate="one_to_one")
    coverage = {
        "v14_rows": int(len(v14)),
        "matched_rows": int(merged[keep[1:]].notna().any(axis=1).sum()),
        "market_feature_count": len(keep) - 1,
    }
    return merged, coverage


def group_table(frame: pd.DataFrame, columns: list[str]) -> pd.DataFrame:
    grouped = frame.groupby(columns, dropna=False).agg(
        trades=("won", "size"), wins=("won", "sum"), net_r=("r", "sum"), avg_r=("r", "mean")
    ).reset_index()
    grouped["wr"] = grouped["wins"] / grouped["trades"]
    grouped["wilson_low"] = [wilson_lower(int(w), int(n)) for w, n in zip(grouped["wins"], grouped["trades"])]
    return grouped.sort_values(["wilson_low", "trades"], ascending=[False, False])


def metrics(frame: pd.DataFrame, selected: np.ndarray | pd.Series | None = None) -> dict:
    data = frame if selected is None else frame.loc[np.asarray(selected, dtype=bool)]
    if data.empty:
        return {"trades": 0, "wins": 0, "wr": None, "net_r": 0.0, "avg_r": None, "wilson_low": None}
    wins = int(data["won"].sum())
    return {
        "trades": int(len(data)),
        "wins": wins,
        "wr": float(data["won"].mean()),
        "net_r": float(data["r"].sum()),
        "avg_r": float(data["r"].mean()),
        "wilson_low": float(wilson_lower(wins, len(data))),
    }


def model_feature_sets(frame: pd.DataFrame) -> dict[str, list[str]]:
    calendar = [
        "hour_sin", "hour_cos", "weekday_sin", "weekday_cos", "month_sin", "month_cos",
        "is_buy", "is_continuation", "quality", "signal_age_h", "prev_same_dir",
    ]
    market = [column for column in frame.columns if column.endswith("_rev")]
    market = [column for column in market if pd.api.types.is_numeric_dtype(frame[column])]
    return {
        "calendar": calendar,
        "market": market,
        "calendar_market": calendar + market,
    }


def estimators() -> dict[str, object]:
    return {
        "logistic": make_pipeline(
            SimpleImputer(strategy="median"),
            StandardScaler(),
            LogisticRegression(C=0.08, max_iter=4000, class_weight="balanced", random_state=23),
        ),
        "random_forest": make_pipeline(
            SimpleImputer(strategy="median"),
            RandomForestClassifier(
                n_estimators=600, max_depth=4, min_samples_leaf=30, max_features=0.45,
                class_weight="balanced", random_state=23, n_jobs=1,
            ),
        ),
        "extra_trees": make_pipeline(
            SimpleImputer(strategy="median"),
            ExtraTreesClassifier(
                n_estimators=600, max_depth=5, min_samples_leaf=25, max_features=0.50,
                class_weight="balanced", random_state=23, n_jobs=1,
            ),
        ),
    }


def threshold_candidates(train_prob: np.ndarray) -> list[tuple[str, float]]:
    candidates = [("all", -1.0)]
    for retention in (0.90, 0.80, 0.70, 0.60):
        candidates.append((f"keep_{int(retention * 100)}pct", float(np.quantile(train_prob, 1.0 - retention))))
    return candidates


def fixed_split_research(frame: pd.DataFrame, sets: dict[str, list[str]]) -> tuple[pd.DataFrame, pd.DataFrame]:
    development = frame[frame["year"] <= 2022]
    validation = frame[frame["year"] == 2023]
    forward = frame[frame["year"] >= 2024]
    rows: list[dict] = []
    predictions: list[pd.DataFrame] = []
    for set_name, columns in sets.items():
        for model_name, estimator in estimators().items():
            fitted = clone(estimator).fit(development[columns], development["won"])
            dev_prob = fitted.predict_proba(development[columns])[:, 1]
            val_prob = fitted.predict_proba(validation[columns])[:, 1]
            forward_prob = fitted.predict_proba(forward[columns])[:, 1]
            candidates = threshold_candidates(dev_prob)
            candidate_scores: list[tuple[float, float, str, float, dict]] = []
            for label, threshold in candidates:
                selected = val_prob >= threshold
                score = metrics(validation, selected)
                retention = score["trades"] / max(1, len(validation))
                # Validation selects one operating point. Net R breaks WR ties;
                # lower than 60% retention is never considered.
                if retention >= 0.60:
                    candidate_scores.append((score["wr"] or 0.0, score["net_r"], label, threshold, score))
            _, _, label, threshold, val_score = max(candidate_scores)
            for period_name, period_frame, prob in (
                ("development", development, dev_prob),
                ("validation", validation, val_prob),
                ("forward", forward, forward_prob),
            ):
                selected = prob >= threshold
                score = metrics(period_frame, selected)
                rows.append(
                    {
                        "feature_set": set_name,
                        "model": model_name,
                        "threshold_label": label,
                        "threshold": threshold,
                        "period": period_name,
                        "period_start": str(period_frame["available"].min()),
                        "period_end": str(period_frame["available"].max()),
                        "available_trades": int(len(period_frame)),
                        "retention": score["trades"] / max(1, len(period_frame)),
                        **score,
                    }
                )
            prediction = forward[["available", "year", "won", "r"]].copy()
            prediction["feature_set"] = set_name
            prediction["model"] = model_name
            prediction["prob_win"] = forward_prob
            prediction["selected"] = forward_prob >= threshold
            predictions.append(prediction)
    return pd.DataFrame(rows), pd.concat(predictions, ignore_index=True)


def expanding_oos(frame: pd.DataFrame, sets: dict[str, list[str]]) -> pd.DataFrame:
    rows: list[dict] = []
    for test_year in sorted(frame["year"].unique()):
        train = frame[frame["year"] < test_year]
        test = frame[frame["year"] == test_year]
        if len(train) < 250 or len(test) < 20:
            continue
        for set_name, columns in sets.items():
            for model_name, estimator in estimators().items():
                fitted = clone(estimator).fit(train[columns], train["won"])
                train_prob = fitted.predict_proba(train[columns])[:, 1]
                test_prob = fitted.predict_proba(test[columns])[:, 1]
                # Predefined 80% retention avoids choosing a threshold on the test year.
                threshold = float(np.quantile(train_prob, 0.20))
                selected = test_prob >= threshold
                score = metrics(test, selected)
                rows.append(
                    {
                        "test_year": int(test_year),
                        "train_rows": int(len(train)),
                        "feature_set": set_name,
                        "model": model_name,
                        "threshold": threshold,
                        "available_trades": int(len(test)),
                        "retention": score["trades"] / len(test),
                        **score,
                    }
                )
    return pd.DataFrame(rows)


def stable_calendar_rules(frame: pd.DataFrame) -> pd.DataFrame:
    development = frame[frame["year"] <= 2022]
    validation = frame[frame["year"] == 2023]
    forward = frame[frame["year"] >= 2024]
    specs = [
        ["hour"], ["session_2h"], ["weekday_name"], ["month"], ["season"], ["route"], ["dir"],
        ["session_2h", "route"], ["session_2h", "dir"], ["weekday_name", "route"],
        ["season", "route"], ["quarter", "route"],
    ]
    rows: list[dict] = []
    for columns in specs:
        dev_table = group_table(development, columns)
        # Only development-derived groups are evaluated later.
        for record in dev_table.to_dict(orient="records"):
            if record["trades"] < 20:
                continue
            key = tuple(record[column] for column in columns)
            masks = {}
            for name, period in (("development", development), ("validation", validation), ("forward", forward)):
                mask = np.ones(len(period), dtype=bool)
                for column, value in zip(columns, key):
                    mask &= period[column].eq(value).to_numpy()
                masks[name] = metrics(period, mask)
            rows.append(
                {
                    "feature": "+".join(columns),
                    "value": "|".join(str(value) for value in key),
                    **{f"dev_{key2}": value2 for key2, value2 in masks["development"].items()},
                    **{f"val_{key2}": value2 for key2, value2 in masks["validation"].items()},
                    **{f"fwd_{key2}": value2 for key2, value2 in masks["forward"].items()},
                }
            )
    result = pd.DataFrame(rows)
    if result.empty:
        return result
    result["stable_score"] = result[["dev_wr", "val_wr", "fwd_wr"]].min(axis=1, skipna=False)
    return result.sort_values(["stable_score", "fwd_trades"], ascending=[False, False])


def summarize(
    run: AuditRun,
    frame: pd.DataFrame,
    coverage: dict,
    fixed: pd.DataFrame,
    expanding: pd.DataFrame,
    stable: pd.DataFrame,
) -> dict:
    yearly = group_table(frame, ["year"]).sort_values("year")
    forward_rows = fixed[fixed["period"] == "forward"].sort_values(["wr", "net_r"], ascending=False)
    expanding_summary = pd.DataFrame()
    if not expanding.empty:
        expanding_summary = expanding.groupby(["feature_set", "model"]).agg(
            trades=("trades", "sum"), wins=("wins", "sum"), net_r=("net_r", "sum"),
            avg_retention=("retention", "mean"), min_year_wr=("wr", "min"),
        ).reset_index()
        expanding_summary["wr"] = expanding_summary["wins"] / expanding_summary["trades"]
        expanding_summary = expanding_summary.sort_values(["wr", "net_r"], ascending=False)
    return {
        "source": {
            "build": run.build,
            "window_label": run.window,
            "period": [str(frame["available"].min()), str(frame["available"].max())],
            "note": "The requested 10Y window contains only the broker history shown by period.",
            "summary": metrics(frame),
            "journal_summary": {"wins": run.wins, "losses": run.losses, "wr": run.wr, "net_r": run.net_r},
            "feature_join": coverage,
        },
        "split": {
            "development": "through 2022",
            "validation": "2023",
            "forward": "2024 onward",
        },
        "by_year": yearly.to_dict(orient="records"),
        "best_fixed_split_forward": forward_rows.head(12).to_dict(orient="records"),
        "expanding_oos_summary": expanding_summary.head(12).to_dict(orient="records"),
        "stable_calendar_groups": stable.head(30).to_dict(orient="records") if not stable.empty else [],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("journal", type=Path)
    parser.add_argument("feature_csv", type=Path)
    parser.add_argument("--build", default="2026-07-18.sol-jp225-session-regime-v14")
    parser.add_argument("--total", type=int, default=975)
    parser.add_argument("--out", type=Path, default=Path("logs/sol_v14_pattern_research.json"))
    args = parser.parse_args()

    run = parse_v14_run(args.journal, args.build, args.total)
    v14 = add_causal_calendar_features(pd.DataFrame(run.rows))
    frame, coverage = merge_market_features(v14, args.feature_csv)
    sets = model_feature_sets(frame)
    fixed, predictions = fixed_split_research(frame, sets)
    expanding = expanding_oos(frame, sets)
    stable = stable_calendar_rules(frame)
    report = summarize(run, frame, coverage, fixed, expanding, stable)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2, default=str) + "\n", encoding="utf-8")
    frame.to_csv(args.out.with_suffix(".dataset.csv"), index=False)
    fixed.to_csv(args.out.with_suffix(".fixed_split.csv"), index=False)
    predictions.to_csv(args.out.with_suffix(".forward_predictions.csv"), index=False)
    expanding.to_csv(args.out.with_suffix(".expanding_oos.csv"), index=False)
    stable.to_csv(args.out.with_suffix(".calendar_stability.csv"), index=False)
    for columns, name in (
        (["hour"], "hour"), (["weekday_name"], "weekday"), (["month"], "month"),
        (["season"], "season"), (["route"], "route"), (["session_2h", "route"], "session_route"),
    ):
        group_table(frame, columns).to_csv(args.out.with_name(args.out.stem + f".{name}.csv"), index=False)
    print(json.dumps(report, indent=2, default=str))


if __name__ == "__main__":
    main()
