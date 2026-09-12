"""Versioned per-strategy champion slots. No pickle loading, training or EA activation.

Stage immutable artifacts/releases first; activate with an expected previous revision.
The EA explicitly reloads the slot only at its existing safe lifecycle boundaries.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
import json
import math
import os
from pathlib import Path
import re
import tempfile

SCHEMA = 'orb.closed256.v1'
FIELDS = ('magic schema features id config dataset runtime_hash custom_hash symbol broker inputs tf '
          'provider revision artifact valid_from valid_until metric_from metric_until n wr net_r dd evaluation').split()
RETRO = 'RETROSPECTIVE_TRAINING_INCLUDED_NOT_OOS'
PROVIDERS = {'ORB_R7_LOGISTIC1', 'ORB_MLP1'}
HEX = re.compile(r'[0-9a-f]{64}\Z')
TOKEN = re.compile(r'[A-Za-z0-9_-]{1,96}\Z')
NUMBER = re.compile(r'[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\Z')


def sha(data):
    return hashlib.sha256(data).hexdigest()


def feature_hash():
    # Same canonical names as the EA, without importing research/training dependencies.
    path = Path(__file__).resolve().parents[1] / 'IndicatorCodeExamples/OrbStrategyMLCore.mqh'
    body = path.read_text().split('string OrbMlFeatureNames()', 1)[1].split('\n}', 1)[0]
    return sha(''.join(re.findall(r'"([^"]*)"', body)).encode())


def token(s):
    if not isinstance(s, str) or not TOKEN.fullmatch(s):
        raise ValueError('Invalid strategy/revision token')
    return s


def number(s, low=-1e12, high=1e12):
    if not NUMBER.fullmatch(str(s)):
        raise ValueError('Invalid numeric field')
    v = float(s)
    if not math.isfinite(v) or abs(v) >= 1e12 or not low <= v <= high:
        raise ValueError('Numeric range')
    return v


def integer(s, low=0, high=4102444800):
    v = number(s, low, high)
    if v != int(v):
        raise ValueError('Integer required')
    return int(v)


def lines(data, limit):
    if not 0 < len(data) <= limit:
        raise ValueError('File size')
    v = data.decode('utf8').split('\n')
    if len(v) < 3 or v[-1] != '' or sha(('\n'.join(v[:-2]) + '\n').encode()) != v[-2]:
        raise ValueError('Checksum/canonical LF')
    return v[:-2]


def encode(m):
    payload = ('\n'.join(str(m[k]) for k in FIELDS) + '\n').encode()
    data = payload + sha(payload).encode() + b'\n'
    parse(data, m['id'])
    return data


def parse(data, ident):
    v = lines(data, 16384)
    if len(v) != len(FIELDS):
        raise ValueError('Manifest layout')
    m = dict(zip(FIELDS, v))
    if m['magic'] != 'ORB_SLOT1' or m['schema'] != SCHEMA or m['features'] != feature_hash() or m['id'] != token(ident):
        raise ValueError('Manifest identity/schema')
    token(m['revision'])
    for k in ('config', 'dataset', 'runtime_hash', 'inputs', 'artifact'):
        if not HEX.fullmatch(m[k]):
            raise ValueError('Invalid hash: ' + k)
    if m['custom_hash'] and not HEX.fullmatch(m['custom_hash']):
        raise ValueError('Invalid custom hash')
    if m['provider'] not in PROVIDERS or not m['symbol'] or not m['broker']:
        raise ValueError('Unsupported provider/missing binding')
    m['tf'] = integer(m['tf'], 1, 49153)
    m['valid_from'] = integer(m['valid_from'], 1)
    m['valid_until'] = integer(m['valid_until'], m['valid_from'] + 1)
    m['metric_from'] = integer(m['metric_from'])
    m['metric_until'] = integer(m['metric_until'], m['metric_from'])
    m['n'] = integer(m['n'], 0, 10000000)
    m['wr'] = number(m['wr'], 0, 100)
    m['net_r'] = number(m['net_r'])
    m['dd'] = number(m['dd'], 0)
    if m['evaluation'] == 'NONE':
        if any(m[k] != 0 for k in ('metric_from', 'metric_until', 'n', 'wr', 'net_r', 'dd')):
            raise ValueError('Unbound metrics')
    elif m['evaluation'] != RETRO or not (m['metric_until'] > m['metric_from'] > 0 and m['n'] > 0):
        raise ValueError('Metrics contract')
    return m


def validate_artifact(m, data):
    if sha(data) != m['artifact']:
        raise ValueError('Artifact hash')
    v = lines(data, 1000000)
    if v[0] != m['provider']:
        raise ValueError('Provider mismatch')
    if v[0] == 'ORB_R7_LOGISTIC1':
        if v[1:5] != [feature_hash(), m['id'], m['config'], m['dataset']]:
            raise ValueError('Archive identity')
        mc, sc = integer(v[5], 1, 8), integer(v[6], 1, 128)
        if len(v) != 7 + 155*mc + 5*sc:
            raise ValueError('Archive layout')
        labels = []
        for i in range(mc):
            a = v[7+155*i:7+155*(i+1)]
            labels.append(integer(a[0], 1))
            number(a[1], 0); number(a[2], 0)
            c = number(a[3])
            if c != -1 and not 0 <= c <= 1:
                raise ValueError('Constant class')
            number(a[4])
            for j in range(50):
                number(a[5+3*j]); number(a[7+3*j])
                if number(a[6+3*j]) <= 1e-12:
                    raise ValueError('Scale')
        previous = 0
        for i in range(sc):
            a = v[7+155*mc+5*i:7+155*mc+5*(i+1)]
            index = integer(a[0], 0, mc-1)
            start = integer(a[1], 1)
            stop = integer(a[2], start+1)
            integer(a[3], 0, start-86401); number(a[4], -3.000000001, 3.000000001)
            if previous > start or labels[index]+86400 >= start:
                raise ValueError('State overlap/leakage')
            if i == 0 and m['valid_from'] < start:
                raise ValueError('Validity before archive')
            previous = stop
        if m['valid_until'] > previous:
            raise ValueError('Validity after archive')
    else:
        if len(v) != 761 or v[1:5] != [SCHEMA, m['config'], feature_hash(), m['dataset']] or v[7] != '40,16':
            raise ValueError('MLP layout/binding')
        cutoff = integer(v[5], 1)
        if cutoff+86400 >= m['valid_from'] or not 0 < number(v[6]) < 1:
            raise ValueError('MLP cutoff/threshold')
        for i, s in enumerate(v[8:]):
            value = number(s)
            if i < 80 and i % 2 == 1 and value <= 1e-12:
                raise ValueError('MLP scale')


def bounded_read(path, limit):
    with Path(path).open('rb') as f:
        data = f.read(limit+1)
    if len(data) > limit:
        raise ValueError('Oversize input')
    return data


def atomic_write(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix='.slot-', suffix='.tmp', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(data); f.flush(); os.fsync(f.fileno())
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


@contextmanager
def writer_lock(root):
    root = Path(root); root.mkdir(parents=True, exist_ok=True)
    # Process-scoped OS lock releases even after a crash; never delete the lock inode.
    with (root / '.writer.lock').open('a+b') as f:
        if f.tell() == 0:
            f.write(b'0'); f.flush()
        f.seek(0)
        if os.name == 'nt':
            import msvcrt
            msvcrt.locking(f.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        try:
            yield
        finally:
            f.seek(0)
            if os.name == 'nt':
                msvcrt.locking(f.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(f, fcntl.LOCK_UN)


def immutable(path, data):
    if path.exists():
        if bounded_read(path, max(len(data), 16384)) != data:
            raise ValueError('Immutable revision/artifact collision')
    else:
        atomic_write(path, data)


def stage(root, manifest, artifact):
    root = Path(root); raw = bounded_read(manifest, 16384)
    ident = lines(raw, 16384)[3]; m = parse(raw, ident)
    data = bounded_read(artifact, 1000000); validate_artifact(m, data)
    with writer_lock(root):
        immutable(root/'Artifacts'/(m['artifact']+'.model'), data)
        immutable(root/m['id']/'Releases'/(m['revision']+'.slot'), raw)
    return m


def activate(root, ident, revision, expected):
    root = Path(root); token(ident); token(revision)
    if expected != 'NONE':
        token(expected)
    with writer_lock(root):
        pointer = root/ident/'active.slot'
        current = parse(bounded_read(pointer, 16384), ident)['revision'] if pointer.exists() else 'NONE'
        if current != expected:
            raise ValueError(f'Activation conflict: expected {expected}, found {current}')
        raw = bounded_read(root/ident/'Releases'/(revision+'.slot'), 16384)
        m = parse(raw, ident)
        validate_artifact(m, bounded_read(root/'Artifacts'/(m['artifact']+'.model'), 1000000))
        # Only mutable file. Readers see either a complete previous or new manifest.
        atomic_write(pointer, raw)
    return m


def pack(binding, artifact, revision, start, stop):
    m = dict(binding)
    data = bounded_read(artifact, 1000000)
    m.update(magic='ORB_SLOT1', schema=SCHEMA, features=feature_hash(), revision=token(revision),
             provider=lines(data, 1000000)[0], artifact=sha(data), valid_from=start, valid_until=stop,
             metric_from=0, metric_until=0, n=0, wr=0, net_r=0, dd=0, evaluation='NONE')
    raw = encode(m); validate_artifact(parse(raw, m['id']), data)
    return raw


def migrate(report, root):
    """Preserve all 52 existing R7 artifacts/decisions. Never replace an assigned slot."""
    report, root = Path(report), Path(root)
    records = json.loads((report/'verification.json').read_text())['records']
    metrics = {r['id']: r for r in json.loads((report/'leaderboard_5y_retrospective.json').read_text())}
    for info in records:
        artifact = report/'Files/OrbML/R7'/(info['id']+'.r7')
        data = bounded_read(artifact, 1000000)
        if sha(data) != info['model_sha']:
            raise ValueError('Migration source changed')
        v = lines(data, 1000000); at = 7 + 155*int(v[5])
        raw = pack(info, artifact, 'r7-20260912', int(float(v[at+1])), int(float(v[-3])))
        m = parse(raw, info['id']); r = metrics[info['id']]; s = r['r7']
        if r['r7_sha'] != m['artifact'] or r['dataset'] != m['dataset'] or r['config'] != m['config']:
            raise ValueError('Migration metrics identity')
        if s and s['trades'] > 0:
            m.update(metric_from=r['from_time'], metric_until=r['to_time'], n=s['trades'], wr=s['wr']*100,
                     net_r=s['net_r'], dd=s['dd_r'], evaluation=RETRO)
        raw = encode(m)
        with writer_lock(root):
            immutable(root/'Artifacts'/(m['artifact']+'.model'), data)
            immutable(root/m['id']/'Releases'/(m['revision']+'.slot'), raw)
        pointer = root/m['id']/'active.slot'
        if not pointer.exists():
            activate(root, m['id'], m['revision'], 'NONE')
        else:
            active = parse(bounded_read(pointer, 16384), m['id'])
            validate_artifact(active, bounded_read(root/'Artifacts'/(active['artifact']+'.model'), 1000000))
    return len(records)


def evaluate(manifest, artifact, csv, output):
    """Attach a reproducible closed-trade retrospective, never an OOS claim.

    New revisions default to N/A until this is run on their exact bound dataset.
    Archive comparison uses the last dated state/weights, as the original leaderboard did.
    """
    import numpy as np
    import pandas as pd
    from orb_ml_filter import load_dataset, portable_predict, FEATURES
    import export_orb_r7_runtime as e

    raw = bounded_read(manifest, 16384)
    m = parse(raw, lines(raw, 16384)[3])
    data = bounded_read(artifact, 1000000); validate_artifact(m, data)
    f, info = load_dataset(Path(csv))
    if info['config_hash'] != m['config'] or info['dataset_sha256'] != m['dataset']:
        raise ValueError('Metrics dataset/config mismatch')
    full = pd.read_csv(csv)
    if len(full.loc[(full.label_valid == 1) & (full.features_valid != 1)]):
        raise ValueError('Missing features in closed trades')
    if f.empty or set(f['preset_id']) != {m['id']}:
        raise ValueError('Metrics strategy mismatch/empty')
    if m['provider'] == 'ORB_MLP1':
        prediction = portable_predict(data, f[FEATURES].to_numpy(float), m['config'])
        keep = prediction >= float(lines(data, 1000000)[6])
    else:
        v = lines(data, 1000000); mc = int(v[5]); at = 7+155*mc
        state = v[at:][-5:]; index = int(float(state[0])); a = v[7+155*index:7+155*(index+1)]
        model = dict(zip(('label', 'gain', 'loss', 'constant', 'bias'), map(float, a[:5])))
        model.update(mean=list(map(float, a[5::3])), scale=list(map(float, a[6::3])), coef=list(map(float, a[7::3])))
        prediction = e.score_model(model, e.r7.r4.r3.returns.design(f).to_numpy(float), float(state[4]))
        keep = prediction >= 0
    stat = e.R.stats(f, keep)
    if stat['trades'] == 0:
        raise ValueError('No retained closed trades; keep metrics N/A')
    m.update(metric_from=int(info['window_from_broker']), metric_until=int(info['asof_broker']),
             n=stat['trades'], wr=100*stat['wr'], net_r=stat['net_r'], dd=stat['dd_r'], evaluation=RETRO)
    atomic_write(output, encode(m))
    return m


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    p = sub.add_parser('pack')
    p.add_argument('--binding', type=Path, required=True); p.add_argument('--artifact', type=Path, required=True)
    p.add_argument('--revision', required=True); p.add_argument('--valid-from', type=int, required=True)
    p.add_argument('--valid-until', type=int, required=True); p.add_argument('--output', type=Path, required=True)
    p = sub.add_parser('stage'); p.add_argument('--root', type=Path, required=True)
    p.add_argument('--manifest', type=Path, required=True); p.add_argument('--artifact', type=Path, required=True)
    p = sub.add_parser('evaluate')
    for name in ('manifest', 'artifact', 'csv', 'output'):
        p.add_argument('--'+name, type=Path, required=True)
    for action in ('activate', 'rollback'):
        p = sub.add_parser(action); p.add_argument('--root', type=Path, required=True)
        p.add_argument('--strategy', required=True); p.add_argument('--revision', required=True)
        p.add_argument('--expected', required=True)
    p = sub.add_parser('list'); p.add_argument('--root', type=Path, required=True)
    p = sub.add_parser('migrate'); p.add_argument('--root', type=Path, required=True)
    p.add_argument('--report', type=Path, default=Path('logs/OrbR7Runtime_20260912'))
    a = parser.parse_args()
    if a.action == 'pack':
        raw = pack(json.loads(a.binding.read_text()), a.artifact, a.revision, a.valid_from, a.valid_until)
        atomic_write(a.output, raw); print(a.output)
    elif a.action == 'stage':
        print(json.dumps(stage(a.root, a.manifest, a.artifact)))
    elif a.action == 'evaluate':
        print(json.dumps(evaluate(a.manifest, a.artifact, a.csv, a.output)))
    elif a.action in ('activate', 'rollback'):
        print(json.dumps(activate(a.root, a.strategy, a.revision, a.expected)))
    elif a.action == 'migrate':
        print('Migrated:', migrate(a.report, a.root))
    else:
        for path in sorted(a.root.glob('*/active.slot')):
            m = parse(bounded_read(path, 16384), path.parent.name)
            print(m['id'], m['provider'], m['revision'], m['artifact'], m['valid_until'])


if __name__ == '__main__':
    main()
