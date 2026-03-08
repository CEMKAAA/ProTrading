"""ML feature hygiene diagnostics for Workbench research mode."""

from __future__ import annotations

from typing import Any, Dict, List

import numpy as np
import pandas as pd


def _safe_int(value: Any, default: int) -> int:
    try:
        return int(value)
    except Exception:
        return int(default)


def _safe_float(value: Any, default: float) -> float:
    try:
        return float(value)
    except Exception:
        return float(default)


def _normalize_close_df(df: pd.DataFrame) -> pd.DataFrame:
    if df is None or df.empty or "close" not in df.columns:
        return pd.DataFrame(columns=["close", "returns"])
    data = df.copy()
    if not isinstance(data.index, pd.DatetimeIndex):
        data.index = pd.to_datetime(data.index, utc=True, errors="coerce")
    data = data[~data.index.isna()].sort_index()
    data = data[~data.index.duplicated(keep="last")]
    out = pd.DataFrame(index=data.index)
    out["close"] = pd.to_numeric(data["close"], errors="coerce")
    out = out.dropna(subset=["close"])
    out["returns"] = np.log(out["close"] / out["close"].shift(1))
    return out


def _feature_drift_pct(
    train_mean: float,
    train_std: float,
    test_mean: float,
    test_std: float,
) -> float:
    denom_mean = max(abs(train_mean), abs(train_std), 1e-9)
    denom_std = max(abs(train_std), 1e-9)
    mean_drift = abs(test_mean - train_mean) / denom_mean
    std_drift = abs(test_std - train_std) / denom_std
    return float((0.6 * mean_drift + 0.4 * std_drift) * 100.0)


def compute_feature_diagnostic(
    df: pd.DataFrame,
    lags: int = 5,
    split_ratio: float = 0.7,
    drift_warn_pct: float = 50.0,
) -> Dict[str, Any]:
    """
    Analyze feature distribution drift between train/test windows.

    Feature prep mirrors Experiments/MLBacktester.py:
    - log returns
    - lag features from returns
    - train/test split
    - test stats evaluated against train distribution baselines
    """
    lags_i = max(1, min(50, _safe_int(lags, 5)))
    split = max(0.5, min(0.9, _safe_float(split_ratio, 0.7)))
    warn = max(5.0, min(500.0, _safe_float(drift_warn_pct, 50.0)))

    base = _normalize_close_df(df)
    if len(base) < max(30, lags_i + 10):
        return {
            "ok": False,
            "reason": "insufficient_bars",
            "lags": lags_i,
            "split_ratio": split,
            "drift_warn_pct": warn,
            "features": [],
            "regime_warning": False,
            "summary": "Insufficient bars for diagnostic.",
        }

    feat = base.copy()
    feature_cols: List[str] = []
    for lag in range(1, lags_i + 1):
        col = f"lag{lag}"
        feat[col] = feat["returns"].shift(lag)
        feature_cols.append(col)
    feat = feat.dropna(subset=feature_cols)

    if len(feat) < max(20, lags_i * 2):
        return {
            "ok": False,
            "reason": "insufficient_feature_rows",
            "lags": lags_i,
            "split_ratio": split,
            "drift_warn_pct": warn,
            "features": [],
            "regime_warning": False,
            "summary": "Insufficient feature rows after lag preparation.",
        }

    split_idx = int(max(1, min(len(feat) - 1, round(len(feat) * split))))
    train = feat.iloc[:split_idx].copy()
    test = feat.iloc[split_idx:].copy()

    if len(train) < 10 or len(test) < 10:
        return {
            "ok": False,
            "reason": "insufficient_split_rows",
            "lags": lags_i,
            "split_ratio": split,
            "drift_warn_pct": warn,
            "features": [],
            "regime_warning": False,
            "summary": "Train/test split too small for reliable drift analysis.",
        }

    rows: List[Dict[str, Any]] = []
    max_drift = 0.0
    for col in feature_cols:
        tr = pd.to_numeric(train[col], errors="coerce").dropna()
        te = pd.to_numeric(test[col], errors="coerce").dropna()
        if tr.empty or te.empty:
            continue

        train_mean = float(tr.mean())
        train_std = float(tr.std(ddof=0))
        test_mean = float(te.mean())
        test_std = float(te.std(ddof=0))
        drift_pct = _feature_drift_pct(train_mean, train_std, test_mean, test_std)
        max_drift = max(max_drift, drift_pct)
        rows.append(
            {
                "name": col,
                "train_mean": float(round(train_mean, 8)),
                "train_std": float(round(train_std, 8)),
                "test_mean": float(round(test_mean, 8)),
                "test_std": float(round(test_std, 8)),
                "drift_pct": float(round(drift_pct, 3)),
            }
        )

    rows.sort(key=lambda x: float(x.get("drift_pct", 0.0)), reverse=True)
    regime_warning = bool(max_drift >= warn)
    status = "warning" if regime_warning else "stable"
    summary = (
        f"Potential regime drift detected (max feature drift {max_drift:.2f}% >= {warn:.2f}%)."
        if regime_warning
        else f"Feature distributions look stable (max drift {max_drift:.2f}%)."
    )

    returns_train = pd.to_numeric(train["returns"], errors="coerce").dropna()
    returns_test = pd.to_numeric(test["returns"], errors="coerce").dropna()
    return {
        "ok": True,
        "status": status,
        "lags": int(lags_i),
        "split_ratio": float(split),
        "drift_warn_pct": float(warn),
        "bars_total": int(len(base)),
        "rows_used": int(len(feat)),
        "train_rows": int(len(train)),
        "test_rows": int(len(test)),
        "returns_stats": {
            "train_mean": float(round(float(returns_train.mean() if len(returns_train) else 0.0), 8)),
            "train_std": float(round(float(returns_train.std(ddof=0) if len(returns_train) else 0.0), 8)),
            "test_mean": float(round(float(returns_test.mean() if len(returns_test) else 0.0), 8)),
            "test_std": float(round(float(returns_test.std(ddof=0) if len(returns_test) else 0.0), 8)),
        },
        "features": rows,
        "max_drift_pct": float(round(max_drift, 3)),
        "regime_warning": regime_warning,
        "summary": summary,
    }
