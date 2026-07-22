#!/usr/bin/env python3
"""Causal multi-timeframe price-path research for Sol Advanced JP225 setups."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.base import clone
from sklearn.ensemble import ExtraTreesClassifier, RandomForestClassifier
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import balanced_accuracy_score, roc_auc_score
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler


TF_SECONDS = {"M1": 60, "M5": 300, "M15": 900, "H1": 3600, "H2": 7200, "H4": 14400, "D1": 86400}
WINDOWS = {
    "M1": (3, 5, 10, 15, 30, 60, 120, 240),
    "M5": (2, 3, 6, 12, 24, 48, 96),
    "M15": (2, 4, 8, 16, 32, 64),
    "H1": (2, 4, 8, 16, 24, 48, 120),
    "H2": (2, 3, 6, 12, 24, 60),
    "H4": (2, 3, 6, 12, 30),
    "D1": (2, 3, 5, 10, 20),
}
CORE_COLUMNS = [
    "q_rev", "sdep_rev", "srng_rev", "sbod_rev", "scl_rev", "swk_rev",
    "rdly_rev", "rstr_rev", "rrng_rev", "rbod_rev", "rcl_rev", "rwk_rev",
    "mss_rev", "mssd_rev", "mssb_rev", "fams_rev", "flag_rev", "fwid_rev",
    "fdst_rev", "fbod_rev", "frng_rev", "fcl_rev", "fvol_rev", "elag_rev",
    "epen_rev", "eclz_rev", "ebod_rev", "erng_rev", "ecl_rev", "ewk_rev",
]


def prepare_rates(path: Path, seconds: int) -> dict[str, np.ndarray]:
    frame = pd.read_parquet(path).sort_values("time").reset_index(drop=True)
    time_ns = pd.to_datetime(frame["time"], utc=True).astype("int64").to_numpy()
    close = frame["close"].to_numpy(float)
    high = frame["high"].to_numpy(float)
    low = frame["low"].to_numpy(float)
    prev_close = np.r_[close[0], close[:-1]]
    tr = np.maximum(high - low, np.maximum(np.abs(high - prev_close), np.abs(low - prev_close)))
    atr = pd.Series(tr).rolling(14, min_periods=5).mean().to_numpy()
    return {
        "available": time_ns + int(seconds * 1e9),
        "open": frame["open"].to_numpy(float),
        "high": high,
        "low": low,
        "close": close,
        "volume": frame["tick_volume"].to_numpy(float),
        "atr": atr,
    }


def window_features(rates: dict[str, np.ndarray], available_ns: int, source_dir: int,
                    label: str, windows: tuple[int, ...]) -> dict[str, float]:
    idx = int(np.searchsorted(rates["available"], available_ns, side="right") - 1)
    if idx < 15:
        return {}
    atr = rates["atr"][idx]
    if not np.isfinite(atr) or atr <= 0:
        return {}
    result: dict[str, float] = {}
    bar_range = max(1e-12, rates["high"][idx] - rates["low"][idx])
    result[f"{label}_body"] = source_dir * (rates["close"][idx] - rates["open"][idx]) / atr
    result[f"{label}_range"] = bar_range / atr
    result[f"{label}_src_reject"] = (
        rates["close"][idx] - rates["low"][idx]
        if source_dir > 0 else rates["high"][idx] - rates["close"][idx]
    ) / bar_range
    result[f"{label}_opp_reject"] = (
        rates["high"][idx] - rates["close"][idx]
        if source_dir > 0 else rates["close"][idx] - rates["low"][idx]
    ) / bar_range
    for window in windows:
        start = idx - window + 1
        if start < 1:
            continue
        closes = rates["close"][start:idx + 1]
        opens = rates["open"][start:idx + 1]
        highs = rates["high"][start:idx + 1]
        lows = rates["low"][start:idx + 1]
        net = source_dir * (closes[-1] - closes[0]) / atr
        path = float(np.abs(np.diff(closes)).sum())
        high = float(highs.max())
        low = float(lows.min())
        width = max(1e-12, high - low)
        signed_bodies = source_dir * (closes - opens)
        result[f"{label}_net{window}"] = net
        result[f"{label}_eff{window}"] = source_dir * (closes[-1] - closes[0]) / max(path, 1e-12)
        result[f"{label}_pos{window}"] = ((closes[-1] - low) / width if source_dir > 0 else (high - closes[-1]) / width)
        result[f"{label}_width{window}"] = width / atr
        result[f"{label}_dirfrac{window}"] = float((signed_bodies > 0).mean())
        result[f"{label}_srcroom{window}"] = ((high - closes[-1]) if source_dir > 0 else (closes[-1] - low)) / atr
        result[f"{label}_opproom{window}"] = ((closes[-1] - low) if source_dir > 0 else (high - closes[-1])) / atr
        mean = float(closes.mean())
        std = float(closes.std())
        result[f"{label}_z{window}"] = source_dir * (closes[-1] - mean) / max(std, atr * 0.05)
    return result


def build_features(setups: pd.DataFrame, rates_dir: Path) -> pd.DataFrame:
    prepared = {
        label: prepare_rates(rates_dir / f"JP225m_{label}.parquet", TF_SECONDS[label])
        for label in WINDOWS
    }
    rows = []
    for row in setups.itertuples(index=False):
        available_ns = int(pd.Timestamp(row.available).value)
        source_dir = int(row.src_rev)
        features: dict[str, float] = {}
        for label, windows in WINDOWS.items():
            features.update(window_features(prepared[label], available_ns, source_dir, label.lower(), windows))
        rows.append(features)
    return pd.DataFrame(rows, index=setups.index)


def models() -> dict[str, object]:
    return {
        "logistic_c002": make_pipeline(
            SimpleImputer(strategy="median"), StandardScaler(),
            LogisticRegression(C=0.02, max_iter=5000, class_weight="balanced", random_state=41),
        ),
        "logistic_c008": make_pipeline(
            SimpleImputer(strategy="median"), StandardScaler(),
            LogisticRegression(C=0.08, max_iter=5000, class_weight="balanced", random_state=41),
        ),
        "random_forest": make_pipeline(
            SimpleImputer(strategy="median"),
            RandomForestClassifier(n_estimators=800, max_depth=4, min_samples_leaf=30,
                                   max_features=0.35, class_weight="balanced", random_state=41, n_jobs=1),
        ),
        "extra_trees": make_pipeline(
            SimpleImputer(strategy="median"),
            ExtraTreesClassifier(n_estimators=800, max_depth=5, min_samples_leaf=25,
                                 max_features=0.40, class_weight="balanced", random_state=41, n_jobs=1),
        ),

    }


def routed_metrics(frame: pd.DataFrame, prediction: np.ndarray) -> dict:
    wins = np.where(prediction.astype(bool), frame["cont_win"], frame["rev_win"]).astype(bool)
    return {"trades": int(len(frame)), "wins": int(wins.sum()), "wr": float(wins.mean())}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("dataset", type=Path)
    parser.add_argument("rates_dir", type=Path)
    parser.add_argument("--out", type=Path, default=Path("logs/sol_pa_raw_path.json"))
    args = parser.parse_args()

    frame = pd.read_csv(args.dataset, low_memory=False)
    frame["available"] = pd.to_datetime(frame["available"], utc=True)
    frame["year"] = frame["available"].dt.year
    raw = build_features(frame, args.rates_dir)
    raw_columns = list(raw.columns)
    frame = pd.concat([frame, raw], axis=1)
    feature_sets = {
        "raw": raw_columns,
        "raw_core": raw_columns + [column for column in CORE_COLUMNS if column in frame],
    }
    labeled = frame[frame["target_cont"].notna()].copy()
    folds = []
    predictions = []
    for test_year in (2023, 2024, 2025, 2026):
        train = labeled[labeled["year"] < test_year]
        test = frame[frame["year"] == test_year]
        test_labeled = labeled[labeled["year"] == test_year]
        for set_name, columns in feature_sets.items():
            for model_name, estimator in models().items():
                fitted = clone(estimator).fit(train[columns], train["target_cont"].astype(int))
                probability = fitted.predict_proba(test[columns])[:, 1]
                prediction = probability >= 0.5
                metric = {
                    "test_year": test_year,
                    "train_rows": int(len(train)),
                    "feature_set": set_name,
                    "model": model_name,
                    **routed_metrics(test, prediction),
                    "continuation_share": float(prediction.mean()),
                }
                if len(test_labeled):
                    labeled_probability = fitted.predict_proba(test_labeled[columns])[:, 1]
                    metric["route_auc"] = float(roc_auc_score(test_labeled["target_cont"], labeled_probability))
                    metric["route_balanced_accuracy"] = float(
                        balanced_accuracy_score(test_labeled["target_cont"], labeled_probability >= 0.5)
                    )
                folds.append(metric)
                part = test[["available", "year", "rev_win", "cont_win"]].copy()
                part["feature_set"] = set_name
                part["model"] = model_name
                part["prob_cont"] = probability
                part["pred_cont"] = prediction
                part["win"] = np.where(prediction, part["cont_win"], part["rev_win"]).astype(bool)
                predictions.append(part)
    folds_frame = pd.DataFrame(folds)
    pred_frame = pd.concat(predictions, ignore_index=True)
    summary = pred_frame.groupby(["feature_set", "model"]).agg(
        trades=("win", "size"), wins=("win", "sum"), wr=("win", "mean")
    ).reset_index()
    min_year = pred_frame.groupby(["feature_set", "model", "year"])["win"].mean().groupby(level=[0, 1]).min()
    summary["min_year_wr"] = [float(min_year.loc[(row.feature_set, row.model)]) for row in summary.itertuples()]
    summary = summary.sort_values(["min_year_wr", "wr"], ascending=False)
    report = {
        "protocol": "expanding walk-forward; fixed 0.5 threshold; all setups retained; causal closed bars only",
        "period": [str(frame.available.min()), str(frame.available.max())],
        "setups": int(len(frame)),
        "raw_feature_count": len(raw_columns),
        "summary": summary.to_dict(orient="records"),
        "folds": folds_frame.to_dict(orient="records"),
    }
    args.out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    folds_frame.to_csv(args.out.with_suffix(".folds.csv"), index=False)
    pred_frame.to_csv(args.out.with_suffix(".predictions.csv"), index=False)
    frame[["available", "year", "src_rev", "rev_win", "cont_win", "target_cont"] + raw_columns].to_parquet(
        args.out.with_suffix(".dataset.parquet"), index=False
    )
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()


