"""
MT5 Strategy Tester validation harness.

Purpose:
  Run MT5's built-in Strategy Tester from a job file, normalize its report,
  normalize our EA-side internal brute-force backtest CSVs, and compare them.

This intentionally uses only Python stdlib so it can run on a trading machine
without installing extra packages.

Example:
  python scripts/mt5_validation_harness.py run --jobs configs/mt5_validation_jobs.example.json --dry-run
  python scripts/mt5_validation_harness.py normalize --jobs configs/mt5_validation_jobs.example.json
  python scripts/mt5_validation_harness.py compare --jobs configs/mt5_validation_jobs.example.json
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import html
import io
import json
import os
import re
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT_DIR = PROJECT_ROOT / "logs" / "mt5_validation"
MAX_TAIL_BYTES = 256 * 1024


PERIOD_ALIASES = {
    "1": "M1",
    "5": "M5",
    "15": "M15",
    "30": "M30",
    "60": "H1",
    "M1": "M1",
    "M5": "M5",
    "M15": "M15",
    "M30": "M30",
    "H1": "H1",
    "H4": "H4",
    "D1": "D1",
}


EA_KIND_ALIASES = {
    "nas": "nas",
    "nas_v3": "nas",
    "nasultimateea": "nas",
    "orb": "orb",
    "orb15": "orb",
    "realorbstrategy": "orb",
    "erl": "erl",
    "erl_irl": "erl",
    "erl_irl_swingmodel": "erl",
}


@dataclass
class ValidationJob:
    job_id: str
    ea: str
    ea_kind: str
    preset: Path
    symbol: str
    timeframe: str
    from_date: str
    to_date: str
    terminal_exe: Optional[Path] = None
    terminal_shortcut: Optional[Path] = None
    terminal_data_dir: Optional[Path] = None
    portable: bool = False
    deposit: float = 10000.0
    currency: str = "USD"
    leverage: str = "1:100"
    model: int = 4
    execution_mode: int = 0
    optimization: bool = False
    visual: bool = False
    shutdown_terminal: bool = True
    timeout_sec: int = 3600
    preset_overrides: Dict[str, str] = field(default_factory=dict)
    internal_backtest_csv: Optional[Path] = None
    internal_process_csv: Optional[Path] = None
    tester_trade_audit_csv: Optional[Path] = None
    combo_filter: Dict[str, str] = field(default_factory=dict)

    @staticmethod
    def from_dict(raw: Dict[str, Any], base_dir: Path) -> "ValidationJob":
        def p(value: Any) -> Optional[Path]:
            if value in (None, ""):
                return None
            path = Path(str(value))
            return path if path.is_absolute() else (base_dir / path).resolve()

        ea = str(raw["ea"])
        ea_kind = str(raw.get("ea_kind") or infer_ea_kind(ea))
        timeframe = normalize_period(str(raw["timeframe"]))
        return ValidationJob(
            job_id=str(raw["job_id"]),
            ea=ea,
            ea_kind=ea_kind,
            preset=p(raw["preset"]) or Path(),
            symbol=str(raw["symbol"]),
            timeframe=timeframe,
            from_date=str(raw["from_date"]),
            to_date=str(raw["to_date"]),
            terminal_exe=p(raw.get("terminal_exe")),
            terminal_shortcut=p(raw.get("terminal_shortcut")),
            terminal_data_dir=p(raw.get("terminal_data_dir")),
            portable=bool(raw.get("portable", False)),
            deposit=float(raw.get("deposit", 10000.0)),
            currency=str(raw.get("currency", "USD")),
            leverage=str(raw.get("leverage", "1:100")),
            model=int(raw.get("model", 4)),
            execution_mode=int(raw.get("execution_mode", 0)),
            optimization=bool(raw.get("optimization", False)),
            visual=bool(raw.get("visual", False)),
            shutdown_terminal=bool(raw.get("shutdown_terminal", True)),
            timeout_sec=int(raw.get("timeout_sec", 3600)),
            preset_overrides={str(k): str(v) for k, v in dict(raw.get("preset_overrides", {})).items()},
            internal_backtest_csv=p(raw.get("internal_backtest_csv")),
            internal_process_csv=p(raw.get("internal_process_csv")),
            tester_trade_audit_csv=p(raw.get("tester_trade_audit_csv")),
            combo_filter={str(k): str(v) for k, v in dict(raw.get("combo_filter", {})).items()},
        )


def infer_ea_kind(ea: str) -> str:
    key = Path(ea).stem.lower().replace("_mt5", "").replace("_ea", "")
    return EA_KIND_ALIASES.get(key, key)


def normalize_period(value: str) -> str:
    key = value.strip().upper().replace("PERIOD_", "")
    if key not in PERIOD_ALIASES:
        raise ValueError(f"Unsupported timeframe: {value}")
    return PERIOD_ALIASES[key]


def load_jobs(path: Path) -> List[ValidationJob]:
    raw = json.loads(path.read_text(encoding="utf-8-sig"))
    items = raw["jobs"] if isinstance(raw, dict) and "jobs" in raw else raw
    if not isinstance(items, list):
        raise ValueError("Job file must be a JSON list or {'jobs': [...]}.")
    return [ValidationJob.from_dict(item, path.parent.resolve()) for item in items]


def resolve_windows_shortcut(path: Path) -> Tuple[Optional[Path], str, Optional[Path]]:
    if not path.exists():
        raise FileNotFoundError(f"Shortcut not found: {path}")
    ps = (
        "$s=(New-Object -ComObject WScript.Shell).CreateShortcut("
        + repr(str(path))
        + "); Write-Output $s.TargetPath; Write-Output $s.Arguments; Write-Output $s.WorkingDirectory"
    )
    proc = subprocess.run(
        ["powershell", "-NoProfile", "-Command", ps],
        capture_output=True,
        text=True,
        timeout=10,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"Failed to resolve shortcut {path}: {proc.stderr.strip()}")
    lines = [line.strip() for line in proc.stdout.splitlines()]
    target = Path(lines[0]) if len(lines) > 0 and lines[0] else None
    args = lines[1] if len(lines) > 1 else ""
    cwd = Path(lines[2]) if len(lines) > 2 and lines[2] else None
    return target, args, cwd


def resolve_terminal(job: ValidationJob) -> Tuple[Path, List[str], Optional[Path]]:
    extra_args: List[str] = []
    cwd: Optional[Path] = None
    terminal = job.terminal_exe
    if job.terminal_shortcut:
        target, args, shortcut_cwd = resolve_windows_shortcut(job.terminal_shortcut)
        if target:
            terminal = target
        if args:
            extra_args.extend(args.split())
        cwd = shortcut_cwd
    if not terminal:
        raise ValueError(f"{job.job_id}: terminal_exe or terminal_shortcut is required for run.")
    if job.portable and "/portable" not in [a.lower() for a in extra_args]:
        extra_args.append("/portable")
    return terminal, extra_args, cwd


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def stamp() -> str:
    return datetime.now().strftime("%Y%m%d_%H%M%S")


def read_set_file(path: Path) -> Dict[str, str]:
    data: Dict[str, str] = {}
    for line in path.read_text(encoding="utf-8-sig", errors="replace").splitlines():
        if not line or line.lstrip().startswith(";") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        data[key.strip()] = value.strip()
    return data


def write_set_file(path: Path, values: Dict[str, str]) -> None:
    ensure_dir(path.parent)
    path.write_text("\n".join(f"{k}={v}" for k, v in values.items()) + "\n", encoding="utf-8")


def fs_safe_id(value: str, prefix_len: int = 44) -> str:
    raw = str(value)
    slug = re.sub(r"[^A-Za-z0-9]+", "_", raw).strip("_").lower()
    digest = hashlib.sha1(raw.encode("utf-8", errors="replace")).hexdigest()[:10]
    if len(slug) > prefix_len:
        slug = slug[:prefix_len].rstrip("_")
    return f"{slug or 'job'}__{digest}"


def materialize_preset(job: ValidationJob, run_dir: Path) -> Path:
    if not job.preset.exists():
        raise FileNotFoundError(f"Preset not found: {job.preset}")
    values = read_set_file(job.preset)
    values.update(job.preset_overrides)
    values.setdefault("InpValidationJobId", job.job_id)
    values.setdefault("InpTesterTradeAuditCsv", "true")
    values.setdefault("InpTesterTradeAuditMaxRows", "50000")
    out = run_dir / "presets" / f"{fs_safe_id(job.job_id)}.set"
    write_set_file(out, values)
    return out


def tester_preset_ref(job: ValidationJob, preset_path: Path, run_dir: Path) -> str:
    if not job.terminal_data_dir:
        return str(preset_path)
    tester_profile_dir = job.terminal_data_dir / "MQL5" / "Profiles" / "Tester"
    try:
        ensure_dir(tester_profile_dir)
        target = tester_profile_dir / f"{fs_safe_id(job.job_id)}.set"
        shutil.copy2(preset_path, target)
        (run_dir / "tester_profile_preset.txt").write_text(str(target), encoding="utf-8")
        return target.name
    except OSError:
        return str(preset_path)


def tester_ini(job: ValidationJob, run_dir: Path, preset_ref: str) -> Tuple[Path, Path]:
    ensure_dir(run_dir)
    short_id = fs_safe_id(job.job_id)
    report_path = run_dir / "reports" / f"{short_id}.xml"
    ensure_dir(report_path.parent)
    ini_path = run_dir / "tester_configs" / f"{short_id}.ini"
    ensure_dir(ini_path.parent)
    lines = [
        "[Tester]",
        f"Expert={job.ea}",
        f"ExpertParameters={preset_ref}",
        f"Symbol={job.symbol}",
        f"Period={job.timeframe}",
        f"Model={job.model}",
        f"ExecutionMode={job.execution_mode}",
        f"FromDate={job.from_date}",
        f"ToDate={job.to_date}",
        f"Deposit={job.deposit:.2f}",
        f"Currency={job.currency}",
        f"Leverage={job.leverage}",
        f"Optimization={1 if job.optimization else 0}",
        f"Visual={1 if job.visual else 0}",
        f"Report={report_path}",
        "ReplaceReport=1",
        f"ShutdownTerminal={1 if job.shutdown_terminal else 0}",
        "",
    ]
    ini_path.write_text("\n".join(lines), encoding="utf-8")
    return ini_path, report_path


def run_job(job: ValidationJob, out_root: Path, dry_run: bool = False) -> Dict[str, Any]:
    terminal, terminal_args, terminal_cwd = resolve_terminal(job)
    run_dir = out_root / fs_safe_id(job.job_id) / stamp()
    ensure_dir(run_dir)
    preset_path = materialize_preset(job, run_dir)
    preset_ref = tester_preset_ref(job, preset_path, run_dir)
    ini_path, report_path = tester_ini(job, run_dir, preset_ref)
    cmd = [str(terminal), *terminal_args, f"/config:{ini_path}"]
    meta = {
        "job_id": job.job_id,
        "ea": job.ea,
        "ea_kind": job.ea_kind,
        "symbol": job.symbol,
        "timeframe": job.timeframe,
        "from_date": job.from_date,
        "to_date": job.to_date,
        "run_dir": str(run_dir),
        "tester_ini": str(ini_path),
        "tester_report": str(report_path),
        "command": cmd,
        "dry_run": dry_run,
    }
    (run_dir / "job.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    if dry_run:
        return {**meta, "status": "dry_run"}
    t0 = time.time()
    try:
        proc = subprocess.run(cmd, cwd=str(terminal_cwd or terminal.parent), timeout=job.timeout_sec)
    except subprocess.TimeoutExpired as exc:
        elapsed = time.time() - t0
        return {
            **meta,
            "status": "timeout",
            "returncode": None,
            "elapsed_sec": round(elapsed, 3),
            "timeout_sec": job.timeout_sec,
            "timeout_cmd": list(exc.cmd) if isinstance(exc.cmd, (list, tuple)) else str(exc.cmd),
        }
    elapsed = time.time() - t0
    audit_path: Optional[Path] = None
    if proc.returncode != 0:
        status = "terminal_returned_error"
    elif not report_path.exists():
        for _ in range(10):
            audit_path = auto_find_tester_trade_audit(job)
            if audit_path:
                break
            time.sleep(0.25)
        status = "ok_no_report_trade_audit" if audit_path else "no_report_generated"
    else:
        status = "ok"
        audit_path = auto_find_tester_trade_audit(job)
    if audit_path and audit_path.exists():
        artifact_dir = run_dir / "artifacts"
        ensure_dir(artifact_dir)
        stable_audit_path = artifact_dir / audit_path.name
        try:
            shutil.copy2(audit_path, stable_audit_path)
            audit_path = stable_audit_path
        except OSError:
            # Keep the original path in the manifest if copying fails; the
            # caller can still inspect the terminal agent directory.
            pass
    copied_artifacts: List[str] = []
    artifact_dir = run_dir / "artifacts"
    for extra_path in auto_find_validation_artifacts(job):
        if audit_path and extra_path.resolve() == Path(audit_path).resolve():
            copied_artifacts.append(str(audit_path))
            continue
        ensure_dir(artifact_dir)
        target = artifact_dir / extra_path.name
        try:
            shutil.copy2(extra_path, target)
            copied_artifacts.append(str(target))
        except OSError:
            copied_artifacts.append(str(extra_path))
    if status == "no_report_generated" and any("InternalTradeEvents" in Path(p).name for p in copied_artifacts):
        status = "ok_internal_event_export"
    return {
        **meta,
        "status": status,
        "returncode": proc.returncode,
        "elapsed_sec": round(elapsed, 3),
        "tester_trade_audit": str(audit_path) if audit_path else "",
        "artifacts": copied_artifacts,
    }


def sniff_csv(path: Path) -> Tuple[List[str], List[Dict[str, str]]]:
    text = read_text_auto(path)
    sample = text[:4096]
    try:
        dialect = csv.Sniffer().sniff(sample, delimiters=",;")
    except csv.Error:
        dialect = csv.excel
    rows: List[Dict[str, str]] = []
    reader = csv.DictReader(text.splitlines(), dialect=dialect)
    for row in reader:
        rows.append({str(k): ("" if v is None else str(v)) for k, v in row.items() if k is not None})
    return list(reader.fieldnames or []), rows


def detect_text_encoding(head: bytes) -> str:
    if head.startswith(b"\xff\xfe") or head.startswith(b"\xfe\xff"):
        return "utf-16"
    if head.startswith(b"\xef\xbb\xbf"):
        return "utf-8-sig"
    if head[:128].count(b"\x00") > 16:
        return "utf-16"
    return "utf-8-sig"


def read_text_auto(path: Path) -> str:
    data = path.read_bytes()
    return data.decode(detect_text_encoding(data[:128]), errors="replace")


def sniff_csv_tail(path: Path, limit: int = 200, max_bytes: int = MAX_TAIL_BYTES) -> List[Dict[str, str]]:
    try:
        size = path.stat().st_size
        with path.open("rb") as f:
            head = f.read(128)
            encoding = detect_text_encoding(head)
            f.seek(0)
            if size <= max_bytes:
                data = f.read()
                text = data.decode(encoding, errors="replace")
                header = ""
            else:
                head_text = f.read(4096).decode(encoding, errors="replace")
                header = head_text.splitlines()[0].strip() if head_text.splitlines() else ""
                offset = size - max_bytes
                if encoding == "utf-16" and offset % 2:
                    offset -= 1
                f.seek(max(0, offset))
                f.readline()
                data = f.read()
                text = data.decode(encoding, errors="replace")
    except OSError:
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
    elif header:
        usable = [header, *lines]
    else:
        usable = lines
    sample = "\n".join(usable[:5])
    try:
        dialect = csv.Sniffer().sniff(sample, delimiters=",;")
    except csv.Error:
        dialect = csv.excel
    try:
        return list(csv.DictReader(io.StringIO("\n".join(usable), newline=""), dialect=dialect))[-limit:]
    except csv.Error:
        return []


def f(row: Dict[str, str], key: str, default: float = 0.0) -> float:
    try:
        return float(str(row.get(key, "")).replace("%", "").replace(" ", ""))
    except ValueError:
        return default


def i(row: Dict[str, str], key: str, default: int = 0) -> int:
    try:
        return int(float(str(row.get(key, "")).replace(" ", "")))
    except ValueError:
        return default


def row_matches(row: Dict[str, str], filters: Dict[str, str]) -> bool:
    for key, expected in filters.items():
        actual = str(row.get(key, ""))
        if actual.lower() != str(expected).lower():
            return False
    return True


def normalize_internal_csv(job: ValidationJob) -> List[Dict[str, Any]]:
    if not job.internal_backtest_csv:
        return []
    path = job.internal_backtest_csv
    if not path.exists():
        raise FileNotFoundError(f"Internal backtest CSV not found: {path}")
    _, rows = sniff_csv(path)
    if job.combo_filter:
        rows = [r for r in rows if row_matches(r, job.combo_filter)]
    normalized = []
    for row in rows:
        normalized.append(normalize_internal_row(job, row, path))
    return normalized


def normalize_tester_trade_audit(job: ValidationJob) -> Optional[Dict[str, Any]]:
    path = job.tester_trade_audit_csv or auto_find_tester_trade_audit(job)
    if not path:
        return None
    if not path.exists():
        raise FileNotFoundError(f"Tester trade audit CSV not found: {path}")
    _, rows = sniff_csv(path)
    in_count = 0
    out_count = 0
    volume_in = 0.0
    volume_out = 0.0
    net_profit = 0.0
    reasons: Dict[str, int] = {}
    first_time = ""
    last_time = ""
    for row in rows:
        if row.get("symbol", job.symbol) != job.symbol:
            continue
        if row.get("job_id") not in ("", job.job_id):
            continue
        entry_type = row.get("entry_type", "")
        reason = row.get("reason", "")
        reasons[reason] = reasons.get(reason, 0) + 1
        if not first_time:
            first_time = row.get("server_time", "")
        last_time = row.get("server_time", "")
        vol = f(row, "volume")
        if entry_type in ("IN", "INOUT"):
            in_count += 1
            volume_in += vol
        if entry_type in ("OUT", "INOUT", "OUT_BY"):
            out_count += 1
            volume_out += vol
            net_profit += f(row, "profit") + f(row, "swap") + f(row, "commission") + f(row, "fee")
    return base_norm(job, "mt5_strategy_tester_trade_audit", path, {}, {}, {
        "deal_rows": len(rows),
        "entry_deals": in_count,
        "exit_deals": out_count,
        "volume_in": round(volume_in, 6),
        "volume_out": round(volume_out, 6),
        "net_profit": round(net_profit, 2),
        "first_time": first_time,
        "last_time": last_time,
        "reasons": reasons,
        "bytes": path.stat().st_size,
    })


def tester_audit_prefix(job: ValidationJob) -> str:
    if job.ea_kind == "nas":
        if "NasUltimate_SATS_PartialNoBE" in job.ea:
            return "NasUltimate_TesterTradeAudit_"
        return "NasV3Lab_TesterTradeAudit_"
    if job.ea_kind == "orb":
        return "ORB15_TesterTradeAudit_"
    if job.ea_kind == "erl":
        return "ERL_IRL_TesterTradeAudit_"
    return "*TesterTradeAudit_"


def auto_find_tester_trade_audit(job: ValidationJob) -> Optional[Path]:
    roots: List[Path] = []
    if job.terminal_data_dir:
        roots.append(job.terminal_data_dir)
        roots.append(job.terminal_data_dir / "MQL5" / "Files")
        roots.append(job.terminal_data_dir / "Tester")
    roots.append(DEFAULT_OUT_DIR)
    pattern = tester_audit_prefix(job) + "*.csv"
    candidates: List[Path] = []
    seen = set()
    for root in roots:
        if not root or not root.exists():
            continue
        try:
            iterator = root.rglob(pattern) if root.is_dir() else []
            for path in iterator:
                sp = str(path).lower()
                if sp in seen or not path.is_file():
                    continue
                seen.add(sp)
                candidates.append(path)
        except OSError:
            continue
    candidates.sort(key=lambda p: p.stat().st_mtime if p.exists() else 0, reverse=True)
    fallback_match: Optional[Path] = None
    expected_tf = normalize_tester_period(job.timeframe)
    for path in candidates[:50]:
        rows = sniff_csv_tail(path, limit=200)
        if not rows:
            continue
        if any(row.get("job_id") == job.job_id for row in rows):
            return path
        for row in rows:
            if str(row.get("symbol", "") or "").lower() != job.symbol.lower():
                continue
            row_tf = normalize_tester_period(row.get("timeframe", ""))
            if row_tf and expected_tf and row_tf != expected_tf:
                continue
            if row.get("job_id") in ("", job.job_id):
                fallback_match = path
                break
        if fallback_match:
            return fallback_match
    return None


def validation_artifact_patterns(job: ValidationJob) -> List[str]:
    patterns = [tester_audit_prefix(job) + "*.csv"]
    if job.ea_kind == "nas":
        patterns.append("NasV3Lab_InternalTradeEvents_*.csv")
    return patterns


def auto_find_validation_artifacts(job: ValidationJob) -> List[Path]:
    roots: List[Path] = []
    if job.terminal_data_dir:
        roots.append(job.terminal_data_dir)
        roots.append(job.terminal_data_dir / "MQL5" / "Files")
        roots.append(job.terminal_data_dir / "Tester")
    roots.append(DEFAULT_OUT_DIR)

    out: List[Path] = []
    seen = set()
    for root in roots:
        if not root or not root.exists():
            continue
        for pattern in validation_artifact_patterns(job):
            try:
                iterator = root.rglob(pattern) if root.is_dir() else []
                for path in iterator:
                    sp = str(path).lower()
                    if sp in seen or not path.is_file():
                        continue
                    seen.add(sp)
                    rows = sniff_csv_tail(path, limit=200)
                    if not any(row.get("job_id") == job.job_id for row in rows):
                        continue
                    out.append(path)
            except OSError:
                continue
    out.sort(key=lambda p: p.stat().st_mtime if p.exists() else 0, reverse=True)
    return out[:20]


def normalize_tester_period(value: str) -> str:
    key = str(value or "").strip().upper().replace("PERIOD_", "")
    return PERIOD_ALIASES.get(key, key)


def normalize_internal_row(job: ValidationJob, row: Dict[str, str], path: Path) -> Dict[str, Any]:
    kind = job.ea_kind
    if kind == "nas":
        combo = {
            "signal_mode": row.get("signal_mode", ""),
            "sensitivity": row.get("sensitivity", ""),
            "rr_mode": row.get("rr_mode", ""),
            "hc_tp1": row.get("hc_tp1", ""),
            "hc_tp2": row.get("hc_tp2", ""),
        }
        return base_norm(job, "ea_internal", path, row, combo, {
            "total_trades": i(row, "total_signals"),
            "wins": i(row, "wins"),
            "losses": i(row, "losses"),
            "win_rate": f(row, "win_rate"),
            "net_r": f(row, "net_r"),
            "profit_factor": f(row, "pf"),
            "avg_r": f(row, "avg_r_per_trade"),
            "effective_from": row.get("effective_from", ""),
            "loaded_from": row.get("loaded_from", ""),
            "loaded_to": row.get("loaded_to", ""),
            "rates_copied": i(row, "rates_copied"),
        })
    if kind == "orb":
        combo = {
            "signal_tf": row.get("signal_tf", ""),
            "delay_min": row.get("delay_min", ""),
            "atr_filter": row.get("atr_filter", ""),
            "vol_filter": row.get("vol_filter", ""),
            "day_filter": row.get("day_filter", ""),
            "be_on_tp1": row.get("be_on_tp1", ""),
        }
        return base_norm(job, "ea_internal", path, row, combo, {
            "total_trades": i(row, "total_signals"),
            "wins": i(row, "wins"),
            "losses": i(row, "losses"),
            "win_rate": f(row, "win_rate"),
            "net_r": f(row, "net_r"),
            "profit_factor": f(row, "pf"),
            "avg_r": f(row, "avg_r_per_trade"),
            "requested_from": row.get("requested_from", ""),
            "day_count": i(row, "day_count"),
        })
    if kind == "erl":
        combo = {
            "htf": row.get("htf", ""),
            "entry_tf": row.get("entry_tf", ""),
            "swing": row.get("swing", ""),
            "target": row.get("target", ""),
            "hc_be": row.get("hc_be", ""),
            "weekly_bias": row.get("weekly_bias", ""),
        }
        return base_norm(job, "ea_internal", path, row, combo, {
            "total_trades": i(row, "total"),
            "wins": i(row, "wins"),
            "losses": i(row, "losses"),
            "open": i(row, "open"),
            "win_rate": f(row, "win_rate"),
            "net_r": f(row, "net_r"),
            "profit_factor": f(row, "pf"),
            "avg_r": f(row, "avg_r"),
        })
    return base_norm(job, "ea_internal", path, row, {}, {})


def base_norm(job: ValidationJob, engine: str, source: Path, row: Dict[str, str], combo: Dict[str, str], metrics: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "job_id": job.job_id,
        "engine": engine,
        "ea": job.ea,
        "ea_kind": job.ea_kind,
        "preset": str(job.preset),
        "symbol": row.get("symbol", job.symbol),
        "timeframe": row.get("chart_tf", row.get("timeframe", job.timeframe)),
        "from_date": job.from_date,
        "to_date": job.to_date,
        "fill_mode": row.get("fill_mode", ""),
        "same_bar_policy": row.get("same_bar_policy", ""),
        "weeks": row.get("weeks", ""),
        "combo": combo,
        "metrics": metrics,
        "source_file": str(source),
    }


def parse_mt5_report(path: Path, job: ValidationJob) -> Dict[str, Any]:
    if not path.exists():
        return base_norm(job, "mt5_strategy_tester", path, {}, {}, {"status": "report_missing"})
    text = path.read_text(encoding="utf-8-sig", errors="replace")
    metrics = parse_mt5_xml_metrics(text) if text.lstrip().startswith("<") else {}
    if not metrics:
        metrics = parse_mt5_text_metrics(text)
    return base_norm(job, "mt5_strategy_tester", path, {}, {}, metrics)


def parse_mt5_xml_metrics(text: str) -> Dict[str, Any]:
    metrics: Dict[str, Any] = {}
    try:
        root = ET.fromstring(text)
    except ET.ParseError:
        return metrics
    flat_text = " ".join((node.text or "").strip() for node in root.iter() if (node.text or "").strip())
    metrics.update(parse_mt5_text_metrics(flat_text))
    for node in root.iter():
        attrs = {k.lower(): v for k, v in node.attrib.items()}
        name = attrs.get("name") or attrs.get("title") or attrs.get("parameter")
        value = attrs.get("value")
        if name and value:
            apply_mt5_metric(metrics, name, value)
    return metrics


def parse_mt5_text_metrics(text: str) -> Dict[str, Any]:
    clean = html.unescape(re.sub(r"<[^>]+>", " ", text))
    clean = re.sub(r"\s+", " ", clean)
    metrics: Dict[str, Any] = {}
    patterns = {
        "net_profit": r"(?:Total Net Profit|Net profit)\s*[:=]?\s*(-?\d+(?:[.,]\d+)?)",
        "gross_profit": r"Gross Profit\s*[:=]?\s*(-?\d+(?:[.,]\d+)?)",
        "gross_loss": r"Gross Loss\s*[:=]?\s*(-?\d+(?:[.,]\d+)?)",
        "profit_factor": r"Profit Factor\s*[:=]?\s*(-?\d+(?:[.,]\d+)?)",
        "total_trades": r"Total Trades\s*[:=]?\s*(\d+)",
        "max_drawdown_pct": r"(?:Equity Drawdown Relative|Maximal Drawdown).*?(\d+(?:[.,]\d+)?)\s*%",
    }
    for key, pattern in patterns.items():
        m = re.search(pattern, clean, re.IGNORECASE)
        if m:
            value = m.group(1).replace(",", ".")
            metrics[key] = float(value) if "." in value else int(value)
    return metrics


def apply_mt5_metric(metrics: Dict[str, Any], name: str, value: str) -> None:
    key = name.strip().lower()
    value = value.strip().replace(",", ".")
    mapping = {
        "total net profit": "net_profit",
        "net profit": "net_profit",
        "gross profit": "gross_profit",
        "gross loss": "gross_loss",
        "profit factor": "profit_factor",
        "total trades": "total_trades",
        "trades": "total_trades",
        "equity drawdown relative": "max_drawdown_pct",
        "maximal drawdown": "max_drawdown_pct",
    }
    out_key = mapping.get(key)
    if not out_key:
        return
    try:
        metrics[out_key] = float(value.replace("%", ""))
    except ValueError:
        metrics[out_key] = value


def write_jsonl(path: Path, rows: Iterable[Dict[str, Any]]) -> None:
    ensure_dir(path.parent)
    with path.open("w", encoding="utf-8") as f_out:
        for row in rows:
            f_out.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")


def write_flat_csv(path: Path, rows: List[Dict[str, Any]]) -> None:
    ensure_dir(path.parent)
    flat_rows = [flatten(row) for row in rows]
    keys = sorted({k for row in flat_rows for k in row.keys()})
    with path.open("w", newline="", encoding="utf-8") as f_out:
        writer = csv.DictWriter(f_out, fieldnames=keys)
        writer.writeheader()
        writer.writerows(flat_rows)


def flatten(row: Dict[str, Any], prefix: str = "") -> Dict[str, Any]:
    out: Dict[str, Any] = {}
    for key, value in row.items():
        name = f"{prefix}{key}" if not prefix else f"{prefix}.{key}"
        if isinstance(value, dict):
            out.update(flatten(value, name))
        else:
            out[name] = value
    return out


def compare_rows(job: ValidationJob, internal: List[Dict[str, Any]], mt5: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    best = pick_best_internal(internal)
    result = {
        "job_id": job.job_id,
        "status": "ok",
        "internal_rows": len(internal),
        "best_internal": best,
        "mt5": mt5,
        "warnings": [],
        "diff": {},
    }
    if not internal:
        result["warnings"].append("internal_backtest_missing_or_no_matching_combo")
    if not mt5 or mt5.get("metrics", {}).get("status") == "report_missing":
        result["warnings"].append("mt5_report_missing")
    if best and mt5:
        bm = best.get("metrics", {})
        mm = mt5.get("metrics", {})
        for key in ("total_trades", "profit_factor"):
            if key in bm and key in mm:
                result["diff"][key] = safe_float(mm.get(key)) - safe_float(bm.get(key))
        if "net_r" in bm and "net_profit" in mm:
            result["warnings"].append("net_r_vs_net_profit_not_directly_comparable_without_trade_level_audit")
    if result["warnings"]:
        result["status"] = "needs_review"
    return result


def safe_float(value: Any) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def pick_best_internal(rows: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    if not rows:
        return None
    return max(rows, key=lambda r: safe_float(r.get("metrics", {}).get("net_r", 0.0)))


def command_run(args: argparse.Namespace) -> int:
    jobs = filter_jobs(load_jobs(Path(args.jobs)), args.job)
    out_root = Path(args.out_dir or DEFAULT_OUT_DIR).resolve()
    rows = []
    failed = False
    for job in jobs:
        row = run_job(job, out_root, dry_run=args.dry_run)
        rows.append(row)
        if not args.dry_run and not str(row.get("status", "")).startswith("ok"):
            failed = True
        print(f"{job.job_id}: {row['status']} -> {row.get('run_dir')}")
    write_jsonl(out_root / "run_manifest.jsonl", rows)
    return 2 if failed else 0


def command_normalize(args: argparse.Namespace) -> int:
    jobs = filter_jobs(load_jobs(Path(args.jobs)), args.job)
    out_root = Path(args.out_dir or DEFAULT_OUT_DIR).resolve()
    rows: List[Dict[str, Any]] = []
    trade_rows: List[Dict[str, Any]] = []
    for job in jobs:
        rows.extend(normalize_internal_csv(job))
        trade = normalize_tester_trade_audit(job)
        if trade:
            trade_rows.append(trade)
    write_jsonl(out_root / "normalized_internal.jsonl", rows)
    write_flat_csv(out_root / "normalized_internal.csv", rows)
    if trade_rows:
        write_jsonl(out_root / "normalized_tester_trade_audit.jsonl", trade_rows)
        write_flat_csv(out_root / "normalized_tester_trade_audit.csv", trade_rows)
    print(f"normalized internal rows: {len(rows)} -> {out_root}")
    if trade_rows:
        print(f"normalized tester trade audits: {len(trade_rows)} -> {out_root}")
    return 0


def command_compare(args: argparse.Namespace) -> int:
    jobs = filter_jobs(load_jobs(Path(args.jobs)), args.job)
    out_root = Path(args.out_dir or DEFAULT_OUT_DIR).resolve()
    comparisons = []
    normalized_all = []
    for job in jobs:
        internal = normalize_internal_csv(job)
        normalized_all.extend(internal)
        report_path = Path(args.report) if args.report and len(jobs) == 1 else None
        mt5 = parse_mt5_report(report_path, job) if report_path else None
        tester_trade = normalize_tester_trade_audit(job)
        cmp_row = compare_rows(job, internal, mt5)
        if tester_trade:
            cmp_row["tester_trade_audit"] = tester_trade
        comparisons.append(cmp_row)
    write_jsonl(out_root / "comparison.jsonl", comparisons)
    write_flat_csv(out_root / "comparison.csv", comparisons)
    if normalized_all:
        write_flat_csv(out_root / "normalized_internal.csv", normalized_all)
    for item in comparisons:
        print(f"{item['job_id']}: {item['status']} warnings={len(item['warnings'])} internal_rows={item['internal_rows']}")
    return 0


def filter_jobs(jobs: List[ValidationJob], job_id: Optional[str]) -> List[ValidationJob]:
    if not job_id:
        return jobs
    selected = [j for j in jobs if j.job_id == job_id]
    if not selected:
        raise ValueError(f"Job not found: {job_id}")
    return selected


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run and compare MT5 Strategy Tester validation jobs.")
    sub = parser.add_subparsers(dest="cmd", required=True)

    def common(p: argparse.ArgumentParser) -> None:
        p.add_argument("--jobs", required=True, help="JSON job file.")
        p.add_argument("--job", help="Optional job_id filter.")
        p.add_argument("--out-dir", help=f"Output dir. Default: {DEFAULT_OUT_DIR}")

    p_run = sub.add_parser("run", help="Create tester config and run MT5 terminal.")
    common(p_run)
    p_run.add_argument("--dry-run", action="store_true", help="Generate .ini/.set/job manifest without launching MT5.")
    p_run.set_defaults(func=command_run)

    p_norm = sub.add_parser("normalize", help="Normalize internal EA brute-force backtest CSVs.")
    common(p_norm)
    p_norm.set_defaults(func=command_normalize)

    p_cmp = sub.add_parser("compare", help="Compare internal CSV rows with an optional MT5 report.")
    common(p_cmp)
    p_cmp.add_argument("--report", help="MT5 tester report path for a single selected job.")
    p_cmp.set_defaults(func=command_compare)
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
