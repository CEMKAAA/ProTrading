"""Local, DLL-free dashboard training queue. Never connects to a trading API."""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import json
import os
from pathlib import Path
import re
import time

import numpy as np

try:
    from . import orb_ml_filter as ml
except ImportError:
    import orb_ml_filter as ml

TERMINAL = {"READY", "REJECTED", "FAILED", "CANCELLED", "PUBLISHED"}


def pack(lines: list[str]) -> bytes:
    if any("\n" in s or "\r" in s for s in lines):
        raise ValueError("Multiline protocol field")
    payload=("\n".join(lines)+"\n").encode("utf-8")
    return payload+ml.sha256(payload).encode()+b"\n"


def unpack(path: Path, count: int, magic: str) -> list[str]:
    data=path.read_bytes()
    if len(data)>8192 or not data.endswith(b"\n"):
        raise ValueError("Invalid protocol length")
    lines=data.decode("utf-8").splitlines()
    if len(lines)!=count+1 or lines[0]!=magic or pack(lines[:-1])!=data:
        raise ValueError("Invalid protocol checksum/schema")
    return lines[:-1]


def safe_id(value: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,240}", value):
        raise ValueError("Unsafe identifier")
    return value


def within(root: Path, *parts: str) -> Path:
    path=root.joinpath(*parts).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError("Path escapes ML root")
    return path


def read_job(path: Path) -> dict:
    v=unpack(path, 8, "ORB_ML_JOB1")
    if v[1] not in {"TRAIN", "PUBLISH"} or not re.fullmatch("[a-f0-9]{64}", v[3]):
        raise ValueError("Invalid action/config")
    for i in [2,4,5]: safe_id(v[i])
    if v[6]: safe_id(v[6])
    if path.stem!=v[2] or not v[7].isdigit():
        raise ValueError("Job identity/timestamp mismatch")
    return dict(action=v[1],job=v[2],config=v[3],dataset=v[4],preset=v[5],ref=v[6],created=int(v[7]))


def write_status(root: Path, job: dict, state: str, percent: float, message: str):
    message=" ".join(str(message).split())[:220]
    message=message.encode("ascii", "replace").decode()
    lines=["ORB_ML_STATUS1",job["job"],job["config"],job["dataset"],job["action"],state,
           str(int(percent)),str(int(time.time())),message,job["ref"]]
    ml.atomic_write(within(root,"Jobs",job["job"]+".status"),pack(lines))


def heartbeat(root: Path):
    ml.atomic_write(within(root,"worker.heartbeat"),str(int(time.time())).encode())


class Cancelled(Exception): pass


def cancelled(root: Path, job: dict):
    if within(root,"Jobs",job["job"]+".cancel").exists():
        raise Cancelled("Cancelled by dashboard; active model unchanged")


def execute(root: Path, job: dict):
    if time.time()-job["created"]>900 or job["created"]>time.time()+60:
        raise ValueError("Request expired or clock mismatch; submit a fresh request")
    dataset=within(root,"Datasets",job["dataset"]+".csv")
    expected=dict(config_hash=job["config"],dataset_id=job["dataset"],preset_id=job["preset"])
    last_update=0.0
    started=time.monotonic()

    def progress(percent, message):
        nonlocal last_update
        cancelled(root,job)
        if time.monotonic()-started>1800:
            raise ValueError("Training exceeded 30-minute worker budget")
        if time.monotonic()-last_update>=0.1 or percent in {1,100}:
            heartbeat(root);write_status(root,job,"RUNNING",percent,message)
            last_update=time.monotonic()

    cancelled(root,job)
    if job["action"]=="TRAIN":
        out=within(root,"Results",job["config"],job["job"])
        report=ml.train(dataset,out,epochs=400,progress=progress,expected=expected)
        cancelled(root,job)
        # Preserve the originating immutable job next to its report/model.
        ml.atomic_write(out/"binding.json",json.dumps(job,sort_keys=True).encode())
        state="READY" if report["deployment_checks_passed"] else "REJECTED"
        message=(f"Test {report['test']['net_r']:+.2f}R / base {report['test_baseline']['net_r']:+.2f}R; "
                 f"WR {report['test']['win_rate']*100:.1f}%; keep {report['test']['retention']*100:.1f}%; "
                 f"{'eligible; explicit USE RESULT required' if state=='READY' else 'quality checks failed; research only'}")
        write_status(root,job,state,100,message)
        return

    if not job["ref"]: raise ValueError("No training run selected")
    source=within(root,"Results",job["config"],job["ref"])
    binding=json.loads((source/"binding.json").read_bytes())
    if any(binding.get(k)!=job[k] for k in ["config","dataset","preset"]) or binding.get("job")!=job["ref"]:
        raise ValueError("Cross-strategy/result binding rejected")
    status=unpack(within(root,"Jobs",job["ref"]+".status"),10,"ORB_ML_STATUS1")
    if status[1:6]!=[job["ref"],job["config"],job["dataset"],"TRAIN","READY"]:
        raise ValueError("Training run is not eligible")
    report=json.loads((source/(job["config"]+".report.json")).read_bytes())
    _,info=ml.load_dataset(dataset)
    if any(info[k]!=v for k,v in expected.items()) or report["dataset"]!=info:
        raise ValueError("Result no longer matches the immutable CSV")
    if not report["deployment_checks_passed"]: raise ValueError("Result failed quality checks")
    bundle=(source/(job["config"]+".candidate.model")).read_bytes()
    if ml.sha256(bundle)!=report["model_sha256"]: raise ValueError("Candidate was modified")
    ml.portable_predict(bundle,np.zeros((1,40)),job["config"])
    header=bundle.decode("ascii").splitlines()
    if header[4]!=info["dataset_sha256"] or int(header[5])!=int(info["asof_broker"]):
        raise ValueError("Candidate data/cutoff mismatch")
    cancelled(root,job)
    ml.atomic_write(within(root,"Models",job["config"]+".model"),bundle)
    write_status(root,job,"PUBLISHED",100,"Published. Press LOAD MODEL, then enable ML when ready.")


def process_one(root: Path, request: Path):
    # Atomic claim, with a single-worker lock. Never automatically replay an
    # interrupted training/publish operation after restart.
    job=read_job(request)
    claim=request.with_suffix(".claimed")
    if claim.exists():
        request.rename(request.with_suffix(".duplicate"));return
    request.rename(claim)
    try:
        write_status(root,job,"RUNNING",0,"Request validated")
        execute(root,job)
    except Cancelled as error:
        write_status(root,job,"CANCELLED",0,str(error))
    except Exception as error:
        write_status(root,job,"FAILED",0,f"{type(error).__name__}: {error}")


def recover(root: Path):
    for path in within(root,"Jobs").glob("*.claimed"):
        try:
            job=read_job(path)
            status=unpack(path.with_suffix(".status"),10,"ORB_ML_STATUS1")
            if status[5] in TERMINAL: continue
        except (ValueError,OSError,KeyError):
            try: job=read_job(path)
            except (ValueError,OSError): continue
        write_status(root,job,"FAILED",0,"Worker interrupted; no automatic replay. Submit a fresh job.")


@contextmanager
def exclusive_worker(root: Path):
    root.mkdir(parents=True,exist_ok=True)
    handle=open(root/"worker.lock","a+b")
    try:
        handle.seek(0)
        if os.name=="nt":
            import msvcrt
            if handle.read(1)==b"": handle.write(b"0");handle.flush()
            handle.seek(0);msvcrt.locking(handle.fileno(),msvcrt.LK_NBLCK,1)
        else:
            import fcntl
            fcntl.flock(handle,fcntl.LOCK_EX|fcntl.LOCK_NB)
        yield
    finally:
        handle.close()


def run(root: Path, once=False):
    with exclusive_worker(root):
        within(root,"Jobs").mkdir(parents=True,exist_ok=True)
        recover(root)
        while True:
            heartbeat(root)
            for request in sorted(within(root,"Jobs").glob("*.request")):
                try: process_one(root,request)
                except (OSError,ValueError,UnicodeError):
                    # Malformed requests cannot escape the queue or execute commands.
                    if request.exists(): request.rename(request.with_suffix(".invalid"))
            if once: break
            time.sleep(1)


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root",type=Path,required=True,help="Common Files/OrbML")
    parser.add_argument("--once",action="store_true",help="Process current queue and exit (test/maintenance)")
    args=parser.parse_args()
    try: run(args.root.resolve(),args.once)
    except OSError as error: parser.exit(1,f"Worker unavailable or already running: {error}\n")
