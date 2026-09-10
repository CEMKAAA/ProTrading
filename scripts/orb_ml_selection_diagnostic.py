"""Read-only frozen-prediction diagnostics, not training or a publish gate.

Month-matched random veto ranks require within-month exchangeability. They are
exploratory, not valid general-purpose time-series significance probabilities.
"""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
import pandas as pd


def assess(frame, draws=2000, seed=20260910):
    required = ['entry_at_broker', 'exit_at_broker', 'net_r', 'keep']
    if not set(required).issubset(frame.columns) or len(frame) == 0:
        raise ValueError('Missing prediction rows/columns')
    frame = frame.sort_values(['entry_at_broker', 'exit_at_broker']).reset_index(drop=True)
    if not np.isfinite(frame[required].to_numpy(float)).all() or not frame.keep.isin([0, 1]).all():
        raise ValueError('Invalid outcomes or selection mask')
    if (frame.exit_at_broker < frame.entry_at_broker).any():
        raise ValueError('Exit precedes entry')
    r = frame.net_r.to_numpy(float)
    keep = frame.keep.to_numpy(bool)
    months = pd.to_datetime(frame.entry_at_broker, unit='s', utc=True).dt.strftime('%Y-%m')
    rng = np.random.default_rng(seed)
    simulations = np.zeros(draws)
    expected = 0.0
    for _, indices in frame.groupby(months).groups.items():
        idx = np.asarray(indices)
        k = int(keep[idx].sum())
        expected += k / len(idx) * float(r[idx].sum())
        if k == len(idx):
            simulations += r[idx].sum()
        elif k:
            for trial in range(draws):
                simulations[trial] += r[rng.choice(idx, k, replace=False)].sum()
    actual = float(r[keep].sum())
    global_expected = float(keep.mean() * r.sum())
    fingerprint = hashlib.sha256(frame[required].to_csv(index=False, float_format='%.12g').encode()).hexdigest()
    low, high = np.quantile(simulations, [.025, .975])
    return dict(rows=len(r), retained=int(keep.sum()), retention=float(keep.mean()),
        base_net_r=float(r.sum()), ml_net_r=actual,
        raw_improvement_r=actual-float(r.sum()),
        count_matched_expected_r=global_expected,
        count_matched_excess_r=actual-global_expected,
        month_matched_expected_r=expected,
        month_matched_excess_r=actual-expected,
        random_month_net_r_q025=float(low), random_month_net_r_q975=float(high),
        random_exceeds_fraction=float((1+np.count_nonzero(simulations >= actual-1e-10))/(draws+1)),
        draws=draws, fingerprint=fingerprint)


def run(results, out, draws):
    table = pd.read_csv(results/'all_models.csv')
    table = table.loc[table.primary.astype(str).str.lower().eq('true')]
    rows, first = [], {}
    for item in table.itertuples():
        path = results/item.id/(item.family+'_prior_predictions.csv')
        before = hashlib.sha256(path.read_bytes()).hexdigest()
        result = assess(pd.read_csv(path), draws)
        if abs(result['ml_net_r']-item.ml_net_r)>1e-7 or abs(result['base_net_r']-item.base_net_r)>1e-7:
            raise ValueError('Summary/predictions mismatch: '+item.id)
        if hashlib.sha256(path.read_bytes()).hexdigest() != before:
            raise ValueError('Prediction file changed during read')
        duplicate = first.get(result['fingerprint'])
        first.setdefault(result['fingerprint'], item.id)
        rows.append(dict(id=item.id, name=item.name, family=item.family,
                         duplicate_of=duplicate, input_sha256=before, **result))
    out.mkdir(parents=True, exist_ok=True)
    payload = dict(protocol='Frozen prior-period predictions; 2018-01-01 to 2021-09-08',
        caveats=['Backward transfer, not forward validation.',
            'Same trade count is not identical notional risk, holding time or floating exposure.',
            'Monthly randomization is an exchangeability-dependent diagnostic, not an overfit certificate.',
            'Monthly retention is conditioned on the realized mask, not a deployable prospective policy.',
            'No new model, threshold, strategy selection or production activation.',
            'Rows from overlapping strategies are not independent; exact duplicates identified only.',
            'Closed-trade R subsets are not complete account/execution replay.'],
        strategies=len(rows), unique_exact_outcome_masks=len(first), models=rows)
    (out/'selection_diagnostic.json').write_text(json.dumps(payload, indent=2), encoding='utf8')
    lines=['# Frozen Model Selection Diagnostic', '', *payload['caveats'], '',
        '| Strategy | Kept | Base R | ML R | Count-matched excess R | Month-matched excess R | Random month 95% range | Random >= ML fraction |',
        '|---|---:|---:|---:|---:|---:|---:|---:|']
    for r in rows:
        lines.append(f"| {r['name']} | {r['retained']}/{r['rows']} | {r['base_net_r']:+.2f} | {r['ml_net_r']:+.2f} | {r['count_matched_excess_r']:+.2f} | {r['month_matched_excess_r']:+.2f} | [{r['random_month_net_r_q025']:+.2f}, {r['random_month_net_r_q975']:+.2f}] | {r['random_exceeds_fraction']:.4f} |")
    lines += ['', '## Exact Duplicate Outcome/Selection Series', '']
    lines += [f"- {r['id']} duplicates {r['duplicate_of']}" for r in rows if r['duplicate_of']]
    (out/'SelectionDiagnostic.md').write_text('\n'.join(lines)+'\n', encoding='utf8')
    print(json.dumps(dict(strategies=len(rows), unique_exact_outcome_masks=len(first), output=str(out))))


if __name__ == '__main__':
    p=argparse.ArgumentParser()
    p.add_argument('--results',type=Path,default=Path('logs/OrbMLPriorFive_20260910/results'))
    p.add_argument('--out',type=Path,default=Path('logs/OrbMLSelectionDiagnostic_20260910'))
    p.add_argument('--draws',type=int,default=2000)
    args=p.parse_args()
    if args.draws < 100:
        p.error('At least 100 random draws required')
    run(args.results,args.out,args.draws)
