import json
from pathlib import Path

from scripts.build_orb_leaderboard import choose_family, score

ROOT = Path(__file__).resolve().parents[1]


def test_score_monotone_and_sample_aware():
    assert score(70, 100, 2) > score(60, 100, 2)
    assert score(70, 100, 1) > score(70, 100, 2)
    assert score(7, 10, 2) < score(70, 100, 2)
    assert score(0, 0, 0) == 0
    assert score(5, 10, float('nan')) == 0


def test_model_choice_ignores_test_outcome():
    reports = {'mlp': {'validation': {'net_r': 4}, 'test': {'net_r': -100}},
               'return': {'validation': {'net_r': 3}, 'test': {'net_r': 100}}}
    assert choose_family(reports, 1) == 'mlp'
    reports['return']['test']['net_r'] = 100000
    assert choose_family(reports, 1) == 'mlp'
    assert choose_family({}, 1) is None


def test_leaderboard_modal_uses_guarded_apply_and_cannot_trade_or_train():
    text = (ROOT/'IndicatorCodeExamples/OrbStrategyLeaderboard.mqh').read_text()
    assert 'if(g_lbOpen&&!control)' in text
    assert 'CHARTEVENT_OBJECT_ENDEDIT&&g_lbOpen' in text
    assert 'OrbStrategyPresetApplyInteractive(g_strategyCandidateIndex)' in text
    for forbidden in ['OrderSend(', 'OrbMlLoad(', 'g_mlEnabled=', 'FileWrite(']:
        assert forbidden not in text
    assert 'ObjectsTotal(' not in text


def test_preset_model_load_preserves_enabled_state_and_rejects_candidate():
    text = (ROOT/'IndicatorCodeExamples/OrbStrategyMLPipeline.mqh').read_text()
    body = text.split('void OrbMlOnStrategyApplied()', 1)[1].split('void OrbMlInit()', 1)[0]
    assert 'OrbMlLoad()' in body
    assert 'g_mlEnabled=' not in body
    assert '.candidate.model' not in text
    history = (ROOT/'IndicatorCodeExamples/OrbStrategyMLHistory.mqh').read_text()
    assert 'g_mlModel.config!=config' in history


def test_campaign_result_bypasses_training_queue_but_not_binding():
    jobs = (ROOT/'IndicatorCodeExamples/OrbStrategyMLJobs.mqh').read_text()
    assert 'OrbMlUsePretrained()' in jobs
    models = (ROOT/'IndicatorCodeExamples/OrbStrategyCampaignModels.mqh').read_text()
    for check in ['OrbStrategyPresetMatchesRuntime(p)', 'OrbCustomInputSignature()!=r.inputs',
                  'OrbCampaignRuntimeHash()!=r.runtime_hash', 'OrbMlBytesSha256(data)!=g_campaignInfo.model_sha',
                  'AccountInfoString(ACCOUNT_SERVER)!=r.broker', 'g_campaignMlp.dataset==g_campaignInfo.dataset']:
        assert check in models
    assert 'g_mlEnabled=' not in models


def test_snapshot_has_all_presets_and_no_live_approval():
    path = ROOT/'logs/OrbMLCampaign_20260909_v3/training_v1/leaderboard.json'
    if not path.exists():
        return  # Campaign artifacts are local; unit tests remain portable.
    rows = json.loads(path.read_text(encoding='utf8'))
    assert len(rows) == len({r['id'] for r in rows}) == 53
    assert sum(r['filtered'] is not None for r in rows) == 50
    for row in rows:
        assert row['status'] in ('RESEARCH', 'NO MODEL')
        assert row['from_broker'] <= row['to_broker']
        if row['filtered']:
            assert row['filtered']['trades'] <= row['baseline']['trades']
