"""
Standalone Dukascopy data downloader.
Runs independently of the backend (not affected by uvicorn restarts).
Usage: python download_data.py EURUSD GBPUSD US500
"""
import sys
import os
import struct
import lzma
import time
import threading
from datetime import datetime, timedelta
from pathlib import Path

import numpy as np
import requests
import urllib3
import pandas as pd

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# Force unbuffered output for background execution
sys.stdout.reconfigure(line_buffering=True)
sys.stderr.reconfigure(line_buffering=True)

BASE_URL = "https://datafeed.dukascopy.com/datafeed"
CSV_DATA_DIR = Path(__file__).resolve().parent / "dashboard" / "data" / "historical"

POINT_VALUES = {
    "XAUUSD": 1000,
    "XAGUSD": 100000,
    "EURUSD": 100000,
    "GBPUSD": 100000,
    "USDJPY": 1000,
    "USDCHF": 100000,
    "USA500IDXUSD": 1000,
}

SYMBOL_MAP = {
    "US500": "USA500IDXUSD",
}

START_DATE = "2024-01-01"
END_DATE = "2026-01-31"


def download_hour_ticks(feed_symbol, year, month, day, hour, session, point_value):
    """Download and parse one hour of tick data. Returns a DataFrame or None."""
    url = f"{BASE_URL}/{feed_symbol}/{year}/{month - 1:02d}/{day:02d}/{hour:02d}h_ticks.bi5"
    try:
        resp = session.get(url, timeout=15)
        if resp.status_code == 404 or len(resp.content) == 0:
            return None
        resp.raise_for_status()
        try:
            data = lzma.decompress(resp.content)
        except lzma.LZMAError:
            return None
        if len(data) == 0:
            return None
        tick_size = 20
        num_ticks = len(data) // tick_size
        if num_ticks == 0:
            return None

        # Vectorized parsing: unpack all ticks at once via numpy
        usable = num_ticks * tick_size
        arr = np.frombuffer(data[:usable], dtype=np.dtype('>i4,>i4,>i4,>f4,>f4'))
        ms_offsets = arr['f0'].astype(np.int64)
        ask_prices = arr['f1'].astype(np.float64) / point_value
        bid_prices = arr['f2'].astype(np.float64) / point_value
        ask_vols = arr['f3'].astype(np.float64)
        bid_vols = arr['f4'].astype(np.float64)

        base_ts = np.datetime64(f'{year:04d}-{month:02d}-{day:02d}T{hour:02d}:00:00', 'ms')
        timestamps = base_ts + ms_offsets.astype('timedelta64[ms]')

        df = pd.DataFrame({
            'ask': ask_prices,
            'bid': bid_prices,
            'ask_vol': ask_vols,
            'bid_vol': bid_vols,
        }, index=pd.DatetimeIndex(timestamps))
        df['mid'] = (df['ask'] + df['bid']) * 0.5
        df['spread'] = df['ask'] - df['bid']
        return df
    except Exception:
        return None


def day_ticks_to_m1_candles(tick_dfs):
    """Convert list of hourly tick DataFrames into M1 candles."""
    if not tick_dfs:
        return pd.DataFrame()
    combined = pd.concat(tick_dfs)
    candles = combined['mid'].resample('1min').agg(
        open='first', high='max', low='min', close='last',
    ).dropna()
    candles['volume'] = combined['ask_vol'].resample('1min').sum()
    candles['spread'] = combined['spread'].resample('1min').mean()
    return candles


def download_symbol(symbol):
    feed_symbol = SYMBOL_MAP.get(symbol, symbol)
    point_value = POINT_VALUES.get(feed_symbol, 100000)

    start_date = datetime.strptime(START_DATE, "%Y-%m-%d")
    end_date = datetime.strptime(END_DATE, "%Y-%m-%d")

    session = requests.Session()
    session.verify = False
    session.headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'

    # Count weekdays
    total_days = sum(1 for i in range((end_date - start_date).days + 1)
                     if (start_date + timedelta(days=i)).weekday() < 5)

    print(f"[{symbol}] Starting download: {total_days} trading days ({START_DATE} to {END_DATE})")
    print(f"[{symbol}] Feed symbol: {feed_symbol}, Point value: {point_value}")

    all_candles = []
    current_date = start_date
    day_count = 0
    bars_total = 0

    while current_date <= end_date:
        if current_date.weekday() < 5:
            hour_dfs = []
            for hour in range(24):
                tick_df = download_hour_ticks(
                    feed_symbol, current_date.year, current_date.month,
                    current_date.day, hour, session, point_value
                )
                if tick_df is not None:
                    hour_dfs.append(tick_df)

            day_candles = day_ticks_to_m1_candles(hour_dfs)
            if not day_candles.empty:
                all_candles.append(day_candles)
                bars_total += len(day_candles)

            day_count += 1
            if day_count % 10 == 0:
                pct = day_count / total_days * 100
                print(f"[{symbol}] Day {day_count}/{total_days} ({pct:.0f}%) | {current_date.strftime('%Y-%m-%d')} | {bars_total:,} bars")

            time.sleep(0.05)
        current_date += timedelta(days=1)

    if not all_candles:
        print(f"[{symbol}] ERROR: No data downloaded!")
        return

    combined = pd.concat(all_candles)
    combined = combined[~combined.index.duplicated(keep='first')]
    combined = combined.sort_index()

    CSV_DATA_DIR.mkdir(parents=True, exist_ok=True)
    actual_start = combined.index.min().strftime("%Y%m%d")
    actual_end = combined.index.max().strftime("%Y%m%d")
    filename = f"{symbol}_M1_{actual_start}_{actual_end}_dukascopy.csv"
    csv_path = CSV_DATA_DIR / filename

    # Determine decimal precision
    price_decimals = 5
    if symbol in ("XAUUSD", "XAGUSD") or feed_symbol.startswith("USA"):
        price_decimals = 3
    elif "JPY" in symbol:
        price_decimals = 3

    # Vectorized CSV writing (avoids slow per-row Python loop)
    out = combined.copy()
    out.insert(0, 'Date', out.index.strftime('%Y.%m.%d'))
    out.insert(1, 'Time', out.index.strftime('%H:%M'))
    spread_mult = 10 ** price_decimals
    out['Spread'] = (out['spread'] * spread_mult).round().astype(int)
    out['Tickvolume'] = out['volume'].fillna(0).astype(int)
    out['Volume'] = 0
    fmt = {col: f'%.{price_decimals}f' for col in ['open', 'high', 'low', 'close']}
    out = out.rename(columns={'open': 'Open', 'high': 'High', 'low': 'Low', 'close': 'Close'})
    out = out[['Date', 'Time', 'Open', 'High', 'Low', 'Close', 'Tickvolume', 'Volume', 'Spread']]
    out.to_csv(csv_path, sep='\t', index=False, float_format=f'%.{price_decimals}f')

    size_mb = csv_path.stat().st_size / (1024 * 1024)
    trading_days = combined.index.normalize().nunique()
    print(f"[{symbol}] DONE! {len(combined):,} bars, {trading_days} days, {size_mb:.1f} MB -> {filename}")


if __name__ == "__main__":
    symbols = sys.argv[1:] if len(sys.argv) > 1 else ["EURUSD", "GBPUSD", "US500"]

    # Run downloads in parallel threads
    threads = []
    for sym in symbols:
        t = threading.Thread(target=download_symbol, args=(sym,))
        t.start()
        threads.append(t)
        time.sleep(1)  # Stagger start by 1 second

    for t in threads:
        t.join()

    print("\n=== ALL DOWNLOADS COMPLETE ===")
