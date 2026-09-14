"""Train current NAS datasets through the already-running isolated job worker."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import time
from nas_ml_filter import engine
from nas_ml_campaign import run

def read_status(path):
    try:
        lines=path.read_text().splitlines()
        return lines[0] if lines else 'QUEUED'
    except (FileNotFoundError,PermissionError):
        # Windows can briefly deny access during the worker's atomic replace.
        # It is not a failed training job; re-read on the next poll.
        return 'QUEUED'

def main(root,out,resume=False):
    if root.name!='NasML':raise ValueError('NAS namespace required')
    heartbeat=root/'heartbeat.txt'
    if not heartbeat.exists() or time.time()-int(heartbeat.read_text())>30:
        raise RuntimeError('NAS worker not healthy; start_nas_ml_worker.ps1 first')
    ml=engine();profile=Path(__file__).resolve().parents[1]/'IndicatorCodeExamples/NasStrategyInputProfile.mqh'
    source=re.search(r'NAS_LIBRARY_SOURCE_HASH "([a-f0-9]{64})"',profile.read_text())[1]
    if resume:
        manifest=json.loads((out/'queue_manifest.json').read_text())
        if manifest['source_hash']!=source:raise ValueError('Source changed; cannot resume this batch')
        return collect(root,out,manifest['jobs'])
    batch=str(time.time_ns());jobs=[];pending=[]
    for pointer in sorted((root/'Datasets').glob('*.latest')):
        a=pointer.read_text().splitlines()
        if len(a)!=4 or hashlib.sha256(('\n'.join(a[:3])+'\n').encode()).hexdigest()!=a[3]:raise ValueError('Pointer checksum')
        csv=root/'Datasets'/(a[2]+'.csv');_,info=ml.load_dataset(csv)
        if info['source_hash']!=source:continue
        if info['preset_id']!=a[0] or info['config_hash']!=a[1]:raise ValueError('Dataset binding')
        for mode in ('0','1'):
            job=f'campaign_{batch}_{a[0]}_{mode}'
            body=('\n'.join(('NAS_JOB1',job,a[0],a[1],a[2],mode))+'\n').encode()
            path=root/'Jobs'/(job+'.job')
            pending.append((path,body+hashlib.sha256(body).hexdigest().encode()+b'\n'))
            jobs.append(job)
    if len(jobs)!=38:raise RuntimeError(f'Expected 19 strategies / 38 jobs; queued {len(jobs)}')
    out.mkdir(parents=True,exist_ok=True)
    (out/'queue_manifest.json').write_text(json.dumps(dict(batch=batch,source_hash=source,jobs=jobs),indent=2))
    for path,data in pending:ml.atomic_write(path,data)
    return collect(root,out,jobs)

def collect(root,out,jobs):
    heartbeat=root/'heartbeat.txt'
    deadline=time.monotonic()+7200;last=-1
    while time.monotonic()<deadline:
        states={}
        for job in jobs:
            status=root/'Jobs'/(job+'.status')
            states[job]=read_status(status)
        completed=sum(s in ('READY','REJECTED','FAILED') for s in states.values())
        if completed!=last:print(f'{completed}/{len(jobs)} completed',flush=True);last=completed
        if completed==len(jobs):break
        if time.time()-int(heartbeat.read_text())>120:raise RuntimeError('Worker heartbeat stale')
        time.sleep(3)
    else:raise TimeoutError('Training still queued/running; do not enqueue duplicates')
    (out/'queue_status.json').write_text(json.dumps(states,indent=2))
    if 'FAILED' in states.values():raise RuntimeError('Training job failed; inspect status, no promotion performed by campaign')
    results,cells=run(root,out,False)
    print(f'Collected {len(cells)} leaderboard cells; ML toggles unchanged.',flush=True)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
    p.add_argument('--resume',action='store_true')
    a=p.parse_args();main(a.root,a.out,a.resume)
