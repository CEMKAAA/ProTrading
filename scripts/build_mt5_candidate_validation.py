"""
Build isolated MT5 native-validation candidate presets/jobs from EA internal
20-week brute-force backtest summaries.

This script does not run MT5. It turns normalized internal result JSON into:
  - CandidateValidation .set files, separated from production presets.
  - A validation job JSON usable by scripts/mt5_validation_harness.py.
  - A compact manifest explaining what was generated.

The generated native jobs are short-window samples. They are intended to be
quality-control probes for selected top combinations, not a full 20-week brute
force replacement.
"""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Dict, Iterable, List, Tuple


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ANALYSIS = PROJECT_ROOT / "logs" / "mt5_validation" / "best_combo_analysis_20260616.json"
DEFAULT_PRESET_ROOT = PROJECT_ROOT / "IndicatorCodeExamples" / "EaPresets" / "CandidateValidation"
DEFAULT_JOBS = PROJECT_ROOT / "configs" / "mt5_candidate_validation_jobs.json"
DEFAULT_REPORT = PROJECT_ROOT / "logs" / "mt5_validation" / "candidate_validation_manifest.json"
DEFAULT_TERMINAL_EXE = "../.tmp/mt5_validation_exness_worker/terminal64.exe"
DEFAULT_TERMINAL_DATA_DIR = "../.tmp/mt5_validation_exness_worker"


NAS_BASE_PRESET = PROJECT_ROOT / "IndicatorCodeExamples" / "EaPresets" / "NAS" / "V3" / "FTMO" / "RiskLotOnly" / "NasUltimateEA_V3_FTMO_RiskLotOnly_10k_1to3R.set"
ORB_BASE_PRESET = PROJECT_ROOT / "IndicatorCodeExamples" / "EaPresets" / "ORB15" / "FTMO" / "RiskLotOnly" / "RealOrbStrategy_FTMO_RiskLotOnly_10k_USTEC_GMT0.set"


NAS_SIGNAL_MODE = {
    "ST+SMA13": "0",
    "ST ONLY": "1",
    "ST+SMA8": "2",
    "ST+SMA5": "3",
    "ST+SMA21": "4",
}

NAS_RR_MODE = {
    "1:1R": "0",
    "1:2R": "1",
    "1:3R": "2",
}

TF_VALUE = {
    "PERIOD_M1": "PERIOD_M1",
    "PERIOD_M5": "PERIOD_M5",
    "PERIOD_M15": "PERIOD_M15",
    "PERIOD_M30": "PERIOD_M30",
    "PERIOD_H1": "PERIOD_H1",
    "M1": "PERIOD_M1",
    "M5": "PERIOD_M5",
    "M15": "PERIOD_M15",
    "M30": "PERIOD_M30",
    "H1": "PERIOD_H1",
    "H4": "PERIOD_H4",
    "D1": "PERIOD_D1",
}

JOB_TF = {
    "PERIOD_M1": "M1",
    "PERIOD_M5": "M5",
    "PERIOD_M15": "M15",
    "PERIOD_M30": "M30",
    "PERIOD_H1": "H1",
    "M1": "M1",
    "M5": "M5",
    "M15": "M15",
    "M30": "M30",
    "H1": "H1",
}

ERL_TARGET = {
    "TP1 1.0R": "0",
    "TP2 1.5R": "1",
    "TP3 2.0R": "2",
}

ERL_HC = {
    "HC OFF": "0",
    "HC@TP1": "1",
    "HC@TP2": "2",
}


@dataclass(frozen=True)
class Candidate:
    rank: int
    key_kind: str
    symbol: str
    chart_tf: str
    result: Dict[str, Any]


def read_set_file(path: Path) -> Dict[str, str]:
    values: Dict[str, str] = {}
    if not path.exists():
        return values
    for line in path.read_text(encoding="utf-8-sig", errors="replace").splitlines():
        if not line.strip() or line.lstrip().startswith(";") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def write_set_file(path: Path, values: Dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(f"{k}={v}" for k, v in values.items()) + "\n", encoding="utf-8")


def slug(value: Any, max_len: int = 96) -> str:
    text = str(value)
    text = text.replace("PERIOD_", "")
    text = re.sub(r"[^A-Za-z0-9]+", "_", text).strip("_")
    return (text[:max_len] or "x").lower()


def combo_signature(result: Dict[str, Any]) -> Tuple[Tuple[str, str], ...]:
    combo = result.get("combo") or {}
    return tuple(sorted((str(k), str(v)) for k, v in combo.items()))


def dedupe_top(results: Iterable[Dict[str, Any]], limit: int) -> List[Dict[str, Any]]:
    seen = set()
    out: List[Dict[str, Any]] = []
    for result in results:
        sig = combo_signature(result)
        if sig in seen:
            continue
        seen.add(sig)
        out.append(result)
        if len(out) >= limit:
            break
    return out


def load_candidates(path: Path, max_per_key: int) -> List[Candidate]:
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    candidates: List[Candidate] = []
    for block in data.get("summary", []):
        key = block.get("key") or []
        if len(key) != 3:
            continue
        kind, symbol, chart_tf = [str(x) for x in key]
        for rank, result in enumerate(dedupe_top(block.get("top5", []), max_per_key), start=1):
            candidates.append(Candidate(rank, kind, symbol, chart_tf, result))
    return candidates


def base_preset(kind: str) -> Dict[str, str]:
    if kind == "nas":
        return read_set_file(NAS_BASE_PRESET)
    if kind == "orb":
        return read_set_file(ORB_BASE_PRESET)
    if kind == "erl":
        return {
            "InpEaEnabled": "true",
            "InpMagic": "31061501",
            "InpDeviationPoints": "30",
            "InpCloseOnReverse": "true",
            "InpBlockSameDirection": "true",
            "InpDefaultHtf": "PERIOD_H4",
            "InpDefaultEntryTf": "PERIOD_M15",
            "InpDefaultSwingLookback": "5",
            "InpDefaultTarget": "1",
            "InpDefaultHalfBe": "1",
            "InpDefaultWeeklyBias": "false",
            "InpCalcHtfBars": "900",
            "InpCalcEntryBars": "5000",
            "InpMaxSwings": "20",
            "InpMaxFvgSearchBars": "20",
            "InpAtrPeriod": "14",
            "InpMinFvgAtrPct": "8.0",
            "InpSlBufferAtrPct": "10.0",
            "InpHistoricalDays": "14",
            "InpDrawHistoricalSignals": "true",
            "InpDrawFvgZones": "true",
            "InpDrawLiveLevels": "true",
            "InpShowDashboard": "true",
            "InpDashboardX": "10",
            "InpDashboardY": "18",
            "InpAccountRiskEnabled": "true",
            "InpRiskPerTradePct": "1.0",
            "InpMaxPortfolioRiskPct": "4.0",
            "InpDailyLossLimitPct": "0.0",
            "InpMaxDrawdownPct": "0.0",
            "InpInitialBalanceOverride": "10000.0",
            "InpFixedLot": "0.10",
            "InpMaxLot": "0.0",
            "InpDayResetHourGmt": "0",
            "InpLiquidateOnBreach": "true",
            "InpAuditTradeCsv": "true",
            "InpAuditPositionProbe": "true",
            "InpAuditProbeSec": "30",
            "InpAuditProbeOnChangeOnly": "true",
            "InpAuditHistoryScanSec": "3",
            "InpTesterTradeAuditCsv": "true",
            "InpTesterTradeAuditMaxRows": "50000",
            "InpValidationJobId": "",
            "InpBacktestWeeks": "20",
            "InpBacktestFillMode": "0",
            "InpBacktestSameBarPolicy": "1",
            "InpBacktestSpreadPts": "0.0",
            "InpBacktestSlippagePts": "0.0",
            "InpBacktestCommissionPerLot": "0.0",
        }
    raise ValueError(f"Unsupported kind: {kind}")


def apply_combo(kind: str, values: Dict[str, str], result: Dict[str, Any]) -> None:
    combo = result.get("combo") or {}
    if kind == "nas":
        values["InpSignalMode"] = NAS_SIGNAL_MODE[str(combo["signal_mode"])]
        values["InpSensitivity"] = str(combo["sensitivity"])
        values["InpRRMode"] = NAS_RR_MODE[str(combo["rr_mode"])]
        values["InpDefaultHcTp1"] = "true" if str(combo.get("hc_tp1", "0")) == "1" else "false"
        values["InpDefaultHcTp2"] = "true" if str(combo.get("hc_tp2", "0")) == "1" else "false"
    elif kind == "orb":
        values["InpSignalTimeframe"] = TF_VALUE[str(combo["signal_tf"])]
        values["InpBreakoutDelayMinutes"] = str(combo["delay_min"])
        values["InpUseAtrRangeFilter"] = "true" if str(combo["atr_filter"]) == "1" else "false"
        values["InpUseVolumeFilter"] = "true" if str(combo["vol_filter"]) == "1" else "false"
        values["InpUseDayFilter"] = "true" if str(combo["day_filter"]) == "1" else "false"
        values["InpMoveToBEOnTp1"] = "true" if str(combo["be_on_tp1"]) == "1" else "false"
    elif kind == "erl":
        values["InpDefaultHtf"] = TF_VALUE[str(combo["htf"])]
        values["InpDefaultEntryTf"] = TF_VALUE[str(combo["entry_tf"])]
        values["InpDefaultSwingLookback"] = str(combo["swing"])
        values["InpDefaultTarget"] = ERL_TARGET[str(combo["target"])]
        values["InpDefaultHalfBe"] = ERL_HC[str(combo["hc_be"])]
        values["InpDefaultWeeklyBias"] = "true" if str(combo["weekly_bias"]).upper() == "ON" else "false"
    else:
        raise ValueError(f"Unsupported kind: {kind}")

    values["InpTesterTradeAuditCsv"] = "true"
    values["InpTesterTradeAuditMaxRows"] = "50000"
    values["InpBacktestFillMode"] = "0"
    values["InpBacktestSameBarPolicy"] = "1"
    values["InpBacktestSpreadPts"] = "0.0"
    values["InpBacktestSlippagePts"] = "0.0"
    values["InpBacktestCommissionPerLot"] = "0.0"
    values["InpShowDashboard"] = "false"
    values["InpDrawHistoricalSignals"] = "false"


def combo_slug(result: Dict[str, Any]) -> str:
    combo = result.get("combo") or {}
    parts = [f"{slug(k, 24)}-{slug(v, 30)}" for k, v in sorted(combo.items())]
    return "__".join(parts)


def preset_path(root: Path, c: Candidate) -> Path:
    combo = combo_slug(c.result)
    folder = root / c.key_kind.upper() / slug(c.symbol) / slug(c.chart_tf) / f"rank{c.rank:02d}__{combo}"
    return folder / f"{slug(c.symbol)}_{slug(c.key_kind)}_{slug(c.chart_tf)}_rank{c.rank:02d}.set"


def ea_name(kind: str) -> str:
    if kind == "nas":
        return "NasUltimateEA"
    if kind == "orb":
        return "RealOrbStrategy"
    if kind == "erl":
        return "ERL_IRL_SwingModel_EA"
    raise ValueError(kind)


def candidate_job_tf(c: Candidate) -> str:
    if c.key_kind == "erl":
        entry_tf = (c.result.get("combo") or {}).get("entry_tf", c.chart_tf)
        return JOB_TF[str(entry_tf)]
    return JOB_TF[str(c.chart_tf)]


def sample_windows(result: Dict[str, Any], samples: int, days: int) -> List[Tuple[str, str, str]]:
    start_raw = result.get("from") or result.get("effective_from") or "2026.01.27 00:00:00"
    end_raw = result.get("loaded_to") or "2026.06.16 23:59:59"
    start = parse_dt(start_raw)
    end = parse_dt(end_raw)
    if end <= start:
        end = start + timedelta(days=140)
    span_days = max(1, (end.date() - start.date()).days)
    if samples <= 1:
        offsets = [span_days // 2]
    else:
        offsets = [round(i * (span_days - 1) / (samples - 1)) for i in range(samples)]
    windows: List[Tuple[str, str, str]] = []
    for idx, offset in enumerate(offsets, start=1):
        a = start + timedelta(days=int(offset))
        b = min(a + timedelta(days=days), end)
        if b <= a:
            b = a + timedelta(days=1)
        windows.append((f"s{idx:02d}", a.strftime("%Y.%m.%d"), b.strftime("%Y.%m.%d")))
    return windows


def parse_dt(value: str) -> datetime:
    value = str(value).strip()
    for fmt in ("%Y.%m.%d %H:%M:%S", "%Y.%m.%d", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d"):
        try:
            return datetime.strptime(value, fmt)
        except ValueError:
            pass
    return datetime(2026, 1, 27)


def build_job(c: Candidate, preset: Path, sample_id: str, from_date: str, to_date: str, timeout_sec: int, nas_internal_export_only: bool = False) -> Dict[str, Any]:
    combo = c.result.get("combo") or {}
    job_id = "__".join([
        "cand",
        slug(c.key_kind),
        slug(c.symbol),
        slug(candidate_job_tf(c)),
        f"r{c.rank:02d}",
        sample_id,
        slug(from_date),
        slug(to_date),
        "export" if (c.key_kind == "nas" and nas_internal_export_only) else "native",
    ])
    preset_ref = Path("..") / preset.relative_to(PROJECT_ROOT)
    preset_overrides = {
        "InpValidationJobId": job_id,
        "InpTesterTradeAuditCsv": "true",
        "InpTesterTradeAuditMaxRows": "50000",
    }
    if c.key_kind == "nas":
        preset_overrides.update({
            "InpValidationInternalTradeExport": "true",
            "InpValidationInternalExportOnly": "true" if nas_internal_export_only else "false",
            "InpValidationExportFrom": f"{from_date} 00:00:00",
            "InpValidationExportTo": f"{to_date} 23:59:59",
        })

    return {
        "job_id": job_id,
        "ea": ea_name(c.key_kind),
        "ea_kind": c.key_kind,
        "preset": str(preset_ref).replace("\\", "/"),
        "symbol": c.symbol,
        "timeframe": candidate_job_tf(c),
        "from_date": from_date,
        "to_date": to_date,
        "terminal_exe": DEFAULT_TERMINAL_EXE,
        "terminal_data_dir": DEFAULT_TERMINAL_DATA_DIR,
        "portable": True,
        "deposit": 10000,
        "currency": "USD",
        "leverage": "1:100",
        "model": 4,
        "execution_mode": 0,
        "timeout_sec": timeout_sec,
        "preset_overrides": preset_overrides,
        "internal_backtest_csv": str(c.result.get("file", "")),
        "combo_filter": {str(k): str(v) for k, v in combo.items()},
        "candidate_source": {
            "rank": c.rank,
            "summary_key": [c.key_kind, c.symbol, c.chart_tf],
            "score": c.result.get("score"),
            "total": c.result.get("total"),
            "net_r": c.result.get("net_r"),
            "pf": c.result.get("pf"),
            "win_rate": c.result.get("win_rate"),
            "internal_file": c.result.get("file"),
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Build MT5 native validation candidates from internal 20w results.")
    parser.add_argument("--analysis", type=Path, default=DEFAULT_ANALYSIS)
    parser.add_argument("--preset-root", type=Path, default=DEFAULT_PRESET_ROOT)
    parser.add_argument("--jobs-out", type=Path, default=DEFAULT_JOBS)
    parser.add_argument("--report-out", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--max-candidates-per-key", type=int, default=5)
    parser.add_argument("--samples-per-candidate", type=int, default=3)
    parser.add_argument("--sample-days", type=int, default=2)
    parser.add_argument("--timeout-sec", type=int, default=600)
    parser.add_argument("--nas-internal-export-only", action="store_true")
    args = parser.parse_args()

    candidates = load_candidates(args.analysis, args.max_candidates_per_key)
    jobs: List[Dict[str, Any]] = []
    manifest_candidates: List[Dict[str, Any]] = []
    for c in candidates:
        values = base_preset(c.key_kind)
        apply_combo(c.key_kind, values, c.result)
        path = preset_path(args.preset_root, c)
        write_set_file(path, values)
        windows = sample_windows(c.result, args.samples_per_candidate, args.sample_days)
        for sample_id, from_date, to_date in windows:
            jobs.append(build_job(c, path, sample_id, from_date, to_date, args.timeout_sec, args.nas_internal_export_only))
        manifest_candidates.append({
            "rank": c.rank,
            "kind": c.key_kind,
            "symbol": c.symbol,
            "chart_tf": c.chart_tf,
            "preset": str(path.relative_to(PROJECT_ROOT)).replace("\\", "/"),
            "combo": c.result.get("combo"),
            "metrics": {
                "total": c.result.get("total"),
                "wins": c.result.get("wins"),
                "losses": c.result.get("losses"),
                "win_rate": c.result.get("win_rate"),
                "net_r": c.result.get("net_r"),
                "pf": c.result.get("pf"),
                "score": c.result.get("score"),
            },
            "sample_windows": windows,
        })

    args.jobs_out.parent.mkdir(parents=True, exist_ok=True)
    args.jobs_out.write_text(json.dumps({"jobs": jobs}, indent=2), encoding="utf-8")
    args.report_out.parent.mkdir(parents=True, exist_ok=True)
    report = {
        "generated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "analysis": str(args.analysis),
        "candidate_count": len(candidates),
        "job_count": len(jobs),
        "preset_root": str(args.preset_root),
        "jobs_out": str(args.jobs_out),
        "candidates": manifest_candidates,
    }
    args.report_out.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({
        "candidate_count": len(candidates),
        "job_count": len(jobs),
        "jobs_out": str(args.jobs_out),
        "report_out": str(args.report_out),
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
