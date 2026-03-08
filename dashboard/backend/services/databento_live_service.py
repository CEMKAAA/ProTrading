"""
Databento live-like candle service for simulation dashboards.

Uses short-interval polling of Databento OHLCV data and returns chart bars
in a normalized format compatible with simulation/workbench live feeds.
"""

from __future__ import annotations

import os
import logging
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

import pandas as pd

try:
    import databento as db
except Exception:  # pragma: no cover - dependency/runtime availability
    db = None


logger = logging.getLogger(__name__)


SYMBOL_TO_DATABENTO: Dict[str, str] = {
    "XAUUSD": "GC.c.0",
    "NAS100": "NQ.c.0",
    "US500": "ES.c.0",
    "EURUSD": "6E.c.0",
    "GBPUSD": "6B.c.0",
}


TIMEFRAME_TO_MINUTES: Dict[str, int] = {
    "M1": 1,
    "M5": 5,
    "M15": 15,
    "M30": 30,
    "H1": 60,
    "H4": 240,
    "D1": 1440,
}


TIMEFRAME_TO_RULE: Dict[str, str] = {
    "M1": "1min",
    "M5": "5min",
    "M15": "15min",
    "M30": "30min",
    "H1": "1h",
    "H4": "4h",
    "D1": "1d",
}


class DatabentoLiveService:
    """Small polling service for Databento OHLCV bars."""

    _SHARED_CLIENTS: Dict[str, Any] = {}

    def __init__(
        self,
        api_key: Optional[str] = None,
        dataset: str = "GLBX.MDP3",
        stype_in: str = "continuous",
    ):
        self.api_key = str(api_key or os.getenv("DATABENTO_API_KEY", "")).strip()
        self.dataset = str(dataset or "GLBX.MDP3").strip()
        self.stype_in = str(stype_in or "continuous").strip()
        self._client = None
        self._bars_cache: Dict[str, Dict[str, Any]] = {}

    def _ensure_client(self):
        if db is None:
            raise RuntimeError("databento package is not installed")
        if not self.api_key:
            raise RuntimeError("Missing Databento API key")
        if self._client is None:
            cache_key = f"{self.api_key}|{self.dataset}|{self.stype_in}"
            if cache_key not in self._SHARED_CLIENTS:
                self._SHARED_CLIENTS[cache_key] = db.Historical(self.api_key)
            self._client = self._SHARED_CLIENTS[cache_key]
        return self._client

    @staticmethod
    def _resolve_symbol(symbol: str, db_symbol: Optional[str] = None) -> str:
        if db_symbol and str(db_symbol).strip():
            return str(db_symbol).strip()
        key = str(symbol or "").upper().strip()
        return SYMBOL_TO_DATABENTO.get(key, key or "NQ.c.0")

    @staticmethod
    def _normalize_ohlcv_df(raw_df: pd.DataFrame) -> pd.DataFrame:
        if raw_df is None or raw_df.empty:
            return pd.DataFrame()

        df = raw_df.copy()
        if not isinstance(df.index, pd.DatetimeIndex):
            if "ts_event" in df.columns:
                df.index = pd.to_datetime(df["ts_event"], utc=True, errors="coerce")
            else:
                return pd.DataFrame()
        if df.index.tz is None:
            df.index = df.index.tz_localize("UTC")
        else:
            df.index = df.index.tz_convert("UTC")

        out = pd.DataFrame(
            {
                "open": pd.to_numeric(df.get("open"), errors="coerce"),
                "high": pd.to_numeric(df.get("high"), errors="coerce"),
                "low": pd.to_numeric(df.get("low"), errors="coerce"),
                "close": pd.to_numeric(df.get("close"), errors="coerce"),
                "volume": pd.to_numeric(df.get("volume"), errors="coerce").fillna(0.0),
            },
            index=df.index,
        )
        out = out.dropna(subset=["open", "high", "low", "close"])
        out = out.sort_index()
        return out

    @staticmethod
    def _resample_to_timeframe(df: pd.DataFrame, timeframe: str) -> pd.DataFrame:
        tf = str(timeframe or "M1").upper()
        if tf == "M1":
            return df
        rule = TIMEFRAME_TO_RULE.get(tf)
        if not rule:
            return pd.DataFrame()
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

    def get_recent_candles(
        self,
        symbol: str = "NAS100",
        timeframe: str = "M1",
        count: int = 300,
        db_symbol: Optional[str] = None,
        lookback_minutes: Optional[int] = None,
        min_refresh_sec: float = 0.0,
    ) -> List[Dict[str, Any]]:
        cache_key = f"{symbol}|{timeframe}|{db_symbol or ''}|{count}|{lookback_minutes or 0}"
        now_utc = datetime.now(timezone.utc)
        if min_refresh_sec > 0:
            cached = self._bars_cache.get(cache_key)
            if cached is not None:
                age = (now_utc - cached.get("fetched_at", now_utc)).total_seconds()
                if age < float(min_refresh_sec):
                    bars = cached.get("bars") or []
                    if bars:
                        return bars[-max(1, min(int(count), 10000)) :]

        client = self._ensure_client()
        tf = str(timeframe or "M1").upper()
        tf_mins = TIMEFRAME_TO_MINUTES.get(tf, 1)
        # Fetch 1m bars and aggregate locally for higher TFs.
        if lookback_minutes is None:
            base = int(count) * max(1, tf_mins) + 40
            needed_base = max(120, min(20000, base))
        else:
            count_cap = max(1, min(int(count), 10000))
            required_from_count = count_cap * max(1, tf_mins) + 60
            max_lookback = max(4000, required_from_count, max(1, tf_mins) * 200)
            needed_base = max(30, min(int(lookback_minutes), int(max_lookback)))
        end_utc = now_utc
        start_utc = end_utc - timedelta(minutes=needed_base)
        resolved = self._resolve_symbol(symbol=symbol, db_symbol=db_symbol)

        data = client.timeseries.get_range(
            dataset=self.dataset,
            symbols=[resolved],
            schema="ohlcv-1m",
            stype_in=self.stype_in,
            start=start_utc.isoformat(),
            end=end_utc.isoformat(),
        )
        raw = data.to_df()
        norm = self._normalize_ohlcv_df(raw)
        if norm.empty:
            return []

        bars_df = self._resample_to_timeframe(norm, tf)
        if bars_df.empty:
            return []
        bars_df = bars_df.tail(max(1, min(int(count), 10000)))

        out: List[Dict[str, Any]] = []
        for ts, row in bars_df.iterrows():
            ts_utc = ts.tz_convert("UTC")
            unix_ts = int(ts_utc.timestamp())
            out.append(
                {
                    "time_unix": unix_ts,
                    "time": ts_utc.isoformat(),
                    "open": float(row["open"]),
                    "high": float(row["high"]),
                    "low": float(row["low"]),
                    "close": float(row["close"]),
                    "volume": int(float(row.get("volume", 0.0))),
                }
            )
        self._bars_cache[cache_key] = {"fetched_at": now_utc, "bars": out}
        return out

    def get_status(
        self,
        symbol: str = "NAS100",
        timeframe: str = "M1",
        db_symbol: Optional[str] = None,
    ) -> Dict[str, Any]:
        try:
            resolved = self._resolve_symbol(symbol=symbol, db_symbol=db_symbol)
            bars = self.get_recent_candles(
                symbol=symbol,
                timeframe=timeframe,
                count=3,
                db_symbol=db_symbol,
            )
            return {
                "ok": True,
                "connected": len(bars) > 0,
                "symbol": str(symbol or "").upper(),
                "resolved_symbol": resolved,
                "timeframe": str(timeframe or "").upper(),
                "dataset": self.dataset,
                "stype_in": self.stype_in,
                "latest_bar": bars[-1] if bars else None,
            }
        except Exception as exc:
            logger.warning("Databento status check failed: %s", exc)
            return {
                "ok": False,
                "connected": False,
                "symbol": str(symbol or "").upper(),
                "resolved_symbol": self._resolve_symbol(symbol=symbol, db_symbol=db_symbol),
                "timeframe": str(timeframe or "").upper(),
                "dataset": self.dataset,
                "stype_in": self.stype_in,
                "error": f"{type(exc).__name__}: {str(exc)}",
            }
