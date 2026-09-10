"""Frozen research-only expected-return challenger. Never exports an EA model."""
from pathlib import Path
import json

import joblib
import numpy as np
from sklearn.linear_model import Ridge
from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

try:
    from .orb_ml_filter import FEATURES, metrics, atomic_write, temporal_split
    from .orb_ml_research import walk_folds, stop_split
except ImportError:
    from orb_ml_filter import FEATURES, metrics, atomic_write, temporal_split
    from orb_ml_research import walk_folds, stop_split

POLICY = 'ORB_RETURN_RESEARCH_20260909_1'
CANDIDATES = ('ridge_10', 'ridge_100', 'ridge_1000', 'hgb_7')
THRESHOLDS = (-1e6, -.10, -.05, 0., .025, .05, .10, .15, .20)
ALIGNED = ('return1_atr', 'return5_atr', 'return20_atr', 'close_ema20_atr',
           'close_ema50_atr', 'ema20_50_atr', 'ema20_slope_atr', 'body_atr')


def design(frame):
    x = frame[FEATURES].copy()
    for name in ALIGNED:
        x['x_aligned_' + name] = frame.f_direction * frame['f_' + name]
    x['x_trend_vol'] = frame.f_regime_trend_depth * frame.f_regime_vol_depth
    x['x_transition_trend'] = frame.f_regime_pending * frame.f_regime_trend_depth
    return x


def estimator(name):
    if name.startswith('ridge_'):
        return make_pipeline(StandardScaler(), Ridge(alpha=float(name.split('_')[1])))
    if name == 'hgb_7':
        return HistGradientBoostingRegressor(max_iter=80, max_leaf_nodes=7,
            min_samples_leaf=30, l2_regularization=10, early_stopping=False, random_state=42)
    raise ValueError(name)


def choose(frame, scores):
    candidates = [(t, metrics(frame, scores, t)) for t in THRESHOLDS]
    candidates = [(t, m) for t, m in candidates if m['retention'] >= .4 and m['trades'] >= min(30, len(frame))]
    return max(candidates, key=lambda z: (z[1]['net_r'], z[1]['trades']))


def family_uncertainty(frame, keep, family_size=106, draws=20000):
    """Centered moving-block bootstrap diagnostic; not proof of stationarity.

    Includes zero-trade calendar days and both 53-strategy model families.
    Bonferroni does not require independence, but marginal bootstrap p-values
    remain approximate and do not repair prior human strategy selection.
    """
    import pandas as pd
    groups = frame.exit_at_broker.to_numpy(np.int64) // 86400
    delta = np.where(keep, 0., -frame.net_r.to_numpy(float))
    daily = pd.Series(delta).groupby(groups).sum()
    daily = daily.reindex(range(int(groups.min()), int(groups.max()) + 1), fill_value=0).to_numpy()
    n = len(daily)
    if n < 30 or not np.any(delta):
        return dict(days=n, p_one_sided=1., p_bonferroni=1., lower_family=0., passed=False)
    block = max(2, int(np.ceil(n ** (1/3))))
    rng = np.random.default_rng(20260909)
    means = []
    for start in range(0, draws, 250):
        seeds = rng.integers(n, size=(min(250, draws-start), int(np.ceil(n/block))))
        ix = ((seeds[:, :, None] + np.arange(block)) % n).reshape(len(seeds), -1)[:, :n]
        means.extend(daily[ix].mean(axis=1))
    means = np.asarray(means)
    observed = float(daily.mean())
    p = float((1 + np.count_nonzero(means-observed >= observed)) / (draws+1))
    lower = float(2*observed - np.quantile(means, 1-.05/family_size))
    return dict(days=n, block_days=block, draws=draws, family_size=family_size,
        mean_daily_delta_r=observed, p_one_sided=p, p_bonferroni=min(1., p*family_size),
        lower_family=lower, passed=bool(observed > 0 and p*family_size < .05 and lower > 0))


def fit(frame, out: Path):
    train, val, test = temporal_split(frame)
    if len(frame) < 300 or len(train) < 150 or len(val) < 40 or len(test) < 40:
        raise ValueError('Insufficient purged samples for return challenger')
    folds = walk_folds(train, 86400)
    candidates = []
    for name in CANDIDATES:
        results = []
        for parent, score in folds:
            sub, cal = stop_split(parent, 86400)
            model = estimator(name).fit(design(sub), sub.net_r)
            threshold, _ = choose(cal, model.predict(design(cal)))
            m = metrics(score, model.predict(design(score)), threshold)
            results.append(dict(delta_r=m['net_r']-float(score.net_r.sum()), threshold=threshold,
                filtered=m, fit_label_max=int(sub.exit_at_broker.max()),
                calibration_start=int(cal.features_at_broker.min()),
                calibration_label_max=int(cal.exit_at_broker.max()), score_start=int(score.features_at_broker.min())))
        candidates.append(dict(name=name, folds=results, median_delta_r=float(np.median([r['delta_r'] for r in results]))))
    winner = max(candidates, key=lambda c: (c['median_delta_r'], -CANDIDATES.index(c['name'])))
    model = estimator(winner['name']).fit(design(train), train.net_r)
    threshold, vm = choose(val, model.predict(design(val)))
    # Both the development decision and calibration must beat abstaining from ML.
    active = winner['median_delta_r'] > 0 and vm['net_r'] > float(val.net_r.sum())
    out.mkdir(parents=True, exist_ok=True)
    freeze = dict(policy=POLICY, selected=winner['name'], threshold=threshold, active=bool(active),
        features=list(design(train).columns), candidates=candidates, validation=vm,
        train_label_max=int(train.exit_at_broker.max()), validation_start=int(val.features_at_broker.min()),
        validation_label_max=int(val.exit_at_broker.max()), test_start=int(test.features_at_broker.min()))
    atomic_write(out/'frozen_selection.json', json.dumps(freeze, indent=2).encode())
    joblib.dump(dict(model=model, features=freeze['features'], threshold=threshold,
                     active=active, research_only=True), out/'return_model.research.joblib')
    scores = model.predict(design(test))
    keep = scores >= threshold if active else np.ones(len(test), dtype=bool)
    tm = metrics(test, keep.astype(float), .5)
    baseline = metrics(test, np.ones(len(test)), 0)
    ci = family_uncertainty(test, keep)
    predictions = test[['features_at_broker', 'entry_at_broker', 'exit_at_broker', 'net_r', 'label_win']].copy()
    predictions['score_net_r'] = scores
    predictions['keep'] = keep.astype(int)
    atomic_write(out/'test_predictions.csv', predictions.to_csv(index=False).encode())
    # Coefficients describe the fitted ridge, not causal economic mechanisms.
    coefficients = None
    if winner['name'].startswith('ridge'):
        coefficients = dict(zip(freeze['features'], model[-1].coef_.tolist()))
    report = dict(**freeze, test=tm, test_baseline=baseline, family_uncertainty=ci,
                  standardized_coefficients=coefficients, published=False,
                  deployment_checks_passed=False, research_only=True)
    atomic_write(out/'report.json', json.dumps(report, indent=2, allow_nan=False).encode())
    return report
