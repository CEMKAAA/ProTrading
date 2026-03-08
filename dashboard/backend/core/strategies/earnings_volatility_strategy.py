"""
Earnings Volatility Crush Strategy (Options-Proxy Backtest).

This strategy targets the post-earnings implied-volatility collapse by selecting
only high-quality earnings events:
  - Negative term-structure slope (near IV > far IV)
  - High 30-day average volume
  - Elevated IV30 / RV30 ratio

Execution window:
  - Entry: 15 minutes before close on the day BEFORE the earnings event.
  - Exit: 15 minutes after open on the day AFTER the earnings event.

Important:
  The core backtest engine is spot-price based, not an options-pricer.
  This strategy therefore uses a controlled proxy PnL model (stored in metadata
  and evaluated by the engine) to emulate short-vol structures:
    - short straddle (high variance)
    - long calendar spread (preferred)
"""

import logging
from datetime import datetime, time, timedelta, date
from typing import Optional, Dict, Any, List, Tuple

import numpy as np
import pandas as pd

from .base import BacktestStrategy, DayContext, TradeSetup

logger = logging.getLogger(__name__)


class EarningsVolatilityStrategy(BacktestStrategy):
    """Filter-driven earnings IV-crush strategy with timed exits."""

    def __init__(self, config: Dict[str, Any]):
        super().__init__(config)
        self._allow_event_lookahead = bool(self.config.get("allow_event_lookahead", False))
        self._traded_event_dates: set = set()
        self._missing_cols_warned = False
        self._event_schedule_cache_key = None
        self._event_schedule_cache: Dict[datetime.date, Tuple[datetime.date, datetime.date]] = {}

    def initialize_day(
        self,
        date: datetime,
        daily_df: Optional[pd.DataFrame],
        intraday_df: pd.DataFrame,
    ) -> DayContext:
        # Strategy is event/filter driven, not directional.
        return DayContext(date=date, bias="neutral", bias_strength=0, atr=1.0)

    def find_setup(
        self,
        bar: pd.Series,
        df: pd.DataFrame,
        day_context: DayContext,
        current_bar_index: int,
    ) -> Optional[TradeSetup]:
        if len(df) < 2 or bar is None or bar.name is None:
            return None

        required = self._required_columns()
        missing = [c for c in required if c not in df.columns]
        if missing:
            if not self._missing_cols_warned:
                logger.warning(
                    "EarningsVolatilityStrategy inactive: missing required columns: %s", missing
                )
                self._missing_cols_warned = True
            return None

        signal_ts = bar.name
        signal_date = signal_ts.date()
        event_meta = self._resolve_event_metadata_for_entry_bar(bar, df, signal_date)
        if not event_meta:
            if self._allow_event_lookahead:
                events_by_entry = self._get_event_schedule(
                    df, self.config.get("earnings_event_col", "earnings_event")
                )
                event_meta = events_by_entry.get(signal_date)
            if not event_meta:
                return None

        event_date, exit_date = event_meta
        if event_date in self._traded_event_dates:
            return None

        # Entry executes at next bar open; enforce precise entry clock.
        interval = self._infer_bar_interval(df)
        intended_entry_ts = signal_ts + interval
        entry_time_cfg = self._parse_hhmm(self.config.get("entry_time", "15:45"))
        if intended_entry_ts.time() != entry_time_cfg:
            return None

        row = bar
        iv_front_col = self.config.get("iv_front_col", "iv_front")
        iv_far_col = self.config.get("iv_far_col", "iv_45d")
        volume30_col = self.config.get("volume30_col", "volume30")
        iv30_col = self.config.get("iv30_col", "iv30")
        rv30_col = self.config.get("rv30_col", "rv30")
        iv_back_col = self.config.get("iv_back_col", "iv_back")

        iv_front = self._to_float(row.get(iv_front_col))
        iv_far = self._to_float(row.get(iv_far_col))
        iv_back = self._to_float(row.get(iv_back_col))
        avg_volume30 = self._to_float(row.get(volume30_col))
        iv30 = self._to_float(row.get(iv30_col))
        rv30 = self._to_float(row.get(rv30_col))
        if any(v is None for v in [iv_front, iv_far, iv_back, avg_volume30, iv30, rv30]):
            return None
        if rv30 <= 0:
            return None

        # Negative slope denotes backwardation (near IV above far IV).
        term_slope = iv_far - iv_front
        term_slope_max = float(self.config.get("term_structure_max_slope", -0.05))
        if term_slope > term_slope_max:
            return None

        min_volume30 = float(self.config.get("min_avg_volume30", 5_000_000))
        if avg_volume30 < min_volume30:
            return None

        iv_rv_ratio = iv30 / rv30
        min_ratio = float(self.config.get("min_iv30_rv30_ratio", 1.25))
        if iv_rv_ratio < min_ratio:
            return None

        structure = str(self.config.get("vol_structure", "long_calendar")).lower()
        front_dte = float(self.config.get("front_dte_days", 7))
        back_dte = float(self.config.get("back_dte_days", 37))
        expiration_gap_days = float(self.config.get("target_expiration_gap_days", 30))
        expected_move_scale = float(self.config.get("expected_move_scale", 1.0))

        # Approximate ATM expected move from near-term IV.
        entry_ref = float(bar.get("close", 0.0))
        if entry_ref <= 0:
            return None
        expected_move_pct = iv_front * np.sqrt(max(front_dte, 1.0) / 365.0) * expected_move_scale
        expected_move_usd = max(entry_ref * expected_move_pct, 0.01)

        # Engine still needs directional SL distance for lot sizing.
        min_sl = float(self.config.get("min_sl_usd", 1.0))
        max_sl = float(self.config.get("max_sl_usd", 25.0))
        risk_distance = max(min_sl, min(max_sl, expected_move_usd))
        sl = entry_ref - risk_distance
        tp = entry_ref + risk_distance * 2.0

        if structure == "short_straddle":
            premium_factor = float(self.config.get("straddle_premium_factor", 0.95))
            premium_usd = entry_ref * iv_front * np.sqrt(max(front_dte, 1.0) / 365.0) * premium_factor
            setup_type = "Earnings Short Straddle (Proxy)"
        else:
            # Preferred calendar: front month crush should exceed back-month decay.
            edge_factor = float(self.config.get("calendar_edge_factor", 1.20))
            iv_edge = max(iv_front - iv_back, 0.0)
            premium_usd = entry_ref * iv_edge * np.sqrt(max(front_dte, 1.0) / 365.0) * edge_factor
            setup_type = "Earnings Long Calendar (Proxy)"

        exit_time_cfg = self._parse_hhmm(self.config.get("exit_time", "09:45"))
        confidence = self._compute_confidence(term_slope, term_slope_max, avg_volume30, min_volume30, iv_rv_ratio, min_ratio)

        metadata = {
            "strategy": "earnings_volatility_strategy",
            "structure": structure,
            "event_date": event_date.isoformat(),
            "exit_date": exit_date.isoformat(),
            "exit_time": exit_time_cfg.strftime("%H:%M"),
            "disable_sl_tp": True,
            "disable_trailing": True,
            "pnl_model": "earnings_short_vol_proxy",
            "premium_usd": float(premium_usd),
            "expected_move_usd": float(expected_move_usd),
            "move_penalty_mult": float(self.config.get("move_penalty_mult", 1.0)),
            "breach_penalty_mult": float(self.config.get("breach_penalty_mult", 2.5)),
            "iv_point_value": float(self.config.get("iv_point_value", 100.0)),
            "calendar_back_vega_weight": float(self.config.get("calendar_back_vega_weight", 0.35)),
            "iv_front_col": iv_front_col,
            "iv_back_col": iv_back_col,
            "iv_front_entry": float(iv_front),
            "iv_back_entry": float(iv_back),
            # Diagnostics
            "term_structure_slope": float(term_slope),
            "term_structure_threshold": float(term_slope_max),
            "iv30_rv30_ratio": float(iv_rv_ratio),
            "iv30_rv30_threshold": float(min_ratio),
            "avg_volume30": float(avg_volume30),
            "avg_volume30_threshold": float(min_volume30),
            "front_dte_days": float(front_dte),
            "back_dte_days": float(back_dte),
            "target_expiration_gap_days": float(expiration_gap_days),
            "intended_entry_time": intended_entry_ts.isoformat(),
        }

        self._traded_event_dates.add(event_date)
        return TradeSetup(
            direction="BUY",  # engine direction required; PnL is handled by custom proxy model
            entry_price=entry_ref,
            stop_loss=sl,
            take_profit=tp,
            setup_type=setup_type,
            confidence=confidence,
            metadata=metadata,
        )

    def should_close_early(self, bar, df, position, day_context):
        meta = position.strategy_metadata or {}
        if meta.get("strategy") != "earnings_volatility_strategy":
            return None
        if bar is None or bar.name is None:
            return None

        exit_date_raw = meta.get("exit_date")
        exit_time_raw = meta.get("exit_time", "09:45")
        if not exit_date_raw:
            return None

        try:
            exit_date = datetime.fromisoformat(str(exit_date_raw)).date()
            exit_time = self._parse_hhmm(str(exit_time_raw))
        except Exception:
            return None

        ts = bar.name
        current_date = ts.date()
        current_time = ts.time()
        if current_date > exit_date:
            return "Post-Earnings Timed Exit"
        if current_date == exit_date and current_time >= exit_time:
            return "Post-Earnings Timed Exit"
        return None

    def get_required_lookback_bars(self) -> int:
        return 50

    @staticmethod
    def _to_float(value) -> Optional[float]:
        try:
            if value is None or pd.isna(value):
                return None
            return float(value)
        except Exception:
            return None

    @staticmethod
    def _parse_hhmm(s: str) -> time:
        hh, mm = [int(x) for x in s.split(":")]
        return time(hh, mm)

    @staticmethod
    def _infer_bar_interval(df: pd.DataFrame) -> timedelta:
        if len(df) < 2:
            return timedelta(minutes=15)
        dt = df.index[-1] - df.index[-2]
        if isinstance(dt, pd.Timedelta):
            dt = dt.to_pytimedelta()
        if dt <= timedelta(0):
            return timedelta(minutes=15)
        return dt

    @staticmethod
    def _build_event_schedule(
        df: pd.DataFrame, earnings_col: str
    ) -> Dict[datetime.date, Tuple[datetime.date, datetime.date]]:
        """
        Map entry-date -> (event-date, exit-date).

        For an event on trading day D:
          entry day = previous trading day
          exit day  = next trading day
        """
        if earnings_col not in df.columns:
            return {}
        trading_days = sorted(pd.unique(df.index.date))
        if len(trading_days) < 3:
            return {}

        event_days = sorted(pd.unique(df[df[earnings_col].astype(bool)].index.date))
        mapping: Dict[datetime.date, Tuple[datetime.date, datetime.date]] = {}
        day_to_idx = {d: i for i, d in enumerate(trading_days)}

        for event_day in event_days:
            idx = day_to_idx.get(event_day)
            if idx is None or idx == 0 or idx >= len(trading_days) - 1:
                continue
            entry_day = trading_days[idx - 1]
            exit_day = trading_days[idx + 1]
            mapping[entry_day] = (event_day, exit_day)
        return mapping

    def _resolve_event_metadata_for_entry_bar(
        self,
        row: pd.Series,
        df: pd.DataFrame,
        signal_date: date,
    ) -> Optional[Tuple[date, date]]:
        """
        Resolve (event_date, exit_date) without requiring lookahead.

        Preferred path uses pre-known dataset features:
        - is_pre_earnings_day
        - days_to_earnings
        - next_earnings_date
        - planned_exit_date
        """
        pre_flag_col = self.config.get("pre_earnings_flag_col", "is_pre_earnings_day")
        days_col = self.config.get("days_to_earnings_col", "days_to_earnings")
        event_date_col = self.config.get("next_earnings_date_col", "next_earnings_date")
        exit_date_col = self.config.get("planned_exit_date_col", "planned_exit_date")

        is_pre_day = False
        if pre_flag_col in row.index:
            v = row.get(pre_flag_col)
            is_pre_day = bool(v) and str(v).strip().lower() not in {"0", "false", "nan", "none"}
        if not is_pre_day and days_col in row.index:
            dv = self._to_float(row.get(days_col))
            is_pre_day = dv is not None and abs(dv - 1.0) < 1e-9

        if not is_pre_day:
            return None

        event_date = self._to_date(row.get(event_date_col))
        exit_date = self._to_date(row.get(exit_date_col))

        if event_date is None:
            # As a weak fallback, infer "next calendar day".
            event_date = signal_date + timedelta(days=1)
        if exit_date is None:
            # If dataset doesn't provide explicit exit date, infer one day after event.
            exit_date = event_date + timedelta(days=1)

        return event_date, exit_date

    def _required_columns(self) -> List[str]:
        return [
            self.config.get("earnings_event_col", "earnings_event"),
            self.config.get("iv_front_col", "iv_front"),
            self.config.get("iv_back_col", "iv_back"),
            self.config.get("iv_far_col", "iv_45d"),
            self.config.get("iv30_col", "iv30"),
            self.config.get("rv30_col", "rv30"),
            self.config.get("volume30_col", "volume30"),
        ]

    @staticmethod
    def _to_date(value) -> Optional[date]:
        try:
            if value is None or pd.isna(value):
                return None
            if isinstance(value, datetime):
                return value.date()
            if isinstance(value, date):
                return value
            return pd.to_datetime(value).date()
        except Exception:
            return None

    def _get_event_schedule(
        self, df: pd.DataFrame, earnings_col: str
    ) -> Dict[datetime.date, Tuple[datetime.date, datetime.date]]:
        """
        Cached event schedule lookup.

        This avoids rebuilding the same schedule on every bar.
        """
        if len(df) == 0:
            return {}
        cache_key = (
            len(df),
            df.index[0],
            df.index[-1],
            earnings_col,
        )
        if cache_key != self._event_schedule_cache_key:
            self._event_schedule_cache = self._build_event_schedule(df, earnings_col)
            self._event_schedule_cache_key = cache_key
        return self._event_schedule_cache

    @staticmethod
    def _compute_confidence(
        term_slope: float,
        term_threshold: float,
        volume30: float,
        volume_threshold: float,
        ratio: float,
        ratio_threshold: float,
    ) -> float:
        # More negative slope => better; larger volume and ratio => better.
        slope_score = min(max((term_threshold - term_slope) / max(abs(term_threshold), 1e-6), 0.0), 2.0)
        vol_score = min(max(volume30 / max(volume_threshold, 1.0), 0.0), 2.0)
        ratio_score = min(max(ratio / max(ratio_threshold, 1e-6), 0.0), 2.0)
        raw = (slope_score + vol_score + ratio_score) / 6.0
        return float(50 + raw * 50)
