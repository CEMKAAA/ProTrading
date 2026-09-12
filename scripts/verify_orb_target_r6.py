"""Read-only source replay of R6 forecasts, boundaries and policy decisions."""
import json
import joblib
import numpy as np
import pandas as pd
from threadpoolctl import threadpool_limits
import orb_target_r6 as r6


def raw_forecast(m, frame):
    x = r6.r4.r3.returns.design(frame)
    assert list(x.columns) == m['features']
    if m['kind'] == 'direct':
        return m['model'].predict(x), None, None, None
    c = m['classifier']
    p = c.predict_proba(x)[:, 1] if c is not None else np.full(len(frame), m['prevalence'])
    sizes = []
    for label in ('gain', 'loss'):
        v = np.full(len(frame), m[label + '_mean'])
        if m['kind'] == 'hgb_two_part':
            h = m['heads'][label]
            assert h['weight'] == (h['n'] / (h['n'] + 100.) if h['n'] >= 60 else 0.)
            if h['model'] is not None:
                v = (1 - h['weight']) * v + h['weight'] * np.maximum(0., h['model'].predict(x))
        sizes.append(v)
    gain, loss = sizes
    return p * gain - (1 - p) * loss, p, gain, loss


def confirmed(frames, scores):
    for f, s in zip(frames, scores):
        k = s >= 0
        u = r6.r4.r3.utility(f, k)
        if k.sum() < 20 or (~k).sum() < 10 or k.mean() < .4 or u['gain'] <= 0 or u['skill'] <= 0:
            return False
    return True


def run():
    root = r6.ROOT
    c = r6.verify_contract(root)
    frames, _ = r6.r4.r3.prepare()
    models = masks = direct_matches = rows = 0
    for source in c['inputs']:
        ident = source['id']; f = frames[ident]
        for year in r6.YEARS:
            folder = root / ident / str(year)
            assert r6.r4.checkpoint_valid(folder)
            cutoff, start, end = r6.r4.dates(year)
            middle = r6.R.stamp(f'{year}-03-09')
            tr = r6.R.partition(f, r6.r4.START, cutoff)
            a = r6.R.partition(f, cutoff, middle)
            b = r6.R.partition(f, middle, start)
            te = r6.R.partition(f, start, end)
            frozen = json.loads((folder / 'frozen_before_test.json').read_text())
            saved = pd.read_csv(folder / 'predictions.csv')
            results = json.loads((folder / 'result.json').read_text())
            for col in ('features_at_broker', 'signal_bar_broker', 'entry_at_broker', 'exit_at_broker', 'net_r'):
                np.testing.assert_allclose(te[col], saved[col], rtol=1e-12, atol=1e-12)
            probabilities = {}
            for kind in r6.KINDS:
                path = folder / (kind + '.research.joblib')
                assert r6.R.digest(path) == frozen['hashes'][path.name]
                m = joblib.load(path)
                assert m['identity'] == r6.r4.r3.r2.identity(tr)
                assert m['rows'] == len(tr) and m['last_label'] == int(tr.exit_at_broker.max())
                assert m['last_label'] < cutoff - r6.R.GAP
                assert int(a.exit_at_broker.max()) < middle - r6.R.GAP
                assert int(b.exit_at_broker.max()) < start - r6.R.GAP
                assert m['positive_rows'] == int((tr.net_r > 0).sum())
                np.testing.assert_allclose(m['train_mean'], tr.net_r.mean(), atol=1e-12)
                for label, values in [('gain', tr.loc[tr.net_r > 0, 'net_r']),
                                      ('loss', -tr.loc[tr.net_r <= 0, 'net_r'])]:
                    np.testing.assert_allclose(m[label + '_mean'], values.mean() if len(values) else 0.)
                sa = raw_forecast(m, a)[0]; sb = raw_forecast(m, b)[0]
                active = confirmed((a, b), (sa, sb))
                assert active == frozen['policies'][kind]['confirmed']
                np.testing.assert_allclose(np.quantile(sa, [.2, .4, .6, .8]), frozen['policies'][kind]['edges'])
                score, p, gain, loss = raw_forecast(m, te)
                np.testing.assert_allclose(score, saved['score_' + kind], rtol=1e-10, atol=1e-10)
                changed = te.copy(); changed['net_r'] = 99999.; changed['exit_at_broker'] += 999999999
                np.testing.assert_array_equal(score, raw_forecast(m, changed)[0])
                if p is not None:
                    probabilities[kind] = p
                    for prefix, value in [('prob_', p), ('gain_', gain), ('loss_', loss)]:
                        np.testing.assert_allclose(value, saved[prefix + kind], rtol=1e-10, atol=1e-10)
                for policy in r6.POLICIES:
                    k = score >= 0 if policy == 'fixed_zero' or active else np.ones(len(te), bool)
                    np.testing.assert_array_equal(k, saved['keep_' + kind + '__' + policy].to_numpy(bool))
                    result = next(x for x in results if x['kind'] == kind and x['policy'] == policy)
                    u = r6.r4.r3.utility(te, k)
                    for label in ('gain', 'skill', 'e', 'd'):
                        np.testing.assert_allclose(u[label], result['test'][label], rtol=1e-10, atol=1e-10)
                    masks += 1
                if kind == 'direct' and year in r6.r4.YEARS:
                    old = joblib.load(r6.r4.ROOT / ident / str(year) / 'hgb__all.research.joblib')
                    np.testing.assert_allclose(score, r6.r4.predict(old, te), rtol=1e-10, atol=1e-10)
                    direct_matches += 1
                models += 1
            np.testing.assert_array_equal(probabilities['hgb_mean'], probabilities['hgb_two_part'])
            if year != 2025:
                assert 'incumbent_keep' not in saved
            else:
                np.testing.assert_array_equal(r6.r4.r3.incumbent(source, te), saved.incumbent_keep.to_numpy(bool))
                fair = max(start, source['incumbent_information_end'] + r6.R.GAP + 1)
                np.testing.assert_array_equal(te.features_at_broker >= fair, saved.fair_pair.to_numpy(bool))
            rows += len(te)
        print(ident, 'verified', flush=True)
    assert models == 352 and masks == 704 and direct_matches == 44
    r6.verify_contract(root)
    result = dict(models_replayed=models, masks_replayed=masks, source_test_rows=rows,
        r4_direct_matches=direct_matches, source_label_and_boundary_checks=True,
        calibration_rules_recomputed=True, probability_and_severity_identity=True,
        future_outcome_mutation_invariant=True, incumbent_scope_verified=True,
        production_files_unchanged=len(c['production']), execution_replay_completed=False,
        prospective_shadow_completed=False, replacement_enabled=False)
    r6.R.dump(root / 'verification.json', result)
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    with threadpool_limits(limits=1):
        run()
