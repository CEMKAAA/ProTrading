"""Chronological model selection; never trains on the final test partition."""
from copy import deepcopy

import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.metrics import log_loss, brier_score_loss
from sklearn.neural_network import MLPClassifier
from sklearn.preprocessing import StandardScaler

POLICY = 'ORB_PURGED_WALK_FORWARD_1'
ALPHAS = (1.0, 10.0, 100.0)
THRESHOLDS = (.05, .35, .45, .5, .55, .6, .65, .7, .75, .8)


def walk_folds(frame, gap):
    """Three forward-only outer folds, with label-end purging at each boundary."""
    ordered = frame.sort_values('features_at_broker')
    n = len(ordered)
    folds = []
    for left, right in ((.5, 2/3), (2/3, 5/6), (5/6, 1.0)):
        start = ordered.iloc[int(n*left)].features_at_broker
        end = ordered.iloc[int(n*right)].features_at_broker if right < 1 else np.inf
        fit = ordered[(ordered.features_at_broker < start) & (ordered.exit_at_broker < start-gap)]
        score = ordered[(ordered.features_at_broker >= start) & (ordered.features_at_broker < end)
                        & (ordered.exit_at_broker < end-gap)]
        if len(fit) < 90 or len(score) < 20:
            raise ValueError('Insufficient purged samples for three walk-forward folds')
        folds.append((fit.copy(), score.copy()))
    return folds


def stop_split(frame, gap):
    boundary = frame.iloc[int(len(frame)*.8)].features_at_broker
    fit = frame[(frame.features_at_broker < boundary) & (frame.exit_at_broker < boundary-gap)]
    stop = frame[frame.features_at_broker >= boundary]
    if len(fit) < 60 or len(stop) < 15 or fit.label_win.nunique() != 2:
        raise ValueError('Insufficient early-stopping samples/classes')
    return fit, stop


def fit_network(frame, features, alpha, gap, epochs, notify, start, span, label):
    fit, stop = stop_split(frame, gap)
    scaler = StandardScaler().fit(fit[features].to_numpy(float))
    x = scaler.transform(fit[features].to_numpy(float))
    z = scaler.transform(stop[features].to_numpy(float))
    model = MLPClassifier(hidden_layer_sizes=(16,), activation='relu', solver='adam',
                          alpha=alpha, random_state=42, shuffle=False, early_stopping=False)
    best = None; best_loss = np.inf; stale = 0; history = []
    for epoch in range(1, epochs+1):
        notify(start+span*(epoch-1)/epochs, f'{label} Epoch {epoch}/{epochs}')
        model.partial_fit(x, fit.label_win.to_numpy(int), classes=np.array([0, 1]))
        loss = float(log_loss(stop.label_win, model.predict_proba(z), labels=[0, 1]))
        if not np.isfinite(loss): raise ValueError('Non-finite early-stopping loss')
        history.append(loss)
        if loss < best_loss-1e-5:
            best_loss=loss; best=deepcopy(model); best_epoch=epoch; stale=0
        else: stale+=1
        if epoch >= 40 and stale >= 30: break
    notify(start+span, f'{label} early-stop checkpoint {best_epoch}; completed {epoch} epochs')
    return best, scaler, dict(best_epoch=best_epoch, epochs_run=epoch,
                              fit_rows=len(fit), stop_rows=len(stop), best_stop_log_loss=best_loss,
                              fit_label_max=int(fit.exit_at_broker.max()),
                              stop_start=int(stop.features_at_broker.min()), loss_curve=history)


def choose_threshold(frame, probs, metric):
    choices=[(t, metric(frame, probs, t)) for t in THRESHOLDS]
    choices=[(t,m) for t,m in choices if m['retention'] >= .4 and m['trades'] >= min(30, len(frame))]
    if not choices: raise ValueError('No threshold retains sufficient validation trades')
    return max(choices, key=lambda pair: (pair[1]['net_r'], pair[1]['trades']))


def uncertainty(frame, probs, threshold):
    """Paired moving-block bootstrap of daily filtered-minus-baseline net R.

    Diagnostic conditional on this test sample, not a multiple-testing correction.
    """
    delta=np.where(probs >= threshold, 0.0, -frame.net_r.to_numpy(float))
    groups=(frame.exit_at_broker.to_numpy(np.int64)//86400)
    daily=pd.Series(delta).groupby(groups).sum().to_numpy()
    n=len(daily)
    if n < 20: return dict(days=n, mean_delta_r=float(delta.sum()/max(1,n)), lower95=None, upper95=None)
    block=max(2, int(np.ceil(n**(1/3))))
    rng=np.random.default_rng(20260909); samples=[]
    for _ in range(1000):
        starts=rng.integers(0, n, size=int(np.ceil(n/block)))
        indices=np.concatenate([(s+np.arange(block))%n for s in starts])[:n]
        samples.append(float(daily[indices].mean()))
    low,high=np.quantile(samples,[.025,.975])
    return dict(days=n, block_days=block, draws=1000, mean_delta_r=float(daily.mean()),
                lower95=float(low), upper95=float(high))


def fit_protocol(train, validation, test, features, metric, gap, epochs, notify):
    folds=walk_folds(train, gap)
    candidates=[]; completed=0; total=len(ALPHAS)*len(folds)+1
    for alpha in ALPHAS:
        fold_reports=[]
        for index,(fit, score) in enumerate(folds):
            model,scaler,early=fit_network(fit,features,alpha,gap,epochs,notify,
                                           5+70*completed/total,70/total,f'alpha={alpha:g} fold={index+1}')
            _, calibration=stop_split(fit,gap)
            p=model.predict_proba(scaler.transform(calibration[features].to_numpy(float)))[:,1]
            threshold,_=choose_threshold(calibration,p,metric)
            q=model.predict_proba(scaler.transform(score[features].to_numpy(float)))[:,1]
            filtered=metric(score,q,threshold); base=metric(score,np.ones(len(score)),0)
            fold_reports.append(dict(early=early, filtered=filtered, baseline=base, threshold=threshold,
                                     train_label_max=int(fit.exit_at_broker.max()),
                                     score_start=int(score.features_at_broker.min()),
                                     delta_r=filtered['net_r']-base['net_r']))
            completed+=1
        candidates.append(dict(alpha=alpha, folds=fold_reports,
                               median_delta_r=float(np.median([f['delta_r'] for f in fold_reports]))))
    # Entire choice is made inside the earliest 60%, never from final test results.
    selected=max(candidates,key=lambda c:(c['median_delta_r'],c['alpha']))
    model,scaler,early=fit_network(train,features,selected['alpha'],gap,epochs,notify,
                                   5+70*completed/total,70/total,'final train')
    vp=model.predict_proba(scaler.transform(validation[features].to_numpy(float)))[:,1]
    threshold,val=choose_threshold(validation,vp,metric)
    notify(78,'Fitting logistic and shallow boosted-tree benchmarks on train only')
    benchmarks=[]
    for name,base_model in [('logistic',LogisticRegression(C=.1,max_iter=1000,random_state=42)),
                            ('shallow_boosting',HistGradientBoostingClassifier(max_iter=80,max_leaf_nodes=7,
                              min_samples_leaf=30,l2_regularization=10,early_stopping=False,random_state=42))]:
        base_scaler=StandardScaler().fit(train[features].to_numpy(float))
        base_model.fit(base_scaler.transform(train[features].to_numpy(float)),train.label_win)
        bv=base_model.predict_proba(base_scaler.transform(validation[features].to_numpy(float)))[:,1]
        bt,bm=choose_threshold(validation,bv,metric)
        benchmarks.append((name,base_model,base_scaler,bt,bm))
    comparator=max(benchmarks,key=lambda b:b[4]['net_r'])[0]
    notify(85,'Weights, alpha, checkpoint, threshold and benchmark frozen; evaluating final test')
    tp=model.predict_proba(scaler.transform(test[features].to_numpy(float)))[:,1]
    benchmark_reports={}
    for name,m,s,t,v in benchmarks:
        bp=m.predict_proba(s.transform(test[features].to_numpy(float)))[:,1]
        benchmark_reports[name]=dict(threshold=t, validation=v, test=metric(test,bp,t))
    notify(90,'Daily block-bootstrap uncertainty and temporal stability diagnostics')
    ci=uncertainty(test,tp,threshold)
    folds_ok=sum(f['delta_r']>0 for f in selected['folds'])>=2
    report=dict(policy=POLICY,candidates=candidates,selected_alpha=selected['alpha'],early_stopping=early,
                benchmarks=benchmark_reports,benchmark_selected_on_validation=comparator,
                bootstrap_delta=ci,walk_forward_stable=folds_ok,
                test_brier=float(brier_score_loss(test.label_win,tp)),
                test_log_loss=float(log_loss(test.label_win,np.c_[1-tp,tp],labels=[0,1])),
                test_blocks=[metric(part,tp[indices],threshold) for indices in np.array_split(np.arange(len(test)),3)
                             if len(indices) for part in [test.iloc[indices]]],
                feature_selection='none; fixed causal schema',test_used_for_fitting=False)
    filtered=metric(test,tp,threshold)
    baseline=metric(test,np.ones(len(test)),0)
    report['extra_gates_passed']=bool(folds_ok and ci['lower95'] is not None and ci['lower95']>0
        and filtered['net_r']>=baseline['net_r']
        and filtered['net_r']>=benchmark_reports[comparator]['test']['net_r'])
    report['rejection_reasons']=[name for name,passed in [
        ('walk_forward_uplift',folds_ok),
        ('uncertain_test_uplift',ci['lower95'] is not None and ci['lower95']>0),
        ('below_unfiltered_test',filtered['net_r']>=baseline['net_r']),
        ('below_simple_benchmark',filtered['net_r']>=benchmark_reports[comparator]['test']['net_r'])] if not passed]
    return model,scaler,threshold,val,tp,report
