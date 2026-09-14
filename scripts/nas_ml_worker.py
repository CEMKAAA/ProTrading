"""NAS-only job consumer. Reuses ORB locking, atomic writes and training code.

No orders, shell commands, pickles or network calls. A training job creates
research candidates only. Qualified result promotion is a separate explicit job.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re
import time

try:
    from .nas_ml_filter import engine
    from .orb_ml_worker import exclusive_worker
    from .nas_model_slot import stage_qualified
except ImportError:
    from nas_ml_filter import engine
    from orb_ml_worker import exclusive_worker
    from nas_model_slot import stage_qualified

def parse_job(path: Path):
    data=path.read_bytes()
    if len(data)>4096 or b'\r' in data: raise ValueError('Noncanonical job')
    a=data.decode('ascii').splitlines()
    if len(a)!=7 or a[0]!='NAS_JOB1' or not data.endswith(b'\n'): raise ValueError('Job format')
    payload=('\n'.join(a[:-1])+'\n').encode()
    if hashlib.sha256(payload).hexdigest()!=a[-1]: raise ValueError('Job checksum')
    if any(not re.fullmatch(r'[A-Za-z0-9_]{1,180}',a[i]) for i in (1,2,4)): raise ValueError('Unsafe identity')
    if not re.fullmatch(r'[a-f0-9]{64}',a[3]) or a[5] not in ('0','1'): raise ValueError('Config/mode')
    if path.stem!=a[1]: raise ValueError('Filename/job mismatch')
    return dict(job=a[1],preset=a[2],config=a[3],dataset=a[4],mode=a[5])

def within(root: Path,relative: str):
    path=(root/relative).resolve()
    if not path.is_relative_to(root.resolve()): raise ValueError('Path escapes NAS namespace')
    return path

def process(root: Path,path: Path):
    ml=engine();job=parse_job(path)
    claim=path.with_suffix('.claimed')
    if claim.exists(): raise ValueError('Already claimed job')
    path.rename(claim)
    status=within(root,f"Jobs/{job['job']}.status")
    def notify(pct,message,state='RUNNING'):
        text=str(message).replace('\r',' ').replace('\n',' ')[:400]
        ml.atomic_write(root/'heartbeat.txt',str(int(time.time())).encode())
        if within(root,f"Jobs/{job['job']}.cancel").exists() and state=='RUNNING':raise ValueError('Training cancelled')
        ml.atomic_write(status,f'{state}\n{pct:.4f}\n{text}\n'.encode())
    try:
        dataset=within(root,f"Datasets/{job['dataset']}.csv")
        output=within(root,f"Models/{job['mode']}")
        report=ml.train(dataset,output,publish=False,advanced=job['mode']=='1',
            epochs=200 if job['mode']=='1' else 0,progress=notify,
            expected={'preset_id':job['preset'],'config_hash':job['config'],'dataset_id':job['dataset']})
        # This is a qualified portable result, not an active EA toggle. Preserve
        # a prior release unless the new candidate actually passed all gates.
        if report['deployment_checks_passed']:
            model=output/(job['config']+'.candidate.model')
            data=model.read_bytes()
            if ml.sha256(data)!=report['model_sha256']:raise ValueError('Model/report checksum mismatch')
            release=output/'Releases'/(report['model_sha256']+'.model')
            ml.atomic_write(release,data)
            ml.atomic_write(output/(job['config']+'.model'),data)
            if job['mode']=='1':stage_qualified(root,report,release)
            notify(100,'Qualified result available. USE RESULT pins it; ML remains OFF.','READY')
        else:
            notify(100,'Validation gates rejected candidate; previous qualified result unchanged.','REJECTED')
    except Exception as error:
        notify(0,f'{type(error).__name__}: {error}','FAILED')
        return False
    return True

def run(root: Path,once=False):
    if root.name!='NasML': raise ValueError('Worker root must be the dedicated NasML directory')
    with exclusive_worker(root):
        jobs=within(root,'Jobs');jobs.mkdir(exist_ok=True)
        ml=engine()
        # No silent replay of partially completed training after process death.
        for claim in jobs.glob('*.claimed'):
            status=claim.with_suffix('.status')
            if not status.exists() or status.read_text().splitlines()[0]=='RUNNING':
                ml.atomic_write(status,b'FAILED\n0\nWorker interrupted; submit a fresh job.\n')
        while True:
            ml.atomic_write(root/'heartbeat.txt',str(int(time.time())).encode())
            for job in sorted(jobs.glob('*.job')):
                try: process(root,job)
                except (OSError,ValueError,UnicodeError) as error:
                    print(f'{job.name}: {error}',flush=True)
                    if job.exists(): job.rename(job.with_suffix('.invalid'))
            if once:return
            time.sleep(1)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,required=True)
    parser.add_argument('--once',action='store_true')
    args=parser.parse_args();run(args.root,args.once)
