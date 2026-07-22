#!/usr/bin/env python3
"""Focused high-retention out-of-sample tests for the Sol V14 dataset."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.base import clone
from sklearn.ensemble import ExtraTreesClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.tree import DecisionTreeClassifier, export_text


def score(data: pd.DataFrame, selected: np.ndarray) -> dict:
    chosen = data.loc[selected]
    rejected = data.loc[~selected]
    return {
        "available": int(len(data)),
        "trades": int(len(chosen)),
        "retention": float(len(chosen) / len(data)),
        "wins": int(chosen["won"].sum()),
        "wr": float(chosen["won"].mean()),
        "net_r": float(chosen["r"].sum()),
        "rejected_trades": int(len(rejected)),
        "rejected_wr": float(rejected["won"].mean()) if len(rejected) else None,
        "rejected_net_r": float(rejected["r"].sum()),
    }


def columns(frame: pd.DataFrame) -> dict[str, list[str]]:
    calendar = [
        "hour_sin", "hour_cos", "weekday_sin", "weekday_cos", "month_sin", "month_cos",
        "is_buy", "is_continuation", "quality", "signal_age_h", "prev_same_dir",
    ]
    market = [c for c in frame.columns if c.endswith("_rev") and pd.api.types.is_numeric_dtype(frame[c])]
    return {
        "calendar": calendar,
        "calendar_market": calendar + market,
    }


def models() -> dict[str, object]:
    return {
        "logistic": make_pipeline(
            SimpleImputer(strategy="median"), StandardScaler(),
            LogisticRegression(C=0.08, max_iter=4000, class_weight="balanced", random_state=31),
        ),
        "tree_d3": make_pipeline(
            SimpleImputer(strategy="median"),
            DecisionTreeClassifier(max_depth=3, min_samples_leaf=35, class_weight="balanced", random_state=31),
        ),
        "tree_d4": make_pipeline(
            SimpleImputer(strategy="median"),
            DecisionTreeClassifier(max_depth=4, min_samples_leaf=30, class_weight="balanced", random_state=31),
        ),
        "extra_trees": make_pipeline(
            SimpleImputer(strategy="median"),
            ExtraTreesClassifier(
                n_estimators=800, max_depth=5, min_samples_leaf=25, max_features=0.50,
                class_weight="balanced", random_state=31, n_jobs=1,
            ),
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("dataset", type=Path)
    parser.add_argument("--out", type=Path, default=Path("logs/sol_v14_high_retention_oos.json"))
    args = parser.parse_args()

    frame = pd.read_csv(args.dataset, low_memory=False)
    frame["available"] = pd.to_datetime(frame["available"], utc=True)
    feature_sets = columns(frame)
    fold_rows: list[dict] = []
    tree_rules: list[dict] = []
    importances: list[dict] = []
    for test_year in (2023, 2024, 2025, 2026):
        train = frame[frame["year"] < test_year]
        test = frame[frame["year"] == test_year]
        for set_name, feature_names in feature_sets.items():
            for model_name, estimator in models().items():
                fitted = clone(estimator).fit(train[feature_names], train["won"])
                train_prob = fitted.predict_proba(train[feature_names])[:, 1]
                test_prob = fitted.predict_proba(test[feature_names])[:, 1]
                for target_retention in (0.95, 0.90, 0.85, 0.80):
                    threshold = float(np.quantile(train_prob, 1.0 - target_retention))
                    fold_rows.append(
                        {
                            "test_year": test_year,
                            "train_rows": int(len(train)),
                            "feature_set": set_name,
                            "model": model_name,
                            "target_retention": target_retention,
                            "threshold": threshold,
                            **score(test, test_prob >= threshold),
                        }
                    )
                terminal = fitted[-1]
                if model_name.startswith("tree_"):
                    tree_rules.append(
                        {
                            "test_year": test_year,
                            "feature_set": set_name,
                            "model": model_name,
                            "rules": export_text(terminal, feature_names=feature_names, decimals=4),
                        }
                    )
                if model_name == "extra_trees":
                    for name, importance in zip(feature_names, terminal.feature_importances_):
                        importances.append(
                            {"test_year": test_year, "feature_set": set_name, "feature": name, "importance": importance}
                        )

    folds = pd.DataFrame(fold_rows)
    summary = folds.groupby(["feature_set", "model", "target_retention"]).agg(
        available=("available", "sum"), trades=("trades", "sum"), wins=("wins", "sum"),
        net_r=("net_r", "sum"), rejected_trades=("rejected_trades", "sum"),
        rejected_net_r=("rejected_net_r", "sum"), min_year_wr=("wr", "min"),
    ).reset_index()
    summary["retention"] = summary["trades"] / summary["available"]
    summary["wr"] = summary["wins"] / summary["trades"]
    # Rejected wins are recovered from totals rather than averaging fold rates.
    total_wins = int(frame[frame["year"] >= 2023]["won"].sum())
    summary["rejected_wins"] = total_wins - summary["wins"]
    summary["rejected_wr"] = summary["rejected_wins"] / summary["rejected_trades"]
    summary = summary.sort_values(["target_retention", "wr", "net_r"], ascending=[False, False, False])

    importance_frame = pd.DataFrame(importances)
    importance_summary = importance_frame.groupby(["feature_set", "feature"]).agg(
        mean_importance=("importance", "mean"), min_importance=("importance", "min"),
        max_importance=("importance", "max"),
    ).reset_index().sort_values(["feature_set", "mean_importance"], ascending=[True, False])

    baseline = frame[frame["year"] >= 2023]
    report = {
        "period": [str(baseline["available"].min()), str(baseline["available"].max())],
        "baseline": {
            "trades": int(len(baseline)), "wins": int(baseline["won"].sum()),
            "wr": float(baseline["won"].mean()), "net_r": float(baseline["r"].sum()),
        },
        "best_at_least_90pct_retention": summary[summary["retention"] >= 0.90].head(15).to_dict(orient="records"),
        "best_all": summary.head(25).to_dict(orient="records"),
        "stable_feature_importance": importance_summary.groupby("feature_set").head(15).to_dict(orient="records"),
    }
    args.out.write_text(json.dumps(report, indent=2, default=str) + "\n", encoding="utf-8")
    folds.to_csv(args.out.with_suffix(".folds.csv"), index=False)
    summary.to_csv(args.out.with_suffix(".summary.csv"), index=False)
    importance_summary.to_csv(args.out.with_suffix(".importance.csv"), index=False)
    args.out.with_suffix(".tree_rules.json").write_text(json.dumps(tree_rules, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, default=str))


if __name__ == "__main__":
    main()
