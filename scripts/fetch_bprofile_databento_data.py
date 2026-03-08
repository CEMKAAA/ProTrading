"""
Fetch Databento futures data and build an enriched dataset for
b_profile_reversion_strategy.

Pipeline:
1) Download NQ (primary) and ES (correlation) ohlcv-1m bars.
2) Download NQ trades + mbp-1 snapshots.
3) Build orderflow/depth proxy features per minute.
4) Resample to target timeframe (default M30).
5) Save a CSV into dashboard/data/historical for direct backtest usage.

Examples:
  # 1) Cost estimate only (recommended first)
  python scripts/fetch_bprofile_databento_data.py --cost-only --start 2025-01-01 --end 2025-03-31

  # 2) Download and build NAS100-named enriched file for b-profile campaign
  python scripts/fetch_bprofile_databento_data.py --start 2025-01-01 --end 2025-12-31 --output-symbol NAS100
"""

from __future__ import annotations

import argparse
import math
import os
import re
import sys
from dataclasses import dataclass
from datetime import time as dtime
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

import numpy as np
import pandas as pd
from dotenv import load_dotenv

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
}


@dataclass
class CostBreakdown:
    schema: str
    symbols: str
    start: str
    end: str
    estimated_usd: float


class BProfileDatabentoFetcher:
    def __init__(self, api_key: str, output_dir: str = "dashboard/data/historical"):
        self.client = db.Historical(api_key)
        self.output_dir = (PROJECT_ROOT / output_dir).resolve()
        self.output_dir.mkdir(parents=True, exist_ok=True)

    def estimate_cost(
        self,
        dataset: str,
        primary_symbol: str,
        corr_symbol: str,
        start: str,
        end: str,
        stype_in: str,
        include_trades: bool = True,
        include_mbp: bool = True,
    ) -> List[CostBreakdown]:
        """
        Estimate Databento cost for planned requests.
        """
        estimates: List[CostBreakdown] = []
        requests: List[Tuple[str, List[str]]] = [
            ("ohlcv-1m", [primary_symbol]),
            ("ohlcv-1m", [corr_symbol]),
        ]
        if include_trades:
            requests.append(("trades", [primary_symbol]))
        if include_mbp:
            requests.append(("mbp-1", [primary_symbol]))
        for schema, symbols in requests:
            try:
                cost = float(
                    self.client.metadata.get_cost(
                        dataset=dataset,
                        symbols=symbols,
                        schema=schema,
                        stype_in=stype_in,
                        start=start,
                        end=end,
                    )
                )
            except Exception as e:
                print(f"WARN cost estimation failed for {schema}/{symbols}: {e}")
                cost = math.nan
            estimates.append(
                CostBreakdown(
                    schema=schema,
                    symbols=",".join(symbols),
                    start=start,
                    end=end,
                    estimated_usd=cost,
                )
            )
        return estimates

    def fetch_ohlcv_1m(
        self,
        dataset: str,
        symbol: str,
        stype_in: str,
        start: str,
        end: str,
    ) -> pd.DataFrame:
        data = self.client.timeseries.get_range(
            dataset=dataset,
            symbols=[symbol],
            schema="ohlcv-1m",
            stype_in=stype_in,
            start=start,
            end=end,
        )
        raw = data.to_df()
        if raw is None or raw.empty:
            raise ValueError(f"No ohlcv-1m data returned for {symbol}")

        df = raw.copy()
        if not isinstance(df.index, pd.DatetimeIndex):
            if "ts_event" in df.columns:
                df.index = pd.to_datetime(df["ts_event"], utc=True, errors="coerce")
            else:
                raise ValueError(f"Missing datetime index/ts_event for {symbol} ohlcv-1m")
        if df.index.tz is None:
            df.index = df.index.tz_localize("UTC")
        df.index = df.index.tz_convert("America/New_York")

        out = pd.DataFrame(index=df.index)
        out["open"] = pd.to_numeric(df.get("open"), errors="coerce")
        out["high"] = pd.to_numeric(df.get("high"), errors="coerce")
        out["low"] = pd.to_numeric(df.get("low"), errors="coerce")
        out["close"] = pd.to_numeric(df.get("close"), errors="coerce")
        if "volume" in df.columns:
            out["volume"] = pd.to_numeric(df["volume"], errors="coerce").fillna(0.0)
        elif "size" in df.columns:
            out["volume"] = pd.to_numeric(df["size"], errors="coerce").fillna(0.0)
        else:
            out["volume"] = 0.0
        out = out.dropna(subset=["open", "high", "low", "close"])
        return out

    def fetch_trades_1m_features(
        self,
        dataset: str,
        symbol: str,
        stype_in: str,
        start: str,
        end: str,
        chunk_days: int = 7,
        session_start: Optional[str] = None,
        session_end: Optional[str] = None,
    ) -> pd.DataFrame:
        """
        Build 1-minute trade-flow features from Databento trades.
        """
        if session_start and session_end:
            chunks = self._build_session_windows(start, end, session_start, session_end)
        else:
            chunks = self._build_date_chunks(start, end, chunk_days=chunk_days)
        parts: List[pd.DataFrame] = []

        for i, (s, e) in enumerate(chunks, start=1):
            print(f"  trades chunk {i}/{len(chunks)}: {s} -> {e}")
            data = self.client.timeseries.get_range(
                dataset=dataset,
                symbols=[symbol],
                schema="trades",
                stype_in=stype_in,
                start=s,
                end=e,
            )
            raw = data.to_df()
            if raw is None or raw.empty:
                continue
            parts.append(raw)

        if not parts:
            return pd.DataFrame()

        df = pd.concat(parts, axis=0)
        if not isinstance(df.index, pd.DatetimeIndex):
            if "ts_event" in df.columns:
                df.index = pd.to_datetime(df["ts_event"], utc=True, errors="coerce")
            else:
                raise ValueError("Trades dataset missing datetime index/ts_event")
        if df.index.tz is None:
            df.index = df.index.tz_localize("UTC")
        df.index = df.index.tz_convert("America/New_York")

        lower = {str(c).lower(): c for c in df.columns}
        price_col = lower.get("price")
        size_col = lower.get("size")
        side_col = lower.get("side")
        if price_col is None or size_col is None:
            raise ValueError("Trades schema missing price/size columns")

        price = pd.to_numeric(df[price_col], errors="coerce")
        size = pd.to_numeric(df[size_col], errors="coerce").fillna(0.0)
        side = df[side_col] if side_col else None
        sign = self._infer_trade_sign(price, side)

        tmp = pd.DataFrame(index=df.index)
        tmp["price"] = price
        tmp["size"] = size
        tmp["signed_size"] = sign * size
        tmp["buy_size"] = np.where(sign > 0, size, 0.0)
        tmp["sell_size"] = np.where(sign < 0, size, 0.0)
        tmp = tmp.dropna(subset=["price"])

        out = tmp.resample("1min").agg(
            {
                "size": "sum",
                "signed_size": "sum",
                "buy_size": "sum",
                "sell_size": "sum",
                "price": ["count", "mean"],
            }
        )
        out.columns = [
            "of_total_size",
            "of_signed_size",
            "of_buy_size",
            "of_sell_size",
            "of_trade_count",
            "of_trade_price_mean",
        ]
        out["of_flow_imbalance"] = out["of_signed_size"] / out["of_total_size"].replace(0, np.nan)
        out["of_flow_imbalance"] = out["of_flow_imbalance"].fillna(0.0)
        return out

    def fetch_mbp_1m_features(
        self,
        dataset: str,
        symbol: str,
        stype_in: str,
        start: str,
        end: str,
        large_lot_threshold: float,
        chunk_days: int = 7,
        session_start: Optional[str] = None,
        session_end: Optional[str] = None,
    ) -> pd.DataFrame:
        """
        Build 1-minute top-of-book depth features from Databento mbp-1.
        """
        if session_start and session_end:
            chunks = self._build_session_windows(start, end, session_start, session_end)
        else:
            chunks = self._build_date_chunks(start, end, chunk_days=chunk_days)
        parts: List[pd.DataFrame] = []
        for i, (s, e) in enumerate(chunks, start=1):
            print(f"  mbp-1 chunk {i}/{len(chunks)}: {s} -> {e}")
            data = self.client.timeseries.get_range(
                dataset=dataset,
                symbols=[symbol],
                schema="mbp-1",
                stype_in=stype_in,
                start=s,
                end=e,
            )
            raw = data.to_df()
            if raw is None or raw.empty:
                continue
            parts.append(raw)

        if not parts:
            return pd.DataFrame()

        df = pd.concat(parts, axis=0)
        if not isinstance(df.index, pd.DatetimeIndex):
            if "ts_event" in df.columns:
                df.index = pd.to_datetime(df["ts_event"], utc=True, errors="coerce")
            else:
                raise ValueError("mbp-1 dataset missing datetime index/ts_event")
        if df.index.tz is None:
            df.index = df.index.tz_localize("UTC")
        df.index = df.index.tz_convert("America/New_York")

        lower = {str(c).lower(): c for c in df.columns}
        bid_col = self._pick_column(lower, ["bid_sz_00", "bid_size_00", "bid_sz_0", "bid_size_0"])
        ask_col = self._pick_column(lower, ["ask_sz_00", "ask_size_00", "ask_sz_0", "ask_size_0"])
        if bid_col is None or ask_col is None:
            raise ValueError("mbp-1 schema missing top-level bid/ask size columns")

        tmp = pd.DataFrame(index=df.index)
        tmp["dom_bid_size"] = pd.to_numeric(df[bid_col], errors="coerce").fillna(0.0)
        tmp["dom_ask_size"] = pd.to_numeric(df[ask_col], errors="coerce").fillna(0.0)
        denom = (tmp["dom_bid_size"] + tmp["dom_ask_size"]).replace(0, np.nan)
        tmp["dom_imbalance"] = (tmp["dom_bid_size"] - tmp["dom_ask_size"]) / denom
        tmp["dom_imbalance"] = tmp["dom_imbalance"].fillna(0.0)
        tmp["dom_large_bid_hit"] = (tmp["dom_bid_size"] >= float(large_lot_threshold)).astype(int)
        tmp["dom_large_ask_hit"] = (tmp["dom_ask_size"] >= float(large_lot_threshold)).astype(int)

        out = tmp.resample("1min").agg(
            {
                "dom_bid_size": "mean",
                "dom_ask_size": "mean",
                "dom_imbalance": "mean",
                "dom_large_bid_hit": "sum",
                "dom_large_ask_hit": "sum",
            }
        )
        out["dom_absorption_score"] = (
            out["dom_large_ask_hit"] - out["dom_large_bid_hit"]
        ) / (out["dom_large_ask_hit"] + out["dom_large_bid_hit"] + 1.0)
        return out

    def build_and_save(
        self,
        dataset: str,
        primary_symbol: str,
        corr_symbol: str,
        output_symbol: str,
        stype_in: str,
        start: str,
        end: str,
        timeframe: str,
        large_lot_threshold: float,
        chunk_days: int,
        session_start: Optional[str] = None,
        session_end: Optional[str] = None,
        include_trades: bool = True,
        include_mbp: bool = True,
        out_filename: Optional[str] = None,
    ) -> Path:
        print(f"Fetching primary ohlcv-1m: {primary_symbol}")
        nqt = self.fetch_ohlcv_1m(dataset, primary_symbol, stype_in, start, end)
        print(f"  OK bars={len(nqt):,}")

        print(f"Fetching correlation ohlcv-1m: {corr_symbol}")
        est = self.fetch_ohlcv_1m(dataset, corr_symbol, stype_in, start, end)
        print(f"  OK bars={len(est):,}")

        if include_trades:
            print("Fetching trades features...")
            trades_1m = self.fetch_trades_1m_features(
                dataset=dataset,
                symbol=primary_symbol,
                stype_in=stype_in,
                start=start,
                end=end,
                chunk_days=chunk_days,
                session_start=session_start,
                session_end=session_end,
            )
            print(f"  OK trade-feature bars={len(trades_1m):,}")
        else:
            trades_1m = pd.DataFrame()
            print("Skipping trades features (--skip-trades).")

        if include_mbp:
            print("Fetching mbp-1 features...")
            mbp_1m = self.fetch_mbp_1m_features(
                dataset=dataset,
                symbol=primary_symbol,
                stype_in=stype_in,
                start=start,
                end=end,
                large_lot_threshold=large_lot_threshold,
                chunk_days=chunk_days,
                session_start=session_start,
                session_end=session_end,
            )
            print(f"  OK mbp-feature bars={len(mbp_1m):,}")
        else:
            mbp_1m = pd.DataFrame()
            print("Skipping mbp-1 features (--skip-mbp).")

        merged = nqt.copy()
        merged = merged.join(trades_1m, how="left")
        merged = merged.join(mbp_1m, how="left")

        corr = pd.DataFrame(index=est.index)
        corr["es_close"] = est["close"]
        corr["es_ret_5m"] = corr["es_close"].pct_change(periods=5)
        corr["es_ret_30m"] = corr["es_close"].pct_change(periods=30)
        merged = merged.join(corr, how="left")

        # Session filter to regular US cash hours.
        merged = merged.between_time("09:30", "16:00")
        merged = merged[merged.index.dayofweek < 5]

        # Fill sparse feature holes conservatively.
        for col in merged.columns:
            if col.startswith(("of_", "dom_", "es_")):
                merged[col] = pd.to_numeric(merged[col], errors="coerce").fillna(0.0)

        # LVA velocity proxy: normalized absolute return speed.
        ret1 = merged["close"].pct_change().fillna(0.0).abs()
        base = ret1.rolling(60, min_periods=10).mean().replace(0, np.nan)
        merged["lva_velocity"] = (ret1 / base).replace([np.inf, -np.inf], np.nan).fillna(0.0)

        if timeframe != "M1":
            merged = self._resample_enriched(merged, timeframe)

        # Persist in UTC with ts_event column.
        out = merged.copy()
        if out.index.tz is None:
            out.index = out.index.tz_localize("America/New_York")
        out.index = out.index.tz_convert("UTC")
        out = out.reset_index().rename(columns={"index": "ts_event"})
        out["ts_event"] = out["ts_event"].dt.strftime("%Y-%m-%dT%H:%M:%SZ")

        if out_filename is None:
            start_tag = pd.to_datetime(start).strftime("%Y%m%d")
            end_tag = pd.to_datetime(end).strftime("%Y%m%d")
            out_filename = f"{output_symbol}_{timeframe}_{start_tag}_{end_tag}_bprofile_enriched.csv"
        out_path = self.output_dir / out_filename
        out.to_csv(out_path, index=False)
        return out_path

    @staticmethod
    def _resample_enriched(df: pd.DataFrame, timeframe: str) -> pd.DataFrame:
        rule = TIMEFRAME_RULES.get(timeframe)
        if not rule:
            raise ValueError(f"Unsupported timeframe: {timeframe}")
        if timeframe == "M1":
            return df
        agg = {
            "open": "first",
            "high": "max",
            "low": "min",
            "close": "last",
            "volume": "sum",
            "of_total_size": "sum",
            "of_signed_size": "sum",
            "of_buy_size": "sum",
            "of_sell_size": "sum",
            "of_trade_count": "sum",
            "of_trade_price_mean": "mean",
            "dom_bid_size": "mean",
            "dom_ask_size": "mean",
            "dom_imbalance": "mean",
            "dom_large_bid_hit": "sum",
            "dom_large_ask_hit": "sum",
            "dom_absorption_score": "mean",
            "es_close": "last",
            "es_ret_5m": "last",
            "es_ret_30m": "last",
            "lva_velocity": "mean",
        }
        available = {k: v for k, v in agg.items() if k in df.columns}
        out = df.resample(rule).agg(available).dropna(subset=["open", "high", "low", "close"])

        # Recompute flow imbalance at target timeframe from summed flows.
        if "of_signed_size" in out.columns and "of_total_size" in out.columns:
            out["of_flow_imbalance"] = out["of_signed_size"] / out["of_total_size"].replace(0, np.nan)
            out["of_flow_imbalance"] = out["of_flow_imbalance"].fillna(0.0)
        return out

    @staticmethod
    def _build_date_chunks(start: str, end: str, chunk_days: int) -> List[Tuple[str, str]]:
        s = pd.to_datetime(start).normalize()
        e = pd.to_datetime(end).normalize() + pd.Timedelta(days=1)
        chunks: List[Tuple[str, str]] = []
        cur = s
        while cur < e:
            nxt = min(cur + pd.Timedelta(days=max(1, chunk_days)), e)
            chunks.append((cur.strftime("%Y-%m-%d"), nxt.strftime("%Y-%m-%d")))
            cur = nxt
        return chunks

    @staticmethod
    def _build_session_windows(
        start: str, end: str, session_start: str, session_end: str
    ) -> List[Tuple[str, str]]:
        """
        Build per-day request windows in NY time then convert to UTC ISO.

        This is useful to cap microstructure costs by requesting only the
        intraday window used by strategy execution (e.g., 10:00-13:00 NY).
        """
        ny = "America/New_York"
        s_day = pd.to_datetime(start).normalize()
        e_day = pd.to_datetime(end).normalize()
        ss = pd.to_datetime(session_start, format="%H:%M").time()
        se = pd.to_datetime(session_end, format="%H:%M").time()

        windows: List[Tuple[str, str]] = []
        day = s_day
        while day <= e_day:
            if day.dayofweek < 5:
                s_ny = pd.Timestamp.combine(day, dtime(ss.hour, ss.minute)).tz_localize(ny)
                e_ny = pd.Timestamp.combine(day, dtime(se.hour, se.minute)).tz_localize(ny)
                if e_ny > s_ny:
                    s_utc = s_ny.tz_convert("UTC").strftime("%Y-%m-%dT%H:%M:%SZ")
                    e_utc = e_ny.tz_convert("UTC").strftime("%Y-%m-%dT%H:%M:%SZ")
                    windows.append((s_utc, e_utc))
            day += pd.Timedelta(days=1)
        return windows

    @staticmethod
    def _pick_column(lower_map: Dict[str, str], candidates: Iterable[str]) -> Optional[str]:
        for c in candidates:
            if c in lower_map:
                return lower_map[c]
        return None

    @staticmethod
    def _infer_trade_sign(price: pd.Series, side: Optional[pd.Series]) -> np.ndarray:
        if side is not None:
            out = np.zeros(len(side), dtype=float)
            side_vals = side.astype(str).str.upper().to_numpy()
            for i, s in enumerate(side_vals):
                if s in ("B", "BUY", "1"):
                    out[i] = 1.0
                elif s in ("A", "S", "SELL", "-1"):
                    out[i] = -1.0
            if np.any(out != 0):
                return out

        # Tick-rule fallback.
        p = pd.to_numeric(price, errors="coerce").to_numpy(dtype=float)
        if len(p) == 0:
            return np.array([], dtype=float)
        dp = np.diff(p, prepend=p[0])
        sign = np.sign(dp)
        sign[sign == 0.0] = 1.0
        return sign


def _load_api_key() -> Optional[str]:
    load_dotenv(PROJECT_ROOT / "dashboard" / ".env")
    load_dotenv(PROJECT_ROOT / ".env")
    key = os.getenv("DATABENTO_API_KEY")
    if key:
        return key.strip()
    return None


def main() -> None:
    parser = argparse.ArgumentParser(description="Fetch Databento data for b-profile microstructure backtests.")
    parser.add_argument("--dataset", type=str, default="GLBX.MDP3")
    parser.add_argument("--primary", type=str, default="NQ.c.0", help="Primary symbol for trade logic")
    parser.add_argument("--correlation", type=str, default="ES.c.0", help="Correlation symbol")
    parser.add_argument("--stype-in", type=str, default="raw_symbol")
    parser.add_argument("--start", type=str, required=True, help="YYYY-MM-DD")
    parser.add_argument("--end", type=str, required=True, help="YYYY-MM-DD (inclusive)")
    parser.add_argument("--timeframe", type=str, default="M30", choices=list(TIMEFRAME_RULES.keys()))
    parser.add_argument("--output-symbol", type=str, default="NAS100", help="Output CSV symbol prefix")
    parser.add_argument("--output-file", type=str, default=None, help="Optional exact output filename")
    parser.add_argument("--large-lot-threshold", type=float, default=100.0)
    parser.add_argument("--chunk-days", type=int, default=7)
    parser.add_argument("--session-start", type=str, default=None, help="Optional NY session start HH:MM for trades/mbp requests")
    parser.add_argument("--session-end", type=str, default=None, help="Optional NY session end HH:MM for trades/mbp requests")
    parser.add_argument("--skip-trades", action="store_true", help="Skip trades schema fetch")
    parser.add_argument("--skip-mbp", action="store_true", help="Skip mbp-1 schema fetch")
    parser.add_argument("--cost-only", action="store_true", help="Only estimate cost, do not download data")
    args = parser.parse_args()

    if args.stype_in == "raw_symbol" and ".c." in str(args.primary).lower():
        print("WARN --stype-in raw_symbol with continuous symbol detected; switching to --stype-in continuous")
        args.stype_in = "continuous"

    api_key = _load_api_key()
    if not api_key:
        raise RuntimeError("DATABENTO_API_KEY not found in dashboard/.env or .env")

    fetcher = BProfileDatabentoFetcher(api_key=api_key)

    print("=" * 78)
    print("B-PROFILE DATABENTO FETCHER")
    print("=" * 78)
    print(f"Dataset:         {args.dataset}")
    print(f"Primary symbol:  {args.primary}")
    print(f"Corr symbol:     {args.correlation}")
    print(f"Date range:      {args.start} -> {args.end}")
    print(f"Target TF:       {args.timeframe}")
    print(f"Output symbol:   {args.output_symbol}")
    print("=" * 78)

    costs = fetcher.estimate_cost(
        dataset=args.dataset,
        primary_symbol=args.primary,
        corr_symbol=args.correlation,
        start=args.start,
        end=args.end,
        stype_in=args.stype_in,
        include_trades=not bool(args.skip_trades),
        include_mbp=not bool(args.skip_mbp),
    )
    total = 0.0
    print("Estimated cost:")
    for c in costs:
        val = c.estimated_usd
        total += (0.0 if math.isnan(val) else val)
        print(f"  {c.schema:9s} {c.symbols:10s} -> ${val:.2f}" if not math.isnan(val) else f"  {c.schema:9s} {c.symbols:10s} -> n/a")
    print(f"  TOTAL ESTIMATE -> ${total:.2f}")
    print("=" * 78)

    if args.cost_only:
        print("Cost-only mode complete.")
        return

    out_path = fetcher.build_and_save(
        dataset=args.dataset,
        primary_symbol=args.primary,
        corr_symbol=args.correlation,
        output_symbol=args.output_symbol,
        stype_in=args.stype_in,
        start=args.start,
        end=args.end,
        timeframe=args.timeframe,
        large_lot_threshold=float(args.large_lot_threshold),
        chunk_days=int(args.chunk_days),
        session_start=args.session_start,
        session_end=args.session_end,
        include_trades=not bool(args.skip_trades),
        include_mbp=not bool(args.skip_mbp),
        out_filename=args.output_file,
    )
    print(f"Saved: {out_path}")


if __name__ == "__main__":
    main()
