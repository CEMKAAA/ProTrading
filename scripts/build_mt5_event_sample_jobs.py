"""
Build MT5 native validation jobs from EA internal trade-event CSV files.

This is the second phase of validation:
  1. Run candidate jobs in internal-export-only mode.
  2. Feed the produced *InternalTradeEvents*.csv files into this script.
  3. Run the generated native jobs around actual signal/trade timestamps.

The sample universe is therefore real trade-producing events, not arbitrary
calendar windows.
"""

from __future__ import annotations

import argparse
import csv
import json
from copy import deepcopy
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Dict, Iterable, List


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE_JOBS = PROJECT_ROOT / "configs" / "mt5_candidate_validation_nas_export_only_jobs.json"
DEFAULT_OUT = PROJECT_ROOT / "configs" / "mt5_candidate_validation_event_sample_jobs.json"
DEFAULT_REPORT = PROJECT_ROOT / "logs" / "mt5_validation" / "event_sample_manifest.json"


def parse_dt(value: str) -> datetime:
    value = str(value).strip()
    for fmt in ("%Y.%m.%d %H:%M:%S", "%Y.%m.%d", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d"):
        try:
            return datetime.strptime(value, fmt)
        except ValueError:
            pass
    raise ValueError(f"Unsupported datetime: {value!r}")


def read_csv(path: Path) -> List[Dict[str, str]]:
    data = path.read_bytes()
    head = data[:128]
    if head.startswith(b"\xff\xfe") or head.startswith(b"\xfe\xff") or head[:128].count(b"\x00") > 16:
        text = data.decode("utf-16", errors="replace")
    else:
        text = data.decode("utf-8-sig", errors="replace")
    return [dict(row) for row in csv.DictReader(text.splitlines())]


def read_jobs(path: Path) -> Dict[str, Dict[str, Any]]:
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    return {str(job["job_id"]): job for job in data.get("jobs", [])}


def unique_rows(rows: Iterable[Dict[str, str]]) -> List[Dict[str, str]]:
    out: List[Dict[str, str]] = []
    seen = set()
    for row in rows:
        key = (
            row.get("job_id", ""),
            row.get("symbol", ""),
            row.get("chart_tf", ""),
            row.get("signal_time", ""),
            row.get("direction", ""),
            row.get("signal_entry", ""),
        )
        if key in seen:
            continue
        seen.add(key)
        out.append(row)
    return out


def sample_events(rows: List[Dict[str, str]], max_samples: int) -> List[Dict[str, str]]:
    if len(rows) <= max_samples:
        return rows
    by_time = sorted(rows, key=lambda r: parse_dt(r["signal_time"]))
    by_r = sorted(rows, key=lambda r: float(r.get("net_r") or 0.0))

    picked: List[Dict[str, str]] = []
    def add(row: Dict[str, str]) -> None:
        if row not in picked:
            picked.append(row)

    add(by_r[0])       # worst
    add(by_r[-1])      # best
    add(by_time[0])    # earliest
    add(by_time[-1])   # latest

    remaining = max_samples - len(picked)
    if remaining > 0:
        span = len(by_time) - 1
        for i in range(remaining):
            idx = round((i + 1) * span / (remaining + 1))
            add(by_time[idx])
    return picked[:max_samples]


def native_job_from_event(source_job: Dict[str, Any], event: Dict[str, str], index: int, before_days: int, after_days: int) -> Dict[str, Any]:
    signal_time = parse_dt(event["signal_time"])
    from_date = (signal_time - timedelta(days=before_days)).strftime("%Y.%m.%d")
    to_date = (signal_time + timedelta(days=after_days)).strftime("%Y.%m.%d")
    base_id = str(source_job["job_id"]).replace("__export", "__native")
    event_id = signal_time.strftime("%Y%m%d_%H%M%S")
    job = deepcopy(source_job)
    job["job_id"] = f"{base_id}__ev{index:02d}__{event_id}"
    job["from_date"] = from_date
    job["to_date"] = to_date
    job["timeout_sec"] = max(300, int(job.get("timeout_sec", 600)))
    overrides = dict(job.get("preset_overrides") or {})
    overrides["InpValidationJobId"] = job["job_id"]
    overrides["InpValidationInternalTradeExport"] = "true"
    overrides["InpValidationInternalExportOnly"] = "false"
    overrides["InpValidationExportFrom"] = f"{from_date} 00:00:00"
    overrides["InpValidationExportTo"] = f"{to_date} 23:59:59"
    overrides["InpTesterTradeAuditCsv"] = "true"
    overrides["InpTesterTradeAuditMaxRows"] = "50000"
    job["preset_overrides"] = overrides
    job["event_sample"] = {
        "source_export_job_id": source_job["job_id"],
        "signal_time": event.get("signal_time", ""),
        "direction": event.get("direction", ""),
        "signal_entry": event.get("signal_entry", ""),
        "signal_sl": event.get("signal_sl", ""),
        "net_r": event.get("net_r", ""),
        "outcome": event.get("outcome", ""),
    }
    return job


def main() -> int:
    parser = argparse.ArgumentParser(description="Build native MT5 validation jobs from internal trade-event CSVs.")
    parser.add_argument("--source-jobs", type=Path, default=DEFAULT_SOURCE_JOBS)
    parser.add_argument("--events", nargs="+", required=True, help="InternalTradeEvents CSV file(s) or glob pattern(s).")
    parser.add_argument("--jobs-out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--report-out", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--samples-per-export-job", type=int, default=5)
    parser.add_argument("--before-days", type=int, default=1)
    parser.add_argument("--after-days", type=int, default=1)
    args = parser.parse_args()

    source_jobs = read_jobs(args.source_jobs)
    event_paths: List[Path] = []
    for item in args.events:
        matches = sorted(PROJECT_ROOT.glob(item)) if any(ch in item for ch in "*?[]") else [Path(item)]
        event_paths.extend((p if p.is_absolute() else PROJECT_ROOT / p) for p in matches)

    grouped: Dict[str, List[Dict[str, str]]] = {}
    for path in event_paths:
        if not path.exists():
            continue
        for row in read_csv(path):
            job_id = row.get("job_id", "")
            if job_id:
                grouped.setdefault(job_id, []).append(row)

    jobs: List[Dict[str, Any]] = []
    report_groups: List[Dict[str, Any]] = []
    for export_job_id, rows in sorted(grouped.items()):
        source_job = source_jobs.get(export_job_id)
        if not source_job:
            continue
        clean_rows = unique_rows(rows)
        samples = sample_events(clean_rows, args.samples_per_export_job)
        for idx, event in enumerate(samples, start=1):
            jobs.append(native_job_from_event(source_job, event, idx, args.before_days, args.after_days))
        report_groups.append({
            "export_job_id": export_job_id,
            "event_count": len(clean_rows),
            "sample_count": len(samples),
            "samples": [
                {
                    "signal_time": row.get("signal_time", ""),
                    "direction": row.get("direction", ""),
                    "net_r": row.get("net_r", ""),
                    "outcome": row.get("outcome", ""),
                }
                for row in samples
            ],
        })

    args.jobs_out.parent.mkdir(parents=True, exist_ok=True)
    args.jobs_out.write_text(json.dumps({"jobs": jobs}, indent=2), encoding="utf-8")
    args.report_out.parent.mkdir(parents=True, exist_ok=True)
    args.report_out.write_text(json.dumps({
        "source_jobs": str(args.source_jobs),
        "event_files": [str(p) for p in event_paths],
        "job_count": len(jobs),
        "groups": report_groups,
    }, indent=2), encoding="utf-8")
    print(json.dumps({"job_count": len(jobs), "jobs_out": str(args.jobs_out), "report_out": str(args.report_out)}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
