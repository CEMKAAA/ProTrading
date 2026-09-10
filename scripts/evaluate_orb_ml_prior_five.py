"""Frozen-weight backward stability test, not chronological forward validation.

No fit, threshold selection, model promotion or production file writes.
"""
import argparse
import hashlib
import json
from pathlib import Path

import joblib
import numpy as np
import pandas as pd

from orb_ml_filter import FEATURES, load_dataset, metrics, portable_predict
from orb_ml_return_campaign import design
from export_orb_campaign_models import numeric_hash


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def compare_settings(old, new):
    a, b = old.read_text(encoding='utf8').splitlines(), new.read_text(encoding='utf8').splitlines()
    if a[:4] != b[:4] or numeric_hash(a[4:]) != numeric_hash(b[4:]):
        raise ValueError('Preset, symbol, TF, inputs, runtime or costs changed: '+old.stem)


def describe(frame, keep):
    return metrics(frame, np.asarray(keep, dtype=float), .5)


def evaluate(common, campaign, out):
    states = {s['preset_id']: s for s in json.loads((campaign/'campaign.json').read_text()) if s['symbol']=='USDJPYm'}
    selected = {r['id']: r['family'] for r in json.loads((campaign/'leaderboard.json').read_text())}
    exports = common/'OrbMLPriorFive_20260910'
    manifests = pd.read_csv(exports/'manifest_USDJPYm.tsv', sep='\t')
    manifests = manifests.loc[manifests.status.eq('EXPORTED')].drop_duplicates('id', keep='last').set_index('id')
    if set(states) != set(manifests.index):
        raise ValueError('USDJPY exports incomplete: '+str(set(states)-set(manifests.index)))
    # Year-level M1/M5 coverage found 2016 daily-density bars and partial 2017.
    # Fix this data-quality mask BEFORE seeing model results; do not optimize it.
    floor = int(pd.Timestamp('2018-01-01', tz='UTC').timestamp())
    ceiling = int(pd.Timestamp('2021-09-09', tz='UTC').timestamp())
    records, yearly, integrity = [], [], []
    out.mkdir(parents=True, exist_ok=True)
    for ident, state in states.items():
        export = manifests.loc[ident]
        path = common/Path(export['path'].replace('\\','/'))
        frame, info = load_dataset(path)
        trained, train_info = load_dataset(Path(state['csv']))
        if train_info['dataset_sha256'] != state['csv_sha256']:
            raise ValueError('Training CSV mutated: '+ident)
        compare_settings(common/'OrbMLCampaign_20260909_v3'/'Settings'/(ident+'.txt'), exports/'Settings'/(ident+'.txt'))
        for field in ['schema','preset_id','symbol','broker','signal_tf_seconds','chart_tf_seconds']:
            if info[field] != train_info[field]:
                raise ValueError('Feature/strategy identity mismatch: '+field)
        if int(info['asof_broker']) != ceiling:
            raise ValueError('Wrong historical cutoff')
        period = frame.loc[(frame.features_at_broker>=floor)&(frame.entry_at_broker>=floor)
            &(frame.features_at_broker<ceiling)&(frame.exit_at_broker<ceiling)].copy()
        if period.empty or period.exit_at_broker.max()>=trained.features_at_broker.min():
            raise ValueError('No independent older observations or temporal overlap')
        base = describe(period, np.ones(len(period), dtype=bool))
        raw = pd.read_csv(path)
        qualified = raw.loc[(raw.features_at_broker>=floor)&(raw.entry_at_broker>=floor)&(raw.features_at_broker<ceiling)]
        integrity.append(dict(id=ident, export_sha256=info['dataset_sha256'], training_sha256=train_info['dataset_sha256'],
            exported_rows=len(raw), density_qualified=len(qualified), evaluated=len(period),
            feature_invalid=int(qualified.features_valid.ne(1).sum()), unresolved_or_invalid=int(qualified.label_valid.ne(1).sum()),
            old_entry_min=int(period.entry_at_broker.min()),old_exit_max=int(period.exit_at_broker.max()),
            training_entry_min=int(trained.features_at_broker.min()), settings_identical=True))
        for family in ['mlp','return']:
            folder=campaign/ident/family
            config=train_info['config_hash']
            model_path=folder/(config+'.candidate.model') if family=='mlp' else folder/'return_model.research.joblib'
            if not model_path.exists():
                continue
            before=digest(model_path)
            if family=='mlp':
                data=model_path.read_bytes()
                lines=data.decode('ascii').splitlines()
                if lines[4] != train_info['dataset_sha256']:
                    raise ValueError('Model training dataset mismatch')
                scores=portable_predict(data,period[FEATURES].to_numpy(float),config)
                threshold=float(lines[6]);active=True
            else:
                bundle=joblib.load(model_path)  # Trusted local training artifact only.
                x=design(period)
                if list(x.columns)!=bundle['features']:
                    raise ValueError('Return feature order changed')
                scores=bundle['model'].predict(x)
                threshold=float(bundle['threshold']);active=bool(bundle['active'])
            if not np.isfinite(scores).all():
                raise ValueError('Non-finite model prediction')
            keep=scores>=threshold if active else np.ones(len(period),dtype=bool)
            filtered=describe(period,keep)
            if digest(model_path)!=before:
                raise ValueError('Model mutated during test')
            row=dict(id=ident,name=state['name'],family=family,primary=selected[ident]==family,active=active,
                threshold=threshold,model_sha256=before,from_broker='2018-01-01',to_broker_exclusive='2021-09-09',
                delta_r=filtered['net_r']-base['net_r'])
            row.update({'base_'+k:v for k,v in base.items()})
            row.update({'ml_'+k:v for k,v in filtered.items()});records.append(row)
            predictions=period[['signal_bar_broker','features_at_broker','entry_at_broker','exit_at_broker','net_r','label_win']].copy()
            predictions['score']=scores;predictions['keep']=keep.astype(int)
            (out/ident).mkdir(exist_ok=True)
            predictions.to_csv(out/ident/(family+'_prior_predictions.csv'),index=False)
            years=pd.to_datetime(period.entry_at_broker,unit='s',utc=True).dt.year.to_numpy()
            for year in np.unique(years):
                mask=years==year;b=describe(period.loc[mask],np.ones(int(mask.sum()),dtype=bool));m=describe(period.loc[mask],keep[mask])
                yearly.append(dict(id=ident,name=state['name'],family=family,primary=row['primary'],year=int(year),
                    base_trades=b['trades'],ml_trades=m['trades'],base_wr=b['win_rate'],ml_wr=m['win_rate'],
                    base_r=b['net_r'],ml_r=m['net_r'],delta_r=m['net_r']-b['net_r'],base_dd=b['peak_drawdown_r'],ml_dd=m['peak_drawdown_r']))
            print(ident,family,'base=',round(base['net_r'],2),'ml=',round(filtered['net_r'],2),'kept=',filtered['trades'],flush=True)
    results=pd.DataFrame(records);results.to_csv(out/'all_models.csv',index=False)
    pd.DataFrame(yearly).to_csv(out/'by_year.csv',index=False)
    (out/'integrity.json').write_text(json.dumps(integrity,indent=2),encoding='utf8')
    primary=results.loc[results.primary]
    summary=dict(strategies=len(states),models=len(results),primary=len(primary),
        improved=int((primary.delta_r>1e-8).sum()),worse=int((primary.delta_r < -1e-8).sum()),unchanged=int((primary.delta_r.abs()<=1e-8).sum()),
        no_veto=int((~primary.active).sum()),median_delta_r=float(primary.delta_r.median()),
        tested_from='2018-01-01',tested_to_exclusive='2021-09-09',full_prior_five_years=False,
        training_modified=False,thresholds_modified=False,forward_test=False)
    (out/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf8')
    lines=['# USDJPY: Frozen-model prior-period test','',
        'Requested 2016-2021 period is not fully available as intraday history. 2016 M1 and M5 each contain only 310 bars; 2017 is partial.',
        'The quality-qualified comparison below covers 2018-01-01 through 2021-09-08. This cutoff was fixed before scoring.',
        'Models, scaler weights and thresholds were frozen from the 2026-09-09 campaign. No training, tuning, activation or family reselection occurred.',
        'This is backward regime-transfer evidence, not forward validation or proof against overfitting. Existing strategy selection may already have used historical charts.',
        'Per-trade lifecycle net R includes the original simulator exits and costs. ML results are entry-veto subsets, not account-level execution replay.',
        'Fallback spread is the same 10 points as the original campaign, with original historical spread handling; commission/slippage assumptions were not upgraded.',
        'DD is closed-trade peak-to-trough R, not floating or EOD challenge drawdown. Strategies are correlated; their PnL must not be summed as independent samples.','',
        '## Previously Selected Models','',
        f"{summary['primary']} models: {summary['improved']} improve net R, {summary['worse']} worsen, {summary['unchanged']} unchanged ({summary['no_veto']} NO VETO).",'',
        '| Strategy | Model | Trades base / ML | WR base / ML | Net R base / ML | DD R base / ML |',
        '|---|---|---:|---:|---:|---:|']
    for r in primary.sort_values('name').itertuples():
        lines.append(f'| {r.name} | {r.family}'+(' (NO VETO)' if not r.active else '')+f' | {r.base_trades}/{r.ml_trades} | {100*r.base_win_rate:.1f}%/{100*r.ml_win_rate:.1f}% | {r.base_net_r:+.2f}/{r.ml_net_r:+.2f} | {r.base_peak_drawdown_r:.2f}/{r.ml_peak_drawdown_r:.2f} |')
    lines+=['','Both frozen model families and year-by-year results are in all_models.csv and by_year.csv. Do not select a new winner on this test and call it independent validation.']
    (out/'Results.md').write_text('\n'.join(lines)+'\n',encoding='utf8')
    print(json.dumps(summary))


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--common',type=Path,required=True)
    parser.add_argument('--campaign',type=Path,default=Path('logs/OrbMLCampaign_20260909_v3/training_v1'))
    parser.add_argument('--out',type=Path,default=Path('logs/OrbMLPriorFive_20260910/results'))
    args=parser.parse_args();evaluate(args.common,args.campaign,args.out)
