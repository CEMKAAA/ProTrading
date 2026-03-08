"""
Merge Max7 constituent features (NVDA/TSLA) into an existing NAS100/US500 M30 CSV.

Use this to enrich Databento M30 files (orderflow columns) with:
  - nvda_close, tsla_close
  - nvda_ret, tsla_ret (6-bar M30 returns)
  - nvda_gap_down, tsla_gap_down (daily open vs previous close)
  - nvda_gap_pct, tsla_gap_pct
  - nvda_open, tsla_open
  - nvda_prev_close, tsla_prev_close
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Dict

import numpy as np
import pandas as pd


ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT / "dashboard" / "data" / "historical"
NY_TZ = "America/New_York"


def _read_base_m30(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path)
    if "ts_event" not in df.columns:
        raise ValueError(f"Missing ts_event in {path.name}")
    idx = pd.to_datetime(df["ts_event"], errors="coerce", utc=True)
    out = df.copy()
    out.index = idx
    out = out.drop(columns=["ts_event"])
    out = out[~out.index.isna()]
    out = out[~out.index.duplicated(keep="first")].sort_index()
    return out


def _read_equity_m15(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path)
    if "ts_event" not in df.columns:
        raise ValueError(f"Missing ts_event in {path.name}")
    idx = pd.to_datetime(df["ts_event"], errors="coerce", utc=True)
    out = pd.DataFrame(
        {
            "open": pd.to_numeric(df.get("open"), errors="coerce").to_numpy(),
            "close": pd.to_numeric(df.get("close"), errors="coerce").to_numpy(),
        },
        index=idx,
    ).dropna(subset=["close"])
    out = out[~out.index.isna()]
    out = out[~out.index.duplicated(keep="first")].sort_index()
    return out


def _daily_gap_table(eq: pd.DataFrame, threshold_pct: float) -> pd.DataFrame:
    if eq.empty:
        return pd.DataFrame(
            columns=["open", "close", "prev_close", "gap_pct", "gap_down"]
        )
    local = eq.tz_convert(NY_TZ)
    rth = local.between_time("09:30", "16:00")
    if rth.empty:
        rth = local

    rows = []
    for day, grp in rth.groupby(rth.index.date):
        g = grp.dropna(subset=["close"])
        if g.empty:
            continue
        op = pd.to_numeric(g["open"], errors="coerce").dropna()
        cl = pd.to_numeric(g["close"], errors="coerce").dropna()
        if cl.empty:
            continue
        open_px = float(op.iloc[0]) if not op.empty else float(cl.iloc[0])
        close_px = float(cl.iloc[-1])
        rows.append((day, open_px, close_px))

    if not rows:
        return pd.DataFrame(
            columns=["open", "close", "prev_close", "gap_pct", "gap_down"]
        )

    daily = pd.DataFrame(rows, columns=["date", "open", "close"]).set_index("date")
    daily["prev_close"] = daily["close"].shift(1)
    daily["gap_pct"] = (daily["open"] - daily["prev_close"]) / daily["prev_close"]
    threshold = max(float(threshold_pct), 0.0) / 100.0
    daily["gap_down"] = daily["gap_pct"] <= -threshold
    return daily


def _align_constituents(
    idx_m30: pd.DatetimeIndex,
    nvda: pd.DataFrame,
    tsla: pd.DataFrame,
    gap_threshold_pct: float,
) -> pd.DataFrame:
    nvda_m30 = nvda.resample("30min").last().rename(columns={"close": "nvda_close"})
    tsla_m30 = tsla.resample("30min").last().rename(columns={"close": "tsla_close"})

    out = pd.DataFrame(index=idx_m30)
    out = out.join(nvda_m30[["nvda_close"]], how="left").join(
        tsla_m30[["tsla_close"]], how="left"
    )
    out[["nvda_close", "tsla_close"]] = out[["nvda_close", "tsla_close"]].ffill(limit=2)

    out["nvda_ret"] = out["nvda_close"].pct_change(periods=6, fill_method=None)
    out["tsla_ret"] = out["tsla_close"].pct_change(periods=6, fill_method=None)

    nvda_gap = _daily_gap_table(nvda, gap_threshold_pct)
    tsla_gap = _daily_gap_table(tsla, gap_threshold_pct)

    local_dates = out.index.tz_convert(NY_TZ).date
    nvda_open: Dict = nvda_gap["open"].to_dict() if not nvda_gap.empty else {}
    nvda_prev: Dict = nvda_gap["prev_close"].to_dict() if not nvda_gap.empty else {}
    nvda_pct: Dict = nvda_gap["gap_pct"].to_dict() if not nvda_gap.empty else {}
    nvda_dn: Dict = nvda_gap["gap_down"].to_dict() if not nvda_gap.empty else {}
    tsla_open: Dict = tsla_gap["open"].to_dict() if not tsla_gap.empty else {}
    tsla_prev: Dict = tsla_gap["prev_close"].to_dict() if not tsla_gap.empty else {}
    tsla_pct: Dict = tsla_gap["gap_pct"].to_dict() if not tsla_gap.empty else {}
    tsla_dn: Dict = tsla_gap["gap_down"].to_dict() if not tsla_gap.empty else {}

    out["nvda_open"] = [nvda_open.get(d, np.nan) for d in local_dates]
    out["nvda_prev_close"] = [nvda_prev.get(d, np.nan) for d in local_dates]
    out["nvda_gap_pct"] = [nvda_pct.get(d, np.nan) for d in local_dates]
    out["nvda_gap_down"] = [nvda_dn.get(d, np.nan) for d in local_dates]

    out["tsla_open"] = [tsla_open.get(d, np.nan) for d in local_dates]
    out["tsla_prev_close"] = [tsla_prev.get(d, np.nan) for d in local_dates]
    out["tsla_gap_pct"] = [tsla_pct.get(d, np.nan) for d in local_dates]
    out["tsla_gap_down"] = [tsla_dn.get(d, np.nan) for d in local_dates]
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description="Merge Max7 features into M30 base CSV")
    parser.add_argument(
        "--input",
        required=True,
        help="Input M30 CSV filename under dashboard/data/historical",
    )
    parser.add_argument(
        "--output",
        default="",
        help="Output CSV filename (default: overwrite input)",
    )
    parser.add_argument(
        "--nvda",
        default="NVDA_M15_20230101_20260217_earnings.csv",
        help="NVDA source CSV filename",
    )
    parser.add_argument(
        "--tsla",
        default="TSLA_M15_20230101_20260217_earnings.csv",
        help="TSLA source CSV filename",
    )
    parser.add_argument(
        "--gap-threshold-pct",
        type=float,
        default=0.20,
        help="Gap-down threshold percent (default 0.20)",
    )
    args = parser.parse_args()

    in_path = DATA_DIR / args.input
    out_path = DATA_DIR / (args.output or args.input)
    nvda_path = DATA_DIR / args.nvda
    tsla_path = DATA_DIR / args.tsla

    if not in_path.exists():
        raise FileNotFoundError(f"Input file not found: {in_path}")
    if not nvda_path.exists():
        raise FileNotFoundError(f"NVDA file not found: {nvda_path}")
    if not tsla_path.exists():
        raise FileNotFoundError(f"TSLA file not found: {tsla_path}")

    base = _read_base_m30(in_path)
    nvda = _read_equity_m15(nvda_path)
    tsla = _read_equity_m15(tsla_path)
    extra = _align_constituents(base.index, nvda, tsla, args.gap_threshold_pct)
    out = base.join(extra, how="left")

    final = out.reset_index().rename(columns={"index": "ts_event"})
    final["ts_event"] = pd.to_datetime(final["ts_event"], utc=True).dt.strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    final.to_csv(out_path, index=False)
    print(f"[ok] wrote {len(final)} rows -> {out_path.name}")


if __name__ == "__main__":
    main()
