"""
Build deterministic earnings-event datasets and trade candidates.

This script can:
1) Load an already-prepared earnings bars CSV, or
2) Fetch and prepare bars from Databento via fetch_earnings_strategy_data.py

Then it creates:
- event-level dataset: one row per earnings event
- candidate dataset: rule-based selected trades using strategy preset thresholds
"""

import argparse
import os
import sys
from pathlib import Path
from typing import Dict

import pandas as pd
from dotenv import load_dotenv

# Add project root to path
PROJECT_ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from dashboard.backend.core.earnings_edge_tools import (  # noqa: E402
    build_event_level_dataset,
    load_earnings_bars_csv,
    select_trade_candidates,
    summarize_selection,
)
from dashboard.backend.core.strategy_registry import StrategyRegistry  # noqa: E402
from scripts.fetch_earnings_strategy_data import EarningsDataFetcher  # noqa: E402


def _load_preset_thresholds(symbol: str, preset: str) -> Dict[str, float]:
    cfg = StrategyRegistry.get_preset_config("earnings_volatility_strategy", preset, symbol)
    if not cfg:
        raise ValueError(f"Unknown preset for earnings_volatility_strategy: {preset}")
    return {
        "term_structure_max_slope": float(cfg.get("term_structure_max_slope", -0.05)),
        "min_avg_volume30": float(cfg.get("min_avg_volume30", 5_000_000)),
        "min_iv30_rv30_ratio": float(cfg.get("min_iv30_rv30_ratio", 1.25)),
        "entry_time": str(cfg.get("entry_time", "15:45")),
        "exit_time": str(cfg.get("exit_time", "09:45")),
        "front_dte_days": float(cfg.get("front_dte_days", 7.0)),
        "expected_move_scale": float(cfg.get("expected_move_scale", 1.0)),
    }


def _fetch_dataset(
    symbol: str,
    timeframe: str,
    start: str,
    end: str,
    output_dir: str,
    earnings_csv: str | None,
    api_key: str,
) -> pd.DataFrame:
    fetcher = EarningsDataFetcher(api_key=api_key, output_dir=output_dir)
    bars = fetcher.fetch_ohlcv(symbol, start, end, timeframe)
    earnings = fetcher.fetch_earnings_events(symbol, start, end, earnings_csv=earnings_csv)
    bars = fetcher.add_earnings_features(bars, earnings)
    bars = fetcher.calculate_iv_metrics(bars)
    fetcher.save_dataset(bars, symbol, timeframe, start, end)
    return bars


def _output_paths(symbol: str, timeframe: str, df: pd.DataFrame, output_dir: str) -> tuple[Path, Path]:
    out_dir = (PROJECT_ROOT / output_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    start_str = df.index.min().strftime("%Y%m%d")
    end_str = df.index.max().strftime("%Y%m%d")
    base = f"{symbol}_{timeframe}_{start_str}_{end_str}"
    events_path = out_dir / f"{base}_earnings_events.csv"
    candidates_path = out_dir / f"{base}_trade_candidates.csv"
    return events_path, candidates_path


def main():
    parser = argparse.ArgumentParser(description="Build deterministic earnings edge datasets")
    parser.add_argument("--symbol", type=str, required=True, help="Stock symbol (e.g. AAPL)")
    parser.add_argument("--timeframe", type=str, default="M15", choices=["M1", "M5", "M15", "M30", "H1", "D1"])
    parser.add_argument("--preset", type=str, default="default", help="Earnings strategy preset")
    parser.add_argument("--min-edge-pct", type=float, default=0.0, help="Minimum edge (expected - realized, in decimal pct)")
    parser.add_argument("--output-dir", type=str, default="data/historical", help="Output directory")

    parser.add_argument("--input-csv", type=str, default=None, help="Optional prepared *_earnings.csv path")
    parser.add_argument("--start", type=str, default=None, help="Fetch start date YYYY-MM-DD (required if --input-csv omitted)")
    parser.add_argument("--end", type=str, default=None, help="Fetch end date YYYY-MM-DD (required if --input-csv omitted)")
    parser.add_argument("--earnings-csv", type=str, default=None, help="Optional earnings calendar CSV for fetch")
    parser.add_argument("--api-key", type=str, default=None, help="Databento API key (or dashboard/.env)")
    args = parser.parse_args()

    symbol = args.symbol.upper()
    load_dotenv(PROJECT_ROOT / "dashboard" / ".env")
    preset_cfg = _load_preset_thresholds(symbol=symbol, preset=args.preset)

    print("=" * 72)
    print("EARNINGS EDGE DATASET BUILDER")
    print("=" * 72)
    print(f"Symbol:     {symbol}")
    print(f"Timeframe:  {args.timeframe}")
    print(f"Preset:     {args.preset}")
    print(f"Output Dir: {(PROJECT_ROOT / args.output_dir).resolve()}")
    print("=" * 72)

    if args.input_csv:
        bars = load_earnings_bars_csv(args.input_csv)
        print(f"Loaded prepared bars CSV: {args.input_csv}")
    else:
        if not args.start or not args.end:
            raise ValueError("--start and --end are required when --input-csv is not provided")
        api_key = args.api_key or os.getenv("DATABENTO_API_KEY")
        if not api_key:
            raise ValueError("DATABENTO_API_KEY not set and --api-key not provided")
        bars = _fetch_dataset(
            symbol=symbol,
            timeframe=args.timeframe,
            start=args.start,
            end=args.end,
            output_dir=args.output_dir,
            earnings_csv=args.earnings_csv,
            api_key=api_key,
        )

    events_df = build_event_level_dataset(
        bars,
        symbol=symbol,
        entry_time=preset_cfg["entry_time"],
        exit_time=preset_cfg["exit_time"],
        front_dte_days=preset_cfg["front_dte_days"],
        expected_move_scale=preset_cfg["expected_move_scale"],
    )
    if events_df.empty:
        print("No event rows generated (check earnings schedule coverage).")
        return

    candidates_df = select_trade_candidates(
        events_df=events_df,
        term_structure_max_slope=preset_cfg["term_structure_max_slope"],
        min_avg_volume30=preset_cfg["min_avg_volume30"],
        min_iv30_rv30_ratio=preset_cfg["min_iv30_rv30_ratio"],
        min_edge_pct=args.min_edge_pct,
    )

    events_path, candidates_path = _output_paths(
        symbol=symbol,
        timeframe=args.timeframe,
        df=bars,
        output_dir=args.output_dir,
    )
    events_df.to_csv(events_path, index=False)
    candidates_df.to_csv(candidates_path, index=False)

    stats = summarize_selection(candidates_df)
    print(f"Saved events:     {events_path}")
    print(f"Saved candidates: {candidates_path}")
    print(f"Events: {stats['events']} | Selected: {stats['selected']}")
    print("=" * 72)


if __name__ == "__main__":
    main()
