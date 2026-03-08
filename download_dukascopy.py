"""
Download historical M1 XAUUSD data from Dukascopy's tick data feed.

Dukascopy provides free tick data via binary files (bi5 format).
This script downloads tick data, aggregates to M1 candles, and saves as CSV.

Usage:
    python download_dukascopy.py --start 2021-01-01 --end 2025-12-31
    python download_dukascopy.py --start 2020-01-01 --end 2025-12-31 --symbol XAUUSD
"""

import argparse
import struct
import io
import lzma
import time
import logging
import sys
import os
from datetime import datetime, timedelta
from pathlib import Path
from typing import List, Tuple, Optional

import requests
import urllib3
import pandas as pd
import numpy as np

# Dukascopy uses self-signed SSL certificate
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Dukascopy data feed base URL
BASE_URL = "https://datafeed.dukascopy.com/datafeed"

# Point values for converting integer prices to decimals
POINT_VALUES = {
    "XAUUSD": 1000,      # Gold: 3 decimal places
    "XAGUSD": 100000,    # Silver: 5 decimal places
    "EURUSD": 100000,    # EUR/USD: 5 decimal places
    "GBPUSD": 100000,
    "USDJPY": 1000,      # JPY pairs: 3 decimal places
    "USDCHF": 100000,
}

# Output directory
OUTPUT_DIR = Path(__file__).parent / "dashboard" / "data" / "historical"


def download_hour_ticks(
    symbol: str,
    year: int,
    month: int,  # 1-based (January = 1)
    day: int,
    hour: int,
    session: requests.Session,
    point_value: int,
) -> Optional[List[Tuple[datetime, float, float, float, float]]]:
    """
    Download and parse one hour of tick data from Dukascopy.

    Returns list of (timestamp, ask, bid, ask_vol, bid_vol) tuples, or None if no data.
    """
    # Dukascopy uses 0-based months (January = 00)
    url = f"{BASE_URL}/{symbol}/{year}/{month - 1:02d}/{day:02d}/{hour:02d}h_ticks.bi5"

    try:
        resp = session.get(url, timeout=15)
        if resp.status_code == 404:
            return None  # No data for this hour (weekend, holiday)
        resp.raise_for_status()

        if len(resp.content) == 0:
            return None

        # Decompress LZMA
        try:
            data = lzma.decompress(resp.content)
        except lzma.LZMAError:
            return None

        if len(data) == 0:
            return None

        # Parse binary ticks: each tick is 20 bytes
        # int32 ms_offset, int32 ask, int32 bid, float32 ask_vol, float32 bid_vol
        tick_size = 20
        num_ticks = len(data) // tick_size
        if num_ticks == 0:
            return None

        ticks = []
        base_time = datetime(year, month, day, hour)

        for i in range(num_ticks):
            offset = i * tick_size
            ms_offset, ask_int, bid_int, ask_vol, bid_vol = struct.unpack(
                '>iiiff', data[offset:offset + tick_size]
            )

            ts = base_time + timedelta(milliseconds=ms_offset)
            ask = ask_int / point_value
            bid = bid_int / point_value

            ticks.append((ts, ask, bid, ask_vol, bid_vol))

        return ticks

    except requests.exceptions.RequestException:
        return None
    except Exception as e:
        logger.debug(f"Error parsing {url}: {e}")
        return None


def ticks_to_m1_candles(ticks: List[Tuple]) -> pd.DataFrame:
    """
    Aggregate tick data into M1 OHLCV candles using mid price.
    """
    if not ticks:
        return pd.DataFrame()

    # Create DataFrame from ticks
    df = pd.DataFrame(ticks, columns=['timestamp', 'ask', 'bid', 'ask_vol', 'bid_vol'])
    df['mid'] = (df['ask'] + df['bid']) / 2
    df['spread'] = df['ask'] - df['bid']
    df.set_index('timestamp', inplace=True)

    # Resample to M1
    candles = df['mid'].resample('1min').agg({
        'open': 'first',
        'high': 'max',
        'low': 'min',
        'close': 'last',
    }).dropna()

    candles['volume'] = df['ask_vol'].resample('1min').sum()
    candles['spread'] = df['spread'].resample('1min').mean()

    # Rename for consistency
    candles.columns = ['open', 'high', 'low', 'close', 'volume', 'spread']

    return candles


def download_day(
    symbol: str,
    date: datetime,
    session: requests.Session,
    point_value: int,
) -> pd.DataFrame:
    """Download all ticks for one day and return M1 candles."""
    all_ticks = []

    for hour in range(24):
        ticks = download_hour_ticks(
            symbol, date.year, date.month, date.day, hour,
            session, point_value
        )
        if ticks:
            all_ticks.extend(ticks)

    return ticks_to_m1_candles(all_ticks)


def download_range(
    symbol: str,
    start_date: datetime,
    end_date: datetime,
    output_dir: Path,
    chunk_months: int = 6,
) -> Path:
    """
    Download M1 data for a date range and save as CSV.

    Downloads data month by month and saves in chunks to avoid memory issues.
    """
    point_value = POINT_VALUES.get(symbol, 100000)
    output_dir.mkdir(parents=True, exist_ok=True)

    session = requests.Session()
    session.verify = False  # Dukascopy uses self-signed SSL cert
    session.headers.update({
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    })

    total_days = (end_date - start_date).days
    current_date = start_date
    all_candles = []
    chunk_start = start_date
    files_created = []
    day_count = 0
    bars_total = 0

    logger.info(f"=" * 60)
    logger.info(f"DUKASCOPY DATA DOWNLOAD")
    logger.info(f"=" * 60)
    logger.info(f"Symbol: {symbol}")
    logger.info(f"Date Range: {start_date.strftime('%Y-%m-%d')} to {end_date.strftime('%Y-%m-%d')}")
    logger.info(f"Total days: {total_days}")
    logger.info(f"Point value: {point_value}")
    logger.info(f"Output: {output_dir}")
    logger.info(f"=" * 60)

    while current_date <= end_date:
        # Skip weekends
        if current_date.weekday() < 5:  # Mon-Fri
            day_candles = download_day(symbol, current_date, session, point_value)

            if not day_candles.empty:
                all_candles.append(day_candles)
                bars_total += len(day_candles)

            day_count += 1
            pct = day_count / total_days * 100
            if day_count % 5 == 0:
                logger.info(
                    f"  Progress: {pct:.1f}% | Day {day_count}/{total_days} | "
                    f"{current_date.strftime('%Y-%m-%d')} | {bars_total:,} bars total"
                )

            # Rate limiting: small delay to be polite to Dukascopy servers
            time.sleep(0.05)

        # Check if we should save a chunk (every chunk_months months)
        months_elapsed = (current_date.year - chunk_start.year) * 12 + (current_date.month - chunk_start.month)
        is_last_day = current_date >= end_date

        if (months_elapsed >= chunk_months and current_date.day == 1) or is_last_day:
            if all_candles:
                combined = pd.concat(all_candles)
                combined = combined[~combined.index.duplicated(keep='first')]
                combined = combined.sort_index()

                # Save chunk
                chunk_end = current_date
                fname = (
                    f"{symbol}_M1_{chunk_start.strftime('%Y%m%d')}_"
                    f"{chunk_end.strftime('%Y%m%d')}_dukascopy.csv"
                )
                fpath = output_dir / fname
                save_as_mt5_csv(combined, fpath)
                files_created.append(fpath)

                logger.info(f"  Saved: {fname} ({len(combined):,} bars)")

                # Reset for next chunk
                all_candles = []
                chunk_start = current_date + timedelta(days=1)

        current_date += timedelta(days=1)

    # Save any remaining data
    if all_candles:
        combined = pd.concat(all_candles)
        combined = combined[~combined.index.duplicated(keep='first')]
        combined = combined.sort_index()

        fname = (
            f"{symbol}_M1_{chunk_start.strftime('%Y%m%d')}_"
            f"{current_date.strftime('%Y%m%d')}_dukascopy.csv"
        )
        fpath = output_dir / fname
        save_as_mt5_csv(combined, fpath)
        files_created.append(fpath)
        logger.info(f"  Saved: {fname} ({len(combined):,} bars)")

    logger.info(f"=" * 60)
    logger.info(f"DOWNLOAD COMPLETE")
    logger.info(f"  Total bars: {bars_total:,}")
    logger.info(f"  Files created: {len(files_created)}")
    for f in files_created:
        logger.info(f"    - {f.name}")
    logger.info(f"=" * 60)

    return output_dir


def save_as_mt5_csv(df: pd.DataFrame, path: Path):
    """Save DataFrame in MT5-compatible CSV format (tab-separated)."""
    out = df.copy()
    out.index.name = None

    # Format as MT5 export: Date\tTime\tOpen\tHigh\tLow\tClose\tTickvolume\tVolume\tSpread
    rows = []
    rows.append("Date\tTime\tOpen\tHigh\tLow\tClose\tTickvolume\tVolume\tSpread")

    for ts, row in out.iterrows():
        date_str = ts.strftime('%Y.%m.%d')
        time_str = ts.strftime('%H:%M')
        spread_val = int(round(row.get('spread', 0) * 100))  # Convert to points
        rows.append(
            f"{date_str}\t{time_str}\t{row['open']:.3f}\t{row['high']:.3f}\t"
            f"{row['low']:.3f}\t{row['close']:.3f}\t"
            f"{int(row.get('volume', 0))}\t0\t{spread_val}"
        )

    with open(path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(rows))


def merge_all_csvs(symbol: str, output_dir: Path):
    """
    After downloading, optionally merge all chunk CSVs into one file.
    """
    pattern = f"{symbol}_M1_*_dukascopy.csv"
    files = sorted(output_dir.glob(pattern))

    if len(files) <= 1:
        logger.info("Only one file, no merge needed.")
        return

    logger.info(f"Merging {len(files)} files...")
    all_dfs = []
    for f in files:
        df = pd.read_csv(f, sep='\t', parse_dates={'datetime': ['Date', 'Time']},
                         index_col='datetime')
        all_dfs.append(df)

    combined = pd.concat(all_dfs)
    combined = combined[~combined.index.duplicated(keep='first')]
    combined = combined.sort_index()

    # Determine date range
    start_str = combined.index.min().strftime('%Y%m%d')
    end_str = combined.index.max().strftime('%Y%m%d')
    merged_name = f"{symbol}_M1_{start_str}_{end_str}_dukascopy.csv"
    merged_path = output_dir / merged_name

    save_as_mt5_csv(combined, merged_path)
    logger.info(f"Merged file: {merged_name} ({len(combined):,} bars)")

    # Remove chunk files
    for f in files:
        if f != merged_path:
            f.unlink()
            logger.info(f"  Removed chunk: {f.name}")


def main():
    parser = argparse.ArgumentParser(
        description="Download M1 historical data from Dukascopy"
    )
    parser.add_argument(
        '--symbol', default='XAUUSD',
        help='Trading symbol (default: XAUUSD)'
    )
    parser.add_argument(
        '--start', required=True,
        help='Start date (YYYY-MM-DD)'
    )
    parser.add_argument(
        '--end', required=True,
        help='End date (YYYY-MM-DD)'
    )
    parser.add_argument(
        '--output', default=None,
        help='Output directory (default: dashboard/data/historical/)'
    )
    parser.add_argument(
        '--no-merge', action='store_true',
        help='Skip merging chunk files into one'
    )

    args = parser.parse_args()

    start_date = datetime.strptime(args.start, '%Y-%m-%d')
    end_date = datetime.strptime(args.end, '%Y-%m-%d')
    output_dir = Path(args.output) if args.output else OUTPUT_DIR

    if start_date >= end_date:
        print("Error: start date must be before end date")
        sys.exit(1)

    # Quick connectivity test
    logger.info("Testing Dukascopy connection...")
    try:
        session = requests.Session()
        session.headers.update({
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        })
        test_url = f"{BASE_URL}/{args.symbol}/2024/00/02/10h_ticks.bi5"
        resp = session.get(test_url, timeout=10)
        if resp.status_code == 200 and len(resp.content) > 0:
            logger.info(f"Connection OK! Got {len(resp.content)} bytes from test URL")
        else:
            logger.warning(f"Test returned status {resp.status_code}, content size {len(resp.content)}")
            logger.warning("Data may not be available for this symbol. Proceeding anyway...")
    except Exception as e:
        logger.error(f"Connection test failed: {e}")
        logger.error("Check your internet connection and try again.")
        sys.exit(1)

    # Download
    download_range(args.symbol, start_date, end_date, output_dir)

    # Merge chunks
    if not args.no_merge:
        merge_all_csvs(args.symbol, output_dir)

    logger.info("Done! You can now use this data in backtests.")


if __name__ == "__main__":
    main()
