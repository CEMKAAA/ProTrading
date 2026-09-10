"""Build a read-only dashboard snapshot; never publish or activate a model."""
import argparse
import json
import math
from pathlib import Path

import numpy as np

try:
    from .orb_ml_filter import load_dataset, temporal_split, metrics
except ImportError:
    from orb_ml_filter import load_dataset, temporal_split, metrics


def score(wins, trades, drawdown):
    if trades <= 0 or not 0 <= wins <= trades or not math.isfinite(drawdown) or drawdown < 0:
        return 0.0
    p, z = wins / trades, 1.96
    lower = (p + z*z/(2*trades) - z*math.sqrt(p*(1-p)/trades + z*z/(4*trades*trades))) / (1+z*z/trades)
    return 100 * lower / (1 + drawdown)


def choose_family(reports, validation_base):
    # Never choose the family on test WR, drawdown or leaderboard rank.
    eligible = [(r['validation']['net_r'] - validation_base, family)
                for family, r in reports.items()]
    return max(eligible, key=lambda v: (v[0], v[1] == 'mlp'))[1] if eligible else None


def quote(value):
    return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"').replace('\n', ' ') + '"'


def build(root, dest):
    records = []
    for state in json.loads((root / 'campaign.json').read_text(encoding='utf8')):
        frame, info = load_dataset(Path(state['csv']))
        if info['excluded_rows']:
            raise ValueError('Leaderboard cannot silently omit invalid labels')
        _, validation, test = temporal_split(frame)
        base = metrics(test, np.ones(len(test)), 0)
        validation_base = metrics(validation, np.ones(len(validation)), 0)['net_r']
        reports = {}
        for family, filename in [('mlp', 'campaign_report.json'), ('return', 'report.json')]:
            path = root / state['preset_id'] / family / filename
            if state['models'].get(family, {}).get('status') == 'TRAINED':
                reports[family] = json.loads(path.read_text(encoding='utf8'))
        selected = choose_family(reports, validation_base)
        report = reports.get(selected)
        filtered = report['test'] if report else None
        if report and (abs(report['test_baseline']['net_r'] - base['net_r']) > 1e-7
                       or report['test_baseline']['trades'] != base['trades']):
            raise ValueError('Baseline and filtered periods do not match')
        records.append(dict(id=state['preset_id'], name=state['name'], symbol=state['symbol'],
                            config=info['config_hash'], baseline=base, filtered=filtered, family=selected,
                            from_broker=int(test.entry_at_broker.min()), to_broker=int(test.entry_at_broker.max()),
                            baseline_score=score(base['wins'], base['trades'], base['peak_drawdown_r']),
                            filtered_score=score(filtered['wins'], filtered['trades'], filtered['peak_drawdown_r']) if filtered else 0,
                            status='RESEARCH' if filtered else 'NO MODEL'))
    lines = ['// Generated frozen 2026-09-09 test snapshot. NOT a model registry.',
             'int OrbLbSnapshotCount(){return '+str(len(records))+';}',
             'bool OrbLbSnapshot(int index,OrbLbRow &r)', '{', '   switch(index)', '   {']
    for i, r in enumerate(records):
        b, m = r['baseline'], r['filtered']
        line = f'      case {i}: r.id={quote(r["id"])};r.name={quote(r["name"])};r.symbol={quote(r["symbol"])};'
        line += f'r.family={quote(r["family"] or "NONE")};r.hasMl={str(m is not None).lower()};'
        line += f'r.fromTime=(datetime){r["from_broker"]};r.toTime=(datetime){r["to_broker"]};'
        for prefix, data, sc in [('base', b, r['baseline_score']), ('ml', m, r['filtered_score'])]:
            data = data or dict(trades=0, win_rate=0, net_r=0, peak_drawdown_r=0)
            line += ''.join(f'r.{prefix}{field}={value:.12f};' for field, value in [
                ('Wr', 100*data['win_rate']), ('R', data['net_r']), ('Dd', data['peak_drawdown_r']), ('Score', sc)])
            line += f'r.{prefix}N={data["trades"]};'
        lines.append(line+'return true;')
    lines += ['   }', '   return false;', '}']
    dest.write_text('\n'.join(lines)+'\n', encoding='utf8')
    (root/'leaderboard.json').write_text(json.dumps(records, indent=2, ensure_ascii=False), encoding='utf8')
    print(f'Leaderboard: {len(records)} strategies; research only; no model publication')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--campaign', type=Path, required=True)
    parser.add_argument('--header', type=Path, required=True)
    args = parser.parse_args()
    build(args.campaign, args.header)
