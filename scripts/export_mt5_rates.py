#!/usr/bin/env python3
"""Export MT5 OHLC history in bounded chunks for offline causal research."""

from __future__ import annotations

import argparse
from datetime import datetime, timedelta, timezone
from pathlib import Path

import MetaTrader5 as mt5
import pandas as pd


TIMEFRAMES = {
    "M1": (mt5.TIMEFRAME_M1, 60, 60),
    "M5": (mt5.TIMEFRAME_M5, 300, 240),
    "M15": (mt5.TIMEFRAME_M15, 900, 720),
    "H1": (mt5.TIMEFRAME_H1, 3600, 1800),
    "H2": (mt5.TIMEFRAME_H2, 7200, 2400),
    "H4": (mt5.TIMEFRAME_H4, 14400, 3600),
    "D1": (mt5.TIMEFRAME_D1, 86400, 5000),
}


def utc_date(value: str) -> datetime:
    return datetime.strptime(value, "%Y-%m-%d").replace(tzinfo=timezone.utc)


def export_timeframe(symbol: str, label: str, start: datetime, end: datetime) -> pd.DataFrame:
    timeframe, seconds, chunk_days = TIMEFRAMES[label]
    chunks = []
    cursor = start
    overlap = timedelta(seconds=seconds * 2)
    while cursor < end:
        chunk_end = min(end, cursor + timedelta(days=chunk_days))
        rates = mt5.copy_rates_range(symbol, timeframe, cursor, chunk_end)
        if rates is None:
            raise RuntimeError(f"{label} copy failed at {cursor}: {mt5.last_error()}")
        if len(rates):
            chunks.append(pd.DataFrame(rates))
        if chunk_end >= end:
            break
        cursor = chunk_end - overlap
    if not chunks:
        raise RuntimeError(f"No {label} rates returned for {symbol}")
    frame = pd.concat(chunks, ignore_index=True).drop_duplicates("time").sort_values("time")
    frame["time"] = pd.to_datetime(frame["time"], unit="s", utc=True)
    return frame.reset_index(drop=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--terminal", type=Path, required=True)
    parser.add_argument("--symbol", required=True)
    parser.add_argument("--from-date", required=True)
    parser.add_argument("--to-date", required=True)
    parser.add_argument("--timeframes", default="M15,H1,H2,H4,D1")
    parser.add_argument("--out-dir", type=Path, required=True)
    args = parser.parse_args()

    if not mt5.initialize(path=str(args.terminal), portable=True, timeout=60000):
        raise RuntimeError(f"MT5 initialize failed: {mt5.last_error()}")
    try:
        if not mt5.symbol_select(args.symbol, True):
            raise RuntimeError(f"Cannot select {args.symbol}: {mt5.last_error()}")
        args.out_dir.mkdir(parents=True, exist_ok=True)
        start = utc_date(args.from_date)
        end = utc_date(args.to_date) + timedelta(days=1)
        for label in [item.strip().upper() for item in args.timeframes.split(",") if item.strip()]:
            if label not in TIMEFRAMES:
                raise ValueError(f"Unsupported timeframe: {label}")
            frame = export_timeframe(args.symbol, label, start, end)
            path = args.out_dir / f"{args.symbol}_{label}.parquet"
            frame.to_parquet(path, index=False)
            print(f"{label}: rows={len(frame)} first={frame.time.iloc[0]} last={frame.time.iloc[-1]} -> {path}")
    finally:
        mt5.shutdown()


if __name__ == "__main__":
    main()
