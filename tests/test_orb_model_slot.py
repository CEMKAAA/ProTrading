import json
from pathlib import Path
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'scripts'))
import orb_model_slot as s

REPORT = Path('logs/OrbR7Runtime_20260912')


def fixture_model(tmp_path):
    info = json.loads((REPORT/'verification.json').read_text())['records'][0]
    artifact = REPORT/'Files/OrbML/R7'/(info['id']+'.r7')
    v = s.lines(artifact.read_bytes(), 1000000); at = 7+155*int(v[5])
    raw = s.pack(info, artifact, 'r1', int(float(v[at+1])), int(float(v[-3])))
    path = tmp_path/'candidate.slot'; path.write_bytes(raw)
    return info, artifact, path


def test_migrate_52_preserves_every_artifact_and_metrics(tmp_path):
    assert s.migrate(REPORT, tmp_path) == 52
    rows = {r['id']: r for r in json.loads((REPORT/'leaderboard_5y_retrospective.json').read_text())}
    for active in tmp_path.glob('*/active.slot'):
        m = s.parse(active.read_bytes(), active.parent.name)
        s.validate_artifact(m, (tmp_path/'Artifacts'/(m['artifact']+'.model')).read_bytes())
        assert m['artifact'] == rows[m['id']]['r7_sha']
        assert m['net_r'] == rows[m['id']]['r7']['net_r']
    before = {p: p.read_bytes() for p in tmp_path.glob('*/active.slot')}
    s.migrate(REPORT, tmp_path)
    assert all(p.read_bytes() == data for p, data in before.items())


def test_stage_activate_conflict_rollback_and_immutable_revision(tmp_path):
    info, artifact, path = fixture_model(tmp_path)
    root = tmp_path/'Slots'; m = s.stage(root, path, artifact)
    assert not (root/m['id']/'active.slot').exists()
    s.activate(root, m['id'], 'r1', 'NONE')
    m['revision'] = 'r2'; path.write_bytes(s.encode(m)); s.stage(root, path, artifact)
    with pytest.raises(ValueError, match='conflict'):
        s.activate(root, m['id'], 'r2', 'NONE')
    s.activate(root, m['id'], 'r2', 'r1')
    s.activate(root, m['id'], 'r1', 'r2')
    m['revision'] = 'r1'; m['valid_from'] += 1; path.write_bytes(s.encode(m))
    with pytest.raises(ValueError, match='Immutable'):
        s.stage(root, path, artifact)


def test_interrupted_activation_preserves_previous(tmp_path, monkeypatch):
    info, artifact, path = fixture_model(tmp_path)
    root = tmp_path/'Slots'; m = s.stage(root, path, artifact)
    s.activate(root, m['id'], 'r1', 'NONE')
    pointer = root/m['id']/'active.slot'; before = pointer.read_bytes()
    m['revision'] = 'r2'; path.write_bytes(s.encode(m)); s.stage(root, path, artifact)
    def fail(*args):
        raise OSError('replace interrupted')
    monkeypatch.setattr(s.os, 'replace', fail)
    with pytest.raises(OSError):
        s.activate(root, m['id'], 'r2', 'r1')
    assert pointer.read_bytes() == before
    assert not list(pointer.parent.glob('.slot-*.tmp'))


@pytest.mark.parametrize('key,value', [('id','../other'), ('revision','r/evil'), ('artifact','../evil'),
    ('provider','PICKLE'), ('features','f'*64), ('custom_hash','bad'), ('wr','NaN'),
    ('valid_until',1), ('evaluation','OOS'), ('n',3)])
def test_manifest_rejects_bad_contract(tmp_path, key, value):
    info, artifact, path = fixture_model(tmp_path)
    m = s.parse(path.read_bytes(), info['id']); m[key] = value
    with pytest.raises(ValueError):
        s.encode(m)


def test_cross_strategy_checksum_and_expiry(tmp_path):
    info, artifact, path = fixture_model(tmp_path)
    with pytest.raises(ValueError):
        s.parse(path.read_bytes(), 'different_strategy')
    with pytest.raises(ValueError):
        s.parse(path.read_bytes()+b'bad', info['id'])
    m = s.parse(path.read_bytes(), info['id'])
    with pytest.raises(ValueError):
        s.validate_artifact(m, artifact.read_bytes()+b'bad')
    m['valid_until'] += 1
    with pytest.raises(ValueError, match='after archive'):
        s.validate_artifact(m, artifact.read_bytes())


def mlp_fixture(info, cutoff=100000):
    v = ['ORB_MLP1', s.SCHEMA, info['config'], s.feature_hash(), info['dataset'], str(cutoff), '0.6', '40,16']
    for i in range(40):
        v += ['0', '1']
    v += ['0']*640 + ['0']*16 + ['0']*16 + ['0.7']
    raw = ('\n'.join(v)+'\n').encode()
    return raw+s.sha(raw).encode()+b'\n'


def test_mlp_provider_plugs_in_without_registry_or_recompile(tmp_path):
    info, _, path = fixture_model(tmp_path)
    artifact = tmp_path/'mlp.model'; artifact.write_bytes(mlp_fixture(info))
    raw = s.pack(info, artifact, 'neural-r2', 200000, 300000)
    path.write_bytes(raw); m = s.stage(tmp_path/'Slots', path, artifact)
    assert m['provider'] == 'ORB_MLP1' and m['evaluation'] == 'NONE'
    assert s.activate(tmp_path/'Slots', m['id'], 'neural-r2', 'NONE')['revision'] == 'neural-r2'
    with pytest.raises(ValueError, match='cutoff'):
        s.pack(info, artifact, 'unsafe', 100001, 300000)


def test_runtime_guards_and_leaderboard_are_revision_bound():
    root = Path('IndicatorCodeExamples')
    runtime = (root/'OrbStrategyR7Runtime.mqh').read_text()
    assert 'OrbStrategyR7Registry' not in runtime and 'OrbR7Record' not in runtime
    assert 'g_r7Slot.ready=false' in runtime and 'OrbCampaignBinding(g_r7Info)' in runtime
    assert 'OrbSlotModelParse(m,text,candidate' in runtime
    board = (root/'OrbStrategyLeaderboard.mqh').read_text()
    assert 'r.hasR7=false' in board
    for guard in ('m.config==r.config', 'm.dataset==r.dataset', 'm.metricFrom==r.fromTime', 'hash==m.artifact'):
        assert guard in board
    assert 'OrbSlotScore' in (root/'OrbStrategyMLHistory.mqh').read_text()


def test_cross_process_writer_lock_blocks_concurrent_activation(tmp_path):
    import subprocess
    root = tmp_path/'Slots'
    code = 'import orb_model_slot as s; from pathlib import Path; import sys;\nwith s.writer_lock(Path(sys.argv[1])): print("unexpected")'
    with s.writer_lock(root):
        import os
        env = dict(os.environ, PYTHONPATH=str(Path('scripts').resolve()))
        result = subprocess.run([sys.executable, '-c', code, str(root)], env=env, capture_output=True, text=True)
        assert result.returncode != 0 and 'unexpected' not in result.stdout


def test_evaluate_new_release_metrics_are_not_stale(tmp_path):
    info, artifact, path = fixture_model(tmp_path)
    import os
    csv = Path(os.environ['APPDATA'])/'MetaQuotes/Terminal/Common/Files'/info['csv']
    if not csv.exists():
        pytest.skip('Local frozen campaign CSV unavailable')
    output = tmp_path/'evaluated.slot'
    m = s.evaluate(path, artifact, csv, output)
    expected = next(r for r in json.loads((REPORT/'leaderboard_5y_retrospective.json').read_text()) if r['id'] == info['id'])
    assert m['net_r'] == pytest.approx(expected['r7']['net_r'], abs=1e-10)
    assert m['dd'] == pytest.approx(expected['r7']['dd_r'], abs=1e-10)
    assert m['n'] == expected['r7']['trades']
    assert m['artifact'] == info['model_sha'] and m['evaluation'] == s.RETRO
