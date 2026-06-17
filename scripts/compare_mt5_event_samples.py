"""
Compare event-sampled internal trade events with MT5 native tester deal audits.

Input is the event-sample job JSON produced by build_mt5_event_sample_jobs.py.
For each job, the script finds the latest harness run artifacts, then reports:
  - sampled internal signal time/direction/entry
  - matching internal event row
  - nearest native IN deal in the same direction
  - latency in minutes and price difference
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT_DIR = PROJECT_ROOT / "logs" / "mt5_validation"
DEFAULT_REPORT = PROJECT_ROOT / "logs" / "mt5_validation" / "event_sample_comparison.csv"


def fs_safe_id(value: str, prefix_len: int = 44) -> str:
    raw = str(value)
    slug = re.sub(r"[^A-Za-z0-9]+", "_", raw).strip("_").lower()
    digest = hashlib.sha1(raw.encode("utf-8", errors="replace")).hexdigest()[:10]
    if len(slug) > prefix_len:
        slug = slug[:prefix_len].rstrip("_")
    return f"{slug or 'job'}__{digest}"


def parse_dt(value: str) -> Optional[datetime]:
    value = str(value or "").strip()
    for fmt in ("%Y.%m.%d %H:%M:%S", "%Y.%m.%d", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d"):
        try:
            return datetime.strptime(value, fmt)
        except ValueError:
            pass
    return None


def read_csv_auto(path: Path) -> List[Dict[str, str]]:
    data = path.read_bytes()
    head = data[:128]
    if head.startswith(b"\xff\xfe") or head.startswith(b"\xfe\xff") or head[:128].count(b"\x00") > 16:
        text = data.decode("utf-16", errors="replace")
    else:
        text = data.decode("utf-8-sig", errors="replace")
    return [dict(row) for row in csv.DictReader(text.splitlines())]


def latest_run_dir(job_id: str, out_root: Path) -> Optional[Path]:
    root = out_root / fs_safe_id(job_id)
    if not root.exists():
        return None
    runs = [p for p in root.iterdir() if p.is_dir()]
    runs.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return runs[0] if runs else None


def nearest_native_in(rows: List[Dict[str, str]], signal_time: datetime, direction: str) -> Optional[Dict[str, str]]:
    best = None
    best_abs = None
    wanted_type = "BUY" if direction.upper() == "BUY" else "SELL"
    for row in rows:
        if row.get("entry_type") not in ("IN", "INOUT"):
            continue
        if row.get("deal_type", "").upper() != wanted_type:
            continue
        t = parse_dt(row.get("server_time", ""))
        if not t:
            continue
        delta = (t - signal_time).total_seconds()
        if delta < -300:
            continue
        score = abs(delta)
        if best_abs is None or score < best_abs:
            best = row
            best_abs = score
    return best


def main() -> int:
    parser = argparse.ArgumentParser(description="Compare event-sampled internal rows with native MT5 tester deals.")
    parser.add_argument("--jobs", type=Path, required=True)
    parser.add_argument("--out-root", type=Path, default=DEFAULT_OUT_DIR)
    parser.add_argument("--report-out", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()

    jobs = json.loads(args.jobs.read_text(encoding="utf-8-sig")).get("jobs", [])
    report_rows: List[Dict[str, Any]] = []
    for job in jobs:
        job_id = str(job["job_id"])
        sample = job.get("event_sample") or {}
        signal_time = parse_dt(sample.get("signal_time", ""))
        run_dir = latest_run_dir(job_id, args.out_root)
        row: Dict[str, Any] = {
            "job_id": job_id,
            "symbol": job.get("symbol", ""),
            "timeframe": job.get("timeframe", ""),
            "sample_signal_time": sample.get("signal_time", ""),
            "sample_direction": sample.get("direction", ""),
            "sample_entry": sample.get("signal_entry", ""),
            "sample_net_r": sample.get("net_r", ""),
            "run_dir": str(run_dir or ""),
            "status": "missing_run",
        }
        if not run_dir or not signal_time:
            report_rows.append(row)
            continue
        artifacts = run_dir / "artifacts"
        internal_files = sorted(artifacts.glob("*InternalTradeEvents*.csv"))
        audit_files = sorted(artifacts.glob("*TesterTradeAudit*.csv"))
        row["internal_files"] = len(internal_files)
        row["tester_audit_files"] = len(audit_files)
        if not internal_files or not audit_files:
            row["status"] = "missing_artifact"
            report_rows.append(row)
            continue

        internal_rows: List[Dict[str, str]] = []
        for path in internal_files:
            internal_rows.extend(read_csv_auto(path))
        target_internal = None
        for item in internal_rows:
            if item.get("signal_time") == sample.get("signal_time") and item.get("direction") == sample.get("direction"):
                target_internal = item
                break
        row["internal_match"] = "1" if target_internal else "0"
        if target_internal:
            row["internal_outcome"] = target_internal.get("outcome", "")
            row["internal_net_r"] = target_internal.get("net_r", "")

        native_rows: List[Dict[str, str]] = []
        for path in audit_files:
            native_rows.extend(read_csv_auto(path))
        native_rows = [r for r in native_rows if r.get("job_id") == job_id]
        match = nearest_native_in(native_rows, signal_time, sample.get("direction", ""))
        if not match:
            row["status"] = "missing_native_entry"
            report_rows.append(row)
            continue
        native_time = parse_dt(match.get("server_time", "")) or signal_time
        latency_min = (native_time - signal_time).total_seconds() / 60.0
        try:
            price_diff = float(match.get("price", "0") or 0) - float(sample.get("signal_entry", "0") or 0)
        except ValueError:
            price_diff = 0.0
        row.update({
            "status": "ok",
            "native_entry_time": match.get("server_time", ""),
            "native_entry_price": match.get("price", ""),
            "native_entry_type": match.get("deal_type", ""),
            "latency_min": round(latency_min, 3),
            "entry_price_diff": round(price_diff, 5),
        })
        report_rows.append(row)

    args.report_out.parent.mkdir(parents=True, exist_ok=True)
    fields = sorted({k for row in report_rows for k in row.keys()})
    with args.report_out.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fields)
        writer.writeheader()
        writer.writerows(report_rows)
    for row in report_rows:
        print(f"{row.get('job_id')}: {row.get('status')} latency_min={row.get('latency_min', '')} diff={row.get('entry_price_diff', '')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
