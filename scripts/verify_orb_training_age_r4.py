"""Recompute saved R4 predictions from original inputs without refitting."""
import json
import joblib
import numpy as np
import pandas as pd
from threadpoolctl import threadpool_limits
import orb_training_age_r4 as r4


def run():
    root=r4.ROOT;contract=r4.assert_frozen(root)
    frames,_=r4.r3.prepare()
    checked=0;negative=[];final_r3_matches=0
    for source in contract['inputs']:
        ident=source['id'];f=frames[ident]
        for year in r4.YEARS:
            folder=root/ident/str(year)
            assert r4.checkpoint_valid(folder)
            cutoff,start,end=r4.dates(year)
            te=r4.R.partition(f,start,end);ca=r4.R.partition(f,cutoff,start)
            saved=pd.read_csv(folder/'predictions.csv')
            for col in ('features_at_broker','entry_at_broker','exit_at_broker','net_r'):
                np.testing.assert_allclose(te[col],saved[col],rtol=1e-12,atol=1e-12)
            frozen=json.loads((folder/'frozen_before_test.json').read_text())
            for kind in r4.KINDS:
                for arm in r4.ARMS:
                    key=kind+'__'+arm;spec=frozen['models'][key]
                    m=joblib.load(folder/(key+'.research.joblib'))
                    tr,w,meta=r4.training_slice(f,cutoff,arm)
                    assert meta==m['meta']==spec['meta']
                    threshold=r4.r3.calibrated(ca,r4.predict(m,ca),kind)
                    assert threshold==spec['threshold']
                    scores=r4.predict(m,te)
                    np.testing.assert_allclose(scores,saved['score_'+key],rtol=1e-12,atol=1e-12)
                    np.testing.assert_array_equal(scores>=threshold,saved['keep_'+key].to_numpy(bool))
                    assert np.isclose(w.sum(),meta['all_rows'])
                    # All outcome and exit-time changes must leave predictions intact.
                    mutated=te.copy();mutated['net_r']=99999.;mutated['label_win']=1
                    mutated['exit_at_broker']+=999999999
                    np.testing.assert_array_equal(scores,r4.predict(m,mutated))
                    negative.extend(m['scaler_checks'] or [])
                    if year==2025 and arm=='all':
                        path=r4.r3.ROOT/ident/(kind+'.research.joblib')
                        np.testing.assert_allclose(scores,r4.r3.predict(joblib.load(path),te),rtol=1e-10,atol=1e-10)
                        final_r3_matches+=1
                    checked+=1
            if year==2024:
                assert 'incumbent_keep' not in saved
            else:
                np.testing.assert_array_equal(r4.r3.incumbent(source,te),saved.incumbent_keep.to_numpy(bool))
                fair=max(start,source['incumbent_information_end']+r4.R.GAP+1)
                np.testing.assert_array_equal(te.features_at_broker>=fair,saved.fair_pair.to_numpy(bool))
    assert checked==352 and final_r3_matches==44
    assert r4.production_snapshot()==contract['production']
    result=dict(models_replayed=checked,final_all_models_matching_r3=final_r3_matches,
        unchanged_prediction_after_outcome_mutation=True,calibration_thresholds_recomputed=True,
        production_files_unchanged=len(contract['production']),
        roundoff_negative_variance_count=len(negative),
        minimum_roundoff_variance=min(x['variance'] for x in negative) if negative else 0,
        roundoff_scales=sorted(set(x['scale'] for x in negative)),replacement_enabled=False)
    r4.R.dump(root/'verification.json',result)
    print(json.dumps(result,indent=2))


if __name__=='__main__':
    with threadpool_limits(limits=1):run()
