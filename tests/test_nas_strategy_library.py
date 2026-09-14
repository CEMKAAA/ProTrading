from pathlib import Path
import hashlib
import json
import re
import numpy as np
import pandas as pd
import pytest

from scripts.nas_strategy_catalog import catalogue
from scripts.nas_ml_filter import engine,validate_labels
from scripts.nas_ml_worker import parse_job,within
from scripts import orb_ml_filter

ROOT=Path(__file__).resolve().parents[1]

def test_catalogue_images_identity_and_actual_tf():
    rows=catalogue()
    assert len(rows)==19
    assert len({r['id'] for r in rows})==19
    assert sum(r['settings']['symbol']=='BTCUSD' for r in rows)==12
    assert all(r['settings']['tf_minutes']==5 for r in rows)
    assert next(r for r in rows if r['name']=='BtcUsdH1Model')['notes']
    assert all(r['metrics'] is None and r['assumptions'] for r in rows)
    assert next(r for r in rows if r['name']=='BTCUSDBestVolume2')['settings']['volume_multiplier']==1

def test_nas_does_not_mutate_orb_trainer_contract():
    old=(orb_ml_filter.SCHEMA,orb_ml_filter.FEATURE_HASH,list(orb_ml_filter.FEATURES))
    nas=engine()
    assert nas.SCHEMA=='nas.closed256.v1'
    assert len(nas.FEATURES)==40 and 'f_orb_range_atr' not in nas.FEATURES
    assert old==(orb_ml_filter.SCHEMA,orb_ml_filter.FEATURE_HASH,orb_ml_filter.FEATURES)
    assert nas.FEATURE_HASH!=orb_ml_filter.FEATURE_HASH

def test_mql_model_adapter_preserves_inference_algorithm():
    a=(ROOT/'IndicatorCodeExamples/OrbStrategyMLCore.mqh').read_text()
    b=(ROOT/'IndicatorCodeExamples/NasStrategyMLCore.mqh').read_text()
    assert a[a.index('bool OrbMlPredict'):].replace('OrbMl','NasMl').replace('ORB_ML_','NAS_ML_')==b[b.index('bool NasMlPredict'):]

def test_temporal_purge_removes_cross_boundary_labels():
    ml=engine()
    f=pd.DataFrame({'features_at_broker':np.arange(100)*86400,'exit_at_broker':np.arange(100)*86400+2*86400})
    train,val,test=ml.temporal_split(f)
    assert train.exit_at_broker.max()<val.features_at_broker.min()-86400
    assert val.exit_at_broker.max()<test.features_at_broker.min()-86400
    assert set(train.index).isdisjoint(val.index) and set(val.index).isdisjoint(test.index)

def job_bytes(**overrides):
    a=dict(job='job_123',preset='nas_abcd',config='a'*64,dataset='nas_abcd_data',mode='0');a.update(overrides)
    payload=('NAS_JOB1\n'+'\n'.join(a[k] for k in ('job','preset','config','dataset','mode'))+'\n').encode()
    return payload+hashlib.sha256(payload).hexdigest().encode()+b'\n'

def test_job_namespace_and_checksum(tmp_path):
    p=tmp_path/'job_123.job';p.write_bytes(job_bytes())
    assert parse_job(p)['config']=='a'*64
    p.write_bytes(job_bytes(dataset='../../OrbML/other'))
    with pytest.raises(ValueError):parse_job(p)
    p.write_bytes(job_bytes().replace(b'nas_abcd_data',b'nas_other_data'))
    with pytest.raises(ValueError):parse_job(p)
    with pytest.raises(ValueError):within(tmp_path,'../escape')

def test_original_signal_core_files_unchanged():
    for name in ('NasUltimate_Core.mqh','SuperTrend_SATS_Core.mqh'):
        before=ROOT/'logs/NasStrategyLibrary_20260912/baseline'/name
        assert before.read_bytes()==(ROOT/'IndicatorCodeExamples'/name).read_bytes()

def test_default_nas_source_unchanged_when_workbench_disabled():
    before=(ROOT/'logs/NasStrategyLibrary_20260912/baseline/NasUltimate_SATS_PartialNoBE_EA.mq5').read_text(encoding='utf-8-sig')
    after=(ROOT/'IndicatorCodeExamples/NasUltimate_SATS_PartialNoBE_EA.mq5').read_text(encoding='utf-8-sig')
    # Every source edit in this adapter is an opt-in compile-time hook.
    after=re.sub(r'#ifdef NAS_STRATEGY_LIBRARY\n(.*?)#else\n(.*?)#endif',lambda m:m.group(2),after,flags=re.S)
    after=re.sub(r'#ifdef NAS_STRATEGY_LIBRARY\n.*?#endif\n?', '',after,flags=re.S)
    assert re.sub(r'\s+','',after)==re.sub(r'\s+','',before)

def test_gate_before_publication_and_historical_acceptance():
    source=(ROOT/'IndicatorCodeExamples/NasUltimate_SATS_PartialNoBE_EA.mq5').read_text()
    live=source[source.index('void ProcessSignalBar()'):source.index('void ReconcileLiveSignalAfterBarClose()')]
    assert live.index('NasLibraryLiveFilter')<live.index('NasProPublishCurrentSignal')
    assert source.index('NasLibraryLiveFilter(rates,p,ai')<source.index('acceptedSignal[ai] = true;')

def test_modal_stale_edit_and_unsafe_apply_guards():
    code=(ROOT/'IndicatorCodeExamples/NasStrategyWorkbench.mqh').read_text()
    assert 'if(StringFind(object,NAS_LIB_PREFIX)!=0)return true;' in code
    assert 'ClearDashboardObjects();g_dashboardForceNextUpdate=true;' in code
    assert 'g_nasBridgeEnabledRuntime||ManagedPositionDirection()!=0' in code
    assert 'p.profile!=NasLibraryInputProfile()' in code
    assert 'MarkDirectionProcessedOnBar(g_lastSignalTime,1)' in code
    assert 'MarkDirectionProcessedOnBar(g_lastSignalTime,-1)' in code

def test_no_hcbe_or_ambiguous_labels_fabricated():
    code=(ROOT/'IndicatorCodeExamples/NasStrategyResearch.mqh').read_text()
    assert 'HCBE research replay has not passed parity yet; export refused' in code
    assert 'if(sl&&tp){quality="AMBIGUOUS_M1";reason="DATA";return false;}' in code
    assert 'm1[i].high+(t.direction<0?spread:0)' in code
    assert 'm1[i].low+(t.direction<0?spread:0)' in code
    assert 'lastLabelTime' in code and 'MODEL' in code


def test_nas_exit_geometry_validator_rejects_fabricated_max_r():
    f=pd.DataFrame([dict(entry=100.,sl=90.,tp=105.,exit_price=101.,gross_r=.1,net_r=.08,
        commission_r=.02,execution_direction=1,exit_reason='REVERSE',entry_valid=1)])
    validate_labels(f)
    f.loc[0,'gross_r']=.5
    with pytest.raises(ValueError,match='exit price/R'):validate_labels(f)
    f.loc[0,'gross_r']=.1;f.loc[0,'exit_reason']='TP'
    with pytest.raises(ValueError,match='level-hit'):validate_labels(f)


def test_simultaneous_exits_do_not_create_order_dependent_drawdown():
    f=pd.DataFrame({'exit_at_broker':[10,20,20,30],'net_r':[1.,-2.,3.,-1.]})
    a=engine().metrics(f,np.ones(4),.5)
    b=engine().metrics(f.iloc[[0,2,1,3]],np.ones(4),.5)
    assert a['peak_drawdown_r']==b['peak_drawdown_r']==1
    assert a['min_cumulative_r']==0 and a['net_r']==1


def test_research_account_exception_cannot_bypass_live_guard():
    code=(ROOT/'IndicatorCodeExamples/NasUltimate_SATS_PartialNoBE_EA.mq5').read_text()
    section=code[code.index('int OnInit()'):code.index('g_tradeStartTimeRuntime = InpTradeStartTime;',code.index('int OnInit()'))]
    assert 'if(InpNasLibraryAllowLive)' in section
    assert 'marginMode != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING' in section


def test_champion_provider_adapter_is_nas_bound_and_orb_untouched():
    from scripts.nas_model_slot import engine as nas_slot
    from scripts import orb_model_slot
    original=orb_model_slot.SCHEMA,orb_model_slot.feature_hash()
    slot=nas_slot()
    assert slot.SCHEMA=='nas.closed256.v1'
    assert slot.feature_hash()==engine().FEATURE_HASH
    assert original==(orb_model_slot.SCHEMA,orb_model_slot.feature_hash())
    assert slot.feature_hash()!=original[1]


def test_audit_and_export_share_replay_and_research_cannot_trade():
    source=(ROOT/'IndicatorCodeExamples/NasUltimate_SATS_PartialNoBE_EA.mq5').read_text()
    replay=(ROOT/'IndicatorCodeExamples/NasStrategyResearch.mqh').read_text()
    assert 'NasLibraryReplayAudit(rates,i,direction,entry,sl,finalTp' in source
    assert 'closed=NasResearchOutcome(t,at,px,pnlR,reason,quality,mfe,mae)' in replay
    assert 'bool valid=NasResearchOutcome(t,exitAt,exitPx,gross,reason,quality,mfe,mae)' in replay
    assert 'if(g_nasLibraryExport)return historical;' in replay
    tick=source[source.index('void OnTick()'):source.index('void OnTradeTransaction(')]
    assert tick.index('!InpNasLibraryAllowLive||g_nasLibraryExport')<tick.index('ProcessSignalBar()')
