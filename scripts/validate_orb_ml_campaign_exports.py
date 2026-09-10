"""Validate completion, causality, PnL and unchanged prior signal geometry."""
import argparse
import json
from pathlib import Path
import pandas as pd
from orb_ml_filter import load_dataset, sha256


def manifest(root):
    return pd.concat([pd.read_csv(p, sep='\t', keep_default_na=False)
        for p in root.glob('manifest_*.tsv')], ignore_index=True).drop_duplicates('id', keep='last')


def csv_path(root, row):
    return root/'Datasets'/row['path'].replace('\\', '/').split('/')[-1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--prior', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    current, previous = manifest(args.root), manifest(args.prior).set_index('id')
    assert len(current) == 53 and current.status.eq('EXPORTED').all()
    result = []
    for row in current.to_dict('records'):
        path = csv_path(args.root, row)
        frame, info = load_dataset(path)
        assert abs(frame.net_r.sum()-float(row['net_r'])) < 1e-6, row['id']
        assert info['excluded_rows'] == 0, row['id']
        assert int(info['asof_broker'])-int(info['window_from_broker']) == 1820*86400
        old = pd.read_csv(csv_path(args.prior, previous.loc[row['id']]))
        keys = ['signal_bar_broker', 'raw_direction']
        comparable = ['entry','sl','tp','execution_direction','exit_at_broker','exit_reason']
        merged = frame.merge(old, on=keys, suffixes=('_new','_old'), validate='one_to_one')
        assert len(merged) == len(frame), row['id']
        for field in comparable:
            pd.testing.assert_series_equal(merged[field+'_new'], merged[field+'_old'], check_names=False)
        valid = merged.label_valid_old.eq(1)
        pd.testing.assert_series_equal(merged.loc[valid,'net_r_new'], merged.loc[valid,'net_r_old'], check_names=False)
        removed = old.merge(frame[keys], on=keys, how='left', indicator=True)
        removed = removed[removed._merge.eq('left_only')]
        assert ((removed.features_at_broker>int(info['asof_broker']))|
                (removed.entry_at_broker>int(info['asof_broker']))).all(), row['id']
        result.append(dict(preset_id=row['id'], name=row['name'], symbol=row['symbol'],
            total_rows=len(frame), csv_sha256=sha256(path.read_bytes()),
            earliest_entry=str(pd.to_datetime(frame.entry_at_broker.min(),unit='s')),
            last_entry=str(pd.to_datetime(frame.entry_at_broker.max(),unit='s')),
            annual_rows={str(k):int(v) for k,v in pd.to_datetime(frame.entry_at_broker,unit='s').dt.year.value_counts().sort_index().items()},
            corrected_entry_timestamps=int(merged.entry_at_broker_new.ne(merged.entry_at_broker_old).sum()),
            recovered_labels=int(merged.label_valid_old.eq(0).sum()),
            future_rows_removed=len(removed), unchanged_signal_geometry=True, unchanged_existing_valid_pnl=True,
            audit_net_r=float(row['net_r']), csv_net_r=float(frame.net_r.sum()),
            bytes=path.stat().st_size))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2, allow_nan=False), encoding='utf8')
    print('PASS', len(result), 'strategies', sum(r['total_rows'] for r in result), 'trades',
          sum(r['recovered_labels'] for r in result), 'recovered labels',
          sum(r['future_rows_removed'] for r in result), 'future rows removed')


if __name__ == '__main__':
    main()
