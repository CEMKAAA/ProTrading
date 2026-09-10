"""Deterministic read-only analysis of frozen campaign results."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import pandas as pd


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    states = json.loads((args.out/'campaign.json').read_text())
    summary, years, regimes = [], [], []
    for state in states:
        for family in ('mlp', 'return'):
            result = state['models'].get(family, {})
            row = dict(preset_id=state['preset_id'], name=state['name'], symbol=state['symbol'], family=family,
                status=result.get('status', state['status']), rows=state.get('dataset', {}).get('usable_rows'),
                error=result.get('error', state.get('error', '')), csv=state['csv'])
            if result.get('status') == 'TRAINED':
                base, model = result['baseline'], result['test']
                row.update(test_base_r=base['net_r'], test_model_r=model['net_r'],
                    uplift_r=model['net_r']-base['net_r'], base_wr=100*base['win_rate'], model_wr=100*model['win_rate'],
                    test_base_trades=base['trades'], test_model_trades=model['trades'], retention=model['retention'],
                    base_dd_r=base['peak_drawdown_r'], model_dd_r=model['peak_drawdown_r'],
                    base_mincum_r=base['min_cumulative_r'], model_mincum_r=model['min_cumulative_r'],
                    family_pass=result['family_uncertainty']['passed'],
                    corrected_p=result['family_uncertainty']['p_bonferroni'],
                    local_checks=result['local_checks'])
                pred = pd.read_csv(args.out/state['preset_id']/family/'test_predictions.csv')
                row['test_from_broker'] = str(pd.to_datetime(pred.entry_at_broker.min(), unit='s'))
                row['test_to_broker'] = str(pd.to_datetime(pred.entry_at_broker.max(), unit='s'))
                raw = pd.read_csv(state['csv'])
                keys = ['features_at_broker', 'entry_at_broker', 'exit_at_broker']
                features = raw[keys + ['f_regime'+str(n) for n in range(6)]]
                merged = pred.merge(features, on=keys, validate='one_to_one')
                merged['year'] = pd.to_datetime(merged.entry_at_broker, unit='s').dt.year
                merged['regime'] = np.where(merged[['f_regime'+str(n) for n in range(6)]].sum(axis=1)>0,
                    merged[['f_regime'+str(n) for n in range(6)]].to_numpy().argmax(axis=1), -1)
                for key, dest in [('year', years), ('regime', regimes)]:
                    for group, frame in merged.groupby(key):
                        selected = frame[frame.keep.eq(1)]
                        dest.append(dict(preset_id=state['preset_id'], name=state['name'], family=family,
                            group=int(group), base_trades=len(frame), kept_trades=len(selected),
                            base_net_r=float(frame.net_r.sum()), model_net_r=float(selected.net_r.sum()),
                            base_wr=float(frame.net_r.gt(0).mean()),
                            model_wr=float(selected.net_r.gt(0).mean()) if len(selected) else None))
            summary.append(row)
    pd.DataFrame(summary).to_csv(args.out/'all_strategies.csv', index=False, encoding='utf-8-sig')
    pd.DataFrame(years).to_csv(args.out/'test_by_year.csv', index=False, encoding='utf-8-sig')
    pd.DataFrame(regimes).to_csv(args.out/'test_by_regime.csv', index=False, encoding='utf-8-sig')
    size = sum(Path(s['csv']).stat().st_size for s in states)
    eligible = [r for r in summary if r['status']=='TRAINED']
    counts = dict(strategies=len(states), datasets_bytes=size,
        trained_models=len(eligible), trained_strategies=len(set(r['preset_id'] for r in eligible)),
        positive_uplift=sum(r['uplift_r']>1e-9 for r in eligible),
        family_pass=sum(r['family_pass'] for r in eligible),
        input_rows=sum(s.get('dataset', {}).get('total_rows', 0) for s in states),
        excluded_rows=sum(s.get('dataset', {}).get('excluded_rows', 0) for s in states))
    (args.out/'counts.json').write_text(json.dumps(counts, indent=2), encoding='utf8')
    print(json.dumps(counts, indent=2))
    table = pd.DataFrame(eligible)
    if len(table): print(table.sort_values('uplift_r', ascending=False)[['name','family','test_base_r','test_model_r','uplift_r','retention','corrected_p']].head(12).to_string(index=False))
    # Self-contained index: all failures stay visible, no automatic model loading.
    lines = ['# Frozen Campaign Results', '', 'Research only. No model activated. See the main methodology report.', '',
             '| Strategy | Symbol | Model | Test baseline R | Test filtered R | Retained | Status |',
             '|---|---|---|---:|---:|---:|---|']
    for r in summary:
        safe = r['name'].replace('|', '/')
        if r['status']=='TRAINED':
            lines.append(f"| {safe} | {r['symbol']} | {r['family']} | {r['test_base_r']:.2f} | {r['test_model_r']:.2f} | {r['retention']:.1%} | {'family diagnostic passed' if r['family_pass'] else 'not validated'} |")
        else:
            lines.append(f"| {safe} | {r['symbol']} | {r['family']} | - | - | - | {r['error'].replace('|','/')} |")
    (args.out/'Results.md').write_text('\n'.join(lines)+'\n', encoding='utf8')
    artifacts = {str(p.relative_to(args.out)): hashlib.sha256(p.read_bytes()).hexdigest()
                 for p in args.out.rglob('*') if p.is_file() and p.name!='artifact_checksums.json'}
    (args.out/'artifact_checksums.json').write_text(json.dumps(artifacts, indent=2), encoding='utf8')


if __name__ == '__main__':
    main()
