import hashlib
import re
from pathlib import Path

import numpy as np
import pandas as pd
import pytest
from sklearn.neural_network import MLPClassifier
from sklearn.preprocessing import StandardScaler
from scripts import orb_ml_filter as ml

ROOT = Path(__file__).resolve().parents[1]


def test_atomic_commit_retries_sharing_denial(tmp_path, monkeypatch):
    path = tmp_path / "state"
    path.write_bytes(b"old")
    replace = ml.os.replace
    attempts = []
    def denied_twice(src, dst):
        attempts.append(1)
        assert path.read_bytes() == b"old"
        if len(attempts) < 3:
            raise PermissionError("reader denies delete sharing")
        replace(src, dst)
    monkeypatch.setattr(ml.os, "replace", denied_twice)
    monkeypatch.setattr(ml.time, "sleep", lambda _: None)
    ml.atomic_write(path, b"new")
    assert path.read_bytes() == b"new" and len(attempts) == 3
    assert not list(tmp_path.glob("*.tmp"))


def test_atomic_commit_permanent_denial_preserves_old(tmp_path, monkeypatch):
    path = tmp_path / "state"
    path.write_bytes(b"old")
    attempts = []
    def denied(src, dst):
        attempts.append(1)
        raise PermissionError("permanent denial")
    monkeypatch.setattr(ml.os, "replace", denied)
    monkeypatch.setattr(ml.time, "sleep", lambda _: None)
    with pytest.raises(PermissionError):
        ml.atomic_write(path, b"new")
    assert path.read_bytes() == b"old" and len(attempts) == 41
    assert not list(tmp_path.glob("*.tmp"))


def dataset_frame(n=400):
    rng = np.random.default_rng(21)
    x = rng.normal(size=(n, len(ml.FEATURES)))
    times = 1_600_000_000 + np.arange(n) * 86400
    win = (x[:, 0] + x[:, 1] > 0).astype(int)
    frame = pd.DataFrame(x, columns=ml.FEATURES)
    values = dict(schema=ml.SCHEMA, source_hash="a" * 64, config_hash="b" * 64,
                  dataset_id="fixture", preset_id="test", symbol="JP225m", broker="offline",
                  signal_tf_seconds=300, chart_tf_seconds=300, window_from_broker=int(times[0] - 1),
                  asof_broker=int(times[-1] + 86400), signal_bar_broker=times,
                  features_at_broker=times + 300, entry_at_broker=times + 300, exit_at_broker=times + 3600,
                  execution_direction="BUY", net_r=np.where(win, 1.0, -1.0), label_valid=1,
                  label_win=win, features_valid=1)
    for name, value in values.items():
        frame[name] = value
    return frame


def save_dataset(tmp_path, frame):
    path = tmp_path / "fixture.csv"
    frame.to_csv(path, index=False)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    Path(str(path) + ".complete").write_text(f"{'b' * 64}\n{len(frame)}\nfixture\n{digest}\n")
    return path


def test_dataset_and_explicit_exclusions(tmp_path):
    frame = dataset_frame()
    frame.loc[0, ["label_valid", "features_valid"]] = 0
    frame.loc[0, "net_r"] = np.nan
    loaded, info = ml.load_dataset(save_dataset(tmp_path, frame))
    assert len(loaded) == 399 and info["excluded_rows"] == 1
    assert info["dataset_sha256"] == hashlib.sha256((tmp_path / "fixture.csv").read_bytes()).hexdigest()


@pytest.mark.parametrize("damage", ["mixed_config", "mixed_symbol", "mixed_broker", "future_features",
                                    "future_outcome", "wrong_label", "duplicate", "missing_feature", "nan_valid_feature"])
def test_dataset_rejects_invalid_contract(tmp_path, damage):
    frame = dataset_frame()
    if damage == "mixed_config": frame.loc[0, "config_hash"] = "c" * 64
    if damage == "mixed_symbol": frame.loc[0, "symbol"] = "USDJPY"
    if damage == "mixed_broker": frame.loc[0, "broker"] = "other"
    if damage == "future_features": frame.loc[0, "features_at_broker"] += 300
    if damage == "future_outcome": frame.loc[0, "exit_at_broker"] = frame.asof_broker.iloc[0] + 1
    if damage == "wrong_label": frame.loc[0, "label_win"] = 1 - frame.label_win.iloc[0]
    if damage == "duplicate": frame.iloc[0] = frame.iloc[1]
    if damage == "missing_feature": frame = frame.drop(columns=ml.FEATURES[1])
    if damage == "nan_valid_feature": frame.loc[0, ml.FEATURES[1]] = np.nan
    with pytest.raises(ValueError): ml.load_dataset(save_dataset(tmp_path, frame))


def test_incomplete_export_rejected(tmp_path):
    path = save_dataset(tmp_path, dataset_frame())
    Path(str(path) + ".complete").unlink()
    with pytest.raises(FileNotFoundError): ml.load_dataset(path)
    with pytest.raises(ValueError): ml.load_dataset(path.with_suffix(".partial"))


def test_completed_csv_cannot_be_modified_unnoticed(tmp_path):
    path = save_dataset(tmp_path, dataset_frame())
    data = path.read_bytes()
    path.write_bytes(data.replace(b"offline", b"changed", 1))
    with pytest.raises(ValueError, match="checksum"):
        ml.load_dataset(path)


def test_insufficient_dataset_cannot_publish(tmp_path):
    with pytest.raises(ValueError, match="300 usable"):
        ml.train(save_dataset(tmp_path, dataset_frame(50)), tmp_path / "models", publish=True)
    assert not (tmp_path / "models").exists()


def test_temporal_split_purges_overlapping_labels():
    frame = dataset_frame()
    frame.loc[220, "exit_at_broker"] = frame.features_at_broker.iloc[245]
    train, val, test = ml.temporal_split(frame)
    assert 220 not in train.index
    assert train.exit_at_broker.max() < val.features_at_broker.min() - 86400
    assert val.exit_at_broker.max() < test.features_at_broker.min() - 86400
    assert set(train.index).isdisjoint(val.index) and set(val.index).isdisjoint(test.index)


def test_scaler_and_threshold_do_not_use_holdout(tmp_path):
    frame = dataset_frame(500)
    report = ml.train(save_dataset(tmp_path, frame), tmp_path / "first")
    modified = frame.copy()
    modified.loc[400:, "net_r"] *= -1
    modified.loc[400:, "label_win"] = 1 - modified.loc[400:, "label_win"]
    modified.loc[400:, ml.FEATURES[3]] += 100
    second = ml.train(save_dataset(tmp_path, modified), tmp_path / "second")
    assert report["threshold"] == second["threshold"]
    a = (tmp_path / "first" / ("b" * 64 + ".candidate.model")).read_text().splitlines()
    b = (tmp_path / "second" / ("b" * 64 + ".candidate.model")).read_text().splitlines()
    assert a[8:-1] == b[8:-1]
    assert not (tmp_path / "first" / ("b" * 64 + ".model")).exists()


@pytest.fixture
def model_bundle():
    frame = dataset_frame(400)
    x = frame[ml.FEATURES].to_numpy()
    scaler = StandardScaler().fit(x)
    model = MLPClassifier(hidden_layer_sizes=(16,), solver="lbfgs", alpha=10, random_state=42, max_iter=1000)
    model.fit(scaler.transform(x), frame.label_win)
    info = {"config_hash": "b" * 64, "dataset_sha256": "c" * 64}
    return ml.encode_model(model, scaler, info, 1700000000, 0.55), x, model, scaler


def test_portable_model_inference_matches_sklearn(model_bundle):
    data, x, model, scaler = model_bundle
    expected = model.predict_proba(scaler.transform(x))[:, 1]
    np.testing.assert_allclose(ml.portable_predict(data, x, "b" * 64), expected, atol=1e-12, rtol=1e-12)


def test_model_corruption_and_cross_config_rejected(model_bundle):
    data, x, _, _ = model_bundle
    with pytest.raises(ValueError): ml.portable_predict(data, x, "a" * 64)
    with pytest.raises(ValueError): ml.portable_predict(data.replace(b"0.55", b"0.95", 1), x, "b" * 64)
    with pytest.raises(ValueError): ml.portable_predict(data[:-5], x, "b" * 64)
    with pytest.raises(ValueError): ml.portable_predict(data + b"1\n", x, "b" * 64)


def test_net_r_metrics_not_nominal_target():
    frame = pd.DataFrame({"net_r": [0.12, -0.07, 2.0, -1.0, 0.0], "exit_at_broker": range(5)})
    result = ml.metrics(frame, np.ones(5), .5)
    assert result["net_r"] == pytest.approx(1.05)
    assert result["wins"] == 2 and result["losses"] == 2 and result["flat"] == 1
    assert result["peak_drawdown_r"] == pytest.approx(1.0)


def test_feature_order_and_causal_guards_match_mql():
    core = (ROOT / "IndicatorCodeExamples/orb/OrbStrategyMLCore.mqh").read_text()
    body = core.split("string OrbMlFeatureNames()", 1)[1].split("\n}", 1)[0]
    names = "".join(re.findall(r'"([^"]*)"', body))
    assert names.split(",") == ml.FEATURES
    pipeline = (ROOT / "IndicatorCodeExamples/orb/OrbStrategyMLPipeline.mqh").read_text()
    features = pipeline.split("bool OrbMlFeatures(", 1)[1].split("\nvoid OrbMlAbort", 1)[0]
    assert "rates[i].time+seconds>cutoff" in features
    assert "state.availableTime>cutoff" in features
    assert "CopyRates(_Symbol,g_rtSignalTf,shift,256,rates)" in features
    assert "rates[255].time!=bar" in features
    assert all(label not in features for label in ["netR", "exitTime", "result.outcome"])


def test_veto_before_both_publishing_and_native_execution():
    source = (ROOT / "IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5").read_text()
    execute = source.split("bool ExecuteOrbEntry(", 1)[1].split("\nbool ", 1)[0]
    gate = execute.index("if(!OrbMlAllow(rawDir,signalBar))")
    assert execute.index("CloseAcceptedNewDayReverseLifecycle(") < gate
    assert gate < execute.index("StoreOrbBridgePlan(") < execute.index("OrbProPublishSignal(")
    assert gate < execute.index("ExecThreeLegs(")
    pipeline = (ROOT / "IndicatorCodeExamples/orb/OrbStrategyMLPipeline.mqh").read_text()
    allow = pipeline.split("bool OrbMlAllow(", 1)[1].split("\nbool OrbMlUiEvent", 1)[0]
    assert "if(!g_mlEnabled)return true;" in allow
    assert 'OrbMlDecision(raw,bar,g_orbHigh,g_orbLow,g_orbEndServer,true' in allow
    assert 'return allowed;' in allow
    decision = (ROOT / "IndicatorCodeExamples/orb/OrbStrategyMLHistory.mqh").read_text()
    assert 'return reason=="ALLOW";' in decision
    assert 'requireOos&&' in decision
    assert "NOT_OUT_OF_SAMPLE" in decision and "MISSING_OR_MISMATCHED_MODEL" in decision


def test_export_captures_base_universe_without_ml_veto():
    source = (ROOT / "IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5").read_text()
    calc = source.split("void ProcessHistoricalCalcDay(", 1)[1].split("void CancelHistoricalAuditBuild", 1)[0]
    assert calc.index("if(!rfAllowed)") < calc.index("OrbMlCapture(") < calc.index("g_histTotal++")
    assert "OrbMlAllow" not in calc
    assert "OrbMlAbort" in source.split("void CancelHistoricalAuditBuild", 1)[1].split("void FinalizeHistoricalAudit", 1)[0]


def test_export_writes_canonical_bytes_not_terminal_text_conversion():
    pipeline = (ROOT / "IndicatorCodeExamples/orb/OrbStrategyMLPipeline.mqh").read_text()
    assert "FileWriteArray(handle,bytes,0,size-1)" in pipeline
    assert "FILE_WRITE|FILE_BIN|FILE_COMMON" in pipeline
    assert "FileWriteString" not in pipeline
    assert "FILE_TXT" not in pipeline.replace("FILE_TXT's CRLF conversion", "")
