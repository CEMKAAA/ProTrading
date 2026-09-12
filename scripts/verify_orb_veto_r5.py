"""Independent source-data replay of R5 policy fits and test masks, no trading."""
import json
import joblib
import numpy as np
import pandas as pd
from threadpoolctl import threadpool_limits
import orb_veto_r5 as r5


def run():
    root=r5.ROOT;contract=r5.verify_inputs(root);frames,_=r5.r4.r3.prepare()
    pairs=0;masks=0;regime_controls=0
    for source in contract['inputs']:
        ident=source['id'];f=frames[ident]
        for year in r5.r4.YEARS:
            folder=root/ident/str(year);assert r5.r4.checkpoint_valid(folder)
            start,test,end=r5.r4.dates(year);middle=r5.R.stamp(f'{year}-03-09')
            a=r5.R.partition(f,start,middle);b=r5.R.partition(f,middle,test);te=r5.R.partition(f,test,end)
            freeze=json.loads((folder/'frozen_before_test.json').read_text())
            saved=pd.read_csv(folder/'predictions.csv')
            for col in ('entry_at_broker','exit_at_broker','net_r'):
                np.testing.assert_allclose(te[col],saved[col],rtol=1e-12,atol=1e-12)
            np.testing.assert_array_equal(r5.regime_ids(te),saved.regime)
            controls=[]
            for kind in r5.r4.KINDS:
                spec=freeze['policies'][kind]
                assert r5.R.digest(spec['model_path'])==spec['model_sha']
                m=joblib.load(spec['model_path']);sa=r5.r4.predict(m,a);sb=r5.r4.predict(m,b)
                rebuilt=r5.build_rules(a,sa,b,sb,start,middle,test)
                for key,value in rebuilt.items():assert value==spec[key]
                scores=r5.r4.predict(m,te)
                np.testing.assert_allclose(scores,saved['score_'+kind],rtol=1e-12,atol=1e-12)
                mutated=te.copy();mutated['net_r']=99999.;mutated['exit_at_broker']+=999999999
                np.testing.assert_array_equal(scores,r5.r4.predict(m,mutated))
                for name,rule in rebuilt['rules'].items():
                    k=r5.apply(rule,scores,r5.regime_ids(te))
                    np.testing.assert_array_equal(k,saved['keep_'+kind+'__'+name].to_numpy(bool))
                    np.testing.assert_array_equal(k,r5.apply(rule,scores,r5.regime_ids(mutated)))
                    if name=='regime_only':controls.append(k);regime_controls+=1
                    else:masks+=1
                pairs+=1
            np.testing.assert_array_equal(controls[0],controls[1])
            if year==2024:assert 'incumbent_keep' not in saved
            else:
                np.testing.assert_array_equal(r5.r4.r3.incumbent(source,te),saved.incumbent_keep.to_numpy(bool))
                fair=max(test,source['incumbent_information_end']+r5.R.GAP+1)
                np.testing.assert_array_equal(te.features_at_broker>=fair,saved.fair_pair.to_numpy(bool))
        print(ident,'verified',flush=True)
    assert pairs==88 and masks==352 and regime_controls==88
    r5.verify_inputs(root)
    result=dict(model_pairs_replayed=pairs,primary_masks_replayed=masks,regime_controls_replayed=regime_controls,
        policies_refit_from_calibration_only=True,outcome_mutation_does_not_change_predictions_or_masks=True,
        regime_only_independent_of_model_kind=True,production_files_unchanged=len(contract['production']),
        execution_replay_completed=False,prospective_shadow_completed=False,replacement_enabled=False)
    r5.R.dump(root/'verification.json',result);print(json.dumps(result,indent=2))


if __name__=='__main__':
    with threadpool_limits(limits=1):run()
