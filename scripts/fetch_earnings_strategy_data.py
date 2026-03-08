"""
Fetch and prepare Earnings IV Crush backtest data.

What this script does:
1. Downloads equity OHLCV bars from Databento (XNAS.ITCH, ohlcv-1m).
2. Builds an earnings calendar from a known-ahead source (CSV or yfinance).
3. Adds non-leaky scheduling features used by the strategy:
   - earnings_event
   - days_to_earnings
   - is_pre_earnings_day
   - next_earnings_date
   - planned_exit_date
4. Computes deterministic volatility proxy columns:
   - rv30
   - iv_front, iv_back, iv_45d, iv30
   - volume30 (30-day average daily volume, projected to bars)
5. Saves a CSV directly to data/historical for backtest ingestion.

Usage:
    python scripts/fetch_earnings_strategy_data.py --symbol AAPL --start 2024-01-01 --end 2024-12-31 --timeframe M15
"""

import argparse
import bisect
import os
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

import numpy as np
import pandas as pd
from dotenv import load_dotenv

# Add project root to path
PROJECT_ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

try:
    import databento as db
except ImportError:
    print("ERROR: databento package not installed. Run: pip install databento")
    sys.exit(1)


TIMEFRAME_RULES: Dict[str, str] = {
    "M1": "1min",
    "M5": "5min",
    "M15": "15min",
    "M30": "30min",
    "H1": "1h",
    "D1": "1D",
}


def _to_date_only(value: str) -> pd.Timestamp:
    return pd.to_datetime(value).normalize()


class EarningsDataFetcher:
    """Fetch and prepare equity data for earnings volatility strategy."""

    def __init__(self, api_key: str, output_dir: str = "data/historical"):
        self.client = db.Historical(api_key)
        self.output_dir = (PROJECT_ROOT / output_dir).resolve()
        self.output_dir.mkdir(parents=True, exist_ok=True)

    def fetch_ohlcv(
        self,
        symbol: str,
        start_date: str,
        end_date: str,
        timeframe: str = "M15",
    ) -> pd.DataFrame:
        """
        Fetch OHLCV bars from Databento and resample to requested timeframe.
        """
        print(f"Fetching {symbol} OHLCV data from Databento ({timeframe})...")

        dataset = "XNAS.ITCH"
        requested_end_exclusive = _to_date_only(end_date) + pd.Timedelta(days=1)
        effective_end_exclusive = requested_end_exclusive

        # Pre-clamp query end to dataset availability to avoid hard 422 failures.
        available_end = self._get_dataset_available_end(dataset)
        if available_end is not None and effective_end_exclusive > available_end:
            print(
                f"  WARN Requested end exceeds dataset availability. "
                f"Clamping end from {effective_end_exclusive} to {available_end}."
            )
            effective_end_exclusive = available_end

        if effective_end_exclusive <= _to_date_only(start_date):
            raise ValueError(
                f"No data available in requested range. "
                f"Requested start={start_date}, requested end={end_date}, "
                f"dataset available_end={available_end}."
            )

        try:
            data = self.client.timeseries.get_range(
                dataset=dataset,
                symbols=[symbol],
                schema="ohlcv-1m",
                start=start_date,
                end=effective_end_exclusive.strftime("%Y-%m-%d"),
                stype_in="raw_symbol",
            )
        except Exception as e:
            # Retry once with parsed available end if Databento reports range overflow.
            msg = str(e)
            overflow = "data_end_after_available_end" in msg
            parsed_end = self._extract_available_end_from_error(msg)
            if overflow and parsed_end is not None and parsed_end > _to_date_only(start_date):
                print(
                    f"  WARN Databento end overflow detected. "
                    f"Retrying with end={parsed_end}."
                )
                data = self.client.timeseries.get_range(
                    dataset=dataset,
                    symbols=[symbol],
                    schema="ohlcv-1m",
                    start=start_date,
                    end=parsed_end.strftime("%Y-%m-%d"),
                    stype_in="raw_symbol",
                )
            else:
                raise

        raw = data.to_df()
        if raw is None or raw.empty:
            raise ValueError(f"No Databento OHLCV data returned for {symbol}")

        df = raw.copy()
        if not isinstance(df.index, pd.DatetimeIndex):
            if "ts_event" in df.columns:
                df.index = pd.to_datetime(df["ts_event"], utc=True, errors="coerce")
            else:
                raise ValueError("Databento response missing datetime index/ts_event")

        if df.index.tz is None:
            df.index = df.index.tz_localize("UTC")
        df.index = df.index.tz_convert("America/New_York")

        price_cols = ["open", "high", "low", "close"]
        missing_price = [c for c in price_cols if c not in df.columns]
        if missing_price:
            raise ValueError(f"Databento response missing OHLC columns: {missing_price}")

        if "volume" in df.columns:
            volume_col = "volume"
        elif "size" in df.columns:
            volume_col = "size"
        else:
            volume_col = None

        bars = pd.DataFrame(
            {
                "open": pd.to_numeric(df["open"], errors="coerce"),
                "high": pd.to_numeric(df["high"], errors="coerce"),
                "low": pd.to_numeric(df["low"], errors="coerce"),
                "close": pd.to_numeric(df["close"], errors="coerce"),
                "volume": pd.to_numeric(df[volume_col], errors="coerce").fillna(0)
                if volume_col
                else 0.0,
            },
            index=df.index,
        ).dropna(subset=["open", "high", "low", "close"])

        # Keep regular US cash session bars.
        bars = bars.between_time("09:30", "16:00")
        bars = bars[bars.index.dayofweek < 5]

        start_ts = pd.Timestamp(start_date, tz="America/New_York")
        end_ts = pd.Timestamp(end_date, tz="America/New_York") + pd.Timedelta(days=1) - pd.Timedelta(seconds=1)
        bars = bars[(bars.index >= start_ts) & (bars.index <= end_ts)]
        if bars.empty:
            raise ValueError(f"No bars in requested range after filtering for {symbol}")

        if timeframe != "M1":
            bars = self._resample_bars(bars, timeframe)

        print(f"  OK Downloaded {len(bars):,} bars ({bars.index.min()} to {bars.index.max()})")
        return bars

    def _get_dataset_available_end(self, dataset: str) -> Optional[pd.Timestamp]:
        """
        Read dataset availability end from Databento metadata.
        Returns a timezone-naive UTC-normalized timestamp for comparison.
        """
        try:
            info = self.client.metadata.get_dataset_range(dataset=dataset)
        except Exception as e:
            print(f"  WARN Could not fetch dataset range metadata: {e}")
            return None

        raw_end = self._extract_end_value(info)
        if raw_end is None:
            return None
        ts = pd.to_datetime(raw_end, utc=True, errors="coerce")
        if pd.isna(ts):
            return None
        return ts.tz_convert(None)

    @staticmethod
    def _extract_end_value(obj: Any) -> Optional[str]:
        """
        Best-effort recursive extraction for an 'end' field from arbitrary JSON.
        """
        if isinstance(obj, dict):
            for k in ("end", "available_end", "to"):
                if k in obj and obj[k] is not None:
                    return str(obj[k])
            for v in obj.values():
                hit = EarningsDataFetcher._extract_end_value(v)
                if hit:
                    return hit
            return None
        if isinstance(obj, list):
            for v in obj:
                hit = EarningsDataFetcher._extract_end_value(v)
                if hit:
                    return hit
            return None
        return None

    @staticmethod
    def _extract_available_end_from_error(message: str) -> Optional[pd.Timestamp]:
        """
        Parse Databento overflow errors like:
        "... has data available up to '2026-02-14 00:00:00+00:00' ..."
        """
        if not message:
            return None
        m = re.search(r"available up to '([^']+)'", message)
        if not m:
            return None
        ts = pd.to_datetime(m.group(1), utc=True, errors="coerce")
        if pd.isna(ts):
            return None
        return ts.tz_convert(None)

    @staticmethod
    def _resample_bars(df: pd.DataFrame, timeframe: str) -> pd.DataFrame:
        rule = TIMEFRAME_RULES.get(timeframe)
        if not rule:
            raise ValueError(f"Unsupported timeframe: {timeframe}")
        if timeframe == "M1":
            return df
        out = (
            df.resample(rule)
            .agg(
                {
                    "open": "first",
                    "high": "max",
                    "low": "min",
                    "close": "last",
                    "volume": "sum",
                }
            )
            .dropna(subset=["open", "high", "low", "close"])
        )
        return out

    def fetch_earnings_events(
        self,
        symbol: str,
        start_date: str,
        end_date: str,
        earnings_csv: Optional[str] = None,
    ) -> pd.DataFrame:
        """
        Fetch known-ahead earnings dates.

        Priority:
        1) User-provided CSV (recommended for production reproducibility)
        2) yfinance earnings_dates
        3) Built-in fallback (limited historical coverage)
        """
        print(f"Fetching earnings calendar for {symbol}...")

        if earnings_csv:
            path = Path(earnings_csv)
            if path.exists():
                try:
                    cal = pd.read_csv(path)
                    if "earnings_date" not in cal.columns:
                        raise ValueError("earnings_csv must contain earnings_date column")
                    if "symbol" in cal.columns:
                        symbol_col = cal["symbol"].astype(str).str.strip().str.upper()
                        cal = cal[symbol_col == symbol.upper()]
                    cal["earnings_date"] = pd.to_datetime(cal["earnings_date"]).dt.tz_localize(None)
                    cal = cal.dropna(subset=["earnings_date"])
                    cal = cal.sort_values("earnings_date").drop_duplicates(subset=["earnings_date"])
                    cal = self._filter_earnings_range(cal, start_date, end_date)
                    print(f"  OK Loaded {len(cal)} events from CSV")
                    return cal
                except Exception as e:
                    print(f"  WARN earnings_csv parse failed: {e}")

        # yfinance often provides historical + upcoming announced dates.
        try:
            import yfinance as yf  # Optional dependency

            ticker = yf.Ticker(symbol)
            edf = ticker.get_earnings_dates(limit=80)
            if edf is not None and len(edf) > 0:
                dates = pd.to_datetime(edf.index).tz_localize(None)
                cal = pd.DataFrame({"earnings_date": dates})
                cal = cal.dropna(subset=["earnings_date"])
                cal = cal.sort_values("earnings_date").drop_duplicates(subset=["earnings_date"])
                cal = self._filter_earnings_range(cal, start_date, end_date)
                if len(cal) > 0:
                    print(f"  OK Loaded {len(cal)} events from yfinance")
                    return cal
        except Exception as e:
            print(f"  WARN yfinance earnings fetch failed: {e}")

        cal = self._fallback_earnings_calendar(symbol, start_date, end_date)
        if len(cal) > 0:
            print(f"  WARN Using fallback calendar with {len(cal)} events")
        else:
            print("  WARN No earnings events available. Provide --earnings-csv for reliable runs.")
        return cal

    @staticmethod
    def _filter_earnings_range(df: pd.DataFrame, start_date: str, end_date: str) -> pd.DataFrame:
        start = pd.to_datetime(start_date)
        end = pd.to_datetime(end_date)
        # Include one-day margins for mapping pre/post event days.
        return df[(df["earnings_date"] >= start - pd.Timedelta(days=1)) & (df["earnings_date"] <= end + pd.Timedelta(days=1))]

    def _fallback_earnings_calendar(self, symbol: str, start_date: str, end_date: str) -> pd.DataFrame:
        """
        Static fallback for major symbols (limited and best-effort).
        """
        known = {
            "AAPL": ["2023-02-02", "2023-05-04", "2023-08-03", "2023-11-02", "2024-02-01", "2024-05-02", "2024-08-01", "2024-11-01"],
            "MSFT": ["2023-01-24", "2023-04-25", "2023-07-25", "2023-10-24", "2024-01-30", "2024-04-25", "2024-07-30", "2024-10-30"],
            "NVDA": ["2023-02-22", "2023-05-24", "2023-08-23", "2023-11-21", "2024-02-21", "2024-05-22", "2024-08-28", "2024-11-20"],
            "AMZN": ["2023-02-02", "2023-04-27", "2023-08-03", "2023-10-26", "2024-02-01", "2024-04-30", "2024-08-01", "2024-10-31"],
            "META": ["2023-02-01", "2023-04-26", "2023-07-26", "2023-10-25", "2024-01-31", "2024-04-24", "2024-07-31", "2024-10-30"],
            "TSLA": ["2023-01-25", "2023-04-19", "2023-07-19", "2023-10-18", "2024-01-24", "2024-04-23", "2024-07-23", "2024-10-23"],
        }
        rows = []
        for d in known.get(symbol.upper(), []):
            ts = pd.to_datetime(d)
            if pd.to_datetime(start_date) - pd.Timedelta(days=1) <= ts <= pd.to_datetime(end_date) + pd.Timedelta(days=1):
                rows.append(ts)
        if not rows:
            return pd.DataFrame(columns=["earnings_date"])
        return pd.DataFrame({"earnings_date": sorted(rows)})

    def add_earnings_features(self, df: pd.DataFrame, earnings_df: pd.DataFrame) -> pd.DataFrame:
        """
        Add non-leaky earnings schedule features to each bar.
        """
        print("Adding earnings schedule features...")
        out = df.copy()
        day_key = pd.Series(out.index.date, index=out.index)
        trading_days = sorted(pd.unique(day_key))
        day_to_idx = {d: i for i, d in enumerate(trading_days)}

        out["earnings_event"] = 0
        out["days_to_earnings"] = 999
        out["is_pre_earnings_day"] = False
        out["next_earnings_date"] = ""
        out["planned_exit_date"] = ""

        if earnings_df is None or earnings_df.empty or len(trading_days) < 2:
            return out

        raw_events = sorted(pd.to_datetime(earnings_df["earnings_date"]).dt.date.unique())
        aligned_events: List[pd.Timestamp] = []
        for e in raw_events:
            # Align off-session dates to the next trading day.
            pos = bisect.bisect_left(trading_days, e)
            if pos < len(trading_days):
                aligned_events.append(trading_days[pos])
        event_days = sorted(set(aligned_events))
        if not event_days:
            return out

        for e in event_days:
            out.loc[day_key == e, "earnings_event"] = 1

        days_map: Dict[object, int] = {}
        next_event_map: Dict[object, str] = {}
        exit_map: Dict[object, str] = {}
        pre_map: Dict[object, bool] = {}

        for d in trading_days:
            pos = bisect.bisect_left(event_days, d)
            if pos >= len(event_days):
                days_map[d] = 999
                next_event_map[d] = ""
                exit_map[d] = ""
                pre_map[d] = False
                continue

            ev = event_days[pos]
            delta = day_to_idx[ev] - day_to_idx[d]
            days_map[d] = int(delta)
            next_event_map[d] = ev.isoformat()
            ev_idx = day_to_idx[ev]
            if ev_idx < len(trading_days) - 1:
                exit_map[d] = trading_days[ev_idx + 1].isoformat()
            else:
                exit_map[d] = ""
            pre_map[d] = delta == 1

        out["days_to_earnings"] = day_key.map(days_map).fillna(999).astype(int)
        out["next_earnings_date"] = day_key.map(next_event_map).fillna("")
        out["planned_exit_date"] = day_key.map(exit_map).fillna("")
        out["is_pre_earnings_day"] = day_key.map(pre_map).fillna(False).astype(bool)

        print(f"  OK Marked earnings days: {int((out['earnings_event'] == 1).sum())}")
        print(f"  OK Marked pre-earnings bars: {int(out['is_pre_earnings_day'].sum())}")
        return out

    @staticmethod
    def _infer_bars_per_day(df: pd.DataFrame) -> int:
        day_counts = df.groupby(df.index.normalize()).size()
        if day_counts.empty:
            return 26
        return int(max(1, day_counts.median()))

    def calculate_iv_metrics(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Calculate deterministic IV proxy metrics (no randomness, no bfill leakage).
        """
        print("Calculating deterministic IV proxy metrics...")
        out = df.copy()
        out["returns"] = out["close"].pct_change()

        bars_per_day = self._infer_bars_per_day(out)
        annualizer = np.sqrt(252.0 * bars_per_day)
        rv_window = max(30, 30 * bars_per_day)
        min_periods = max(20, rv_window // 5)

        rv30 = out["returns"].rolling(rv_window, min_periods=min_periods).std() * annualizer
        rv_ewm = out["returns"].ewm(span=max(20, bars_per_day * 5), min_periods=20).std() * annualizer
        rv30 = rv30.combine_first(rv_ewm)
        rv30 = rv30.ffill()
        if rv30.notna().any():
            rv30 = rv30.fillna(float(rv30.dropna().iloc[0]))
        else:
            rv30 = rv30.fillna(0.25)
        rv30 = rv30.clip(lower=0.05, upper=3.0)
        out["rv30"] = rv30

        base_iv = (out["rv30"] * 1.25).clip(lower=0.05, upper=3.5)
        if "days_to_earnings" in out.columns:
            dte = pd.to_numeric(out["days_to_earnings"], errors="coerce").fillna(999).clip(lower=0, upper=999)
        else:
            dte = pd.Series(999, index=out.index, dtype=float)
        proximity = np.exp(-dte.clip(upper=15) / 3.0)

        out["iv_front"] = (base_iv * (1.0 + 0.35 * proximity)).clip(lower=0.05, upper=4.0)
        out["iv_back"] = (base_iv * (1.0 + 0.12 * proximity)).clip(lower=0.05, upper=4.0)
        out["iv_45d"] = (base_iv * (1.0 + 0.05 * proximity)).clip(lower=0.05, upper=4.0)
        out["iv30"] = (base_iv * (1.0 + 0.20 * proximity)).clip(lower=0.05, upper=4.0)

        daily_vol = out.groupby(out.index.normalize())["volume"].sum()
        daily_vol30 = daily_vol.rolling(30, min_periods=5).mean()
        fallback_daily = daily_vol.expanding(min_periods=1).mean()
        day_idx = out.index.normalize()
        vol30_vals = pd.Series(day_idx, index=out.index).map(daily_vol30.to_dict())
        vol30_vals = vol30_vals.fillna(pd.Series(day_idx, index=out.index).map(fallback_daily.to_dict()))
        out["volume30"] = pd.to_numeric(vol30_vals, errors="coerce").fillna(0.0)

        print("  OK IV proxy and liquidity metrics computed")
        return out

    def save_dataset(
        self,
        df: pd.DataFrame,
        symbol: str,
        timeframe: str,
        start_date: str,
        end_date: str,
    ) -> str:
        start_str = start_date.replace("-", "")
        end_str = end_date.replace("-", "")
        filename = f"{symbol}_{timeframe}_{start_str}_{end_str}_earnings.csv"
        filepath = self.output_dir / filename

        required_cols = [
            "open",
            "high",
            "low",
            "close",
            "volume",
            "earnings_event",
            "days_to_earnings",
            "is_pre_earnings_day",
            "next_earnings_date",
            "planned_exit_date",
            "iv_front",
            "iv_back",
            "iv_45d",
            "iv30",
            "rv30",
            "volume30",
        ]
        missing = [c for c in required_cols if c not in df.columns]
        if missing:
            raise ValueError(f"Dataset is missing required columns: {missing}")

        df.to_csv(filepath)
        print(f"  OK Saved: {filepath}")
        print(f"  OK Shape: {df.shape}")
        print(f"  OK Date range: {df.index.min()} to {df.index.max()}")
        return str(filepath)


def main():
    parser = argparse.ArgumentParser(description="Fetch earnings strategy data from Databento")
    parser.add_argument("--symbol", type=str, default="AAPL", help="Stock symbol")
    parser.add_argument("--start", type=str, required=True, help="Start date YYYY-MM-DD")
    parser.add_argument("--end", type=str, required=True, help="End date YYYY-MM-DD")
    parser.add_argument("--timeframe", type=str, default="M15", choices=["M1", "M5", "M15", "M30", "H1", "D1"])
    parser.add_argument("--output-dir", type=str, default="data/historical", help="Output directory")
    parser.add_argument("--api-key", type=str, help="Databento API key (or set in dashboard/.env)")
    parser.add_argument("--earnings-csv", type=str, default=None, help="Optional CSV file with earnings_date column")
    args = parser.parse_args()

    load_dotenv(PROJECT_ROOT / "dashboard" / ".env")
    api_key = args.api_key or os.getenv("DATABENTO_API_KEY")
    if not api_key:
        print("ERROR: DATABENTO_API_KEY not found in dashboard/.env and --api-key not provided")
        sys.exit(1)

    print("=" * 72)
    print("EARNINGS IV CRUSH DATA PREP")
    print("=" * 72)
    print(f"Symbol:     {args.symbol.upper()}")
    print(f"Timeframe:  {args.timeframe}")
    print(f"Date Range: {args.start} -> {args.end}")
    print(f"Output Dir: {(PROJECT_ROOT / args.output_dir).resolve()}")
    print("=" * 72)

    fetcher = EarningsDataFetcher(api_key=api_key, output_dir=args.output_dir)

    try:
        bars = fetcher.fetch_ohlcv(args.symbol.upper(), args.start, args.end, args.timeframe)
        earnings = fetcher.fetch_earnings_events(
            args.symbol.upper(),
            args.start,
            args.end,
            earnings_csv=args.earnings_csv,
        )
        bars = fetcher.add_earnings_features(bars, earnings)
        bars = fetcher.calculate_iv_metrics(bars)
        filepath = fetcher.save_dataset(
            bars,
            args.symbol.upper(),
            args.timeframe,
            args.start,
            args.end,
        )

        print("\n" + "=" * 72)
        print("SUCCESS")
        print("=" * 72)
        print(f"Dataset ready for backtesting: {filepath}")
        print("Next: upload the CSV in Data Management and run Earnings IV Crush.")
        print("=" * 72)

    except Exception as e:
        print("\n" + "=" * 72)
        print("FAILED")
        print("=" * 72)
        print(f"Error: {e}")
        raise


if __name__ == "__main__":
    main()
