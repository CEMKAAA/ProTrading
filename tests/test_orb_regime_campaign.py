from pathlib import Path
import sys
import numpy as np
import pandas as pd
import pytest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import orb_regime_campaign as c
import orb_regime_campaign_report as report


def frame(n=220):
    rng = np.random.default_rng(912)
    f = pd.DataFrame(rng.normal(size=(n, len(c.FEATURES))), columns=c.FEATURES)
    f['f_direction'] = np.where(np.arange(n) % 2, 1., -1.)
    f['f_regime_age'] = np.arange(n) % 10
    f['f_rf_index'] = np.arange(n) % 13
    f['entry'] = 100.
    f['sl'] = 98.
    f['tp'] = 104.
    f['obs_atr14'] = 1.
    f['strategy'] = 'A'
    f['symbol'] = 'USDJPY'
    f['features_at_broker'] = c.stamp('2021-01-01') + np.arange(n)*86400
    f['entry_at_broker'] = f.features_at_broker + 1
    f['exit_at_broker'] = f.features_at_broker + 3600
    f['net_r'] = np.where(np.arange(n) % 2, 2., -1.)
    f['label_win'] = (f.net_r > 0).astype(int)
    f['cost_r'] = .03
    f['exit_reason'] = 'TP'
    return f


def test_outcome_columns_cannot_enter_feature_matrix():
    f = frame()
    expected = c.design(f, True, True, ['A', 'B'])
    f['net_r'] = -9999.
    f['label_win'] = 0
    f['cost_r'] = 10000.
    f['exit_reason'] = 'FUTURE_SECRET'
    f['exit_at_broker'] += 9999999
    pd.testing.assert_frame_equal(expected, c.design(f, True, True, ['A', 'B']))


def test_regime_ablation_excludes_all_regime_and_rf_columns():
    f = frame()
    base = c.design(f, False, False, [])
    reg = c.design(f, True, False, [])
    f.loc[:, [x for x in c.FEATURES if x.startswith('f_regime')]] = 2.
    f['f_rf_index'] = 12
    pd.testing.assert_frame_equal(base, c.design(f, False, False, []))
    assert not reg.equals(c.design(f, True, False, []))
    assert not any('regime' in x or 'rf_' in x for x in base.columns)


def test_geometry_is_planned_and_not_inferred_from_realized_return():
    x = c.design(frame(), True, False, [])
    assert (x.x_target_r == 2).all()
    assert (x.x_sl_atr == 2).all()
    f = frame(); f['sl'] = f.entry
    with pytest.raises(ValueError, match='geometry'):
        c.design(f, True, False, [])


def test_purging_rejects_cross_boundary_and_embargo_labels():
    f = frame(10)
    end = int(f.features_at_broker.iloc[7])
    f.loc[0, 'exit_at_broker'] = end + 10
    f.loc[1, 'exit_at_broker'] = end - c.GAP
    got = c.partition(f, 0, end)
    assert 0 not in got.index and 1 not in got.index
    assert (got.exit_at_broker < end-c.GAP).all()
    assert (got.features_at_broker < end).all()


def test_same_calendar_boundary_applies_to_sparse_and_dense_strategies():
    a = frame(100)
    b = a.iloc[::3].copy(); b['strategy'] = 'B'
    end = int(a.features_at_broker.iloc[70])
    p = c.partition(pd.concat([a, b]), 0, end)
    assert (p.groupby('strategy').exit_at_broker.max() < end-c.GAP).all()


def test_duplicate_variant_days_do_not_increase_pooled_day_weight():
    f = frame(2)
    f = pd.concat([f.iloc[[0]]] * 5 + [f.iloc[[1]]], ignore_index=True)
    w = c.weights(f)
    assert np.isclose(w[:5].sum(), w[5])


def test_no_veto_does_not_invent_selection_skill():
    f = frame(50)
    v = c.selection_value(f, np.ones(len(f), bool))
    assert v['gain'] == 0 and v['skill'] == 0 and v['count_skill'] == 0
    q = c.choose(f, np.ones(len(f)))
    assert q['score'] == 0 and q['retention'] == 1


def test_threshold_retention_floor_and_positive_selection():
    f = frame(100)
    q = c.choose(f, np.where(f.net_r > 0, .2, -.2))
    assert q['retention'] >= .5 and q['score'] > 0
    assert c.choose(f.iloc[:10], np.zeros(10)) is None


def test_drawdown_uses_exit_sequence_and_groups_same_timestamp():
    f = frame(4)
    f['net_r'] = [4., -3., 2., -4.]
    assert c.stats(f, np.ones(4, bool))['dd_r'] == 5.
    f.loc[1, 'exit_at_broker'] = f.loc[0, 'exit_at_broker']
    f['net_r'] = [-4., 4., 1., -1.]
    assert c.stats(f, np.ones(4, bool))['dd_r'] == 1.


@pytest.mark.parametrize('kind', c.CANDIDATES)
def test_models_fit_only_training_features_and_predict_finite(kind):
    f = frame()
    model = c.fit_one(f, kind, ['A'])
    assert model is not None
    assert np.isfinite(c.predict(model, f.iloc[-10:])).all()
    if 'stop_start' in model:
        assert model['fit_label_max'] < model['stop_start']-c.GAP
    assert 'net_r' not in model['features']
    if kind in ('local_base', 'pool_base'):
        x = c.design(f, False, kind.startswith('pool'), ['A'])
        np.testing.assert_allclose(model['scaler'].mean_, np.average(x, axis=0, weights=c.weights(f)))


def test_daily_contrasts_reconcile_with_trade_selection_totals():
    f = frame(100)
    f['keep'] = (np.arange(len(f)) % 3 != 0).astype(int)
    start = int(f.features_at_broker.min())//86400
    end = int(f.exit_at_broker.max())//86400
    m = report.daily_contrasts(f, ['A'], start, end)
    v = c.selection_value(f, f.keep.to_numpy(bool))
    np.testing.assert_allclose(m.sum(axis=0), [v['gain'], v['skill']])


def test_joint_bootstrap_preserves_identical_strategy_dependence():
    rng = np.random.default_rng(19)
    daily = rng.normal(size=(90, 2))
    m = np.column_stack([daily, daily])
    a = report.block_diagnostic(m, 5, draws=300)
    b = report.block_diagnostic(m, 5, draws=300)
    for k in a:
        np.testing.assert_array_equal(a[k], b[k])
        np.testing.assert_array_equal(a[k][:2], a[k][2:])


def test_no_veto_bootstrap_is_not_significant():
    r = report.block_diagnostic(np.zeros((90, 2)), 20, draws=300)
    np.testing.assert_array_equal(r['p'], [1., 1.])
    np.testing.assert_array_equal(r['low'], [0., 0.])


def test_outcome_fingerprint_does_not_depend_on_selection_mask():
    f = frame(5)
    f['signal_bar_broker'] = f.features_at_broker - 300
    f['keep'] = 1
    original = report.fingerprint(f)
    f['keep'] = 0
    assert report.fingerprint(f) == original
    f.loc[0, 'net_r'] += 1
    assert report.fingerprint(f) != original
