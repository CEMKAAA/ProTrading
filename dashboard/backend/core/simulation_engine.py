"""
Simulation Replay Engine
Replays historical data bar-by-bar, evaluating strategy steps and managing positions.
"""

import pandas as pd
import numpy as np
from pathlib import Path
from typing import Optional, Dict, List, Any
from datetime import datetime, timedelta
from collections import deque
import logging
import json

logger = logging.getLogger(__name__)

# Instrument specs for P&L calculation
INSTRUMENT_SPECS = {
    "XAUUSD": {"contract_size": 100, "pip_value": 0.01},
    "NAS100": {"contract_size": 1, "pip_value": 1.0},
    "US500": {"contract_size": 1, "pip_value": 1.0},
    "GBPUSD": {"contract_size": 100000, "pip_value": 0.0001},
    "EURUSD": {"contract_size": 100000, "pip_value": 0.0001},
    "USDJPY": {"contract_size": 100000, "pip_value": 0.01},
}


class SimulationReplayEngine:
    """Replays historical data bar-by-bar, evaluating strategy steps."""

    def __init__(self, strategy_id: str, symbol: str, timeframe: str,
                 data_file: Optional[str] = None, config: Optional[dict] = None):
        self.strategy_id = strategy_id
        self.symbol = symbol.upper()
        self.timeframe = timeframe.upper()
        self.config = config or {}
        self.current_bar = 0
        self.balance = self.config.get("initial_balance", 10000.0)
        self.open_positions: List[Dict] = []
        self.closed_trades: List[Dict] = []
        self.day_context = None
        self.current_date = None
        self._indicators_cache: Dict[str, Any] = {}
        self._indicator_offsets: Dict[str, int] = {}
        self._has_streamed_bar = False
        self._incremental_runtime: Dict[str, Any] = {}
        self._strategy = None
        self._strategy_available = False

        # Load data
        self.df = self._load_data(data_file)
        self.total_bars = len(self.df) if self.df is not None else 0

        # Try to create strategy instance
        try:
            from dashboard.backend.core.strategies.factory import create_strategy
            self._strategy = create_strategy(strategy_id, self.config)
            if self._strategy is not None:
                self._strategy_available = True
                logger.info(f"Strategy {strategy_id} loaded for simulation")
        except Exception as e:
            logger.warning(f"Could not load strategy {strategy_id}: {e}")

        # Build daily DataFrame for initialize_day
        if self.df is not None and not self.df.empty:
            self._daily_df = self.df.resample("D").agg({
                "open": "first", "high": "max", "low": "min",
                "close": "last", "volume": "sum"
            }).dropna(subset=["open"])
        else:
            self._daily_df = pd.DataFrame()

    def _load_data(self, data_file: Optional[str]) -> Optional[pd.DataFrame]:
        """Load CSV data into DataFrame."""
        data_dir = Path(__file__).resolve().parents[2] / "data" / "historical"

        if data_file:
            # Try exact path first, then under data_dir
            candidates = [Path(data_file)]
            if not candidates[0].is_absolute():
                candidates = [data_dir / data_file]
            for p in candidates:
                if p.exists():
                    df = self._parse_csv(p)
                    return self._maybe_resample(df, p.name)
            logger.warning(f"Data file not found: {data_file}")

        # Auto-discover matching CSV
        if data_dir.exists():
            pattern = f"{self.symbol}_{self.timeframe}_*.csv"
            matches = sorted(data_dir.glob(pattern), key=lambda p: p.stat().st_mtime, reverse=True)
            if not matches:
                # Try M1 data for resampling
                m1_pattern = f"{self.symbol}_M1_*.csv"
                matches = sorted(data_dir.glob(m1_pattern), key=lambda p: p.stat().st_mtime, reverse=True)
            if matches:
                df = self._parse_csv(matches[0])
                if df is not None:
                    df = self._maybe_resample(df, matches[0].name)
                    logger.info(f"Auto-loaded: {matches[0].name} ({len(df)} bars)")
                return df

        logger.warning(f"No CSV data found for {self.symbol}_{self.timeframe}")
        return pd.DataFrame()

    def _parse_csv(self, path: Path) -> Optional[pd.DataFrame]:
        """Parse a CSV file into a DataFrame with DatetimeIndex."""
        try:
            # sep=None lets pandas infer comma/tab/semicolon (Dukascopy is tab-delimited).
            df = pd.read_csv(path, sep=None, engine="python")
            # Normalize column names
            df.columns = [c.strip().lower() for c in df.columns]

            # Support both single datetime columns and split Date+Time columns.
            datetime_series: Optional[pd.Series] = None
            drop_cols: List[str] = []
            if "date" in df.columns and "time" in df.columns:
                dt_text = df["date"].astype(str).str.strip() + " " + df["time"].astype(str).str.strip()
                datetime_series = pd.to_datetime(dt_text, format="%Y.%m.%d %H:%M", errors="coerce", utc=True)
                if datetime_series.isna().all():
                    datetime_series = pd.to_datetime(dt_text, errors="coerce", utc=True)
                drop_cols = ["date", "time"]
            else:
                time_col = None
                for candidate in ["ts_event", "datetime", "timestamp", "time", "date"]:
                    if candidate in df.columns:
                        time_col = candidate
                        break
                if time_col is None and len(df.columns) > 0:
                    time_col = df.columns[0]
                if time_col is None:
                    logger.error(f"No datetime column found in {path.name}")
                    return None
                datetime_series = pd.to_datetime(df[time_col], errors="coerce", utc=True)
                drop_cols = [time_col]

            if datetime_series is None or datetime_series.isna().all():
                logger.error(f"Could not parse datetimes in {path.name}")
                return None
            if getattr(datetime_series.dt, "tz", None) is not None:
                datetime_series = datetime_series.dt.tz_convert(None)

            df.insert(0, "_dt", datetime_series)
            for c in drop_cols:
                if c in df.columns:
                    df.drop(columns=[c], inplace=True)
            df.set_index("_dt", inplace=True)
            df.sort_index(inplace=True)
            df = df[~df.index.isna()]
            df = df[~df.index.duplicated(keep="first")]

            # Ensure required columns
            required = ["open", "high", "low", "close"]
            for col in required:
                if col not in df.columns:
                    logger.error(f"Missing column '{col}' in {path.name}")
                    return None

            # Coerce numeric columns
            for col in required + ["volume", "tickvolume", "tick_volume"]:
                if col in df.columns:
                    df[col] = pd.to_numeric(df[col], errors="coerce")

            if "volume" not in df.columns:
                # Dukascopy uses Tickvolume, keep that as volume proxy.
                if "tickvolume" in df.columns:
                    df["volume"] = df["tickvolume"].fillna(0)
                elif "tick_volume" in df.columns:
                    df["volume"] = df["tick_volume"].fillna(0)
                else:
                    df["volume"] = 0
            elif df["volume"].fillna(0).eq(0).all():
                if "tickvolume" in df.columns:
                    df["volume"] = df["tickvolume"].fillna(0)
                elif "tick_volume" in df.columns:
                    df["volume"] = df["tick_volume"].fillna(0)

            # Drop any rows with NaN in OHLC
            df.dropna(subset=required, inplace=True)

            return df
        except Exception as e:
            logger.error(f"Failed to parse CSV {path}: {e}")
            return None

    def _maybe_resample(self, df: Optional[pd.DataFrame], source_name: str) -> pd.DataFrame:
        """Resample M1 fallback data to the requested timeframe when needed."""
        if df is None:
            return pd.DataFrame()
        if df.empty or self.timeframe == "M1":
            return df
        upper_name = source_name.upper()
        if f"_{self.timeframe}_" in upper_name:
            return df
        if "_M1_" not in upper_name:
            return df

        rules = {
            "M5": "5min",
            "M15": "15min",
            "M30": "30min",
            "H1": "1h",
        }
        rule = rules.get(self.timeframe)
        if not rule:
            return df

        resampled = df.resample(rule).agg(
            {
                "open": "first",
                "high": "max",
                "low": "min",
                "close": "last",
                "volume": "sum",
            }
        )
        resampled.dropna(subset=["open", "high", "low", "close"], inplace=True)
        return resampled

    def advance_to_bar(self, target_bar: int) -> dict:
        """Advance to target bar. Returns bars, indicators, steps, trade updates."""
        if self.df is None or self.df.empty:
            return {"error": "No data loaded", "bars": [], "steps": [], "indicators": {}}

        target_bar = min(target_bar, self.total_bars - 1)
        target_bar = max(target_bar, 0)

        new_bars = []
        trade_updates = []

        start_idx = self.current_bar + (1 if self._has_streamed_bar else 0)
        for i in range(start_idx, target_bar + 1):
            if i >= self.total_bars:
                break

            bar = self.df.iloc[i]
            bar_date = self.df.index[i]

            # Check for new trading day
            day_date = bar_date.date() if hasattr(bar_date, "date") else bar_date
            if day_date != self.current_date and self._strategy_available:
                self.current_date = day_date
                try:
                    daily_slice = self._daily_df[self._daily_df.index.date <= day_date]
                    intraday_slice = self.df.iloc[:i] if i > 0 else self.df.iloc[:1]
                    self.day_context = self._strategy.initialize_day(
                        day_date, daily_slice, intraday_slice
                    )
                except Exception as e:
                    logger.debug(f"initialize_day failed for {day_date}: {e}")

            # Check open positions for SL/TP
            closed_this_bar = self._check_positions(bar, i)
            trade_updates.extend(closed_this_bar)

            # Collect bar data for frontend
            new_bars.append({
                "time": int(bar_date.timestamp()) if hasattr(bar_date, "timestamp") else 0,
                "open": float(bar["open"]),
                "high": float(bar["high"]),
                "low": float(bar["low"]),
                "close": float(bar["close"]),
                "volume": float(bar.get("volume", 0)),
            })

        self.current_bar = target_bar
        if new_bars:
            self._has_streamed_bar = True

        # Compute indicators for current state
        indicators = self._compute_indicators()
        indicators_delta = self._compute_indicator_delta(indicators)

        # Evaluate step conditions
        steps = self._evaluate_steps(indicators=indicators)

        # Get strategy suggestion
        suggestion = self._get_strategy_suggestion()

        # Compute chart overlays
        overlays = self._get_chart_overlays()

        # Open position P&L
        open_pnl = self._compute_open_pnl()

        return {
            "bars": new_bars,
            "current_bar": self.current_bar,
            "total_bars": self.total_bars,
            "indicators": indicators,
            "indicators_delta": indicators_delta,
            "steps": steps,
            "overlays": overlays,
            "suggestion": suggestion,
            "closed_trades": trade_updates,
            "open_positions": self.open_positions,
            "open_pnl": open_pnl,
            "balance": self.balance,
            "day_context": {
                "bias": self.day_context.bias if self.day_context else "neutral",
                "bias_strength": self.day_context.bias_strength if self.day_context else 0,
                "atr": self.day_context.atr if self.day_context else 0,
                "levels": self.day_context.levels if self.day_context else {},
            } if self.day_context else None,
        }

    def _compute_indicator_delta(self, indicators: Dict[str, Any]) -> Dict[str, Any]:
        """Return only newly-added indicator points since last emission."""
        delta: Dict[str, Any] = {}
        for key, value in indicators.items():
            if not isinstance(value, list):
                delta[key] = value
                continue
            prev = int(self._indicator_offsets.get(key, 0))
            if prev < 0:
                prev = 0
            if prev > len(value):
                prev = 0
            piece = value[prev:]
            self._indicator_offsets[key] = len(value)
            if piece:
                delta[key] = piece
        return delta

    def _check_positions(self, bar, bar_idx: int) -> List[Dict]:
        """Check if any open position hit SL/TP on this bar."""
        closed = []
        remaining = []

        for pos in self.open_positions:
            hit = None
            exit_price = None
            stop_loss = pos.get("stop_loss")
            stop_enabled = stop_loss is not None and np.isfinite(float(stop_loss)) and float(stop_loss) > 0.0
            take_profit = pos.get("take_profit")
            tp_enabled = take_profit is not None and np.isfinite(float(take_profit)) and float(take_profit) > 0.0

            if pos["direction"] == "BUY":
                if stop_enabled and bar["low"] <= float(stop_loss):
                    hit = "SL"
                    exit_price = float(stop_loss)
                elif tp_enabled and bar["high"] >= float(take_profit):
                    hit = "TP"
                    exit_price = float(take_profit)
            else:  # SELL
                if stop_enabled and bar["high"] >= float(stop_loss):
                    hit = "SL"
                    exit_price = float(stop_loss)
                elif tp_enabled and bar["low"] <= float(take_profit):
                    hit = "TP"
                    exit_price = float(take_profit)

            if hit:
                pnl = self._calculate_pnl(pos, exit_price)
                r_mult = self._calculate_r_multiple(pos, exit_price)
                self.balance += pnl

                bar_time = self.df.index[bar_idx]
                trade_record = {
                    "id": pos.get("id"),
                    "direction": pos["direction"],
                    "entry_price": pos["entry_price"],
                    "exit_price": exit_price,
                    "exit_bar": bar_idx,
                    "exit_time": str(bar_time),
                    "exit_reason": hit,
                    "pnl": round(pnl, 2),
                    "r_multiple": round(r_mult, 2),
                    "lot_size": pos.get("lot_size", 0.01),
                }
                closed.append(trade_record)
                self.closed_trades.append(trade_record)
            else:
                remaining.append(pos)

        self.open_positions = remaining
        return closed

    def _calculate_pnl(self, pos: dict, exit_price: float) -> float:
        """Calculate P&L for a trade."""
        specs = INSTRUMENT_SPECS.get(self.symbol, {"contract_size": 100, "pip_value": 0.01})
        lot_size = pos.get("lot_size", 0.01)
        price_diff = exit_price - pos["entry_price"]
        if pos["direction"] == "SELL":
            price_diff = -price_diff
        return price_diff * lot_size * specs["contract_size"]

    def _calculate_r_multiple(self, pos: dict, exit_price: float) -> float:
        """Calculate R-multiple for a trade."""
        stop_loss = pos.get("stop_loss")
        if stop_loss is None or (not np.isfinite(float(stop_loss))) or float(stop_loss) <= 0.0:
            return 0
        risk = abs(pos["entry_price"] - float(stop_loss))
        if risk == 0:
            return 0
        price_diff = exit_price - pos["entry_price"]
        if pos["direction"] == "SELL":
            price_diff = -price_diff
        return price_diff / risk

    def execute_trade(
        self,
        direction: str,
        sl: float,
        tp: Optional[float],
        lot_size: float = 0.01,
        entry_price_override: Optional[float] = None,
        entry_time_unix: Optional[int] = None,
    ) -> dict:
        """Record a user's manual trade."""
        use_override = entry_price_override is not None and np.isfinite(float(entry_price_override))
        if (self.df is None or self.df.empty or self.current_bar >= self.total_bars) and not use_override:
            raise ValueError("No data available for trade")

        if use_override:
            entry_price = float(entry_price_override)
            if entry_time_unix is not None:
                bar_time = datetime.utcfromtimestamp(int(entry_time_unix))
            elif self.df is not None and not self.df.empty and self.current_bar < self.total_bars:
                bar_time = self.df.index[self.current_bar]
            else:
                bar_time = datetime.utcnow()
        else:
            bar = self.df.iloc[self.current_bar]
            entry_price = float(bar["close"])  # Enter at current bar close
            bar_time = self.df.index[self.current_bar]

        pos = {
            "id": None,  # Will be set by caller after DB insert
            "direction": direction,
            "entry_price": entry_price,
            "entry_bar": self.current_bar,
            "entry_time": str(bar_time),
            "stop_loss": sl,
            "take_profit": tp,
            "lot_size": lot_size,
        }
        self.open_positions.append(pos)

        return {
            "entry_price": entry_price,
            "entry_bar": self.current_bar,
            "entry_time": str(bar_time),
        }

    def close_position(
        self,
        trade_id: int,
        exit_price_override: Optional[float] = None,
        exit_time_unix: Optional[int] = None,
    ) -> dict:
        """Manually close a position by trade_id."""
        use_override = exit_price_override is not None and np.isfinite(float(exit_price_override))
        if (self.df is None or self.df.empty or self.current_bar >= self.total_bars) and not use_override:
            raise ValueError("No data available for close")

        if use_override:
            exit_price = float(exit_price_override)
            if exit_time_unix is not None:
                bar_time = datetime.utcfromtimestamp(int(exit_time_unix))
            elif self.df is not None and not self.df.empty and self.current_bar < self.total_bars:
                bar_time = self.df.index[self.current_bar]
            else:
                bar_time = datetime.utcnow()
        else:
            bar = self.df.iloc[self.current_bar]
            exit_price = float(bar["close"])
            bar_time = self.df.index[self.current_bar]

        for i, pos in enumerate(self.open_positions):
            if pos.get("id") == trade_id:
                pnl = self._calculate_pnl(pos, exit_price)
                r_mult = self._calculate_r_multiple(pos, exit_price)
                self.balance += pnl

                record = {
                    "id": trade_id,
                    "direction": pos["direction"],
                    "entry_price": pos["entry_price"],
                    "exit_price": exit_price,
                    "exit_bar": self.current_bar,
                    "exit_time": str(bar_time),
                    "exit_reason": "manual",
                    "pnl": round(pnl, 2),
                    "r_multiple": round(r_mult, 2),
                }
                self.closed_trades.append(record)
                self.open_positions.pop(i)
                return record

        raise ValueError(f"Position {trade_id} not found")

    def _compute_indicators(self) -> dict:
        """Calculate indicators for chart overlay based on strategy type."""
        if self.df is None or self.df.empty or self.current_bar < 1:
            return {}
        cached_bar = self._indicators_cache.get("bar")
        if cached_bar == self.current_bar and isinstance(self._indicators_cache.get("result"), dict):
            return self._indicators_cache["result"]

        df = self.df.iloc[:self.current_bar + 1]
        close = df["close"]
        result = {}

        try:
            sid = self.strategy_id
            if sid in ("keltner_breakout_strategy", "macd_ema_strategy"):
                result = self._compute_indicators_incremental(sid)
                self._indicators_cache = {"bar": self.current_bar, "result": result}
                return result

            # Common indicators
            if len(close) >= 20:
                result["sma_20"] = self._series_to_list(close.rolling(20).mean())

            if sid in ("orb_strategy", "advanced_orb_strategy", "orb_ml_strategy", "advanced_orb_ml_strategy"):
                result.update(self._compute_orb_indicators(df))

            elif sid == "macd_ema_strategy":
                result.update(self._compute_macd_indicators(df))

            elif sid == "basso_strategy":
                result.update(self._compute_basso_indicators(df))

            elif sid == "confluence_zone_strategy":
                result.update(self._compute_confluence_indicators(df))

            elif sid == "liquidity_sweep_strategy":
                result.update(self._compute_liquidity_indicators(df))

            elif sid == "vwap_reversion_strategy":
                result.update(self._compute_vwap_indicators(df))

            elif sid == "keltner_breakout_strategy":
                result.update(self._compute_keltner_indicators(df))

            elif sid == "bb_squeeze_strategy":
                result.update(self._compute_bb_indicators(df))

        except Exception as e:
            logger.debug(f"Indicator computation error: {e}")

        self._indicators_cache = {"bar": self.current_bar, "result": result}
        return result

    def _new_incremental_series(self) -> Dict[str, Any]:
        return {
            "sma_20": [],
            "ema_9": [],
            "ema_21": [],
            "ema_50": [],
            "ema_200": [],
            "macd_line": [],
            "macd_signal": [],
            "macd_histogram": [],
            "kc_upper": [],
            "kc_lower": [],
            "kc_mid": [],
            "bb_upper": [],
            "bb_lower": [],
            "roc": [],
            "adx": [],
            "squeeze": [],
        }

    def _reset_incremental_runtime(self, sid: str) -> Dict[str, Any]:
        runtime = {
            "sid": sid,
            "last_bar": -1,
            "series": self._new_incremental_series(),
            "close_win20": deque(maxlen=20),
            "close_win13": deque(maxlen=13),
            "ema9": None,
            "ema21": None,
            "ema50": None,
            "ema200": None,
            "ema12": None,
            "ema26": None,
            "macd_signal": None,
            "ema20": None,
            "atr10": None,
            "atr14": None,
            "plus_dm_ema14": None,
            "minus_dm_ema14": None,
            "adx14": None,
            "prev_close": None,
            "prev_high": None,
            "prev_low": None,
        }
        self._incremental_runtime = runtime
        return runtime

    @staticmethod
    def _append_point(series: List[Dict[str, Any]], ts: int, value: Optional[float]) -> None:
        if value is None:
            return
        if not np.isfinite(value):
            return
        series.append({"time": ts, "value": round(float(value), 5)})

    def _compute_indicators_incremental(self, sid: str) -> Dict[str, Any]:
        runtime = self._incremental_runtime
        if not runtime or runtime.get("sid") != sid:
            runtime = self._reset_incremental_runtime(sid)
        if self.current_bar < runtime.get("last_bar", -1):
            runtime = self._reset_incremental_runtime(sid)

        start = int(runtime.get("last_bar", -1)) + 1
        end = self.current_bar
        if start < 0:
            start = 0

        alpha9 = 2.0 / (9 + 1)
        alpha10 = 2.0 / (10 + 1)
        alpha12 = 2.0 / (12 + 1)
        alpha14 = 2.0 / (14 + 1)
        alpha20 = 2.0 / (20 + 1)
        alpha21 = 2.0 / (21 + 1)
        alpha26 = 2.0 / (26 + 1)
        alpha50 = 2.0 / (50 + 1)
        alpha200 = 2.0 / (200 + 1)

        for i in range(start, end + 1):
            row = self.df.iloc[i]
            ts_idx = self.df.index[i]
            ts = int(ts_idx.timestamp()) if hasattr(ts_idx, "timestamp") else 0
            c = float(row["close"])
            h = float(row["high"])
            l = float(row["low"])

            prev_close = runtime.get("prev_close")
            prev_high = runtime.get("prev_high")
            prev_low = runtime.get("prev_low")

            # Common windows
            runtime["close_win20"].append(c)
            runtime["close_win13"].append(c)
            if len(runtime["close_win20"]) == 20:
                arr20 = np.array(runtime["close_win20"], dtype=float)
                sma20 = float(arr20.mean())
                self._append_point(runtime["series"]["sma_20"], ts, sma20)

            if sid == "macd_ema_strategy":
                # EMA stack
                runtime["ema9"] = c if runtime["ema9"] is None else (alpha9 * c + (1.0 - alpha9) * runtime["ema9"])
                runtime["ema21"] = c if runtime["ema21"] is None else (alpha21 * c + (1.0 - alpha21) * runtime["ema21"])
                runtime["ema50"] = c if runtime["ema50"] is None else (alpha50 * c + (1.0 - alpha50) * runtime["ema50"])
                runtime["ema200"] = c if runtime["ema200"] is None else (alpha200 * c + (1.0 - alpha200) * runtime["ema200"])
                self._append_point(runtime["series"]["ema_9"], ts, runtime["ema9"])
                self._append_point(runtime["series"]["ema_21"], ts, runtime["ema21"])
                self._append_point(runtime["series"]["ema_50"], ts, runtime["ema50"])
                self._append_point(runtime["series"]["ema_200"], ts, runtime["ema200"])

                # MACD
                runtime["ema12"] = c if runtime["ema12"] is None else (alpha12 * c + (1.0 - alpha12) * runtime["ema12"])
                runtime["ema26"] = c if runtime["ema26"] is None else (alpha26 * c + (1.0 - alpha26) * runtime["ema26"])
                macd_line = runtime["ema12"] - runtime["ema26"]
                runtime["macd_signal"] = (
                    macd_line if runtime["macd_signal"] is None
                    else (alpha9 * macd_line + (1.0 - alpha9) * runtime["macd_signal"])
                )
                macd_hist = macd_line - runtime["macd_signal"]
                self._append_point(runtime["series"]["macd_line"], ts, macd_line)
                self._append_point(runtime["series"]["macd_signal"], ts, runtime["macd_signal"])
                self._append_point(runtime["series"]["macd_histogram"], ts, macd_hist)

                # ADX (shared)
                tr = (h - l) if prev_close is None else max(h - l, abs(h - prev_close), abs(l - prev_close))
                plus_dm = 0.0
                minus_dm = 0.0
                if prev_high is not None and prev_low is not None:
                    plus_dm = h - prev_high
                    minus_dm = prev_low - l
                    plus_dm = plus_dm if plus_dm > 0 else 0.0
                    minus_dm = minus_dm if minus_dm > 0 else 0.0
                    if plus_dm <= minus_dm:
                        plus_dm = 0.0
                    if minus_dm <= plus_dm:
                        minus_dm = 0.0

                runtime["atr14"] = tr if runtime["atr14"] is None else (alpha14 * tr + (1.0 - alpha14) * runtime["atr14"])
                runtime["plus_dm_ema14"] = plus_dm if runtime["plus_dm_ema14"] is None else (alpha14 * plus_dm + (1.0 - alpha14) * runtime["plus_dm_ema14"])
                runtime["minus_dm_ema14"] = minus_dm if runtime["minus_dm_ema14"] is None else (alpha14 * minus_dm + (1.0 - alpha14) * runtime["minus_dm_ema14"])
                atr14 = runtime["atr14"]
                adx_val = None
                if atr14 and atr14 > 1e-12:
                    plus_di = 100.0 * runtime["plus_dm_ema14"] / atr14
                    minus_di = 100.0 * runtime["minus_dm_ema14"] / atr14
                    denom = plus_di + minus_di
                    if denom > 1e-12:
                        dx = abs(plus_di - minus_di) / denom * 100.0
                        runtime["adx14"] = dx if runtime["adx14"] is None else (alpha14 * dx + (1.0 - alpha14) * runtime["adx14"])
                        adx_val = runtime["adx14"]
                self._append_point(runtime["series"]["adx"], ts, adx_val)

            elif sid == "keltner_breakout_strategy":
                # EMA20 + ATR10 => KC
                runtime["ema20"] = c if runtime["ema20"] is None else (alpha20 * c + (1.0 - alpha20) * runtime["ema20"])
                tr10 = (h - l) if prev_close is None else max(h - l, abs(h - prev_close), abs(l - prev_close))
                runtime["atr10"] = tr10 if runtime["atr10"] is None else (alpha10 * tr10 + (1.0 - alpha10) * runtime["atr10"])
                ema20 = runtime["ema20"]
                atr10 = runtime["atr10"]
                kc_upper = ema20 + 1.5 * atr10
                kc_lower = ema20 - 1.5 * atr10
                self._append_point(runtime["series"]["kc_mid"], ts, ema20)
                self._append_point(runtime["series"]["kc_upper"], ts, kc_upper)
                self._append_point(runtime["series"]["kc_lower"], ts, kc_lower)

                bb_upper = None
                bb_lower = None
                if len(runtime["close_win20"]) == 20:
                    arr20 = np.array(runtime["close_win20"], dtype=float)
                    sma20 = float(arr20.mean())
                    std20 = float(arr20.std(ddof=1))
                    bb_upper = sma20 + 2.0 * std20
                    bb_lower = sma20 - 2.0 * std20
                    self._append_point(runtime["series"]["bb_upper"], ts, bb_upper)
                    self._append_point(runtime["series"]["bb_lower"], ts, bb_lower)

                # squeeze marker should be index-aligned with bars
                if bb_upper is None or bb_lower is None:
                    runtime["series"]["squeeze"].append(False)
                else:
                    runtime["series"]["squeeze"].append(bool(bb_lower > kc_lower and bb_upper < kc_upper))

                # ROC12
                if len(runtime["close_win13"]) == 13:
                    base = float(runtime["close_win13"][0])
                    roc = ((c - base) / base * 100.0) if abs(base) > 1e-12 else np.nan
                    self._append_point(runtime["series"]["roc"], ts, roc)

                # ADX14
                tr14 = (h - l) if prev_close is None else max(h - l, abs(h - prev_close), abs(l - prev_close))
                plus_dm = 0.0
                minus_dm = 0.0
                if prev_high is not None and prev_low is not None:
                    plus_dm = h - prev_high
                    minus_dm = prev_low - l
                    plus_dm = plus_dm if plus_dm > 0 else 0.0
                    minus_dm = minus_dm if minus_dm > 0 else 0.0
                    if plus_dm <= minus_dm:
                        plus_dm = 0.0
                    if minus_dm <= plus_dm:
                        minus_dm = 0.0

                runtime["atr14"] = tr14 if runtime["atr14"] is None else (alpha14 * tr14 + (1.0 - alpha14) * runtime["atr14"])
                runtime["plus_dm_ema14"] = plus_dm if runtime["plus_dm_ema14"] is None else (alpha14 * plus_dm + (1.0 - alpha14) * runtime["plus_dm_ema14"])
                runtime["minus_dm_ema14"] = minus_dm if runtime["minus_dm_ema14"] is None else (alpha14 * minus_dm + (1.0 - alpha14) * runtime["minus_dm_ema14"])
                atr14 = runtime["atr14"]
                adx_val = None
                if atr14 and atr14 > 1e-12:
                    plus_di = 100.0 * runtime["plus_dm_ema14"] / atr14
                    minus_di = 100.0 * runtime["minus_dm_ema14"] / atr14
                    denom = plus_di + minus_di
                    if denom > 1e-12:
                        dx = abs(plus_di - minus_di) / denom * 100.0
                        runtime["adx14"] = dx if runtime["adx14"] is None else (alpha14 * dx + (1.0 - alpha14) * runtime["adx14"])
                        adx_val = runtime["adx14"]
                self._append_point(runtime["series"]["adx"], ts, adx_val)

            runtime["prev_close"] = c
            runtime["prev_high"] = h
            runtime["prev_low"] = l

        runtime["last_bar"] = end

        # Build strategy-specific result contract
        if sid == "macd_ema_strategy":
            return {
                "sma_20": runtime["series"]["sma_20"],
                "ema_9": runtime["series"]["ema_9"],
                "ema_21": runtime["series"]["ema_21"],
                "ema_50": runtime["series"]["ema_50"],
                "ema_200": runtime["series"]["ema_200"],
                "macd_line": runtime["series"]["macd_line"],
                "macd_signal": runtime["series"]["macd_signal"],
                "macd_histogram": runtime["series"]["macd_histogram"],
                "adx": runtime["series"]["adx"],
            }

        return {
            "sma_20": runtime["series"]["sma_20"],
            "kc_upper": runtime["series"]["kc_upper"],
            "kc_lower": runtime["series"]["kc_lower"],
            "kc_mid": runtime["series"]["kc_mid"],
            "bb_upper": runtime["series"]["bb_upper"],
            "bb_lower": runtime["series"]["bb_lower"],
            "squeeze": runtime["series"]["squeeze"],
            "roc": runtime["series"]["roc"],
            "adx": runtime["series"]["adx"],
        }

    def _compute_orb_indicators(self, df: pd.DataFrame) -> dict:
        """ORB strategy: session levels, ORB range."""
        result = {}
        # Get session levels from day_context
        if self.day_context and self.day_context.levels:
            lvls = self.day_context.levels
            levels = {}
            for key in ["asian_high", "asian_low", "pd_high", "pd_low",
                        "london_high", "london_low", "orb_high", "orb_low"]:
                if key in lvls and lvls[key] is not None:
                    levels[key] = float(lvls[key])
            result["session_levels"] = levels
        return result

    def _compute_macd_indicators(self, df: pd.DataFrame) -> dict:
        """MACD+EMA: EMA lines, MACD histogram, ADX."""
        close = df["close"]
        result = {}
        if len(close) >= 200:
            result["ema_9"] = self._series_to_list(close.ewm(span=9, adjust=False).mean())
            result["ema_21"] = self._series_to_list(close.ewm(span=21, adjust=False).mean())
            result["ema_50"] = self._series_to_list(close.ewm(span=50, adjust=False).mean())
            result["ema_200"] = self._series_to_list(close.ewm(span=200, adjust=False).mean())
        elif len(close) >= 50:
            result["ema_9"] = self._series_to_list(close.ewm(span=9, adjust=False).mean())
            result["ema_21"] = self._series_to_list(close.ewm(span=21, adjust=False).mean())
            result["ema_50"] = self._series_to_list(close.ewm(span=50, adjust=False).mean())

        if len(close) >= 26:
            ema12 = close.ewm(span=12, adjust=False).mean()
            ema26 = close.ewm(span=26, adjust=False).mean()
            macd_line = ema12 - ema26
            signal = macd_line.ewm(span=9, adjust=False).mean()
            histogram = macd_line - signal
            result["macd_line"] = self._series_to_list(macd_line)
            result["macd_signal"] = self._series_to_list(signal)
            result["macd_histogram"] = self._series_to_list(histogram)

        adx = self._compute_adx(df, 14)
        if adx is not None:
            result["adx"] = self._series_to_list(adx)
        return result

    def _compute_basso_indicators(self, df: pd.DataFrame) -> dict:
        """Basso: SMA20, overextension bands, RSI."""
        close = df["close"]
        result = {}
        if len(close) >= 20:
            sma = close.rolling(20).mean()
            atr = self._compute_atr_series(df, 14)
            result["sma_20"] = self._series_to_list(sma)
            if atr is not None:
                result["upper_band"] = self._series_to_list(sma + 2 * atr)
                result["lower_band"] = self._series_to_list(sma - 2 * atr)

        rsi = self._compute_rsi(close, 14)
        if rsi is not None:
            result["rsi"] = self._series_to_list(rsi)
        return result

    def _compute_confluence_indicators(self, df: pd.DataFrame) -> dict:
        """Confluence Zone: EMA50/200, session levels."""
        close = df["close"]
        result = {}
        if len(close) >= 200:
            result["ema_50"] = self._series_to_list(close.ewm(span=50, adjust=False).mean())
            result["ema_200"] = self._series_to_list(close.ewm(span=200, adjust=False).mean())
        elif len(close) >= 50:
            result["ema_50"] = self._series_to_list(close.ewm(span=50, adjust=False).mean())

        if self.day_context and self.day_context.levels:
            result["session_levels"] = {
                k: float(v) for k, v in self.day_context.levels.items()
                if v is not None
            }
        return result

    def _compute_liquidity_indicators(self, df: pd.DataFrame) -> dict:
        """Liquidity Sweep: session levels."""
        result = {}
        if self.day_context and self.day_context.levels:
            result["session_levels"] = {
                k: float(v) for k, v in self.day_context.levels.items()
                if v is not None
            }
        return result

    def _compute_vwap_indicators(self, df: pd.DataFrame) -> dict:
        """VWAP: VWAP line with sigma bands (resets daily), RSI, ADX."""
        result = {}
        close = df["close"]
        volume = df["volume"]

        # Compute daily-reset VWAP
        if len(close) >= 10 and volume.sum() > 0:
            typical = (df["high"] + df["low"] + close) / 3

            # Group by date for daily reset
            dates = df.index.date
            vwap = pd.Series(np.nan, index=df.index)
            std = pd.Series(0.0, index=df.index)

            for day in pd.unique(dates):
                mask = dates == day
                day_tp = typical[mask]
                day_vol = volume[mask]
                day_cumvol = day_vol.cumsum()
                day_cumtp = (day_tp * day_vol).cumsum()
                day_vwap = day_cumtp / day_cumvol.replace(0, np.nan)

                sq_diff = ((day_tp - day_vwap) ** 2 * day_vol).cumsum()
                day_var = sq_diff / day_cumvol.replace(0, np.nan)
                day_std = np.sqrt(day_var.fillna(0))

                vwap[mask] = day_vwap
                std[mask] = day_std

            vwap = vwap.ffill()

            result["vwap"] = self._series_to_list(vwap)
            result["vwap_upper_2"] = self._series_to_list(vwap + 2 * std)
            result["vwap_lower_2"] = self._series_to_list(vwap - 2 * std)
            result["vwap_upper_3"] = self._series_to_list(vwap + 3 * std)
            result["vwap_lower_3"] = self._series_to_list(vwap - 3 * std)

        rsi = self._compute_rsi(close, 14)
        if rsi is not None:
            result["rsi"] = self._series_to_list(rsi)

        adx = self._compute_adx(df, 14)
        if adx is not None:
            result["adx"] = self._series_to_list(adx)
        return result

    def _compute_keltner_indicators(self, df: pd.DataFrame) -> dict:
        """Keltner: KC bands, BB bands, squeeze dots, ADX, ROC."""
        close = df["close"]
        result = {}

        if len(close) >= 20:
            # Keltner Channel
            ema20 = close.ewm(span=20, adjust=False).mean()
            atr = self._compute_atr_series(df, 10)
            if atr is not None:
                kc_upper = ema20 + 1.5 * atr
                kc_lower = ema20 - 1.5 * atr
                result["kc_upper"] = self._series_to_list(kc_upper)
                result["kc_lower"] = self._series_to_list(kc_lower)
                result["kc_mid"] = self._series_to_list(ema20)

            # Bollinger Bands
            sma20 = close.rolling(20).mean()
            std20 = close.rolling(20).std()
            bb_upper = sma20 + 2 * std20
            bb_lower = sma20 - 2 * std20
            result["bb_upper"] = self._series_to_list(bb_upper)
            result["bb_lower"] = self._series_to_list(bb_lower)

            # Squeeze: BB inside KC
            if atr is not None:
                squeeze = (bb_lower > kc_lower) & (bb_upper < kc_upper)
                result["squeeze"] = [bool(v) for v in squeeze.fillna(False).tolist()]

        # ROC
        if len(close) >= 12:
            roc = ((close - close.shift(12)) / close.shift(12) * 100)
            result["roc"] = self._series_to_list(roc)

        adx = self._compute_adx(df, 14)
        if adx is not None:
            result["adx"] = self._series_to_list(adx)
        return result

    def _compute_bb_indicators(self, df: pd.DataFrame) -> dict:
        """BB Squeeze: BB bands, bandwidth, volume, linreg."""
        close = df["close"]
        result = {}

        if len(close) >= 20:
            sma20 = close.rolling(20).mean()
            std20 = close.rolling(20).std()
            bb_upper = sma20 + 2 * std20
            bb_lower = sma20 - 2 * std20
            bandwidth = ((bb_upper - bb_lower) / sma20 * 100).fillna(0)

            result["bb_upper"] = self._series_to_list(bb_upper)
            result["bb_lower"] = self._series_to_list(bb_lower)
            result["bb_mid"] = self._series_to_list(sma20)
            result["bandwidth"] = self._series_to_list(bandwidth)

        # Volume
        result["volume"] = [float(v) for v in df["volume"].fillna(0).tolist()]

        # Linear regression slope (simplified)
        if len(close) >= 20:
            linreg = close.rolling(20).apply(
                lambda x: np.polyfit(range(len(x)), x, 1)[0] if len(x) == 20 else 0,
                raw=True,
            )
            result["linreg_slope"] = self._series_to_list(linreg)

        return result

    # ── Technical indicator helpers ──────────────────────────

    def _compute_rsi(self, series: pd.Series, period: int = 14) -> Optional[pd.Series]:
        """Compute RSI."""
        if len(series) < period + 1:
            return None
        delta = series.diff()
        gain = delta.where(delta > 0, 0.0)
        loss = (-delta.where(delta < 0, 0.0))
        avg_gain = gain.ewm(alpha=1/period, min_periods=period, adjust=False).mean()
        avg_loss = loss.ewm(alpha=1/period, min_periods=period, adjust=False).mean()
        rs = avg_gain / avg_loss.replace(0, np.nan)
        return 100 - (100 / (1 + rs))

    def _compute_adx(self, df: pd.DataFrame, period: int = 14) -> Optional[pd.Series]:
        """Compute ADX."""
        if len(df) < period * 2:
            return None
        high = df["high"]
        low = df["low"]
        close = df["close"]

        plus_dm = high.diff()
        minus_dm = -low.diff()
        plus_dm[plus_dm < 0] = 0
        minus_dm[minus_dm < 0] = 0

        # When plus_dm <= minus_dm, set plus_dm to 0 and vice versa
        plus_dm[(plus_dm <= minus_dm)] = 0
        minus_dm[(minus_dm <= plus_dm)] = 0

        tr = pd.concat([
            high - low,
            (high - close.shift()).abs(),
            (low - close.shift()).abs(),
        ], axis=1).max(axis=1)

        atr = tr.ewm(span=period, adjust=False).mean()
        plus_di = 100 * (plus_dm.ewm(span=period, adjust=False).mean() / atr.replace(0, np.nan))
        minus_di = 100 * (minus_dm.ewm(span=period, adjust=False).mean() / atr.replace(0, np.nan))
        dx = (abs(plus_di - minus_di) / (plus_di + minus_di).replace(0, np.nan)) * 100
        adx = dx.ewm(span=period, adjust=False).mean()
        return adx

    def _compute_atr_series(self, df: pd.DataFrame, period: int = 14) -> Optional[pd.Series]:
        """Compute ATR series."""
        if len(df) < period:
            return None
        tr = pd.concat([
            df["high"] - df["low"],
            (df["high"] - df["close"].shift()).abs(),
            (df["low"] - df["close"].shift()).abs(),
        ], axis=1).max(axis=1)
        return tr.ewm(span=period, adjust=False).mean()

    def _series_to_list(self, series: pd.Series) -> list:
        """Convert pandas Series to list of {time, value} for chart."""
        timestamps = self.df.index[:len(series)]
        vals = series.values
        result = []
        for i in range(len(vals)):
            if i < len(timestamps) and not (pd.isna(vals[i]) if isinstance(vals[i], float) else False):
                t = timestamps[i]
                ts = int(t.timestamp()) if hasattr(t, "timestamp") else 0
                result.append({"time": ts, "value": round(float(vals[i]), 5)})
        return result

    def _evaluate_steps(self, indicators: Optional[dict] = None) -> list:
        """Evaluate step conditions for current bar. Returns step states."""
        from dashboard.backend.core.simulation_step_definitions import get_step_definitions

        steps_def = get_step_definitions(self.strategy_id)
        if not steps_def or "steps" not in steps_def:
            return []

        result = []
        for step in steps_def["steps"]:
            completed = False
            detail = ""

            cond = step.get("condition", "")
            try:
                completed, detail = self._check_condition(cond, step, indicators_cache=indicators)
            except Exception as e:
                detail = f"Error: {e}"

            result.append({
                "id": step.get("id", ""),
                "title": step.get("title", ""),
                "description": step.get("description", ""),
                "completed": completed,
                "detail": detail,
                "icon": step.get("icon", "bi-circle"),
            })
        return result

    def _check_condition(self, condition: str, step: dict, indicators_cache: Optional[dict] = None) -> tuple:
        """Check a step condition. Returns (completed, detail)."""
        if not condition or self.df is None or self.df.empty:
            return False, ""

        bar = self.df.iloc[self.current_bar] if self.current_bar < self.total_bars else None
        if bar is None:
            return False, ""

        # Generic conditions
        if condition == "always":
            return True, "Ready"

        if condition == "has_day_context":
            ok = self.day_context is not None
            return ok, f"Bias: {self.day_context.bias}" if ok else "Waiting for day start"

        if condition == "bias_bullish_or_bearish":
            if self.day_context and self.day_context.bias in ("bullish", "bearish"):
                return True, f"{self.day_context.bias.title()} (strength: {self.day_context.bias_strength})"
            return False, "No clear bias yet"

        if condition == "bias_strong":
            threshold = step.get("threshold", 40)
            if self.day_context and self.day_context.bias_strength >= threshold:
                return True, f"Strength: {self.day_context.bias_strength} >= {threshold}"
            strength = self.day_context.bias_strength if self.day_context else 0
            return False, f"Strength: {strength} < {threshold}"

        if condition == "has_open_position":
            has = len(self.open_positions) > 0
            return has, "Position open" if has else "No position"

        if condition == "position_closed":
            has_closed = len(self.closed_trades) > 0
            return has_closed, f"{len(self.closed_trades)} trades completed" if has_closed else "No completed trades"

        if condition == "strategy_setup_detected":
            suggestion = self._get_strategy_suggestion()
            if suggestion:
                return True, f"Setup: {suggestion.get('setup_type', 'detected')}"
            return False, "No setup detected"

        if condition == "ema_aligned_bull":
            inds = indicators_cache if indicators_cache is not None else self._compute_indicators()
            e9 = inds.get("ema_9", [])
            e21 = inds.get("ema_21", [])
            e50 = inds.get("ema_50", [])
            if e9 and e21 and e50:
                v9 = e9[-1]["value"] if e9 else 0
                v21 = e21[-1]["value"] if e21 else 0
                v50 = e50[-1]["value"] if e50 else 0
                if v9 > v21 > v50:
                    return True, f"EMA9({v9:.1f}) > EMA21({v21:.1f}) > EMA50({v50:.1f})"
                elif v9 < v21 < v50:
                    return True, f"Bearish: EMA9 < EMA21 < EMA50"
            return False, "EMAs not aligned"

        if condition == "adx_above":
            threshold = step.get("threshold", 25)
            inds = indicators_cache if indicators_cache is not None else self._compute_indicators()
            adx_list = inds.get("adx", [])
            if adx_list:
                val = adx_list[-1]["value"]
                if val >= threshold:
                    return True, f"ADX = {val:.1f} >= {threshold}"
                return False, f"ADX = {val:.1f} < {threshold}"
            return False, "ADX not computed"

        if condition == "adx_below":
            threshold = step.get("threshold", 30)
            inds = indicators_cache if indicators_cache is not None else self._compute_indicators()
            adx_list = inds.get("adx", [])
            if adx_list:
                val = adx_list[-1]["value"]
                if val < threshold:
                    return True, f"ADX = {val:.1f} < {threshold}"
                return False, f"ADX = {val:.1f} >= {threshold}"
            return False, "ADX not computed"

        if condition == "rsi_extreme":
            inds = indicators_cache if indicators_cache is not None else self._compute_indicators()
            rsi_list = inds.get("rsi", [])
            if rsi_list:
                val = rsi_list[-1]["value"]
                if val < 30:
                    return True, f"RSI = {val:.1f} (oversold)"
                elif val > 70:
                    return True, f"RSI = {val:.1f} (overbought)"
                return False, f"RSI = {val:.1f} (neutral)"
            return False, "RSI not computed"

        if condition == "squeeze_on":
            inds = indicators_cache if indicators_cache is not None else self._compute_indicators()
            squeeze = inds.get("squeeze", [])
            if squeeze and squeeze[-1]:
                return True, "Squeeze ON - volatility compressed"
            return False, "No squeeze"

        if condition == "squeeze_fired":
            inds = indicators_cache if indicators_cache is not None else self._compute_indicators()
            squeeze = inds.get("squeeze", [])
            if len(squeeze) >= 2 and not squeeze[-1] and squeeze[-2]:
                return True, "Squeeze FIRED!"
            return False, "Waiting for squeeze release"

        if condition == "price_beyond_band":
            inds = indicators_cache if indicators_cache is not None else self._compute_indicators()
            bb_upper = inds.get("bb_upper", [])
            bb_lower = inds.get("bb_lower", [])
            price = float(bar["close"])
            if bb_upper and price > bb_upper[-1]["value"]:
                return True, f"Price {price:.2f} above upper BB {bb_upper[-1]['value']:.2f}"
            if bb_lower and price < bb_lower[-1]["value"]:
                return True, f"Price {price:.2f} below lower BB {bb_lower[-1]['value']:.2f}"
            return False, "Price within bands"

        if condition == "overextended":
            inds = indicators_cache if indicators_cache is not None else self._compute_indicators()
            sma = inds.get("sma_20", [])
            upper = inds.get("upper_band", [])
            lower = inds.get("lower_band", [])
            price = float(bar["close"])
            if upper and price > upper[-1]["value"]:
                return True, f"Price above upper band (overextended up)"
            if lower and price < lower[-1]["value"]:
                return True, f"Price below lower band (overextended down)"
            return False, "Not overextended"

        if condition == "vwap_deviation":
            inds = indicators_cache if indicators_cache is not None else self._compute_indicators()
            upper2 = inds.get("vwap_upper_2", [])
            lower2 = inds.get("vwap_lower_2", [])
            price = float(bar["close"])
            if upper2 and price > upper2[-1]["value"]:
                return True, f"Price above VWAP +2σ"
            if lower2 and price < lower2[-1]["value"]:
                return True, f"Price below VWAP -2σ"
            return False, "Price within 2σ of VWAP"

        # Default: unknown condition
        return False, f"Condition '{condition}' not evaluated"

    def _get_strategy_suggestion(self) -> Optional[dict]:
        """What would the bot do here? Call find_setup()."""
        if not self._strategy_available or self.df is None:
            return None
        if self.current_bar < 1 or self.current_bar >= self.total_bars:
            return None

        try:
            bar = self.df.iloc[self.current_bar]
            df_slice = self.df.iloc[:self.current_bar]
            if self.day_context is None:
                return None
            setup = self._strategy.find_setup(bar, df_slice, self.day_context, self.current_bar)
            if setup:
                return {
                    "direction": setup.direction,
                    "entry_price": setup.entry_price,
                    "stop_loss": setup.stop_loss,
                    "take_profit": setup.take_profit,
                    "setup_type": setup.setup_type,
                    "confidence": setup.confidence,
                }
        except Exception as e:
            logger.debug(f"find_setup error: {e}")
        return None

    def _get_chart_overlays(self) -> dict:
        """Return horizontal lines, rectangles, markers for the chart."""
        overlays = {"lines": [], "rectangles": [], "markers": []}

        # Session levels as horizontal lines
        if self.day_context and self.day_context.levels:
            level_colors = {
                "orb_high": "#2196F3", "orb_low": "#2196F3",
                "asian_high": "#FF9800", "asian_low": "#FF9800",
                "pd_high": "#9C27B0", "pd_low": "#9C27B0",
                "london_high": "#4CAF50", "london_low": "#4CAF50",
            }
            for key, val in self.day_context.levels.items():
                if val is not None:
                    overlays["lines"].append({
                        "price": float(val),
                        "label": key.replace("_", " ").title(),
                        "color": level_colors.get(key, "#666"),
                        "style": "dashed" if "low" in key else "solid",
                    })

        # Open position SL/TP lines
        for pos in self.open_positions:
            stop_loss = pos.get("stop_loss")
            if stop_loss is not None and np.isfinite(float(stop_loss)) and float(stop_loss) > 0.0:
                overlays["lines"].append({
                    "price": float(stop_loss),
                    "label": "Stop Loss",
                    "color": "#F44336",
                    "style": "solid",
                })
            take_profit = pos.get("take_profit")
            if take_profit is not None and np.isfinite(float(take_profit)) and float(take_profit) > 0.0:
                overlays["lines"].append({
                    "price": float(take_profit),
                    "label": "Take Profit",
                    "color": "#4CAF50",
                    "style": "solid",
                })
            overlays["lines"].append({
                "price": pos["entry_price"],
                "label": f"Entry ({pos['direction']})",
                "color": "#2196F3",
                "style": "dotted",
            })

        return overlays

    def _compute_open_pnl(self) -> float:
        """Compute unrealized P&L for open positions."""
        if not self.open_positions or self.df is None or self.current_bar >= self.total_bars:
            return 0.0

        current_price = float(self.df.iloc[self.current_bar]["close"])
        total = 0.0
        for pos in self.open_positions:
            total += self._calculate_pnl(pos, current_price)
        return round(total, 2)
