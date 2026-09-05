import json
from pathlib import Path
import time
from types import SimpleNamespace

import numpy as np
import pytest

from scripts import orb_ml_filter as ml
from scripts import orb_ml_worker as worker
from tests.test_orb_ml_filter import dataset_frame, save_dataset


def setup(root):
    data=root/"Datasets";data.mkdir()
    save_dataset(data,dataset_frame(500))
    (root/"Jobs").mkdir()
    return data/"fixture.csv"


def request(root, action="TRAIN", name="b123_100_job", ref="", config="b"*64, preset="test"):
    path=root/"Jobs"/(name+".request")
    ml.atomic_write(path,worker.pack(["ORB_ML_JOB1",action,name,config,"fixture",preset,ref,str(int(time.time()))]))
    return path


def status(root, name="b123_100_job"):
    return worker.unpack(root/"Jobs"/(name+".status"),10,"ORB_ML_STATUS1")


def prepare_result(root):
    setup(root)
    path=request(root);job=worker.read_job(path)
    path.rename(path.with_suffix(".claimed"))
    _,info=ml.load_dataset(root/"Datasets/fixture.csv")
    model=SimpleNamespace(hidden_layer_sizes=(16,),activation="relu",classes_=np.array([0,1]),
                          coefs_=[np.zeros((40,16)),np.zeros((16,1))],intercepts_=[np.zeros(16),np.zeros(1)])
    scaler=SimpleNamespace(mean_=np.zeros(40),scale_=np.ones(40))
    bundle=ml.encode_model(model,scaler,info,int(info["asof_broker"]),.5)
    out=root/"Results"/job["config"]/job["job"];out.mkdir(parents=True)
    (out/"binding.json").write_text(json.dumps(job))
    (out/(job["config"]+".candidate.model")).write_bytes(bundle)
    (out/(job["config"]+".report.json")).write_text(json.dumps(dict(
        dataset=info,deployment_checks_passed=True,model_sha256=ml.sha256(bundle))))
    worker.write_status(root,job,"READY",100,"Synthetic protocol fixture; not a performance claim")
    return job,out,bundle


def test_dashboard_train_has_real_epoch_progress_no_auto_publish(tmp_path,monkeypatch):
    setup(tmp_path);seen=[]
    original=worker.write_status
    def capture(root,job,state,percent,message):
        seen.append((state,percent,message));original(root,job,state,percent,message)
    monkeypatch.setattr(worker,"write_status",capture)
    worker.process_one(tmp_path,request(tmp_path))
    assert status(tmp_path)[5] in {"READY","REJECTED"}
    assert any("Epoch " in m and 5 < p < 80 for _,p,m in seen)
    assert not (tmp_path/"Models").exists()
    report=json.loads(next((tmp_path/"Results").rglob("*.report.json")).read_text())
    assert report["epochs"]==400 and report["solver"]=="adam"
    assert report["train_label_max"] < report["validation_start"]-86400


@pytest.mark.parametrize("field,value",[("config","c"*64),("preset","different")])
def test_wrong_strategy_csv_rejected(tmp_path,field,value):
    setup(tmp_path)
    worker.process_one(tmp_path,request(tmp_path,**{field:value}))
    assert status(tmp_path)[5]=="FAILED"
    assert "binding mismatch" in status(tmp_path)[8]
    assert not (tmp_path/"Models").exists()


def test_cancelled_queued_job_never_trains(tmp_path):
    setup(tmp_path);path=request(tmp_path);path.with_suffix(".cancel").touch()
    worker.process_one(tmp_path,path)
    assert status(tmp_path)[5]=="CANCELLED"
    assert not (tmp_path/"Results").exists()


def test_cancel_during_training_does_not_write_candidate(tmp_path,monkeypatch):
    setup(tmp_path);original=worker.write_status
    def cancel(root,job,state,percent,message):
        original(root,job,state,percent,message)
        if percent>=5: (root/"Jobs"/(job["job"]+".cancel")).touch()
    monkeypatch.setattr(worker,"write_status",cancel)
    worker.process_one(tmp_path,request(tmp_path))
    assert status(tmp_path)[5]=="CANCELLED"
    assert not list(tmp_path.rglob("*.candidate.model"))


def test_publish_requires_explicit_matching_ready_result(tmp_path):
    job,out,bundle=prepare_result(tmp_path)
    assert not (tmp_path/"Models").exists()
    worker.process_one(tmp_path,request(tmp_path,"PUBLISH","b123_publish",job["job"]))
    assert status(tmp_path,"b123_publish")[5]=="PUBLISHED"
    assert (tmp_path/"Models"/(job["config"]+".model")).read_bytes()==bundle


@pytest.mark.parametrize("damage",["config","dataset","preset","checksum","quality","cancel"])
def test_bad_promotion_preserves_existing_model(tmp_path,damage):
    job,out,bundle=prepare_result(tmp_path)
    active=tmp_path/"Models"/(job["config"]+".model");active.parent.mkdir();active.write_bytes(b"previous")
    if damage in {"config","dataset","preset"}:
        binding=json.loads((out/"binding.json").read_text());binding[damage]="other"
        (out/"binding.json").write_text(json.dumps(binding))
    if damage=="checksum": (out/(job["config"]+".candidate.model")).write_bytes(bundle+b"x")
    if damage=="quality": worker.write_status(tmp_path,job,"REJECTED",100,"Rejected")
    path=request(tmp_path,"PUBLISH","b123_publish",job["job"])
    if damage=="cancel": path.with_suffix(".cancel").touch()
    worker.process_one(tmp_path,path)
    assert status(tmp_path,"b123_publish")[5] in {"FAILED","CANCELLED"}
    assert active.read_bytes()==b"previous"


def test_interrupted_claim_not_replayed(tmp_path):
    setup(tmp_path);path=request(tmp_path);job=worker.read_job(path)
    path.rename(path.with_suffix(".claimed"));worker.write_status(tmp_path,job,"RUNNING",24,"Epoch 100/400")
    worker.recover(tmp_path)
    assert status(tmp_path)[5]=="FAILED"
    assert not (tmp_path/"Results").exists()


def test_duplicate_claim_not_reexecuted(tmp_path):
    job,_,_=prepare_result(tmp_path)
    worker.process_one(tmp_path,request(tmp_path))
    assert status(tmp_path)[5]=="READY"
    assert (tmp_path/"Jobs"/(job["job"]+".duplicate")).exists()


def test_request_path_traversal_and_tampering_rejected(tmp_path):
    setup(tmp_path);p=request(tmp_path)
    lines=worker.unpack(p,8,"ORB_ML_JOB1");lines[4]="../foreign"
    p.write_bytes(worker.pack(lines))
    with pytest.raises(ValueError): worker.read_job(p)
    p.write_bytes(p.read_bytes().replace(b"TRAIN",b"OTHER"))
    with pytest.raises(ValueError): worker.read_job(p)


def test_two_workers_cannot_claim_simultaneously(tmp_path):
    with worker.exclusive_worker(tmp_path):
        with pytest.raises(OSError):
            with worker.exclusive_worker(tmp_path): pass


def test_mql_browsing_and_actions_are_strategy_scoped():
    source=(Path(__file__).resolve().parents[1]/"IndicatorCodeExamples/OrbStrategyMLJobs.mqh").read_text()
    assert 'marker[0]!=config' in source and 'lines[2]==g_mlBrowseConfig' in source
    assert 'lines[3]==OrbMlSelectedDataset()' in source
    assert 's[5]!="READY"' in source
    assert 'OrbStrategyPresetHasActiveLifecycle()' in source
    assert 'ShellExecute' not in source and '#import' not in source
