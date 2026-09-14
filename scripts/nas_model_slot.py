"""NAS-bound adapter for ORB's immutable, compare-and-swap champion slots."""
from pathlib import Path
import hashlib
import importlib.util

try:
    from .build_nas_ml_contract import FEATURES,SCHEMA
except ImportError:
    from build_nas_ml_contract import FEATURES,SCHEMA


def engine():
    spec=importlib.util.spec_from_file_location('nas_isolated_slot',Path(__file__).with_name('orb_model_slot.py'))
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    module.SCHEMA=SCHEMA
    module.feature_hash=lambda:hashlib.sha256(','.join('f_'+f for f in FEATURES).encode()).hexdigest()
    return module


def stage_qualified(root,report,artifact):
    root=Path(root)
    if root.name!='NasML':raise ValueError('NAS namespace required')
    if not report['deployment_checks_passed']:raise ValueError('Unqualified champion')
    slot=engine();info=report['dataset'];artifact=Path(artifact)
    if slot.sha(artifact.read_bytes())!=report['model_sha256']:raise ValueError('Candidate changed')
    binding=dict(id=info['preset_id'],config=info['config_hash'],dataset=info['dataset_sha256'],
        runtime_hash=info['source_hash'],custom_hash='',symbol=info['symbol'],broker=info['broker'],
        inputs=info['config_hash'],tf=int(info['signal_tf_seconds'])//60)
    # Same broker-clock domain as feature availability; validity is deliberately
    # bounded. No silent indefinite use of stale calibration.
    start=int(report['last_label_broker'])+86401
    revision='nas-'+report['model_sha256'][:24]
    raw=slot.pack(binding,artifact,revision,start,start+30*86400)
    staging=root/'Models'/'1'/'Releases'/(revision+'.slot')
    slot.atomic_write(staging,raw)
    slots=root/'Slots';manifest=slot.stage(slots,staging,artifact)
    active=slots/binding['id']/'active.slot'
    if not active.exists():
        manifest=slot.activate(slots,binding['id'],revision,'NONE')
    else:
        # Re-training is not permission to replace a previously selected model.
        manifest=slot.parse(slot.bounded_read(active,16384),binding['id'])
    return manifest
