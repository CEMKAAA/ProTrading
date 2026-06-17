from __future__ import annotations

import csv
import json
import math
import os
import shutil
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Iterable, List, Tuple


ROOT = Path(__file__).resolve().parents[1]
MT5_FILES = Path(os.environ["APPDATA"]) / "MetaQuotes" / "Terminal" / "D0E8209F77C8CF37AD8BF550E51FF075" / "MQL5" / "Files"
OUT_ROOT = ROOT / "logs" / "winner_preset_generation"

NAS_RISK_TEMPLATE = ROOT / "IndicatorCodeExamples" / "EaPresets" / "NAS" / "V3" / "FTMO" / "RiskLotOnly" / "NasUltimateEA_V3_FTMO_RiskLotOnly_10k_1to3R.set"
NAS_FTMO_TEMPLATE = ROOT / "IndicatorCodeExamples" / "EaPresets" / "NAS" / "V3" / "FTMO" / "NasUltimateEA_V3_FTMO_10k_1to3R.set"
ORB_RISK_TEMPLATE = ROOT / "IndicatorCodeExamples" / "EaPresets" / "ORB15" / "FTMO" / "RiskLotOnly" / "RealOrbStrategy_FTMO_RiskLotOnly_10k_USTEC_GMT0.set"
ORB_FTMO_TEMPLATE = ROOT / "IndicatorCodeExamples" / "EaPresets" / "ORB15" / "FTMO" / "RealOrbStrategy_FTMO_10k_USTEC_GMT0.set"

ERL_CANDIDATE_TEMPLATE = ROOT / "IndicatorCodeExamples" / "EaPresets" / "CandidateValidation" / "ERL" / "ustecm" / "h1" / "rank01__entry_tf-h1__hc_be-hc_tp1__htf-d1__swing-3__target-tp2_1_5r__weekly_bias-on" / "ustecm_erl_h1_rank01.set"


NAS_SIGNAL_MODE = {
    "ST+SMA13": "0",
    "ST ONLY": "1",
    "ST+SMA8": "2",
    "ST+SMA5": "3",
    "ST+SMA21": "4",
}
NAS_RR_MODE = {"1:1R": "0", "1:2R": "1", "1:3R": "2"}

TF_ENUM = {
    "M1": "PERIOD_M1",
    "M5": "PERIOD_M5",
    "M15": "PERIOD_M15",
    "M30": "PERIOD_M30",
    "H1": "PERIOD_H1",
    "H4": "PERIOD_H4",
    "D1": "PERIOD_D1",
}
TF_NUM = {"M1": "1", "M5": "5", "M15": "15", "M30": "30", "H1": "60", "H4": "240", "D1": "1440"}
ERL_TARGET = {"TP1 1.0R": "0", "TP2 1.5R": "1", "TP3 2.0R": "2"}
ERL_HC = {"HC OFF": "0", "HC@TP1": "1", "HC@TP2": "2"}


def read_csv(path: Path) -> List[Dict[str, str]]:
    raw = path.read_bytes()
    enc = "utf-16" if raw.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig"
    lines = raw.decode(enc, errors="replace").splitlines()
    if not lines:
        return []
    delim = "\t" if "\t" in lines[0] else ","
    rows = []
    for row in csv.DictReader(lines, delimiter=delim):
        clean = {str(k).strip("\ufeff\x00 "): str(v).strip("\x00 ") for k, v in row.items() if k is not None}
        rows.append(clean)
    return rows


def to_float(row: Dict[str, str], key: str, default: float = 0.0) -> float:
    try:
        value = row.get(key, "")
        if value == "":
            return default
        out = float(value)
        return out if math.isfinite(out) else default
    except Exception:
        return default


def to_int(row: Dict[str, str], key: str, default: int = 0) -> int:
    try:
        return int(float(row.get(key, "")))
    except Exception:
        return default


def slug(text: Any) -> str:
    s = str(text).lower().replace("+", "plus").replace(":", "").replace("@", "at")
    s = s.replace(" ", "_").replace(".", "p").replace("/", "_").replace("\\", "_")
    keep = []
    for ch in s:
        keep.append(ch if ch.isalnum() or ch in ("_", "-") else "_")
    return "_".join(part for part in "".join(keep).split("_") if part)


def read_set(path: Path) -> Dict[str, str]:
    data: Dict[str, str] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line.strip() or "=" not in line:
            continue
        k, v = line.split("=", 1)
        data[k.strip()] = v.strip()
    return data


def write_set(path: Path, values: Dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(f"{k}={v}" for k, v in values.items()) + "\n", encoding="utf-8")


def set_common_risk(values: Dict[str, str], mode: str) -> Dict[str, str]:
    out = dict(values)
    for key in (
        "InpAuditEnabled",
        "InpAuditTradeCsv",
        "InpAuditPositionProbe",
        "InpTesterTradeAuditCsv",
        "InpAuditCsv",
        "InpLogOnInit",
    ):
        if key in out:
            out[key] = "false"
    if "InpAccountRiskEnabled" in out:
        out["InpAccountRiskEnabled"] = "true"
    if "InpAdvancedLotEnabled" in out:
        out["InpAdvancedLotEnabled"] = "true"
    if "InpUseAutoRiskLot" in out:
        out["InpUseAutoRiskLot"] = "true"
    if "InpRiskPerTradePct" in out:
        out["InpRiskPerTradePct"] = "1.0"
    if "InpInitialBalanceOverride" in out:
        out["InpInitialBalanceOverride"] = "10000.0"
    if mode == "FTMO":
        if "InpDailyLossLimitPct" in out:
            out["InpDailyLossLimitPct"] = "5.0"
        if "InpMaxDrawdownPct" in out:
            out["InpMaxDrawdownPct"] = "10.0"
    else:
        if "InpDailyLossLimitPct" in out:
            out["InpDailyLossLimitPct"] = "0.0"
        if "InpMaxDrawdownPct" in out:
            out["InpMaxDrawdownPct"] = "0.0"
    if "InpShowDashboard" in out:
        out["InpShowDashboard"] = "true"
    if "InpDrawHistoricalSignals" in out:
        out["InpDrawHistoricalSignals"] = "true"
    return out


def latest_files(prefix: str) -> List[Path]:
    files = sorted(MT5_FILES.glob(f"{prefix}_BruteBacktest_*.csv"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not files:
        return []
    latest_date = files[0].name.split("_BruteBacktest_")[-1].split("_")[0]
    return [p for p in files if f"_BruteBacktest_{latest_date}_" in p.name]


def dedupe(rows: Iterable[Dict[str, str]], keys: List[str]) -> List[Dict[str, str]]:
    seen = set()
    out = []
    for r in rows:
        sig = tuple(r.get(k, "") for k in keys)
        if sig in seen:
            continue
        seen.add(sig)
        out.append(r)
    return out


def min_trade_pool(rows: List[Dict[str, str]], count_key: str) -> List[Dict[str, str]]:
    if not rows:
        return []
    max_total = max(to_int(r, count_key) for r in rows)
    threshold = 20 if max_total >= 60 else 8 if max_total >= 20 else 5 if max_total >= 5 else 1
    pool = [r for r in rows if to_int(r, count_key) >= threshold]
    return pool or rows


def select_three(rows: List[Dict[str, str]], count_key: str, avg_key: str) -> Dict[str, Dict[str, str]]:
    pool = min_trade_pool(rows, count_key)
    positive = [r for r in pool if to_float(r, "net_r") > 0] or pool
    best_pnl = max(positive, key=lambda r: (to_float(r, "net_r"), to_float(r, "pf"), to_float(r, "win_rate"), to_int(r, count_key)))
    best_wr_pool = [r for r in pool if to_float(r, "net_r") > 0] or pool
    best_wr = max(best_wr_pool, key=lambda r: (to_float(r, "win_rate"), to_float(r, "net_r"), to_float(r, "pf"), to_int(r, count_key)))
    best_edge = max(
        positive,
        key=lambda r: (
            to_float(r, avg_key),
            to_float(r, "pf"),
            to_float(r, "edge_pct"),
            to_float(r, "net_r"),
            to_int(r, count_key),
        ),
    )
    return {"best_edge": best_edge, "best_pnl": best_pnl, "best_wr": best_wr}


def load_results() -> Dict[str, List[Dict[str, str]]]:
    all_rows: Dict[str, List[Dict[str, str]]] = {}
    for kind, prefix in [("NAS", "NasV3Lab"), ("ORB", "ORB15"), ("ERL", "ERL_IRL")]:
        rows = []
        for file in latest_files(prefix):
            for row in read_csv(file):
                row["_source_file"] = str(file)
                row["_kind"] = kind
                rows.append(row)
        all_rows[kind] = rows
    all_rows["NAS"] = dedupe(all_rows["NAS"], ["symbol", "chart_tf", "signal_mode", "sensitivity", "rr_mode", "hc_tp1", "hc_tp2", "weeks", "total_signals", "net_r"])
    all_rows["ORB"] = dedupe(all_rows["ORB"], ["symbol", "chart_tf", "signal_tf", "delay_min", "atr_filter", "vol_filter", "day_filter", "be_on_tp1", "weeks", "total_signals", "net_r"])
    all_rows["ERL"] = dedupe(all_rows["ERL"], ["symbol", "htf", "entry_tf", "swing", "target", "hc_be", "weekly_bias", "weeks", "total", "net_r"])
    return all_rows


def group_results(rows_by_kind: Dict[str, List[Dict[str, str]]]) -> Dict[Tuple[str, str, str], List[Dict[str, str]]]:
    groups: Dict[Tuple[str, str, str], List[Dict[str, str]]] = defaultdict(list)
    for row in rows_by_kind["NAS"]:
        groups[("NAS", row.get("symbol", ""), row.get("chart_tf", ""))].append(row)
    for row in rows_by_kind["ORB"]:
        groups[("ORB", row.get("symbol", ""), row.get("chart_tf", ""))].append(row)
    for row in rows_by_kind["ERL"]:
        groups[("ERL", row.get("symbol", ""), row.get("entry_tf", ""))].append(row)
    return groups


def nas_preset(row: Dict[str, str], mode: str) -> Dict[str, str]:
    base = read_set(NAS_FTMO_TEMPLATE if mode == "FTMO" else NAS_RISK_TEMPLATE)
    base = set_common_risk(base, mode)
    base["InpSignalMode"] = NAS_SIGNAL_MODE[row["signal_mode"]]
    base["InpSensitivity"] = row["sensitivity"]
    base["InpRRMode"] = NAS_RR_MODE[row["rr_mode"]]
    base["InpDefaultHcTp1"] = "true" if row["hc_tp1"] == "1" else "false"
    base["InpDefaultHcTp2"] = "true" if row["hc_tp2"] == "1" else "false"
    return base


def orb_preset(row: Dict[str, str], mode: str) -> Dict[str, str]:
    base = read_set(ORB_FTMO_TEMPLATE if mode == "FTMO" else ORB_RISK_TEMPLATE)
    base = set_common_risk(base, mode)
    base["InpSignalTimeframe"] = TF_NUM.get(row["signal_tf"], row["signal_tf"])
    base["InpBreakoutDelayMinutes"] = row["delay_min"]
    base["InpUseAtrRangeFilter"] = "true" if row["atr_filter"] == "1" else "false"
    base["InpUseVolumeFilter"] = "true" if row["vol_filter"] == "1" else "false"
    base["InpUseDayFilter"] = "true" if row["day_filter"] == "1" else "false"
    base["InpMoveToBEOnTp1"] = "true" if row["be_on_tp1"] == "1" else "false"
    return base


def erl_preset(row: Dict[str, str], mode: str) -> Dict[str, str]:
    base = read_set(ERL_CANDIDATE_TEMPLATE)
    base = set_common_risk(base, mode)
    base["InpDefaultHtf"] = TF_ENUM[row["htf"]]
    base["InpDefaultEntryTf"] = TF_ENUM[row["entry_tf"]]
    base["InpDefaultSwingLookback"] = row["swing"]
    base["InpDefaultTarget"] = ERL_TARGET[row["target"]]
    base["InpDefaultHalfBe"] = ERL_HC[row["hc_be"]]
    base["InpDefaultWeeklyBias"] = "true" if row["weekly_bias"] == "ON" else "false"
    return base


def row_metrics(row: Dict[str, str], kind: str) -> Dict[str, Any]:
    count_key = "total_signals" if kind in ("NAS", "ORB") else "total"
    avg_key = "avg_r_per_trade" if kind in ("NAS", "ORB") else "avg_r"
    return {
        "total": to_int(row, count_key),
        "wins": to_int(row, "wins"),
        "losses": to_int(row, "losses"),
        "win_rate": to_float(row, "win_rate"),
        "net_r": to_float(row, "net_r"),
        "pf": to_float(row, "pf"),
        "avg_r": to_float(row, avg_key),
        "weeks": row.get("weeks", ""),
    }


def combo_slug(kind: str, row: Dict[str, str]) -> str:
    if kind == "NAS":
        return f"{slug(row['signal_mode'])}__sens-{row['sensitivity']}__rr-{slug(row['rr_mode'])}__hc1-{row['hc_tp1']}__hc2-{row['hc_tp2']}"
    if kind == "ORB":
        return f"sig-{slug(row['signal_tf'])}__delay-{row['delay_min']}__atr-{row['atr_filter']}__vol-{row['vol_filter']}__day-{row['day_filter']}__be-{row['be_on_tp1']}"
    return f"htf-{slug(row['htf'])}__entry-{slug(row['entry_tf'])}__swing-{row['swing']}__target-{slug(row['target'])}__hc-{slug(row['hc_be'])}__weekly-{slug(row['weekly_bias'])}"


def preset_root(kind: str, mode: str) -> Path:
    if kind == "NAS":
        return ROOT / "IndicatorCodeExamples" / "EaPresets" / "NAS" / "V3" / "Winners" / mode
    if kind == "ORB":
        return ROOT / "IndicatorCodeExamples" / "EaPresets" / "ORB15" / "Winners" / mode
    return ROOT / "IndicatorCodeExamples" / "EaPresets" / "ERL_IRL" / "Winners" / mode


def generate() -> Dict[str, Any]:
    rows = load_results()
    groups = group_results(rows)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = OUT_ROOT / stamp
    out_dir.mkdir(parents=True, exist_ok=True)

    # These folders are generated artifacts. Recreate them to prevent stale
    # winner presets from previous chart/timeframe runs.
    for kind in ("NAS", "ORB", "ERL"):
        root = preset_root(kind, "FTMO").parent
        if root.exists():
            shutil.rmtree(root)

    selections: List[Dict[str, Any]] = []
    for (kind, symbol, tf), group in sorted(groups.items()):
        if not group:
            continue
        count_key = "total_signals" if kind in ("NAS", "ORB") else "total"
        avg_key = "avg_r_per_trade" if kind in ("NAS", "ORB") else "avg_r"
        selected = select_three(group, count_key, avg_key)
        for criterion, row in selected.items():
            for mode in ("FTMO", "RiskLotOnly"):
                if kind == "NAS":
                    values = nas_preset(row, mode)
                elif kind == "ORB":
                    values = orb_preset(row, mode)
                else:
                    values = erl_preset(row, mode)
                rel_dir = Path(slug(symbol)) / slug(tf) / criterion
                filename = f"{slug(symbol)}_{slug(kind)}_{slug(tf)}_{criterion}__{combo_slug(kind, row)}.set"
                path = preset_root(kind, mode) / rel_dir / filename
                write_set(path, values)
                selections.append({
                    "kind": kind,
                    "symbol": symbol,
                    "tf": tf,
                    "criterion": criterion,
                    "mode": mode,
                    "preset": str(path.relative_to(ROOT)),
                    "combo": combo_slug(kind, row),
                    "metrics": row_metrics(row, kind),
                    "source_file": row.get("_source_file", ""),
                })

    fields = ["kind", "symbol", "tf", "criterion", "mode", "preset", "combo", "total", "wins", "losses", "win_rate", "net_r", "pf", "avg_r", "weeks", "source_file"]
    with (out_dir / "winner_presets.csv").open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fields)
        writer.writeheader()
        for s in selections:
            flat = {k: s.get(k, "") for k in fields}
            flat.update(s["metrics"])
            writer.writerow(flat)
    (out_dir / "winner_presets.json").write_text(json.dumps(selections, indent=2, ensure_ascii=False), encoding="utf-8")
    return {"out_dir": str(out_dir), "selection_count": len(selections), "groups": len(groups), "rows": {k: len(v) for k, v in rows.items()}}


if __name__ == "__main__":
    print(json.dumps(generate(), indent=2, ensure_ascii=False))
