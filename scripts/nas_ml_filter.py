"""NAS adapter: reuse ORB purging, fitting, portability and validation gates.

Load into an isolated module instance: never mutate the running ORB trainer's
schema. Every dataset/model is additionally bound to its NAS configuration hash.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
from pathlib import Path
import sys
import numpy as np


def validate_labels(frame):
    """Check the financial identity, not just the binary target column."""
    if frame.empty:
        return
    values=frame[['entry','sl','tp','exit_price','gross_r','net_r','commission_r','execution_direction']].to_numpy(float)
    if not np.isfinite(values).all():raise ValueError('Invalid NAS outcome geometry')
    risk=(frame.entry-frame.sl).abs().to_numpy(float)
    direction=frame.execution_direction.to_numpy(float)
    if not np.isin(direction,[-1,1]).all() or (risk<=0).any():raise ValueError('Invalid NAS direction/risk')
    if ((frame.entry-frame.sl)*direction<=0).any() or ((frame.tp-frame.entry)*direction<=0).any():
        raise ValueError('Reversed NAS protection')
    gross=direction*(frame.exit_price-frame.entry)/risk
    if not np.allclose(gross,frame.gross_r,atol=1e-8,rtol=1e-9):raise ValueError('NAS exit price/R mismatch')
    if (frame.commission_r<0).any() or not np.allclose(frame.net_r,frame.gross_r-frame.commission_r,atol=1e-8,rtol=1e-9):
        raise ValueError('NAS commission/net R mismatch')
    for label,column in [('SL','sl'),('TP','tp')]:
        rows=frame.loc[frame.exit_reason==label]
        if not np.allclose(rows.exit_price,rows[column],atol=1e-8,rtol=1e-10):raise ValueError('NAS level-hit price mismatch')
    if 'entry_valid' in frame and not (frame.entry_valid==1).all():raise ValueError('Unresolved NAS entry labeled valid')

try:
    from .build_nas_ml_contract import FEATURES, SCHEMA
except ImportError:
    from build_nas_ml_contract import FEATURES, SCHEMA

def engine():
    spec=importlib.util.spec_from_file_location('nas_isolated_orb_trainer',Path(__file__).with_name('orb_ml_filter.py'))
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.__package__=__package__
    module.SCHEMA=SCHEMA
    module.FEATURES=['f_'+x for x in FEATURES]
    module.FEATURE_HASH=hashlib.sha256(','.join(module.FEATURES).encode()).hexdigest()
    original_load=module.load_dataset
    def load(path):
        frame,info=original_load(path)
        validate_labels(frame)
        return frame,info
    module.load_dataset=load
    original_metrics=module.metrics
    def metrics(frame,probability,threshold):
        result=original_metrics(frame,probability,threshold)
        # Simultaneous exits must not create an arbitrary intra-timestamp DD.
        events=frame.loc[probability>=threshold].groupby('exit_at_broker').net_r.sum().sort_index()
        curve=np.r_[0.,events.to_numpy(float).cumsum()]
        result['min_cumulative_r']=float(curve.min())
        result['peak_drawdown_r']=float((np.maximum.accumulate(curve)-curve).max())
        return result
    module.metrics=metrics
    return module

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--csv',type=Path,required=True)
    parser.add_argument('--output-dir',type=Path,required=True)
    parser.add_argument('--advanced',action='store_true')
    parser.add_argument('--epochs',type=int,default=200)
    args=parser.parse_args()
    model=engine()
    report=model.train(args.csv,args.output_dir,publish=False,advanced=args.advanced,
        epochs=args.epochs if args.advanced else 0,
        progress=lambda percent,message:print(f'{percent:.1f}% {message}',flush=True))
    print('Deployment checks:',report['deployment_checks_passed'],'(no automatic activation)')

if __name__=='__main__': main()
