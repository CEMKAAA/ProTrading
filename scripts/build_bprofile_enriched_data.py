"""
Build enriched M30 index datasets for b_profile_reversion_strategy.

Creates:
  - dashboard/data/historical/NAS100_M30_20240101_20260213_bprofile_enriched.csv
  - dashboard/data/historical/US500_M30_20240101_20260212_bprofile_enriched.csv

The output includes NVDA/TSLA context columns so constituent confirmation
(`constituent_confirmation_mode='required'`) can function:
  - nvda_close, tsla_close
  - nvda_ret, tsla_ret  (6-bar M30 returns)
"""

from __future__ import annotations

from pathlib import Path
import pandas as pd
import numpy as np


ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT / "dashboard" / "data" / "historical"


def _read_mt5_m1(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path, sep="\t")
    dt = pd.to_datetime(
        df["Date"].astype(str).str.strip() + " " + df["Time"].astype(str).str.strip(),
        format="%Y.%m.%d %H:%M",
        errors="coerce",
        utc=True,
    )
    out = pd.DataFrame(
        {
            "open": pd.to_numeric(df["Open"], errors="coerce").to_numpy(),
            "high": pd.to_numeric(df["High"], errors="coerce").to_numpy(),
            "low": pd.to_numeric(df["Low"], errors="coerce").to_numpy(),
            "close": pd.to_numeric(df["Close"], errors="coerce").to_numpy(),
            "volume": pd.to_numeric(df.get("Tickvolume", 0), errors="coerce").fillna(0).to_numpy(),
            "spread": pd.to_numeric(df.get("Spread", 0), errors="coerce").fillna(0).to_numpy(),
        },
        index=dt,
    ).dropna(subset=["open", "high", "low", "close"])
    out = out[~out.index.duplicated(keep="first")].sort_index()
    return out


def _read_equity_m15(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path)
    dt = pd.to_datetime(df["ts_event"], errors="coerce", utc=True)
    out = pd.DataFrame(
        {
            "close": pd.to_numeric(df["close"], errors="coerce").to_numpy(),
        },
        index=dt,
    ).dropna(subset=["close"])
    out = out[~out.index.duplicated(keep="first")].sort_index()
    return out


def _resample_index_to_m30(df_m1: pd.DataFrame) -> pd.DataFrame:
    m30 = (
        df_m1.resample("30min")
        .agg(
            {
                "open": "first",
                "high": "max",
                "low": "min",
                "close": "last",
                "volume": "sum",
                "spread": "mean",
            }
        )
        .dropna(subset=["open", "high", "low", "close"])
    )
    return m30


def _align_constituents(idx_m30: pd.DatetimeIndex, nvda: pd.DataFrame, tsla: pd.DataFrame) -> pd.DataFrame:
    nvda_m30 = nvda.resample("30min").last().rename(columns={"close": "nvda_close"})
    tsla_m30 = tsla.resample("30min").last().rename(columns={"close": "tsla_close"})

    joined = pd.DataFrame(index=idx_m30)
    joined = joined.join(nvda_m30, how="left").join(tsla_m30, how="left")
    joined[["nvda_close", "tsla_close"]] = joined[["nvda_close", "tsla_close"]].ffill(limit=2)

    # 6-bar M30 return (approx. 3-hour pressure context).
    if len(joined) == 0:
        joined["nvda_ret"] = np.nan
        joined["tsla_ret"] = np.nan
        return joined

    joined["nvda_ret"] = joined["nvda_close"].pct_change(periods=6)
    joined["tsla_ret"] = joined["tsla_close"].pct_change(periods=6)
    return joined


def _write_enriched(
    index_symbol: str,
    in_file: str,
    out_file: str,
    start: str,
    end: str,
    nvda_file: str,
    tsla_file: str,
) -> None:
    idx_m1 = _read_mt5_m1(DATA_DIR / in_file)
    nvda = _read_equity_m15(DATA_DIR / nvda_file)
    tsla = _read_equity_m15(DATA_DIR / tsla_file)

    m30 = _resample_index_to_m30(idx_m1)
    extra = _align_constituents(m30.index, nvda, tsla)
    out = m30.join(extra, how="left")

    start_ts = pd.Timestamp(start, tz="UTC")
    end_ts = pd.Timestamp(end, tz="UTC")
    out = out[(out.index >= start_ts) & (out.index <= end_ts)]
    out = out.dropna(subset=["open", "high", "low", "close"])

    out = out.reset_index().rename(columns={"index": "ts_event"})
    out["ts_event"] = out["ts_event"].dt.strftime("%Y-%m-%dT%H:%M:%SZ")
    path = DATA_DIR / out_file
    out.to_csv(path, index=False)
    print(f"[ok] {index_symbol}: wrote {len(out)} rows -> {path.name}")


def main() -> None:
    _write_enriched(
        index_symbol="NAS100",
        in_file="NAS100_M1_20230102_20260213_dukascopy.csv",
        out_file="NAS100_M30_20240101_20260213_bprofile_enriched.csv",
        start="2024-01-01",
        end="2026-02-13 23:59:59",
        nvda_file="NVDA_M15_20230101_20260217_earnings.csv",
        tsla_file="TSLA_M15_20230101_20260217_earnings.csv",
    )
    _write_enriched(
        index_symbol="US500",
        in_file="US500_M1_20240101_20260212_dukascopy.csv",
        out_file="US500_M30_20240101_20260212_bprofile_enriched.csv",
        start="2024-01-01",
        end="2026-02-12 23:59:59",
        nvda_file="NVDA_M15_20230101_20260217_earnings.csv",
        tsla_file="TSLA_M15_20230101_20260217_earnings.csv",
    )


if __name__ == "__main__":
    main()
