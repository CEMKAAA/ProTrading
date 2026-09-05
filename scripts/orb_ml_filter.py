"""Train a per-configuration ORB veto model. No terminal, order or HTTP access.

Usage: python scripts/orb_ml_filter.py --csv <Common/Files/OrbML/Datasets/file.csv>
Only --publish can create the .model filename recognized by the EA. It requires
passing validation/test safeguards, but those do not prove future profitability.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import tempfile
import warnings
import platform

import numpy as np
import pandas as pd
import sklearn
from sklearn.exceptions import ConvergenceWarning
from sklearn.neural_network import MLPClassifier
from sklearn.preprocessing import StandardScaler

SCHEMA = "orb.closed256.v1"
FEATURES = (
    "direction body_atr range_atr upper_wick_atr lower_wick_atr return1_atr return5_atr "
    "return20_atr rsi14 close_ema20_atr close_ema50_atr ema20_50_atr ema_cross volume_ratio20 "
    "atr_ratio64 efficiency20 spread_atr hour_sin hour_cos weekday_sin weekday_cos regime_valid "
    "regime0 regime1 regime2 regime3 regime4 regime5 regime_trend_depth regime_vol_depth "
    "regime_age regime_transition_conf regime_pending rf_index orb_range_atr close_orb_high_atr "
    "close_orb_low_atr minutes_from_orb_end ema20_slope_atr invert"
).split()
FEATURES = ["f_" + f for f in FEATURES]
FEATURE_HASH = hashlib.sha256(",".join(FEATURES).encode()).hexdigest()
HIDDEN = 16


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def load_dataset(path: Path) -> tuple[pd.DataFrame, dict]:
    if path.suffix.lower() != ".csv":
        raise ValueError("Only completed .csv exports are accepted, not partial artifacts")
    completion = Path(str(path) + ".complete").read_text(encoding="utf-8").splitlines()
    if len(completion) != 4:
        raise ValueError("Invalid completion marker")
    data = path.read_bytes()
    if sha256(data) != completion[3]:
        raise ValueError("CSV content no longer matches its completion checksum")
    frame = pd.read_csv(io.BytesIO(data), keep_default_na=True, dtype={c: str for c in
        ["schema", "source_hash", "config_hash", "dataset_id", "preset_id", "symbol", "broker"]})
    if frame.empty or len(frame) != int(completion[1]):
        raise ValueError("CSV row count differs from completion marker or no trades")
    identities = ["schema", "source_hash", "config_hash", "dataset_id", "preset_id", "symbol", "broker",
                  "signal_tf_seconds", "chart_tf_seconds", "window_from_broker", "asof_broker"]
    for col in identities:
        if frame[col].isna().any() or frame[col].nunique() != 1:
            raise ValueError(f"Mixed or missing dataset identity: {col}")
    info = {col: str(frame[col].iloc[0]) for col in identities}
    if info["schema"] != SCHEMA or info["config_hash"] != completion[0] or info["dataset_id"] != completion[2]:
        raise ValueError("Schema/config/dataset mismatch")
    for col in ["config_hash", "source_hash"]:
        if not re.fullmatch(r"[a-f0-9]{64}", info[col]):
            raise ValueError(f"Invalid {col}")
    if [c for c in frame.columns if c.startswith("f_")] != FEATURES:
        raise ValueError("Feature schema or order changed")
    keys = ["signal_bar_broker", "entry_at_broker", "execution_direction"]
    if frame.duplicated(keys).any():
        raise ValueError("Duplicate candidate keys")
    for col in ["label_valid", "features_valid"]:
        if not frame[col].isin([0, 1]).all():
            raise ValueError(f"Invalid flag: {col}")
    times = frame[["signal_bar_broker", "features_at_broker", "entry_at_broker", "asof_broker"]].to_numpy(float)
    if not np.isfinite(times).all() or (times != np.floor(times)).any():
        raise ValueError("Missing/nonintegral timestamps")
    if not (frame.features_at_broker == frame.signal_bar_broker + int(info["signal_tf_seconds"])).all():
        raise ValueError("Features must be available at the original signal close")
    if (frame.features_at_broker > frame.entry_at_broker).any() or (frame.entry_at_broker > frame.asof_broker).any():
        raise ValueError("Causal availability violation")
    labels = frame.loc[frame.label_valid == 1]
    if (labels.exit_at_broker < labels.entry_at_broker).any() or (labels.exit_at_broker > labels.asof_broker).any():
        raise ValueError("Outcome boundary violation")
    if not np.isfinite(labels[["net_r", "exit_at_broker"]].to_numpy(float)).all():
        raise ValueError("Invalid outcome values")
    if not (labels.label_win == (labels.net_r > 0).astype(int)).all():
        raise ValueError("Win labels do not agree with realized net R")
    usable = frame.loc[(frame.label_valid == 1) & (frame.features_valid == 1)].copy()
    if not np.isfinite(usable[FEATURES].to_numpy(float)).all():
        raise ValueError("NaN/inf in rows declared feature-valid")
    info.update(dataset_sha256=sha256(data), total_rows=len(frame), usable_rows=len(usable),
                excluded_rows=len(frame) - len(usable))
    return usable.sort_values(["features_at_broker", "entry_at_broker"]).reset_index(drop=True), info


def temporal_split(frame: pd.DataFrame, embargo_seconds: int = 86400) -> tuple[pd.DataFrame, ...]:
    if embargo_seconds < 0 or len(frame) < 10:
        raise ValueError("Invalid embargo or insufficient chronological rows")
    ordered = frame.sort_values("features_at_broker")
    val_start = int(ordered.iloc[int(len(ordered) * 0.6)].features_at_broker)
    test_start = int(ordered.iloc[int(len(ordered) * 0.8)].features_at_broker)
    if val_start >= test_start:
        raise ValueError("Cannot create distinct chronological partitions")
    # A trade's label cannot depend on prices in the next partition.
    train = ordered.loc[(ordered.features_at_broker < val_start) &
                        (ordered.exit_at_broker < val_start - embargo_seconds)].copy()
    validation = ordered.loc[(ordered.features_at_broker >= val_start) &
                             (ordered.features_at_broker < test_start) &
                             (ordered.exit_at_broker < test_start - embargo_seconds)].copy()
    test = ordered.loc[ordered.features_at_broker >= test_start].copy()
    return train, validation, test


def metrics(frame: pd.DataFrame, probability: np.ndarray, threshold: float) -> dict:
    selected = frame.loc[probability >= threshold].sort_values("exit_at_broker")
    pnl = selected.net_r.to_numpy(float)
    curve = np.r_[0.0, np.cumsum(pnl)]
    wins = int((pnl > 0).sum())
    return dict(trades=len(pnl), retention=len(pnl) / max(1, len(frame)), wins=wins,
                losses=int((pnl < 0).sum()), flat=int((pnl == 0).sum()),
                win_rate=wins / max(1, len(pnl)), net_r=float(pnl.sum()),
                mean_r=float(pnl.mean()) if len(pnl) else 0.0,
                min_cumulative_r=float(curve.min()),
                peak_drawdown_r=float((np.maximum.accumulate(curve) - curve).max()))


def encode_model(model: MLPClassifier, scaler: StandardScaler, info: dict,
                 last_label: int, threshold: float) -> bytes:
    if model.hidden_layer_sizes != (HIDDEN,) or model.activation != "relu" or list(model.classes_) != [0, 1]:
        raise ValueError("Only a binary 40x16 ReLU MLP is portable")
    if model.coefs_[0].shape != (40, 16) or model.coefs_[1].shape != (16, 1):
        raise ValueError("Unexpected model shape")
    tokens = ["ORB_MLP1", SCHEMA, info["config_hash"], FEATURE_HASH,
              info["dataset_sha256"], str(last_label), format(threshold, ".17g"), "40,16"]
    numbers = np.r_[np.column_stack([scaler.mean_, scaler.scale_]).ravel(),
                    model.coefs_[0].ravel(), model.intercepts_[0],
                    model.coefs_[1].ravel(), model.intercepts_[1]]
    if not np.isfinite(numbers).all() or (np.abs(numbers) >= 1e12).any() or (scaler.scale_ <= 1e-12).any():
        raise ValueError("Non-portable numeric range")
    tokens += [format(float(value), ".17g") for value in numbers]
    payload = ("\n".join(tokens) + "\n").encode()
    return payload + sha256(payload).encode() + b"\n"


def portable_predict(data: bytes, x: np.ndarray, expected_config: str) -> np.ndarray:
    lines = data.decode("ascii").splitlines()
    expected = 8 + 80 + 640 + 32 + 1
    if len(lines) != expected + 1 or not data.endswith(b"\n"):
        raise ValueError("Model length")
    if sha256(("\n".join(lines[:-1]) + "\n").encode()) != lines[-1]:
        raise ValueError("Model checksum")
    if lines[:4] != ["ORB_MLP1", SCHEMA, expected_config, FEATURE_HASH] or lines[7] != "40,16":
        raise ValueError("Model binding")
    values = np.array([float(t) for t in lines[8:-1]])
    if not np.isfinite(values).all() or (np.abs(values) >= 1e12).any():
        raise ValueError("Model values")
    means = values[:80:2]
    scales = values[1:80:2]
    if (scales <= 1e-12).any():
        raise ValueError("Model scales")
    z = (np.asarray(x, dtype=float) - means) / scales
    hidden = np.maximum(0, z @ values[80:720].reshape(40, 16) + values[720:736])
    logits = hidden @ values[736:752] + values[752]
    return np.exp(-np.logaddexp(0, -logits))


def train(csv_path: Path, out_dir: Path, publish: bool = False, embargo_hours: float = 24,
          *, epochs: int = 0, progress=None, expected: dict | None = None) -> dict:
    def notify(percent, message):
        if progress is not None:
            progress(percent, message)  # may raise to cancel before any deployment
    notify(1, "Validating completed CSV")
    frame, info = load_dataset(csv_path)
    if expected and any(info.get(k) != v for k, v in expected.items()):
        raise ValueError("Job/CSV strategy binding mismatch")
    if len(frame) < 300:
        raise ValueError(f"Need at least 300 usable trades, got {len(frame)}; no model published")
    train_df, val_df, test_df = temporal_split(frame, int(embargo_hours * 3600))
    if len(train_df) < 150 or len(val_df) < 40 or len(test_df) < 40 or train_df.label_win.nunique() != 2:
        raise ValueError("Insufficient purged samples/classes for honest training/validation/test")
    scaler = StandardScaler().fit(train_df[FEATURES].to_numpy(float))
    if epochs and not 1 <= epochs <= 2000:
        raise ValueError("Invalid epoch budget")
    model = MLPClassifier(hidden_layer_sizes=(HIDDEN,), activation="relu", solver="adam" if epochs else "lbfgs", alpha=10.0,
                          max_iter=1000, random_state=42, early_stopping=False)
    notify(5, "Chronological split and train-only scaler complete")
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always", ConvergenceWarning)
        x_train=scaler.transform(train_df[FEATURES].to_numpy(float))
        y_train=train_df.label_win.to_numpy(int)
        if epochs:
            for epoch in range(epochs):
                notify(5+75*epoch/epochs, f"Epoch {epoch}/{epochs}")
                model.partial_fit(x_train, y_train, classes=np.array([0, 1]))
            notify(80, f"Epoch {epochs}/{epochs} complete")
        else:
            model.fit(x_train, y_train)
    converged = not any(issubclass(w.category, ConvergenceWarning) for w in caught)
    if epochs:
        # Do not call a fixed epoch budget 'converged' just because partial_fit
        # does not emit convergence warnings. This uses training loss only.
        curve=np.asarray(model.loss_curve_, dtype=float)
        converged=bool(len(curve)>=40 and np.isfinite(curve).all()
                       and abs(curve[-20:].mean()-curve[-40:-20].mean())<=1e-3)
    notify(83, "Selecting threshold on validation only")
    val_probability = model.predict_proba(scaler.transform(val_df[FEATURES].to_numpy(float)))[:, 1]
    candidates = [(threshold, metrics(val_df, val_probability, threshold))
                  for threshold in [0.05, 0.35, 0.45, 0.50, 0.55, 0.60, 0.65, 0.70, 0.75, 0.80]]
    candidates = [(t, m) for t, m in candidates if m["retention"] >= 0.4 and m["trades"] >= 30]
    if not candidates:
        raise ValueError("No validation threshold retains sufficient trades")
    threshold, validation = max(candidates, key=lambda item: (item[1]["net_r"], item[1]["trades"]))
    # Test is first consulted only after weights/scaler/threshold are frozen.
    notify(88, "Evaluating frozen model on test partition")
    test_probability = model.predict_proba(scaler.transform(test_df[FEATURES].to_numpy(float)))[:, 1]
    test = metrics(test_df, test_probability, threshold)
    baseline_val = metrics(val_df, np.ones(len(val_df)), 0.0)
    baseline_test = metrics(test_df, np.ones(len(test_df)), 0.0)
    last_label = int(info["asof_broker"])  # deployment must be later than the whole research observation window
    bundle = encode_model(model, scaler, info, last_label, threshold)
    parity = portable_predict(bundle, frame[FEATURES].to_numpy(float), info["config_hash"])
    native = model.predict_proba(scaler.transform(frame[FEATURES].to_numpy(float)))[:, 1]
    error = float(np.max(np.abs(parity - native)))
    if error > 1e-10:
        raise ValueError(f"Portable inference parity failed: {error}")
    notify(95, "Portable inference parity verified")
    qualified = bool(converged and validation["net_r"] > 0 and validation["net_r"] >= baseline_val["net_r"]
                     and test["trades"] >= 30 and test["retention"] >= 0.4 and test["net_r"] > 0)
    report = dict(dataset=info, feature_schema=SCHEMA, feature_names=FEATURES, hidden=HIDDEN,
                  versions=dict(python=platform.python_version(), numpy=np.__version__, pandas=pd.__version__, sklearn=sklearn.__version__),
                  threshold=threshold, seed=42, regularization_alpha=10.0, converged=converged,
                  solver=model.solver, epochs=epochs, optimizer_steps=int(model.n_iter_),
                  train_rows=len(train_df), validation_rows=len(val_df), test_rows=len(test_df),
                  purged_rows=len(frame) - len(train_df) - len(val_df) - len(test_df),
                  embargo_hours=embargo_hours, validation=validation, test=test,
                  validation_baseline=baseline_val, test_baseline=baseline_test,
                  train_feature_max=int(train_df.features_at_broker.max()),
                  train_label_max=int(train_df.exit_at_broker.max()),
                  validation_start=int(val_df.features_at_broker.min()),
                  test_start=int(test_df.features_at_broker.min()), last_label_broker=last_label,
                  probability_parity_max_error=error, deployment_checks_passed=qualified,
                  published=bool(publish and qualified), model_sha256=sha256(bundle),
                  warnings=["Historical simulations, not actual fills. Scores are not calibrated guarantees.",
                            "Base-strategy labels are unchanged by ML; portfolio overlaps need separate replay.",
                            "Repeated model/strategy selection contaminates the holdout; reserve fresh forward data.",
                            "Broker-local timestamps; no inferred historical UTC offset."])
    key = info["config_hash"]
    atomic_write(out_dir / (key + ".candidate.model"), bundle)
    atomic_write(out_dir / (key + ".report.json"), json.dumps(report, indent=2, allow_nan=False).encode())
    # Human-visible regression vectors can also be loaded by an isolated MQL script.
    vectors = frame[FEATURES].head(12).copy()
    vectors["expected_probability"] = native[:len(vectors)]
    atomic_write(out_dir / (key + ".vectors.csv"), vectors.to_csv(index=False).encode())
    if publish:
        if not qualified:
            raise ValueError("Deployment checks failed. Candidate/report saved; active .model was NOT replaced")
        atomic_write(out_dir / (key + ".model"), bundle)
    notify(100, "Research artifacts saved; activation requires explicit approval")
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--embargo-hours", type=float, default=24)
    parser.add_argument("--publish", action="store_true", help="Explicitly install model if checks pass; never enables EA toggle")
    args = parser.parse_args()
    if not np.isfinite(args.embargo_hours) or args.embargo_hours < 0:
        parser.error("embargo must be nonnegative and finite")
    output = args.output_dir or args.csv.parent.parent / "Models"
    try:
        report = train(args.csv, output, args.publish, args.embargo_hours)
    except (ValueError, OSError, KeyError) as error:
        parser.exit(1, f"ML FILTER: {error}\n")
    print(json.dumps({k: report[k] for k in ["train_rows", "validation_rows", "test_rows", "threshold",
                                             "validation", "test", "test_baseline", "published"]}, indent=2))
    print(f"Artifacts: {output}")


if __name__ == "__main__":
    main()
