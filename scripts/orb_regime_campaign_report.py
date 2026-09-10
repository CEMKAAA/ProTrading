"""Post-freeze diagnostics only. Cannot select, train, or deploy campaign models."""
from pathlib import Path
import argparse
import json
import hashlib
import joblib
import numpy as np
import pandas as pd
from threadpoolctl import threadpool_limits
from orb_regime_campaign import CANDIDATES, SEED, dump, digest, stats, selection_value
from orb_ml_filter import atomic_write


def daily_contrasts(frame, identities, start, end):
    days = np.arange(start, end+1)
    matrix = np.zeros((len(days), 2*len(identities)))
    for j, ident in enumerate(identities):
        f = frame.loc[frame.strategy == ident].copy()
        keep = f.keep.to_numpy(bool)
        months = pd.to_datetime(f.entry_at_broker, unit='s', utc=True).dt.strftime('%Y-%m')
        q = pd.Series(keep.astype(float), index=f.index).groupby(months).transform('mean').to_numpy()
        y = f.net_r.to_numpy(float)
        ix = (f.exit_at_broker.to_numpy()//86400-start).astype(int)
        np.add.at(matrix[:, 2*j], ix, y*(keep.astype(float)-1.))
        np.add.at(matrix[:, 2*j+1], ix, y*(keep.astype(float)-q))
    return matrix


def block_diagnostic(matrix, block, draws=20000, seed=SEED):
    # Identical blocks across all strategies preserve cross-strategy dependence.
    # Circular moving blocks assume approximate stationarity; this is exploratory.
    rng = np.random.default_rng(seed+block)
    n, k = matrix.shape
    actual = matrix.sum(axis=0)
    distribution = np.empty((draws, k))
    for lo in range(0, draws, 200):
        size = min(200, draws-lo)
        starts = rng.integers(0, n, size=(size, (n+block-1)//block))
        indices = ((starts[:, :, None]+np.arange(block)) % n).reshape(size, -1)[:, :n]
        counts = np.stack([np.bincount(x, minlength=n) for x in indices]).astype(float)
        distribution[lo:lo+size] = counts @ matrix
    null_distribution = distribution-actual
    p = (1+(null_distribution >= actual-1e-12).sum(axis=0))/(draws+1)
    return dict(actual=actual, low=np.quantile(distribution, .025, axis=0),
                high=np.quantile(distribution, .975, axis=0), p=p)


def fingerprint(f):
    cols = ['signal_bar_broker', 'entry_at_broker', 'exit_at_broker', 'net_r']
    return hashlib.sha256(f.sort_values(cols[:3])[cols].to_csv(index=False, float_format='%.12g').encode()).hexdigest()


def run(root, draws):
    contract = json.loads((root/'contract.json').read_text())
    identities = sorted(r['id'] for r in contract['inputs'])
    names = {r['id']:r['name'] for r in contract['inputs']}
    parts=[]; annual=[]; ablations=[]
    model_checks=[]
    for year in (2024, 2025, 2026):
        folder = root/str(year)
        checkpoint = json.loads((folder/'complete.json').read_text())
        for name, sha in checkpoint['artifacts'].items():
            if digest(folder/name) != sha:
                raise ValueError('Changed frozen artifact: '+name)
        for path in folder.glob('*/*.joblib'):
            # Artifacts were generated here and verified against the frozen manifest.
            bundle = joblib.load(path)
            models = bundle.values() if path.name.startswith('local_') else [bundle]
            boundary = int(pd.Timestamp(f'{year-1}-'+('01-01' if path.parent.name=='development' else '07-01'),
                                       tz='UTC').timestamp())
            for model in models:
                if model is None:
                    continue
                scaler = model['scaler']
                if not np.isfinite(scaler.scale_).all() or (scaler.scale_ <= 0).any():
                    raise ValueError('Invalid trained scaler')
                if model['train_label_max'] >= boundary-86400:
                    raise ValueError('Training label crossed chronological boundary')
                if 'stop_start' in model and model['fit_label_max'] >= model['stop_start']-86400:
                    raise ValueError('Internal fit/stop overlap')
                negative = np.flatnonzero(scaler.var_ < 0)
                model_checks.append(dict(file=str(path.relative_to(root)), kind=model['kind'],
                    tiny_negative_variances=[dict(feature=model['features'][j], variance=float(scaler.var_[j]),
                        scale=float(scaler.scale_[j])) for j in negative]))
        parts.append(pd.read_csv(folder/'predictions.csv'))
        annual.extend(json.loads((folder/'summary.json').read_text()))
        ablations.extend(json.loads((folder/'ablations.json').read_text()))
    f = pd.concat(parts, ignore_index=True)
    if not f.keep.isin([0, 1]).all():
        raise ValueError('Invalid mask')
    records=[]; regime_rows=[]; comparisons=[]
    for ident in identities:
        s = f.loc[f.strategy == ident].copy()
        if s.empty:
            continue
        keep = s.keep.to_numpy(bool)
        base = stats(s, np.ones(len(s), bool)); ml = stats(s, keep)
        records.append(dict(id=ident, name=names[ident], symbol=str(s.symbol.iloc[0]), base=base, ml=ml,
            **selection_value(s, keep), fingerprint=fingerprint(s),
            active_years=[int(y) for y in sorted(s.loc[s.kind != 'NO_VETO', 'year'].unique())]))
        for r in range(6):
            g = s.loc[s['f_regime'+str(r)] == 1]
            regime_rows.append(dict(id=ident, regime=r, base=stats(g, np.ones(len(g), bool)),
                ml=stats(g, g.keep.to_numpy(bool))))
        for family in ('local', 'pool'):
            a = 'keep_'+family+'_base'; b = 'keep_'+family+'_regime'
            matched = s.loc[s[a].notna() & s[b].notna()] if a in s and b in s else s.iloc[:0]
            if matched.empty:
                continue
            ma = stats(matched, matched[a].to_numpy(bool)); mb = stats(matched, matched[b].to_numpy(bool))
            va = selection_value(matched, matched[a].to_numpy(bool)); vb = selection_value(matched, matched[b].to_numpy(bool))
            comparisons.append(dict(id=ident, family=family, matched_rows=len(matched),
                no_regime=ma, regime=mb, delta_r=mb['net_r']-ma['net_r'],
                delta_month_skill_r=vb['skill']-va['skill']))
    identities = [r['id'] for r in records]
    first = int(pd.Timestamp('2024-01-01', tz='UTC').timestamp())//86400
    last = int(contract['cutoff'])//86400
    matrix = daily_contrasts(f, identities, first, last)
    uncertainty={}
    for block in (5, 20):
        print(f'Block sensitivity {block} days: {draws} paired resamples', flush=True)
        result = block_diagnostic(matrix, block, draws)
        for j, record in enumerate(records):
            if not np.allclose(result['actual'][2*j:2*j+2], [record['gain'], record['skill']]):
                raise ValueError('Daily aggregation differs from trade diagnostics')
            item={}
            for offset, metric in enumerate(('gain', 'month_skill')):
                k=2*j+offset
                item[metric]=dict(low=float(result['low'][k]), high=float(result['high'][k]),
                    p_one_sided=float(result['p'][k]),
                    p_bonferroni_53=float(min(1., result['p'][k]*53)))
            uncertainty.setdefault(record['id'], {})[str(block)] = item
    for record in records:
        record['block_sensitivity'] = uncertainty[record['id']]
        record['exploratory_family_pass'] = bool(record['gain'] > 0 and record['skill'] > 0 and
            all(uncertainty[record['id']][str(b)][m]['p_bonferroni_53'] < .05
                for b in (5, 20) for m in ('gain', 'month_skill')))
    duplicate_groups={}
    for r in records:
        duplicate_groups.setdefault(r['fingerprint'], []).append(r['id'])
    duplicates=[v for v in duplicate_groups.values() if len(v)>1]
    payload=dict(research_only=True, fresh_holdout=False, draws=draws, strategy_count=len(records),
        unique_outcome_series=len(duplicate_groups), duplicates=duplicates, records=records,
        trained_models_checked=len(model_checks), model_checks=model_checks,
        annual=annual, matched_regime_ablations=comparisons, regime_results=regime_rows,
        warning='Closed-trade R, not floating/EOD/account DD. Historical strategy-selection bias remains. '
                'Bootstrap correction covers 53 frozen policies, NOT all earlier research or post-hoc ablations.')
    dump(root/'evaluation.json', payload)
    rows=[]
    for r in records:
        rows.append(dict(id=r['id'], name=r['name'], symbol=r['symbol'], active_years=','.join(map(str,r['active_years'])),
            base_n=r['base']['trades'], selected_n=r['ml']['trades'], base_r=r['base']['net_r'], ml_r=r['ml']['net_r'],
            gain_r=r['gain'], month_skill_r=r['skill'], base_wr=r['base']['wr'], ml_wr=r['ml']['wr'],
            base_dd_r=r['base']['dd_r'], ml_dd_r=r['ml']['dd_r'], retention=r['ml']['retention'],
            exploratory_family_pass=r['exploratory_family_pass']))
    atomic_write(root/'comparison.csv', pd.DataFrame(rows).to_csv(index=False).encode())
    lines=['# ORB Regime Campaign R1 Results', '',
        'Research only. No deployment. Test years were previously inspected during strategy research.', '',
        '## Design', '',
        '53 frozen datasets; shared chronological boundaries; original feature availability; 24h label purge.',
        'Six prespecified models, validation-only thresholds/model choices, then frozen annual test.',
        'Regime models use six existing states, age/transition/depth, RF01-RF12 and fixed interactions.',
        'NO_VETO keeps the existing strategy when validation does not support a filter.', '',
        '## Annual Frozen Policy', '', '| Year | Scored | Active filters | Improved R | Worse R | Unchanged |',
        '|---|---:|---:|---:|---:|---:|']
    for year in (2024,2025,2026):
        a=[x for x in annual if x['year']==year and x['status']=='scored']
        lines.append(f'| {year}'+(' partial' if year==2026 else '')+
            f' | {len(a)} | {sum(x["kind"]!="NO_VETO" for x in a)} | '+
            f'{sum(x["gain"]>1e-8 for x in a)} | {sum(x["gain"]< -1e-8 for x in a)} | '+
            f'{sum(abs(x["gain"])<=1e-8 for x in a)} |')
    lines += ['', '## Aggregate By Strategy', '',
        'These are separate strategy experiments, NOT an additive fund portfolio. Ranking below is descriptive only.',
        '', '| Strategy | Base N / ML N | Base R / ML R | Gain R | Month-matched skill R | Base WR / ML WR | Base DD / ML DD (R) |',
        '|---|---:|---:|---:|---:|---:|---:|']
    for r in sorted(records, key=lambda x:x['gain'], reverse=True):
        a,b=r['base'],r['ml']
        wr=lambda x:'n/a' if x is None else f'{100*x:.1f}%'
        lines.append(f'| {r["id"]} | {a["trades"]} / {b["trades"]} | {a["net_r"]:+.2f} / {b["net_r"]:+.2f} | '+
            f'{r["gain"]:+.2f} | {r["skill"]:+.2f} | {wr(a["wr"])} / {wr(b["wr"])} | {a["dd_r"]:.2f} / {b["dd_r"]:.2f} |')
    lines += ['', '## Does Regime Information Help?', '',
        'Paired candidates below share rows, training dates, regularization and threshold grid; only regime features differ.',
        'Thresholds differ because each was calibrated on pre-test data. This is feature-family ablation, not a deployable new selection.', '',
        '| Family | Matched strategies | Regime improves R | Regime worsens R | Same R | Improves month skill |',
        '|---|---:|---:|---:|---:|---:|']
    for family in ('local', 'pool'):
        a=[x for x in comparisons if x['family']==family]
        lines.append(f'| {family} | {len(a)} | {sum(x["delta_r"]>1e-8 for x in a)} | '+
            f'{sum(x["delta_r"]< -1e-8 for x in a)} | {sum(abs(x["delta_r"])<=1e-8 for x in a)} | '+
            f'{sum(x["delta_month_skill_r"]>1e-8 for x in a)} |')
    passes=[r['id'] for r in records if r['exploratory_family_pass']]
    lines += ['', '## Uncertainty And Limitations', '',
        f'- {len(duplicate_groups)} distinct exact outcome series among {len(records)} strategies. Related series are still dependent.',
        f'- {draws} paired circular daily-block resamples; sensitivity at 5 and 20 calendar days; same blocks across strategies.',
        '- Both improvement over base and month-count-matched selection skill must pass each block sensitivity.',
        f'- Exploratory Bonferroni-53 passes: {len(passes)}. '+(', '.join(passes) if passes else 'None.'),
        '- Correction does not erase earlier strategy/feature research, reused holdouts, or post-hoc analysis of all six families.',
        '- Approximate stationary block resampling is not a guarantee in changing regimes. Months include exposure controls, not equal holding-time risk.',
        '- Input features/labels pass schema and chronological guards; this does not independently certify every historical simulator assumption.',
        '- SL/TP/ATR geometry is known at the candidate entry; exit, cost_r, net_r, MFE/MAE and labels are excluded from model inputs.',
        '- Annual boundary purging excludes crossing or late-closing trades. This is not an uninterrupted account replay.',
        '- Filtering frozen trades does not resimulate subsequent stateful position availability. Validate execution state before any deployment.',
        '- Closed-trade drawdown does not cover floating PnL, broker slippage, currency conversion, margin or EOD trailing drawdown.',
        '- Dataset net R inherits the existing simulator cost assumptions. No future fill/cost information is used as a feature.',
        f'- {len(model_checks)} fitted bundles passed finite scaler and chronological-label checks. '+
        f'{sum(bool(m["tiny_negative_variances"]) for m in model_checks)} scalers have tiny negative roundoff variance; '+
        'per-feature values and effective scales are recorded in evaluation.json. Models were not modified after freezing.',
        '- 2026 is partial; 2024-2026 is not a fresh ten-year forward test.',
        '- No model, strategy, or threshold is promoted automatically. A frozen new forward paper period remains necessary.', '',
        '## Files', '',
        '`contract.json`: code and dataset hashes. `<year>/frozen_before_test.json`: selection before scoring.',
        '`<year>/development.json`: all candidates including failures. `evaluation.json`: per-regime and block diagnostics.',
        '`comparison.csv`: sortable strategy comparison. Model artifacts end in `.research.joblib`.', '']
    atomic_write(root/'Results.md', '\n'.join(lines).encode())
    print(f'Report complete: {len(records)} strategies; exploratory family passes={len(passes)}', flush=True)


if __name__ == '__main__':
    p=argparse.ArgumentParser()
    p.add_argument('--root', type=Path, default=Path('logs/OrbRegimeCampaign_20260910_R1'))
    p.add_argument('--draws', type=int, default=20000)
    a=p.parse_args()
    with threadpool_limits(limits=1):
        run(a.root,a.draws)
