"""Independent aggregate reconciliation and immutable-input verification."""
from collections import defaultdict
import json
from pathlib import Path
import numpy as np
import pandas as pd
import orb_regime_leaderboard as c


def verify():
    campaign=json.loads((c.OUT/'campaign.json').read_text())
    for p in campaign['provenance']:
        if c.slot.sha(Path(p['path']).read_bytes())!=p['sha256']:raise ValueError('Changed input '+p['path'])
    for p in campaign['files']:
        raw=(c.OUT/'Files/OrbML/RegimeLeaderboard'/p['name']).read_bytes()
        if c.slot.sha(raw)!=p['sha256']:raise ValueError('Changed report')
        c.slot.lines(raw,16384)
    by_id={x['preset_id']:x for x in json.loads(c.CAMPAIGN.read_text())}
    checked=0
    for row in campaign['rows']:
        if row['mode']!='VANILLA':continue
        f=pd.read_csv(by_id[row['id']]['csv']);f=f.loc[(f.label_valid==1)&(f.features_valid==1)]
        bins=defaultdict(list)
        for t in f.to_dict('records'):
            selected=[i for i in range(6) if t[f'f_regime{i}']==1]
            bucket=selected[0] if t['f_regime_valid']==1 and len(selected)==1 else 6
            bins[-1].append(t);bins[bucket].append(t)
        for cell in row['cells']:
            trades=bins[cell['bucket']];events=defaultdict(float)
            for t in trades:events[t['exit_at_broker']]+=t['net_r']
            total=0.;peak=0.;dd=0.
            for time in sorted(events):
                total+=events[time];peak=max(peak,total);dd=max(dd,peak-total)
            if len(trades)!=cell['n'] or abs(total-cell['net_r'])>1e-8 or abs(dd-cell['dd_r'])>1e-8:
                raise ValueError('Independent reconciliation '+row['id'])
            checked+=1
    # Existing full-window baseline/model results are an independent frozen control.
    previous={r['id']:r for r in json.loads((c.ROOT/'logs/OrbR7Runtime_20260912/leaderboard_5y_retrospective.json').read_text())}
    for r in campaign['rows']:
        old=previous[r['id']][{'VANILLA':'base','LEGACY':'legacy','R7':'r7'}[r['mode']]]
        if r['mode']=='R7' and r['model_sha']!=previous[r['id']]['r7_sha']:continue
        a=r['cells'][0]
        assert a['n']==old['trades'] and a['w']==old['wins'] and a['l']==old['losses']
        assert abs(a['net_r']-old['net_r'])<1e-8 and abs(a['dd_r']-old['dd_r'])<1e-8
    result=dict(independent_vanilla_cells=checked,full_window_pairs=len(campaign['rows']),verified_reports=len(campaign['files']),failed=0)
    c.slot.atomic_write(c.OUT/'verification.json',(json.dumps(result,indent=2)+'\n').encode());print(result)


if __name__=='__main__':verify()
