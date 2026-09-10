"""Checkpointed offline campaign; reads Common CSVs, writes only research output."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import time

# Bound CPU fan-out so research does not starve live terminals.
os.environ.setdefault('OMP_NUM_THREADS', '1')
os.environ.setdefault('OPENBLAS_NUM_THREADS', '1')
os.environ.setdefault('MKL_NUM_THREADS', '1')
import numpy as np
import pandas as pd
from threadpoolctl import threadpool_limits

from orb_ml_filter import load_dataset, temporal_split, train, portable_predict, FEATURES, atomic_write
from orb_ml_return_campaign import fit, family_uncertainty


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    # Resume only identical executable research code; no reuse across silent edits.
    code = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in
            [Path(__file__), Path(__file__).with_name('orb_ml_filter.py'),
             Path(__file__).with_name('orb_ml_research.py'), Path(__file__).with_name('orb_ml_return_campaign.py')]}
    provenance = args.out/'code_hashes.json'
    if provenance.exists() and json.loads(provenance.read_text()) != code:
        raise ValueError('Code changed: use a new output directory, do not overwrite frozen results')
    atomic_write(provenance, json.dumps(code, indent=2).encode())
    manifests = [pd.read_csv(p, sep='\t', keep_default_na=False) for p in args.root.glob('manifest_*.tsv')]
    manifest = pd.concat(manifests, ignore_index=True).drop_duplicates('id', keep='last').sort_values('index')
    if len(manifest) != 53 or not (manifest.status == 'EXPORTED').all():
        raise ValueError('Expected 53 completed strategy exports; inspect manifests first')
    records = []
    for pos, row in enumerate(manifest.to_dict('records'), 1):
        dest = args.out/row['id']
        dest.mkdir(exist_ok=True)
        state_path = dest/'state.json'
        csv = args.root/'Datasets'/Path(row['path'].replace('\\', '/')).name
        digest = hashlib.sha256(csv.read_bytes()).hexdigest()
        if state_path.exists():
            state = json.loads(state_path.read_text())
            if state['csv_sha256'] != digest: raise ValueError('Dataset changed after training')
            records.append(state)
            print(f'{pos}/53 RESUME {row["id"]}', flush=True)
            continue
        started = time.monotonic()
        state = dict(preset_id=row['id'], name=row['name'], symbol=row['symbol'],
                     csv=str(csv), csv_sha256=digest, export=row, models={})
        print(f'{pos}/53 START {row["id"]}', flush=True)
        try:
            frame, info = load_dataset(csv)
            state['dataset'] = info
            state['coverage'] = dict(first_entry=int(frame.entry_at_broker.min()),
                last_entry=int(frame.entry_at_broker.max()), rows_by_year={str(k): int(v) for k,v in
                pd.to_datetime(frame.entry_at_broker, unit='s').dt.year.value_counts().sort_index().items()})
            if abs(float(frame.net_r.sum())-float(row['net_r'])) > 1e-6:
                raise ValueError('CSV label sum differs from MQL audit manifest')
            for family in ('mlp', 'return'):
                try:
                    with threadpool_limits(limits=1):
                        if family == 'mlp':
                            last = [-1]
                            def progress(pct, message):
                                bucket = int(pct)//20
                                if bucket > last[0]:
                                    print(f'  {row["id"]} MLP {pct:.0f}% {message}', flush=True)
                                    last[0] = bucket
                            report = train(csv, dest/'mlp', advanced=True, epochs=400, publish=False, progress=progress)
                            _, _, test = temporal_split(frame)
                            bundle = (dest/'mlp'/(info['config_hash']+'.candidate.model')).read_bytes()
                            probs = portable_predict(bundle, test[FEATURES].to_numpy(float), info['config_hash'])
                            keep = probs >= report['threshold']
                            report['family_uncertainty'] = family_uncertainty(test, keep)
                            pred = test[['features_at_broker','entry_at_broker','exit_at_broker','net_r','label_win']].copy()
                            pred['probability'] = probs; pred['keep'] = keep.astype(int)
                            atomic_write(dest/'mlp'/'test_predictions.csv', pred.to_csv(index=False).encode())
                            atomic_write(dest/'mlp'/'campaign_report.json', json.dumps(report, indent=2, allow_nan=False).encode())
                        else:
                            report = fit(frame, dest/'return')
                    state['models'][family] = dict(status='TRAINED', test=report['test'],
                        baseline=report['test_baseline'], family_uncertainty=report['family_uncertainty'],
                        local_checks=report['deployment_checks_passed'], published=False)
                except Exception as exc:
                    state['models'][family] = dict(status='BLOCKED', error=f'{type(exc).__name__}: {exc}')
                    print(f'  {family} BLOCKED {exc}', flush=True)
            state['status'] = 'PROCESSED'
        except Exception as exc:
            state['status'] = 'DATA_BLOCKED'; state['error'] = f'{type(exc).__name__}: {exc}'
            print(f'  DATA BLOCKED {exc}', flush=True)
        state['elapsed_seconds'] = round(time.monotonic()-started, 2)
        atomic_write(state_path, json.dumps(state, indent=2, allow_nan=False).encode())
        records.append(state)
        atomic_write(args.out/'campaign.json', json.dumps(records, indent=2, allow_nan=False).encode())
        print(f'{pos}/53 END {row["id"]} {state["elapsed_seconds"]}s', flush=True)
    atomic_write(args.out/'campaign.json', json.dumps(records, indent=2, allow_nan=False).encode())
    print('CAMPAIGN COMPLETE; NO MODEL ACTIVATED', flush=True)


if __name__ == '__main__':
    main()
