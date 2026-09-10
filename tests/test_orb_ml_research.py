import numpy as np
from scripts import orb_ml_filter as ml
from scripts import orb_ml_research as research
from tests.test_orb_ml_filter import dataset_frame, save_dataset


def test_all_walk_forward_and_early_stopping_boundaries_are_purged():
    frame=dataset_frame(800)
    train,_,test=ml.temporal_split(frame)
    for fit,score in research.walk_folds(train,86400):
        assert fit.exit_at_broker.max()<score.features_at_broker.min()-86400
        sub,stop=research.stop_split(fit,86400)
        assert sub.exit_at_broker.max()<stop.features_at_broker.min()-86400
        assert score.features_at_broker.max()<test.features_at_broker.min()


def test_bootstrap_rejects_no_improvement_and_is_reproducible():
    frame=dataset_frame(200)
    ci=research.uncertainty(frame,np.ones(len(frame)),.5)
    assert ci['lower95']==ci['upper95']==0
    assert ci==research.uncertainty(frame,np.ones(len(frame)),.5)


def test_advanced_training_progress_and_frozen_holdout(tmp_path):
    csv=save_dataset(tmp_path,dataset_frame(500))
    progress=[]
    report=ml.train(csv,tmp_path/'result',epochs=60,advanced=True,progress=lambda p,m:progress.append(p))
    assert progress==sorted(progress)
    assert report['research']['policy']==research.POLICY
    assert report['research']['test_used_for_fitting'] is False
    assert set(report['research']['benchmarks'])=={'logistic','shallow_boosting'}
    assert report['probability_parity_max_error']<1e-10
    assert report['research']['early_stopping']['fit_label_max']<report['research']['early_stopping']['stop_start']-86400


def test_test_outcomes_do_not_change_weights_or_threshold():
    frame=dataset_frame(500)
    tr,val,test=ml.temporal_split(frame)
    args=(tr,val,test,ml.FEATURES,ml.metrics,86400,40,lambda *_:None)
    first=research.fit_protocol(*args)
    changed=test.copy();changed['net_r']=-changed.net_r;changed['label_win']=(changed.net_r>0).astype(int)
    second=research.fit_protocol(tr,val,changed,ml.FEATURES,ml.metrics,86400,40,lambda *_:None)
    assert first[2]==second[2]
    for a,b in zip(first[0].coefs_,second[0].coefs_): np.testing.assert_array_equal(a,b)
    np.testing.assert_array_equal(first[1].mean_,second[1].mean_)
