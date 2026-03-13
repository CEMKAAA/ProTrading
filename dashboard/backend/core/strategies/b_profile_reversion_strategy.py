"""
B-Profile Failed Auction Reversion Strategy.

Core idea:
1) Previous session shows a "b-shape" (long-liquidation style profile).
2) Current session probes above previous value-area high (VAH) and fails.
3) Price re-enters value (close back below VAH) with bearish pressure.
4) Optional constituent-divergence confirmation (e.g., NVDA/TSLA weakness).
5) Short with asymmetric payoff (high R multiple).
"""

import logging
from datetime import datetime, time
from typing import Optional, Dict, Any, Tuple, List

import numpy as np
import pandas as pd

from .base import BacktestStrategy, DayContext, TradeSetup

logger = logging.getLogger(__name__)


class BProfileReversionStrategy(BacktestStrategy):
    """Intraday failed-auction fade after b-shape profile context."""

    def __init__(self, config: Dict[str, Any]):
        super().__init__(config)
        self._traded_days: set = set()
        self._profile_cache: Dict[datetime.date, Dict[str, float]] = {}
        # Explicit config reads keep registry/runtime parity checks honest for
        # constituent column overrides that are consumed dynamically later.
        self._nvda_return_col = self.config.get("nvda_return_col")
        self._tsla_return_col = self.config.get("tsla_return_col")
        self._nvda_close_col = self.config.get("nvda_close_col")
        self._tsla_close_col = self.config.get("tsla_close_col")

    def initialize_day(
        self,
        date: datetime,
        daily_df: Optional[pd.DataFrame],
        intraday_df: pd.DataFrame,
    ) -> DayContext:
        ctx = DayContext(date=date, bias="neutral", bias_strength=0)
        if intraday_df is not None and len(intraday_df) >= 14:
            ctx.atr = self._calculate_atr(intraday_df, 14)
        else:
            ctx.atr = 1.0
        return ctx

    def find_setup(
        self,
        bar: pd.Series,
        df: pd.DataFrame,
        day_context: DayContext,
        current_bar_index: int,
    ) -> Optional[TradeSetup]:
        if len(df) < 80 or bar is None or bar.name is None:
            return None

        signal_ts = bar.name
        trade_day = signal_ts.date()
        if bool(self.config.get("one_trade_per_day", True)) and trade_day in self._traded_days:
            return None

        atr = float(day_context.atr) if day_context.atr and day_context.atr > 0 else self._calculate_atr(df, 14)
        atr = max(atr, 1e-6)

        prev_day = self._get_previous_trading_day(df, trade_day)
        if prev_day is None:
            return None

        profile = self._get_prev_day_profile(df, prev_day)
        if profile is None:
            return None

        b_shape_ok = (
            profile["lower_share"] >= float(self.config.get("min_lower_distribution_share", 0.58))
            and profile["upper_tail_share"] <= float(self.config.get("max_upper_tail_share", 0.22))
            and profile["b_shape_score"] >= float(self.config.get("min_b_shape_score", 0.58))
        )
        if not b_shape_ok:
            return None

        prev_vah = profile["vah"]
        prev_val = profile["val"]
        if not np.isfinite(prev_vah) or not np.isfinite(prev_val) or prev_vah <= prev_val:
            return None

        breakout_buf = float(self.config.get("breakout_buffer_atr", 0.08)) * atr
        reentry_buf = float(self.config.get("reentry_buffer_atr", 0.02)) * atr

        high = float(bar.get("high", np.nan))
        close = float(bar.get("close", np.nan))
        open_price = float(bar.get("open", np.nan))
        low = float(bar.get("low", np.nan))
        if not all(np.isfinite([high, close, open_price, low])):
            return None

        # False breakout and re-acceptance into value area.
        if high < (prev_vah + breakout_buf):
            return None
        if close > (prev_vah - reentry_buf):
            return None

        # Bearish pressure confirmation.
        if not self._has_bearish_pressure(bar, atr):
            return None

        # Liquidity-void check near highs (weak participation on extension).
        if not self._has_top_liquidity_void(df):
            return None

        # Optional cross-asset correlation confirmation (e.g., ES weakness).
        corr_ok, corr_meta = self._correlation_ok(df)
        if not corr_ok:
            return None

        # Optional orderflow/depth confirmation from Databento-enriched columns.
        of_ok, of_meta = self._orderflow_confirmation_ok(df)
        if not of_ok:
            return None

        # Optional constituent divergence check.
        weak_ok, weak_meta = self._constituent_weakness_ok(df)
        if not weak_ok:
            return None

        # Optional constituent open-gap filter (e.g., NVDA gap down day).
        gap_ok, gap_meta = self._constituent_gap_ok(df)
        if not gap_ok:
            return None

        # Stop just above failed auction highs.
        recent_window = int(self.config.get("failed_auction_lookback_bars", 6))
        recent = df.iloc[-recent_window:] if recent_window > 1 else df.iloc[[-1]]
        failed_highs = recent[recent["high"] >= prev_vah]["high"]
        sweep_high = float(failed_highs.max()) if len(failed_highs) > 0 else high

        sl_buffer = float(self.config.get("sl_buffer_atr", 0.15)) * atr
        raw_sl = sweep_high + sl_buffer
        entry_ref = open_price
        if raw_sl <= entry_ref:
            raw_sl = entry_ref + float(self.config.get("min_sl_usd", 1.0))

        sl_dist = raw_sl - entry_ref
        min_sl = float(self.config.get("min_sl_usd", 1.0))
        max_sl = float(self.config.get("max_sl_usd", 20.0))
        sl_dist = max(min_sl, min(max_sl, sl_dist))
        sl = entry_ref + sl_dist

        # Target: previous value-area low or minimum R target.
        rr_min = float(self.config.get("min_rr_ratio", 4.5))
        rr_stretch = float(self.config.get("stretch_rr_ratio", 6.0))
        use_stretch = profile["b_shape_score"] >= float(self.config.get("stretch_rr_bshape_score", 0.70))
        rr_target = rr_stretch if use_stretch else rr_min
        rr_to_val = (entry_ref - prev_val) / sl_dist if sl_dist > 0 else 0.0
        if rr_to_val >= rr_target:
            tp = prev_val
        else:
            tp = entry_ref - (sl_dist * rr_target)

        if tp >= entry_ref:
            return None

        confidence = self._compute_confidence(profile, bar, atr, weak_meta)
        metadata = {
            "strategy": "b_profile_reversion_strategy",
            "profile_val": float(prev_val),
            "profile_vah": float(prev_vah),
            "profile_poc": float(profile["poc"]),
            "b_shape_score": float(profile["b_shape_score"]),
            "lower_share": float(profile["lower_share"]),
            "upper_tail_share": float(profile["upper_tail_share"]),
            "rr_plan": float((entry_ref - tp) / max(sl_dist, 1e-6)),
            "failed_high": float(sweep_high),
            "weakness_mode": weak_meta.get("mode"),
            "weakness_available": bool(weak_meta.get("available", False)),
            "weakness_value": weak_meta.get("value"),
            "gap_mode": gap_meta.get("mode"),
            "gap_available": bool(gap_meta.get("available", False)),
            "gap_nvda": gap_meta.get("nvda_gap_down"),
            "gap_tsla": gap_meta.get("tsla_gap_down"),
            "correlation_mode": corr_meta.get("mode"),
            "correlation_available": bool(corr_meta.get("available", False)),
            "correlation_value": corr_meta.get("value"),
            "orderflow_mode": of_meta.get("mode"),
            "orderflow_available": bool(of_meta.get("available", False)),
            "orderflow_flow_imbalance": of_meta.get("flow_imbalance"),
            "orderflow_dom_imbalance": of_meta.get("dom_imbalance"),
            "orderflow_absorption": of_meta.get("absorption_score"),
            "orderflow_lva_velocity": of_meta.get("lva_velocity"),
            "entry_date": trade_day.isoformat(),
            "flat_time": str(self.config.get("flat_time", "15:55")),
        }

        self._traded_days.add(trade_day)
        return TradeSetup(
            direction="SELL",
            entry_price=entry_ref,
            stop_loss=sl,
            take_profit=tp,
            setup_type="B-Profile Failed Auction Reversion (Short)",
            confidence=confidence,
            metadata=metadata,
        )

    def should_close_early(self, bar, df, position, day_context):
        meta = position.strategy_metadata or {}
        if meta.get("strategy") != "b_profile_reversion_strategy":
            return None
        if bar is None or bar.name is None:
            return None

        ts = bar.name
        trade_day = self._to_date(meta.get("entry_date"))
        if trade_day is not None and ts.date() > trade_day:
            return "Session Boundary Exit"

        flat_time = self._parse_hhmm(str(meta.get("flat_time", "15:55")))
        if ts.time() >= flat_time:
            return "Session Time Exit"

        # Invalidation: strong reclaim above failed auction level.
        failed_high = meta.get("failed_high")
        atr = float(day_context.atr) if day_context.atr and day_context.atr > 0 else 1.0
        if failed_high is not None and float(bar.get("close", 0.0)) > (float(failed_high) + 0.30 * atr):
            return "Failed Auction Invalidated"
        return None

    def get_required_lookback_bars(self) -> int:
        return 180

    def _get_previous_trading_day(
        self, df: pd.DataFrame, current_day: datetime.date
    ) -> Optional[datetime.date]:
        trading_days = sorted(pd.unique(df.index.date))
        if len(trading_days) < 2:
            return None
        idx_map = {d: i for i, d in enumerate(trading_days)}
        idx = idx_map.get(current_day)
        if idx is None or idx <= 0:
            return None
        return trading_days[idx - 1]

    def _get_prev_day_profile(
        self, df: pd.DataFrame, prev_day: datetime.date
    ) -> Optional[Dict[str, float]]:
        cached = self._profile_cache.get(prev_day)
        if cached is not None:
            return cached

        prev_df = df[df.index.date == prev_day]
        if len(prev_df) < int(self.config.get("min_profile_bars", 30)):
            return None

        low_min = float(prev_df["low"].min())
        high_max = float(prev_df["high"].max())
        if not np.isfinite(low_min) or not np.isfinite(high_max) or high_max <= low_min:
            return None

        n_bins = int(self.config.get("profile_bins", 48))
        n_bins = max(16, min(160, n_bins))

        prices = ((prev_df["high"] + prev_df["low"] + prev_df["close"]) / 3.0).to_numpy(dtype=float)
        use_volume = bool(self.config.get("profile_use_volume", True))
        if use_volume and "volume" in prev_df.columns:
            weights = np.maximum(prev_df["volume"].to_numpy(dtype=float), 0.0)
            if np.nansum(weights) <= 0:
                weights = np.ones_like(prices)
        else:
            weights = np.ones_like(prices)

        hist, edges = np.histogram(prices, bins=n_bins, range=(low_min, high_max), weights=weights)
        total = float(np.sum(hist))
        if total <= 0:
            return None
        centers = 0.5 * (edges[:-1] + edges[1:])
        poc_idx = int(np.argmax(hist))
        poc = float(centers[poc_idx])

        target = float(self.config.get("value_area_pct", 0.70))
        target = min(max(target, 0.50), 0.95)
        low_idx = poc_idx
        high_idx = poc_idx
        acc = float(hist[poc_idx])
        while acc < target * total and (low_idx > 0 or high_idx < len(hist) - 1):
            left_val = hist[low_idx - 1] if low_idx > 0 else -1
            right_val = hist[high_idx + 1] if high_idx < len(hist) - 1 else -1
            if right_val >= left_val:
                high_idx += 1
                acc += float(hist[high_idx])
            else:
                low_idx -= 1
                acc += float(hist[low_idx])

        val = float(edges[low_idx])
        vah = float(edges[high_idx + 1])

        mid = len(hist) // 2
        lower_share = float(np.sum(hist[:mid]) / total)
        upper_tail_start = int(len(hist) * 0.75)
        upper_tail_share = float(np.sum(hist[upper_tail_start:]) / total)

        # b-shape score: more mass in lower half + thin upper tail.
        b_shape_score = 0.6 * lower_share + 0.4 * (1.0 - upper_tail_share)
        out = {
            "poc": poc,
            "val": val,
            "vah": vah,
            "lower_share": lower_share,
            "upper_tail_share": upper_tail_share,
            "b_shape_score": float(b_shape_score),
        }
        self._profile_cache[prev_day] = out
        return out

    def _has_bearish_pressure(self, bar: pd.Series, atr: float) -> bool:
        open_price = float(bar.get("open", np.nan))
        close = float(bar.get("close", np.nan))
        high = float(bar.get("high", np.nan))
        low = float(bar.get("low", np.nan))
        if not all(np.isfinite([open_price, close, high, low])):
            return False
        candle_range = max(high - low, 1e-6)
        body = max(open_price - close, 0.0)
        body_atr = body / max(atr, 1e-6)
        close_to_low = (close - low) / candle_range
        upper_wick = high - max(open_price, close)
        upper_wick_ratio = upper_wick / candle_range

        if body_atr < float(self.config.get("min_bear_body_atr", 0.12)):
            return False
        if close_to_low > float(self.config.get("max_close_to_low_ratio", 0.45)):
            return False
        if upper_wick_ratio < float(self.config.get("min_upper_wick_ratio", 0.20)):
            return False
        return True

    def _has_top_liquidity_void(self, df: pd.DataFrame) -> bool:
        if "volume" not in df.columns:
            return True
        lookback = int(self.config.get("volume_lookback_bars", 24))
        if len(df) < max(lookback, 3):
            return True
        recent = df.iloc[-lookback:]
        rolling_vol = float(np.nanmean(recent["volume"].to_numpy(dtype=float)))
        signal_vol = float(df.iloc[-1].get("volume", 0.0))
        if rolling_vol <= 0:
            return True
        max_ratio = float(self.config.get("max_top_volume_ratio", 0.90))
        return signal_vol <= rolling_vol * max_ratio

    def _constituent_weakness_ok(self, df: pd.DataFrame) -> Tuple[bool, Dict[str, Any]]:
        mode = str(self.config.get("constituent_confirmation_mode", "auto")).lower()
        meta = {"mode": mode, "available": False, "value": None}
        if mode == "off":
            return True, meta

        lookback = int(self.config.get("constituent_lookback_bars", 6))
        th = float(self.config.get("constituent_weakness_threshold", -0.001))
        require_both = bool(self.config.get("require_both_constituents", False))

        nvda = self._extract_constituent_return(df, "nvda", lookback)
        tsla = self._extract_constituent_return(df, "tsla", lookback)
        values = [v for v in [nvda, tsla] if v is not None]
        if not values:
            if mode == "required":
                return False, meta
            return True, meta

        meta["available"] = True
        avg_ret = float(np.mean(values))
        meta["value"] = avg_ret

        if require_both and len(values) >= 2:
            ok = all(v <= th for v in values)
        else:
            ok = avg_ret <= th
        return bool(ok), meta

    def _correlation_ok(self, df: pd.DataFrame) -> Tuple[bool, Dict[str, Any]]:
        """
        Cross-asset correlation gate for short setups.

        Typical use: require ES return to be weak/negative while shorting NQ/NAS100.
        """
        mode = str(self.config.get("correlation_confirmation_mode", "auto")).lower()
        col = str(self.config.get("correlation_return_col", "es_ret_5m"))
        max_ret = float(self.config.get("correlation_max_ret_short", 0.0005))
        require_negative = bool(self.config.get("correlation_require_negative", True))

        meta = {"mode": mode, "available": False, "value": None, "column": col}
        if mode == "off":
            return True, meta
        if col not in df.columns:
            return (False, meta) if mode == "required" else (True, meta)

        val = self._to_float(df.iloc[-1].get(col))
        if val is None:
            return (False, meta) if mode == "required" else (True, meta)

        meta["available"] = True
        meta["value"] = float(val)
        if require_negative:
            ok = val <= max_ret
        else:
            ok = abs(val) <= abs(max_ret)
        return bool(ok), meta

    def _constituent_gap_ok(self, df: pd.DataFrame) -> Tuple[bool, Dict[str, Any]]:
        """
        Optional constituent gap-down filter for event-driven short bias.

        This supports columns like:
          - nvda_gap_down / tsla_gap_down (bool/int)
          - nvda_open + nvda_prev_close (or tsla_*)
          - fallback to return columns (treated as gap proxy if <= -threshold)
        """
        mode = str(self.config.get("constituent_gap_mode", "auto")).lower()
        require_nvda = bool(self.config.get("require_nvda_gap_down", False))
        require_tsla = bool(self.config.get("require_tsla_gap_down", False))
        threshold_pct = float(self.config.get("gap_down_threshold_pct", 0.20))
        gap_threshold = max(threshold_pct, 0.0) / 100.0

        meta: Dict[str, Any] = {
            "mode": mode,
            "available": False,
            "nvda_gap_down": None,
            "tsla_gap_down": None,
        }
        if mode == "off" or (not require_nvda and not require_tsla):
            return True, meta

        checks: List[bool] = []
        if require_nvda:
            v = self._extract_gap_down_signal(df, "nvda", gap_threshold)
            meta["nvda_gap_down"] = v
            if v is None:
                if mode == "required":
                    return False, meta
            else:
                meta["available"] = True
                checks.append(bool(v))

        if require_tsla:
            v = self._extract_gap_down_signal(df, "tsla", gap_threshold)
            meta["tsla_gap_down"] = v
            if v is None:
                if mode == "required":
                    return False, meta
            else:
                meta["available"] = True
                checks.append(bool(v))

        if not checks:
            return (False, meta) if mode == "required" else (True, meta)
        return bool(all(checks)), meta

    def _orderflow_confirmation_ok(self, df: pd.DataFrame) -> Tuple[bool, Dict[str, Any]]:
        """
        Orderflow/depth confirmation gate.

        Uses optional Databento-derived columns if present:
          - of_flow_imbalance
          - dom_imbalance
          - dom_absorption_score
          - lva_velocity
        """
        mode = str(self.config.get("orderflow_confirmation_mode", "auto")).lower()
        flow_col = str(self.config.get("orderflow_flow_col", "of_flow_imbalance"))
        dom_col = str(self.config.get("orderflow_dom_col", "dom_imbalance"))
        absorption_col = str(self.config.get("orderflow_absorption_col", "dom_absorption_score"))
        lva_col = str(self.config.get("orderflow_lva_velocity_col", "lva_velocity"))

        max_flow = float(self.config.get("max_flow_imbalance_short", -0.02))
        max_dom = float(self.config.get("max_dom_imbalance_short", -0.02))
        min_absorption = float(self.config.get("min_absorption_score_short", 0.0))
        min_lva_velocity = float(self.config.get("min_lva_velocity", 0.0))

        meta = {
            "mode": mode,
            "available": False,
            "flow_imbalance": None,
            "dom_imbalance": None,
            "absorption_score": None,
            "lva_velocity": None,
        }
        if mode == "off":
            return True, meta

        values: Dict[str, float] = {}
        for key, col in (
            ("flow_imbalance", flow_col),
            ("dom_imbalance", dom_col),
            ("absorption_score", absorption_col),
            ("lva_velocity", lva_col),
        ):
            if col in df.columns:
                v = self._to_float(df.iloc[-1].get(col))
                if v is not None:
                    values[key] = float(v)
                    meta[key] = float(v)

        if not values:
            return (False, meta) if mode == "required" else (True, meta)

        meta["available"] = True
        checks: List[bool] = []
        if "flow_imbalance" in values:
            checks.append(values["flow_imbalance"] <= max_flow)
        if "dom_imbalance" in values:
            checks.append(values["dom_imbalance"] <= max_dom)
        if "absorption_score" in values:
            checks.append(values["absorption_score"] >= min_absorption)
        if "lva_velocity" in values:
            checks.append(values["lva_velocity"] >= min_lva_velocity)

        if not checks:
            return (False, meta) if mode == "required" else (True, meta)
        return bool(all(checks)), meta

    def _extract_gap_down_signal(
        self, df: pd.DataFrame, symbol_key: str, gap_threshold: float
    ) -> Optional[bool]:
        # 1) Direct boolean/int gap flag.
        gap_candidates = [
            self.config.get(f"{symbol_key}_gap_col"),
            f"{symbol_key}_gap_down",
            f"{symbol_key}_gap",
            f"{symbol_key}_is_gap_down",
        ]
        for col in gap_candidates:
            if col in df.columns:
                raw = df.iloc[-1].get(col)
                if raw is None or pd.isna(raw):
                    continue
                if isinstance(raw, str):
                    s = raw.strip().lower()
                    if s in {"1", "true", "yes", "y"}:
                        return True
                    if s in {"0", "false", "no", "n"}:
                        return False
                try:
                    return bool(int(float(raw)))
                except Exception:
                    continue

        # 2) Open vs previous close columns.
        open_candidates = [
            self.config.get(f"{symbol_key}_open_col"),
            f"{symbol_key}_open",
            f"{symbol_key.upper()}_open",
        ]
        prev_close_candidates = [
            self.config.get(f"{symbol_key}_prev_close_col"),
            f"{symbol_key}_prev_close",
            f"{symbol_key}_close_prev",
            f"{symbol_key.upper()}_prev_close",
        ]
        for open_col in open_candidates:
            for prev_col in prev_close_candidates:
                if open_col in df.columns and prev_col in df.columns:
                    o = self._to_float(df.iloc[-1].get(open_col))
                    pc = self._to_float(df.iloc[-1].get(prev_col))
                    if o is None or pc is None or pc == 0:
                        continue
                    return ((o - pc) / abs(pc)) <= -gap_threshold

        # 3) Fallback: return column as gap proxy when nothing else exists.
        ret = self._extract_constituent_return(df, symbol_key, lookback=1)
        if ret is None:
            return None
        return ret <= -gap_threshold

    def _extract_constituent_return(
        self, df: pd.DataFrame, symbol_key: str, lookback: int
    ) -> Optional[float]:
        # Preferred: precomputed return column.
        configured_ret_col = self.config.get(f"{symbol_key}_return_col")
        configured_close_col = self.config.get(f"{symbol_key}_close_col")
        ret_candidates = [
            configured_ret_col,
            f"{symbol_key}_ret",
            f"{symbol_key}_return",
            f"{symbol_key}_ret_5m",
            f"{symbol_key}_pct_change",
        ]
        for col in ret_candidates:
            if col in df.columns:
                v = self._to_float(df.iloc[-1].get(col))
                if v is not None:
                    return v

        # Fallback: compute return from close series column.
        close_candidates = [
            configured_close_col,
            f"{symbol_key}_close",
            f"{symbol_key.upper()}_close",
            f"{symbol_key}.close",
        ]
        for col in close_candidates:
            if col in df.columns and len(df[col]) > lookback:
                series = pd.to_numeric(df[col], errors="coerce")
                now = self._to_float(series.iloc[-1])
                then = self._to_float(series.iloc[-1 - lookback])
                if now is None or then is None or then == 0:
                    continue
                return (now - then) / abs(then)
        return None

    def _compute_confidence(
        self,
        profile: Dict[str, float],
        bar: pd.Series,
        atr: float,
        weak_meta: Dict[str, Any],
    ) -> float:
        score = 40.0
        score += min(max((profile["b_shape_score"] - 0.50) * 100.0, 0.0), 25.0)

        open_price = float(bar.get("open", 0.0))
        close = float(bar.get("close", 0.0))
        body_atr = max(open_price - close, 0.0) / max(atr, 1e-6)
        score += min(body_atr * 20.0, 20.0)

        if weak_meta.get("available"):
            val = float(weak_meta.get("value", 0.0))
            if val < 0:
                score += min(abs(val) * 2000.0, 15.0)
        return float(min(max(score, 1.0), 99.0))

    @staticmethod
    def _calculate_atr(df: pd.DataFrame, period: int = 14) -> float:
        if len(df) < period + 1:
            return 1.0
        high = df["high"]
        low = df["low"]
        close = df["close"]
        tr1 = high - low
        tr2 = (high - close.shift(1)).abs()
        tr3 = (low - close.shift(1)).abs()
        tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
        atr = tr.rolling(period).mean()
        v = atr.iloc[-1]
        if pd.isna(v) or v <= 0:
            return 1.0
        return float(v)

    @staticmethod
    def _parse_hhmm(value: str) -> time:
        hh, mm = [int(x) for x in str(value).split(":")]
        return time(hh, mm)

    @staticmethod
    def _to_date(value):
        if value is None:
            return None
        try:
            return pd.to_datetime(value).date()
        except Exception:
            return None

    @staticmethod
    def _to_float(value) -> Optional[float]:
        try:
            if value is None or pd.isna(value):
                return None
            return float(value)
        except Exception:
            return None
