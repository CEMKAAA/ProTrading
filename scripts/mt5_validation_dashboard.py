"""
Small local dashboard for MT5 validation jobs.

Run:
  python scripts/mt5_validation_dashboard.py --port 8765

Open:
  http://127.0.0.1:8765

Design constraints:
  - stdlib only
  - no QuantDesk dependency
  - bounded file reads for space/performance safety
  - portable MT5 worker friendly
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import os
import shutil
import subprocess
import sys
import threading
import time
import uuid
from datetime import datetime, timedelta
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import parse_qs, urlparse


PROJECT_ROOT = Path(__file__).resolve().parents[1]
HARNESS = PROJECT_ROOT / "scripts" / "mt5_validation_harness.py"
OUT_ROOT = PROJECT_ROOT / "logs" / "mt5_validation"
TMP_JOBS = OUT_ROOT / "_dashboard_jobs"
SHORT_OUT_ROOT = Path(os.environ.get("MT5_VALIDATION_OUT_ROOT", r"C:\tmp\mt5v"))
DEFAULT_SHORTCUT = Path(r"C:\Users\Cem\Desktop\DEMOMT5.lnk")
DEFAULT_TERMINAL_DIR = Path(r"C:\MT5\DEMO")
VALIDATION_WORKER_DIR = Path(r"C:\tmp\MT5_VALIDATION_WORKER")
VALIDATION_WORKER_EXE = VALIDATION_WORKER_DIR / "terminal64.exe"
MAX_TAIL_BYTES = 256 * 1024
MAX_EVENTS = 250


EA_DEFS = {
    "nas": {
        "label": "NAS V3",
        "ea": "NasUltimateEa",
        "preset_root": PROJECT_ROOT / "IndicatorCodeExamples" / "EaPresets" / "NAS" / "V3",
        "audit_globs": ["NasV3Lab_TesterTradeAudit_*.csv", "NasV3Lab_BacktestProcess_*.csv", "NasV3Lab_BruteBacktest_*.csv"],
        "default_tf": "M15",
    },
    "orb": {
        "label": "ORB15",
        "ea": "OrbUltimateEA",
        "preset_root": PROJECT_ROOT / "IndicatorCodeExamples" / "EaPresets" / "ORB15",
        "audit_globs": ["ORB15_TesterTradeAudit_*.csv", "ORB15_BacktestProcess_*.csv", "ORB15_BruteBacktest_*.csv"],
        "default_tf": "M1",
    },
    "erl": {
        "label": "ERL/IRL",
        "ea": "ERL_IRL_SwingModel_EA",
        "preset_root": PROJECT_ROOT / "IndicatorCodeExamples" / "EaPresets" / "ERL_IRL",
        "audit_globs": ["ERL_IRL_TesterTradeAudit_*.csv", "ERL_IRL_BacktestProcess_*.csv", "ERL_IRL_BruteBacktest_*.csv"],
        "default_tf": "M15",
    },
}


STATE_LOCK = threading.Lock()
RUNS: Dict[str, Dict[str, Any]] = {}


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def now_iso() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def json_response(handler: BaseHTTPRequestHandler, payload: Any, status: int = 200) -> None:
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Cache-Control", "no-store")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def text_response(handler: BaseHTTPRequestHandler, body: str, content_type: str = "text/html; charset=utf-8") -> None:
    data = body.encode("utf-8")
    handler.send_response(200)
    handler.send_header("Content-Type", content_type)
    handler.send_header("Cache-Control", "no-store")
    handler.send_header("Content-Length", str(len(data)))
    handler.end_headers()
    handler.wfile.write(data)


def read_body(handler: BaseHTTPRequestHandler) -> Dict[str, Any]:
    n = int(handler.headers.get("Content-Length", "0") or "0")
    raw = handler.rfile.read(n) if n > 0 else b"{}"
    return json.loads(raw.decode("utf-8-sig") or "{}")


def list_presets(kind: str) -> List[Dict[str, str]]:
    info = EA_DEFS.get(kind)
    if not info:
        return []
    root = Path(info["preset_root"])
    if not root.exists():
        return []
    rows = []
    for path in sorted(root.rglob("*.set")):
        rows.append({"name": path.name, "path": str(path), "rel": str(path.relative_to(root))})
    return rows


def detect_text_encoding(head: bytes) -> str:
    if head.startswith(b"\xff\xfe") or head.startswith(b"\xfe\xff"):
        return "utf-16"
    if head.startswith(b"\xef\xbb\xbf"):
        return "utf-8-sig"
    if head[:128].count(b"\x00") > 16:
        return "utf-16"
    return "utf-8-sig"


def safe_tail(path: Path, max_bytes: int = MAX_TAIL_BYTES) -> str:
    try:
        size = path.stat().st_size
        with path.open("rb") as f:
            head = f.read(128)
            encoding = detect_text_encoding(head)
            f.seek(0)
            if size > max_bytes:
                offset = size - max_bytes
                if encoding == "utf-16" and offset % 2:
                    offset -= 1
                f.seek(max(0, offset))
                f.readline()
            data = f.read()
        return data.decode(encoding, errors="replace")
    except OSError:
        return ""


def sniff_rows_from_tail(path: Path, limit: int = MAX_EVENTS) -> List[Dict[str, str]]:
    text = safe_tail(path)
    if not text.strip():
        return []
    lines = text.splitlines()
    if not lines:
        return []
    header_idx = -1
    for idx, line in enumerate(lines):
        if "job_id" in line and "engine" in line:
            header_idx = idx
            break
    if header_idx >= 0:
        usable = lines[header_idx:]
    else:
        head = safe_head_line(path)
        usable = [head, *lines] if head else lines
    sample = "\n".join(usable[:5])
    try:
        dialect = csv.Sniffer().sniff(sample, delimiters=",;")
    except csv.Error:
        dialect = csv.excel
    rows = list(csv.DictReader(io.StringIO("\n".join(usable), newline=""), dialect=dialect))
    return [{str(k): "" if v is None else str(v) for k, v in row.items() if k is not None} for row in rows[-limit:]]


def safe_head_line(path: Path) -> str:
    try:
        with path.open("rb") as f:
            head = f.read(4096)
        return head.decode(detect_text_encoding(head[:128]), errors="replace").splitlines()[0].strip()
    except (OSError, IndexError):
        return ""


def terminal_files_roots() -> List[Path]:
    roots = [
        VALIDATION_WORKER_DIR / "MQL5" / "Files",
        VALIDATION_WORKER_DIR / "Tester",
        DEFAULT_TERMINAL_DIR / "MQL5" / "Files",
        DEFAULT_TERMINAL_DIR / "Tester",
        SHORT_OUT_ROOT,
        OUT_ROOT,
    ]
    return [r for r in roots if r.exists()]


def find_recent_audit_files(kind: str, seconds: int = 24 * 3600) -> List[Path]:
    info = EA_DEFS.get(kind, {})
    globs = info.get("audit_globs", [])
    cutoff = time.time() - seconds
    found: List[Path] = []
    for root in terminal_files_roots():
        for pattern in globs:
            try:
                for path in root.rglob(pattern):
                    if path.is_file() and path.stat().st_mtime >= cutoff:
                        found.append(path)
            except OSError:
                continue
    found.sort(key=lambda p: p.stat().st_mtime if p.exists() else 0, reverse=True)
    return found[:20]


def summarize_audits(kind: str, job_id: str = "") -> Dict[str, Any]:
    files = find_recent_audit_files(kind)
    events: List[Dict[str, Any]] = []
    signals: List[Dict[str, Any]] = []
    deal_rows = 0
    net_profit = 0.0
    bytes_total = 0
    for path in files:
        try:
            bytes_total += path.stat().st_size
        except OSError:
            pass
        rows = sniff_rows_from_tail(path)
        for row in rows:
            if job_id and row.get("job_id") not in ("", job_id):
                continue
            event = {
                "file": path.name,
                "time": row.get("server_time") or row.get("gmt_time") or row.get("timestamp") or row.get("ts_gmt") or "",
                "type": row.get("entry_type") or row.get("event") or row.get("engine") or "",
                "dir": row.get("deal_type") or row.get("direction") or row.get("dir") or "",
                "price": row.get("price") or row.get("entry") or "",
                "profit": row.get("profit") or row.get("pnl") or "",
                "reason": row.get("reason") or row.get("detail") or "",
            }
            events.append(event)
            if row.get("entry_type") in ("IN", "INOUT"):
                signals.append(event)
                deal_rows += 1
            if row.get("entry_type") in ("OUT", "INOUT", "OUT_BY"):
                try:
                    net_profit += float(row.get("profit", "0") or 0) + float(row.get("swap", "0") or 0) + float(row.get("commission", "0") or 0) + float(row.get("fee", "0") or 0)
                except ValueError:
                    pass
    return {
        "files": [{"path": str(p), "name": p.name, "bytes": p.stat().st_size, "mtime": datetime.fromtimestamp(p.stat().st_mtime).strftime("%H:%M:%S")} for p in files[:12]],
        "events": events[-MAX_EVENTS:],
        "signals": signals[-100:],
        "deal_entry_count": deal_rows,
        "net_profit": round(net_profit, 2),
        "bytes_total": bytes_total,
    }


def build_job_payload(data: Dict[str, Any], preset: str, suffix: str) -> Dict[str, Any]:
    kind = data.get("ea_kind", "nas")
    info = EA_DEFS[kind]
    job_id = f"{kind}_{data.get('symbol','USTECm')}_{data.get('timeframe', info['default_tf'])}_{suffix}".replace(".", "_").lower()
    overrides = dict(data.get("preset_overrides") or {})
    overrides.setdefault("InpValidationJobId", job_id)
    overrides.setdefault("InpTesterTradeAuditCsv", "true")
    overrides.setdefault("InpTesterTradeAuditMaxRows", str(int(data.get("max_audit_rows") or 50000)))
    payload = {
        "job_id": job_id,
        "ea": data.get("ea") or info["ea"],
        "ea_kind": kind,
        "preset": preset,
        "symbol": data.get("symbol", "USTECm"),
        "timeframe": data.get("timeframe") or info["default_tf"],
        "from_date": data.get("from_date"),
        "to_date": data.get("to_date"),
        "portable": True,
        "deposit": float(data.get("deposit") or 10000),
        "currency": data.get("currency", "USD"),
        "leverage": data.get("leverage", "1:100"),
        "model": int(data.get("model") or 4),
        "execution_mode": int(data.get("execution_mode") or 0),
        "timeout_sec": int(data.get("timeout_sec") or 1800),
        "shutdown_terminal": bool(data.get("shutdown_terminal", False)),
        "preset_overrides": overrides,
    }
    if data.get("terminal_exe"):
        payload["terminal_exe"] = data.get("terminal_exe")
    elif VALIDATION_WORKER_EXE.exists():
        payload["terminal_exe"] = str(VALIDATION_WORKER_EXE)
        payload["terminal_data_dir"] = str(VALIDATION_WORKER_DIR)
    else:
        payload["terminal_shortcut"] = data.get("terminal_shortcut") or str(DEFAULT_SHORTCUT)
        payload["terminal_data_dir"] = data.get("terminal_data_dir") or str(DEFAULT_TERMINAL_DIR)
    return payload


def run_harness_async(run_id: str, jobs_path: Path) -> None:
    run_root = SHORT_OUT_ROOT / "dashboard_runs" if SHORT_OUT_ROOT.exists() else OUT_ROOT / "dashboard_runs"
    cmd = [sys.executable, str(HARNESS), "run", "--jobs", str(jobs_path), "--out-dir", str(run_root)]
    with STATE_LOCK:
        RUNS[run_id]["status"] = "running"
        RUNS[run_id]["command"] = cmd
        RUNS[run_id]["started_at"] = now_iso()
    try:
        proc = subprocess.Popen(cmd, cwd=str(PROJECT_ROOT), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        lines: List[str] = []
        while True:
            line = proc.stdout.readline() if proc.stdout else ""
            if line:
                lines.append(line.rstrip())
                lines = lines[-200:]
                with STATE_LOCK:
                    RUNS[run_id]["log"] = lines
            if proc.poll() is not None:
                break
            time.sleep(0.25)
        rc = proc.returncode
        with STATE_LOCK:
            RUNS[run_id]["status"] = "completed" if rc == 0 else "failed"
            RUNS[run_id]["returncode"] = rc
            RUNS[run_id]["finished_at"] = now_iso()
            RUNS[run_id]["log"] = lines
    except Exception as exc:
        with STATE_LOCK:
            RUNS[run_id]["status"] = "failed"
            RUNS[run_id]["error"] = str(exc)
            RUNS[run_id]["finished_at"] = now_iso()


def start_run(data: Dict[str, Any]) -> Dict[str, Any]:
    kind = data.get("ea_kind", "nas")
    if kind not in EA_DEFS:
        raise ValueError(f"Unknown ea_kind: {kind}")
    presets = data.get("presets") or ([data["preset"]] if data.get("preset") else [])
    if not presets:
        raise ValueError("At least one preset is required.")
    if not data.get("from_date") or not data.get("to_date"):
        raise ValueError("from_date and to_date are required.")
    run_id = datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + uuid.uuid4().hex[:6]
    ensure_dir(TMP_JOBS)
    jobs = [build_job_payload(data, str(Path(p)), f"{run_id}_{idx+1}") for idx, p in enumerate(presets)]
    jobs_path = TMP_JOBS / f"{run_id}.json"
    jobs_path.write_text(json.dumps({"jobs": jobs}, indent=2), encoding="utf-8")
    with STATE_LOCK:
        RUNS[run_id] = {
            "run_id": run_id,
            "status": "queued",
            "created_at": now_iso(),
            "jobs_path": str(jobs_path),
            "jobs": jobs,
            "log": [],
        }
    t = threading.Thread(target=run_harness_async, args=(run_id, jobs_path), daemon=True)
    t.start()
    return RUNS[run_id]


def cleanup(days: int = 7, keep_latest: int = 20) -> Dict[str, Any]:
    deleted = []
    cutoff = time.time() - days * 86400
    roots = [OUT_ROOT]
    if SHORT_OUT_ROOT.exists():
        roots.append(SHORT_OUT_ROOT)
    candidates = []
    for root in roots:
        candidates.extend([p for p in root.rglob("*") if p.is_dir() and p.name[:8].isdigit()])
    candidates.sort(key=lambda p: p.stat().st_mtime if p.exists() else 0, reverse=True)
    for idx, path in enumerate(candidates):
        try:
            if idx < keep_latest:
                continue
            if path.stat().st_mtime > cutoff:
                continue
            shutil.rmtree(path)
            deleted.append(str(path))
        except OSError:
            continue
    return {"deleted": deleted, "count": len(deleted)}


HTML = r"""
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<title>MT5 Validation Cockpit</title>
<style>
:root{--bg:#10141b;--panel:#d8dee7;--ink:#111827;--muted:#64748b;--red:#e93f55;--blue:#2563eb;--cyan:#38bdf8;--ok:#16a34a;--line:#9aa7b8}
*{box-sizing:border-box} body{margin:0;font-family:Bahnschrift,'Segoe UI',sans-serif;background:radial-gradient(circle at 20% 0,#263246 0,#10141b 42%,#07090d 100%);color:#e5edf7}
.wrap{max-width:1380px;margin:0 auto;padding:22px}.hero{display:flex;align-items:center;justify-content:space-between;margin-bottom:18px}
.title{font-size:28px;letter-spacing:.12em;text-transform:uppercase}.sub{color:#9fb1c8;font-size:13px}
.grid{display:grid;grid-template-columns:390px 1fr;gap:16px}.card{background:linear-gradient(145deg,#eef2f7,#cbd5e1);color:var(--ink);border:1px solid #f8fafc;border-radius:18px;box-shadow:0 22px 70px #0008;overflow:hidden}
.card.dark{background:linear-gradient(145deg,#111827,#0b111a);color:#e5edf7;border-color:#263244}.head{padding:14px 16px;background:linear-gradient(90deg,#dfe6ef,#b9c7d9);font-weight:800;letter-spacing:.08em}
.dark .head{background:linear-gradient(90deg,#1f2937,#111827);color:#dbeafe}.body{padding:16px}
label{font-size:11px;color:#526071;font-weight:800;text-transform:uppercase;letter-spacing:.08em}.dark label{color:#9fb1c8}
input,select,button{width:100%;border:1px solid #94a3b8;border-radius:10px;padding:9px 10px;background:#f8fafc;color:#111827;font-weight:700}
button{cursor:pointer;background:linear-gradient(135deg,var(--blue),#0ea5e9);color:white;border:0;box-shadow:0 8px 22px #2563eb55}
button.red{background:linear-gradient(135deg,var(--red),#fb7185)}button.ghost{background:#111827;color:#e5edf7;border:1px solid #334155;box-shadow:none}
.row{display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-bottom:10px}.full{margin-bottom:10px}
.presetbox{height:170px;overflow:auto;background:#f8fafc;border:1px solid #94a3b8;border-radius:12px;padding:8px}
.preset{display:flex;gap:8px;align-items:center;padding:6px;border-bottom:1px solid #e2e8f0;font-size:12px}.preset input{width:auto}
.metrics{display:grid;grid-template-columns:repeat(4,1fr);gap:10px}.metric{padding:13px;border-radius:14px;background:#121a27;border:1px solid #263244}.metric b{display:block;font-size:24px;color:#fff}.metric span{font-size:11px;color:#9fb1c8}
.timeline{height:290px;position:relative;background:linear-gradient(180deg,#0b111a,#111827);border:1px solid #263244;border-radius:16px;overflow:hidden;margin-top:12px}
.rail{position:absolute;left:18px;right:18px;top:50%;height:2px;background:#3b4657}.arrow{position:absolute;top:50%;transform:translate(-50%,-50%);padding:6px 8px;border-radius:9px;font-weight:900;font-size:12px;box-shadow:0 0 24px #000}
.BUY{background:#16a34a;color:white}.SELL{background:#e11d48;color:white}.OUT{background:#64748b;color:white}
.events{max-height:330px;overflow:auto;font-family:Consolas,monospace;font-size:12px}.event{display:grid;grid-template-columns:130px 70px 70px 1fr;gap:8px;padding:6px 0;border-bottom:1px solid #263244;color:#dbeafe}
.log{height:170px;overflow:auto;background:#05070a;border:1px solid #263244;border-radius:12px;padding:10px;font-family:Consolas,monospace;font-size:12px;color:#9fe1ff}
.pill{display:inline-block;padding:4px 8px;border-radius:999px;background:#1e293b;color:#dbeafe;font-size:12px;margin-left:6px}
@media(max-width:960px){.grid{grid-template-columns:1fr}.metrics{grid-template-columns:repeat(2,1fr)}}
</style>
</head>
<body>
<div class="wrap">
  <div class="hero"><div><div class="title">MT5 Validation Cockpit</div><div class="sub">Portable Strategy Tester runner · bounded audit tail · trade-level evidence</div></div><div><span class="pill" id="worker">worker</span></div></div>
  <div class="grid">
    <div class="card">
      <div class="head">MISSION CONFIG</div>
      <div class="body">
        <div class="row"><div><label>EA</label><select id="ea"></select></div><div><label>Symbol</label><input id="symbol" value="USTECm"></div></div>
        <div class="row"><div><label>Timeframe</label><select id="tf"><option>M1</option><option>M5</option><option selected>M15</option><option>M30</option><option>H1</option></select></div><div><label>Deposit</label><input id="deposit" value="10000"></div></div>
        <div class="row"><div><label>From</label><input id="from" value="2026.06.01"></div><div><label>To</label><input id="to" value="2026.06.16"></div></div>
        <div class="row"><div><label>Max audit rows</label><input id="maxrows" value="50000"></div><div><label>Timeout sec</label><input id="timeout" value="1800"></div></div>
        <div class="full"><label>Preset / Presets</label><div class="presetbox" id="presets"></div></div>
        <div class="row"><button onclick="run()">RUN TESTER</button><button class="red" onclick="cleanup()">CLEAN OLD RUNS</button></div>
        <div class="full"><button class="ghost" onclick="refresh()">REFRESH TELEMETRY</button></div>
      </div>
    </div>
    <div class="card dark">
      <div class="head">LIVE AUDIT TELEMETRY <span class="pill" id="status">idle</span></div>
      <div class="body">
        <div class="metrics">
          <div class="metric"><b id="mDeals">0</b><span>entry deals</span></div>
          <div class="metric"><b id="mPnl">0</b><span>tester audit pnl</span></div>
          <div class="metric"><b id="mFiles">0</b><span>audit files</span></div>
          <div class="metric"><b id="mBytes">0</b><span>bytes scanned</span></div>
        </div>
        <div class="timeline"><div class="rail"></div><div id="arrows"></div></div>
        <div class="row" style="grid-template-columns:1fr 1fr;margin-top:12px">
          <div><label>Runner log</label><div class="log" id="runlog"></div></div>
          <div><label>Audit files</label><div class="log" id="files"></div></div>
        </div>
        <label>Events</label><div class="events" id="events"></div>
      </div>
    </div>
  </div>
</div>
<script>
let currentRun=null, poll=null, cfg=null;
async function api(path, opts={}){const r=await fetch(path,{headers:{'Content-Type':'application/json'},...opts});return await r.json();}
function fmtBytes(n){if(n>1048576)return (n/1048576).toFixed(1)+' MB'; if(n>1024)return (n/1024).toFixed(1)+' KB'; return String(n)}
async function init(){cfg=await api('/api/config'); document.getElementById('worker').textContent=cfg.worker_shortcut+' -> '+cfg.worker_target;
 const ea=document.getElementById('ea'); ea.innerHTML=''; cfg.eas.forEach(x=>{const o=document.createElement('option');o.value=x.kind;o.textContent=x.label;ea.appendChild(o)}); ea.onchange=loadPresets; await loadPresets(); await refresh();}
async function loadPresets(){const kind=document.getElementById('ea').value; const data=await api('/api/presets?ea_kind='+kind); const box=document.getElementById('presets'); box.innerHTML='';
 data.presets.forEach((p,i)=>{const d=document.createElement('label'); d.className='preset'; d.innerHTML=`<input type="checkbox" ${i==0?'checked':''} value="${p.path.replaceAll('"','&quot;')}"><span>${p.rel}</span>`; box.appendChild(d)});}
function selectedPresets(){return [...document.querySelectorAll('#presets input:checked')].map(x=>x.value)}
async function run(){const body={ea_kind:ea.value,symbol:symbol.value,timeframe:tf.value,from_date:from.value,to_date:to.value,deposit:deposit.value,max_audit_rows:maxrows.value,timeout_sec:timeout.value,presets:selectedPresets()};
 const r=await api('/api/run',{method:'POST',body:JSON.stringify(body)}); currentRun=r.run_id; status.textContent=r.status; if(poll)clearInterval(poll); poll=setInterval(refresh,2000); await refresh();}
async function cleanup(){const r=await api('/api/cleanup',{method:'POST',body:JSON.stringify({days:7,keep_latest:20})}); alert('deleted '+r.count+' old dirs');}
async function refresh(){const kind=ea.value||'nas'; const qs=currentRun?'?run_id='+currentRun+'&ea_kind='+kind:'?ea_kind='+kind; const s=await api('/api/state'+qs);
 status.textContent=s.run?.status||'watching'; mDeals.textContent=s.audit.deal_entry_count; mPnl.textContent=s.audit.net_profit; mFiles.textContent=s.audit.files.length; mBytes.textContent=fmtBytes(s.audit.bytes_total);
 runlog.innerHTML=(s.run?.log||[]).slice(-80).map(x=>'<div>'+esc(x)+'</div>').join('');
 files.innerHTML=s.audit.files.map(f=>`<div>${esc(f.mtime)} · ${esc(f.name)} · ${fmtBytes(f.bytes)}</div>`).join('');
 renderEvents(s.audit.events||[]); renderArrows(s.audit.signals||[]);}
function renderEvents(rows){events.innerHTML=rows.slice(-80).reverse().map(e=>`<div class="event"><span>${esc(e.time)}</span><span>${esc(e.type)}</span><span>${esc(e.dir)}</span><span>${esc(e.price)} ${esc(e.profit)} ${esc(e.reason)}</span></div>`).join('')}
function renderArrows(rows){const box=document.getElementById('arrows'); box.innerHTML=''; const n=Math.max(rows.length,1); rows.slice(-40).forEach((e,i)=>{const x=5+(i/(Math.max(n-1,1)))*90; const d=(e.dir||'').includes('SELL')?'SELL':'BUY'; const el=document.createElement('div'); el.className='arrow '+d; el.style.left=x+'%'; el.textContent=d=='BUY'?'▲ BUY':'▼ SELL'; el.title=(e.time||'')+' '+(e.price||''); box.appendChild(el)})}
function esc(x){return String(x??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]))}
init();
</script>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args: Any) -> None:
        return

    def do_GET(self) -> None:
        try:
            parsed = urlparse(self.path)
            if parsed.path == "/":
                return text_response(self, HTML)
            if parsed.path == "/api/config":
                return json_response(self, self.api_config())
            if parsed.path == "/api/presets":
                qs = parse_qs(parsed.query)
                return json_response(self, {"presets": list_presets(qs.get("ea_kind", ["nas"])[0])})
            if parsed.path == "/api/state":
                qs = parse_qs(parsed.query)
                run_id = qs.get("run_id", [""])[0]
                kind = qs.get("ea_kind", ["nas"])[0]
                with STATE_LOCK:
                    run = RUNS.get(run_id) if run_id else None
                return json_response(self, {"run": run, "audit": summarize_audits(kind, run_id)})
            return json_response(self, {"error": "not_found"}, 404)
        except Exception as exc:
            return json_response(self, {"error": str(exc)}, 500)

    def do_POST(self) -> None:
        try:
            if self.path == "/api/run":
                return json_response(self, start_run(read_body(self)))
            if self.path == "/api/cleanup":
                data = read_body(self)
                return json_response(self, cleanup(int(data.get("days", 7)), int(data.get("keep_latest", 20))))
            return json_response(self, {"error": "not_found"}, 404)
        except Exception as exc:
            return json_response(self, {"error": str(exc)}, 500)

    def api_config(self) -> Dict[str, Any]:
        target = ""
        if DEFAULT_SHORTCUT.exists():
            try:
                proc = subprocess.run(
                    ["powershell", "-NoProfile", "-Command", "$s=(New-Object -ComObject WScript.Shell).CreateShortcut('"+str(DEFAULT_SHORTCUT)+"');$s.TargetPath+' '+$s.Arguments"],
                    capture_output=True, text=True, timeout=5
                )
                target = proc.stdout.strip()
            except Exception:
                target = ""
        return {
            "project_root": str(PROJECT_ROOT),
            "out_root": str(OUT_ROOT),
            "short_out_root": str(SHORT_OUT_ROOT) if SHORT_OUT_ROOT.exists() else "",
            "worker_shortcut": str(DEFAULT_SHORTCUT),
            "validation_worker": str(VALIDATION_WORKER_EXE) if VALIDATION_WORKER_EXE.exists() else "",
            "worker_target": target,
            "eas": [{"kind": k, "label": v["label"], "ea": v["ea"], "default_tf": v["default_tf"]} for k, v in EA_DEFS.items()],
        }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    ensure_dir(OUT_ROOT)
    ensure_dir(TMP_JOBS)
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"MT5 validation dashboard: http://{args.host}:{args.port}")
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
