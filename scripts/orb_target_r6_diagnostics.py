"""Post-test descriptive diagnosis, never a model selection or deployment step."""
import json
import joblib
import numpy as np
import pandas as pd
import orb_target_r6 as r6


def run():
    root = r6.ROOT
    contract = r6.verify_contract(root)
    d = json.loads((root / 'evaluation.json').read_text())
    annual = [x for x in d['annual'] if x['policy'] == 'fixed_zero']
    representatives = {g[0] for g in d['duplicate_groups']}
    forecasts = {}
    for source in contract['inputs']:
        for year in r6.YEARS:
            folder = root / source['id'] / str(year)
            assert r6.r4.checkpoint_valid(folder)
            forecasts[source['id'], year] = pd.read_csv(folder / 'predictions.csv')
    summaries = []
    for dedup in (False, True):
        for kind in r6.KINDS:
            for year in r6.YEARS:
                rows = [x for x in annual if x['kind'] == kind and x['year'] == year
                        and (not dedup or x['id'] in representatives)]
                biases = []; prevalences = []; actuals = []; retentions = []
                for x in rows:
                    f = forecasts[x['id'], year]
                    retentions.append(f['keep_' + kind + '__fixed_zero'].mean())
                    if kind != 'direct':
                        m = joblib.load(root / x['id'] / str(year) / (kind + '.research.joblib'))
                        actual = float((f.net_r > 0).mean())
                        actuals.append(actual); prevalences.append(m['prevalence'])
                        biases.append(float(f['prob_' + kind].mean()) - actual)
                summaries.append(dict(deduplicated=dedup, kind=kind, year=year, strategies=len(rows),
                    gain_positive=sum(x['test']['gain'] > 0 for x in rows),
                    skill_positive=sum(x['test']['skill'] > 0 for x in rows),
                    ranking_positive=sum(x['test_profile']['positive'] for x in rows),
                    mse_beats_training_mean=sum(x['mse'] < x['mean_baseline_mse'] for x in rows),
                    brier_beats_training_prevalence=None if kind == 'direct' else sum(
                        x['test_probability']['brier'] < x['test_probability']['prior_brier'] for x in rows),
                    median_retention=float(np.median(retentions)),
                    median_probability_bias=None if not biases else float(np.median(biases)),
                    median_train_win_rate=None if not prevalences else float(np.median(prevalences)),
                    median_test_win_rate=None if not actuals else float(np.median(actuals))))
    corrected = {}
    for metric in ('gain', 'skill', 'direct'):
        corrected[metric] = [dict(id=x['id'], kind=x['kind'], policy=x['policy']) for x in d['records']
            if x['kind'] != 'direct' and all(x['bootstrap'][str(b)][metric]['p132'] < .05 for b in (5, 20))]
    paired = []
    for policy in r6.POLICIES:
        deltas = []
        for ident in representatives:
            sub = {x['kind']:x for x in d['records'] if x['id'] == ident and x['policy'] == policy}
            deltas.append(sub['hgb_two_part']['test']['ml']['net_r'] - sub['hgb_mean']['test']['ml']['net_r'])
        paired.append(dict(policy=policy, deduplicated_strategies=len(deltas),
            conditional_magnitude_better=sum(v > 1e-8 for v in deltas),
            conditional_magnitude_worse=sum(v < -1e-8 for v in deltas),
            same=sum(abs(v) <= 1e-8 for v in deltas)))
    r6.R.dump(root / 'diagnostics.json', dict(descriptive_only=True, summaries=summaries,
        corrected_passes=corrected, magnitude_ablation=paired,
        duplicate_groups=[g for g in d['duplicate_groups'] if len(g) > 1], replacement_enabled=False))
    print(json.dumps(dict(summaries=[x for x in summaries if x['deduplicated'] and x['kind']=='logistic_mean'],
        magnitude_ablation=paired), indent=2))
    r6.verify_contract(root)


if __name__ == '__main__':
    run()
