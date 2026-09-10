"""Explicit experimental model adapter; no fitting, activation or order access."""
import argparse
import hashlib
import json
from pathlib import Path

import joblib
import numpy as np

try:
    from .orb_ml_filter import FEATURE_HASH, FEATURES, load_dataset, portable_predict, atomic_write
    from .orb_ml_return_campaign import design
    from .build_orb_leaderboard import quote
except ImportError:
    from orb_ml_filter import FEATURE_HASH, FEATURES, load_dataset, portable_predict, atomic_write
    from orb_ml_return_campaign import design
    from build_orb_leaderboard import quote


def digest(data):
    return hashlib.sha256(data).hexdigest()


def numeric_hash(values):
    # Runtime settings are decimal UI values; ignore serialization noise far below their resolution.
    return digest(('\n'.join(format(float(v), '.12f') for v in values)+'\n').encode())


def function(text, name):
    start = text.index(name+'(')
    start = text.index('{', start)
    depth = 1
    end = start + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end].replace('\r\n', '\n')


def encode_return(bundle, report, info):
    model = bundle['model']
    kind = 'RIDGE' if report['selected'].startswith('ridge') else 'HGB'
    cutoff = max(report['train_label_max'], report['validation_label_max'])
    tokens = ['ORB_RETURN1', info['config_hash'], FEATURE_HASH, info['dataset_sha256'], str(cutoff),
              format(bundle['threshold'], '.17g'), str(int(bundle['active'])), kind]
    if kind == 'RIDGE':
        tokens += ['0', format(float(model[-1].intercept_), '.17g')]
        values = np.r_[np.column_stack([model[0].mean_, model[0].scale_]).ravel(), model[-1].coef_]
        tokens += [format(float(v), '.17g') for v in values]
    else:
        tokens += [str(len(model._predictors)), format(float(model._baseline_prediction[0, 0]), '.17g')]
        for trees in model._predictors:
            if len(trees) != 1:
                raise ValueError('Unexpected multi-output tree')
            nodes = trees[0].nodes
            if any(nodes['is_categorical']):
                raise ValueError('Categorical tree unsupported')
            tokens.append(str(len(nodes)))
            for node in nodes:
                tokens += [str(int(node['is_leaf'])), str(int(node['feature_idx'])), format(float(node['num_threshold']), '.17g'),
                           format(float(node['value']), '.17g'), str(int(node['left'])), str(int(node['right']))]
    payload = ('\n'.join(tokens)+'\n').encode('ascii')
    return payload + digest(payload).encode() + b'\n'


def predict_return(data, x):
    lines = data.decode('ascii').splitlines()
    if digest(('\n'.join(lines[:-1])+'\n').encode()) != lines[-1]:
        raise ValueError('Checksum')
    x = np.asarray(x, float)
    if x.shape[1] != 50 or not np.isfinite(x).all():
        raise ValueError('Features')
    bias = float(lines[9])
    if lines[7] == 'RIDGE':
        v = np.array(lines[10:-1], float)
        return ((x-v[:100:2])/v[1:100:2]) @ v[100:] + bias
    result = np.full(len(x), bias)
    pos = 10
    for _ in range(int(lines[8])):
        count = int(lines[pos]); pos += 1
        nodes = np.array(lines[pos:pos+6*count], float).reshape(count, 6); pos += 6*count
        for row, features in enumerate(x):
            index = 0
            for _ in range(count):
                leaf, feature, threshold, value, left, right = nodes[index]
                if leaf:
                    result[row] += value
                    break
                index = int(left if features[int(feature)] <= threshold else right)
            else:
                raise ValueError('Tree cycle')
    if pos != len(lines)-1:
        raise ValueError('Trailing tokens')
    return result


def build(root, sources, out):
    snapshot = root.parent/'compiled_sources'
    # Explicit compatibility proof. UI/build changes do not justify blanket hash bypass.
    for name in ['OrbStrategyPresetLibrary.mqh', 'OrbStrategyUserContract.mqh', 'OrbStrategyMLCore.mqh',
                 'NasUltimate_Core.mqh', 'LiqNarrativeSol_RegimeV3.mqh']:
        if (sources/name).read_text(encoding='utf8') != (snapshot/name).read_text(encoding='utf8'):
            raise ValueError('Campaign engine contract changed: '+name)
    current = (sources/'OrbStrategyMLPipeline.mqh').read_text(encoding='utf8')
    prior = (snapshot/'OrbStrategyMLPipeline.mqh').read_text(encoding='utf8')
    if function(current, 'OrbMlFeatures') != function(prior, 'OrbMlFeatures'):
        raise ValueError('Feature extraction changed')
    out.mkdir(parents=True, exist_ok=True)
    ranking = json.loads((root/'leaderboard.json').read_text(encoding='utf8'))
    states = {s['preset_id']: s for s in json.loads((root/'campaign.json').read_text())}
    records, statements, vectors = [], [], []
    for row in ranking:
        if not row['family']:
            continue
        state = states[row['id']]
        csv = Path(state['csv']); frame, info = load_dataset(csv)
        if info['dataset_sha256'] != state['csv_sha256']:
            raise ValueError('Campaign CSV changed')
        folder = root/row['id']/row['family']
        if row['family'] == 'mlp':
            data = (folder/(info['config_hash']+'.candidate.model')).read_bytes()
            # Existing portable MLP was already parity-tested against sklearn.
            actual = portable_predict(data, frame[FEATURES].to_numpy(float), info['config_hash'])
            error = 0.0
            kind = 'MLP'
        else:
            report = json.loads((folder/'report.json').read_text())
            bundle = joblib.load(folder/'return_model.research.joblib')
            data = encode_return(bundle, report, info)
            expected = bundle['model'].predict(design(frame))
            actual = predict_return(data, design(frame).to_numpy())
            error = float(np.max(np.abs(expected-actual)))
            if error > 1e-10 or not np.array_equal(expected >= bundle['threshold'], actual >= bundle['threshold']):
                raise ValueError('Portable return prediction/decision mismatch')
            kind = 'RIDGE' if report['selected'].startswith('ridge') else 'HGB'
        if not np.isfinite(actual).all():
            raise ValueError('Invalid inference')
        threshold = float(data.decode().splitlines()[6 if kind == 'MLP' else 5])
        active = kind == 'MLP' or bool(bundle['active'])
        for index in sorted({0, len(frame)//2, len(frame)-1}):
            values = [row['id'], format(float(actual[index]), '.17g'), format(threshold, '.17g'),
                      str(int(not active or actual[index] >= threshold))]
            values += [format(float(v), '.17g') for v in frame.iloc[index][FEATURES].to_numpy(float)]
            vectors.append(';'.join(values))
        model_file = row['id']+'.experimental'
        atomic_write(out/model_file, data)
        settings = (csv.parent.parent/'Settings'/(row['id']+'.txt')).read_text(encoding='utf8').splitlines()
        if len(settings) != 50 or settings[1] != row['symbol']:
            raise ValueError('Settings contract')
        # Only simulator fill costs (last six values) are omitted; all strategy runtime values remain bound.
        runtime_hash = numeric_hash(settings[4:44])
        custom_hash = ''
        if row['id'].startswith('user_'):
            for p in (csv.parent.parent/'UserStrategies').glob('*.preset'):
                values = p.read_text(encoding='utf8').splitlines()
                if values[6] == row['id']:
                    # Names and legacy family=ANY are metadata; symbol is independently bound.
                    custom_hash = numeric_hash(values[11:64]); break
            if not custom_hash:
                raise ValueError('Custom snapshot missing')
        broker = str(frame.iloc[0].broker)
        r = dict(id=row['id'], config=info['config_hash'], dataset=info['dataset_sha256'], model_sha=digest(data),
                 kind=kind, runtime_hash=runtime_hash, custom_hash=custom_hash, symbol=row['symbol'],
                 broker=broker, tf=int(settings[2]), inputs=settings[3], csv=str(csv), max_error=error)
        records.append(r)
        fields = {k: r[k] for k in ('id','config','dataset','model_sha','kind','runtime_hash','custom_hash','symbol','broker','inputs')}
        # Common-relative CSV location is discoverable without copying/retraining data.
        fields['csv'] = 'OrbMLCampaign_20260909_v3\\Datasets\\'+csv.name
        statements.append('   if(id=='+quote(r['id'])+'){'+''.join('r.'+k+'='+quote(v)+';' for k,v in fields.items())+'r.tf='+str(r['tf'])+';return true;}')
    text = '// Generated experimental campaign registry; verified settings, immutable model checksums.\n'
    text += 'bool OrbCampaignRecord(string id,OrbCampaignInfo &r)\n{\n'+'\n'.join(statements)+'\n   return false;\n}\n'
    (sources/'OrbStrategyCampaignRegistry.mqh').write_text(text, encoding='utf8')
    (out/'adapter_verification.json').write_text(json.dumps(records, indent=2), encoding='utf8')
    (out/'probe_vectors.txt').write_text('\n'.join(vectors)+'\n', encoding='ascii')
    print(f'Exported {len(records)} experimental models; max return error {max(r["max_error"] for r in records):.3g}; no training or activation')


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--campaign', type=Path, required=True)
    p.add_argument('--sources', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    a = p.parse_args(); build(a.campaign, a.sources, a.out)
