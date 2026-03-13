"""
Advanced Event-Driven Backtest Engine.

This module adds an event-driven orchestration layer while preserving the
existing backtest engine as-is. It does not modify legacy engine behavior.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, time
from enum import Enum
import hashlib
import heapq
import logging
from typing import Any, Callable, Dict, List, Optional, Tuple

import pandas as pd

from .backtest_engine import BacktestEngine, BacktestConfig
from .future_data_guard import FutureDataGuard

logger = logging.getLogger(__name__)


class EventType(str, Enum):
    BAR = "bar"
    POSITION_MANAGE = "position_manage"
    SIGNAL_EVAL = "signal_eval"
    SIGNAL = "signal"
    ORDER = "order"
    FILL = "fill"


@dataclass
class EngineEvent:
    """Generic event message used by the event bus."""

    event_type: EventType
    timestamp: datetime
    symbol: str
    priority: int = 50
    payload: Dict[str, Any] = field(default_factory=dict)


@dataclass(order=True)
class _QueuedEvent:
    """Heap item for deterministic event ordering."""

    sort_key: Tuple[datetime, int, int]
    event: EngineEvent = field(compare=False)


class EventBus:
    """Small in-memory priority event bus."""

    def __init__(self):
        self._handlers: Dict[EventType, List[Callable[[EngineEvent], None]]] = {}
        self._queue: List[_QueuedEvent] = []
        self._seq = 0

    def register(self, event_type: EventType, handler: Callable[[EngineEvent], None]) -> None:
        self._handlers.setdefault(event_type, []).append(handler)

    def emit(self, event: EngineEvent) -> None:
        item = _QueuedEvent(
            sort_key=(event.timestamp, event.priority, self._seq),
            event=event,
        )
        self._seq += 1
        heapq.heappush(self._queue, item)

    def process_due(self, up_to_ts: datetime) -> int:
        """
        Process all queued events with timestamp <= up_to_ts.

        Returns:
            Number of processed events.
        """
        processed = 0
        while self._queue and self._queue[0].sort_key[0] <= up_to_ts:
            queued = heapq.heappop(self._queue)
            handlers = self._handlers.get(queued.event.event_type, [])
            for handler in handlers:
                handler(queued.event)
            processed += 1
        return processed

    def clear(self) -> None:
        self._queue.clear()


class AdvancedEventBacktestEngine(BacktestEngine):
    """
    Event-driven backtest engine.

    It reuses execution, cost model, position lifecycle, and metrics from
    BacktestEngine, but orchestrates runtime via an event bus.
    """

    def __init__(self, config: BacktestConfig, strategy=None):
        super().__init__(config, strategy=strategy)
        self.event_bus = EventBus()
        self._strategy_uses_orb = True
        self._event_trace: List[Dict[str, Any]] = []
        self._trace_enabled = False
        self._runtime: Dict[str, Any] = {}
        self._register_handlers()

    def _register_handlers(self) -> None:
        self.event_bus.register(EventType.BAR, self._on_bar_event)
        self.event_bus.register(EventType.POSITION_MANAGE, self._on_position_manage_event)
        self.event_bus.register(EventType.SIGNAL_EVAL, self._on_signal_eval_event)
        self.event_bus.register(EventType.SIGNAL, self._on_signal_event)
        self.event_bus.register(EventType.ORDER, self._on_order_event)
        self.event_bus.register(EventType.FILL, self._on_fill_event)

    def _trace(self, event: EngineEvent, note: str = "") -> None:
        if not self._trace_enabled:
            return
        self._event_trace.append(
            {
                "timestamp": event.timestamp.isoformat(),
                "event_type": event.event_type.value,
                "priority": event.priority,
                "note": note,
            }
        )

    def run(self, progress_callback=None, enable_event_trace: bool = False) -> Dict[str, Any]:
        """
        Execute event-driven backtest.

        Args:
            progress_callback: Optional callback function(progress, message)
            enable_event_trace: If true, includes event timeline in results.
        """
        self.status = "RUNNING"
        self.progress = 0.0
        self._trace_enabled = bool(enable_event_trace)
        self._event_trace = []
        self._log_config_parameters()

        try:
            self._update_progress(5, "Fetching historical data...", progress_callback)

            def data_progress_callback(data_pct, message):
                overall_pct = 5 + (data_pct / 100.0) * 5
                self._update_progress(overall_pct, f"Data: {message}", progress_callback)

            df = self.data_provider.get_historical_data(
                self.config.symbol,
                self.config.timeframe,
                self.config.start_date,
                self.config.end_date,
                progress_callback=data_progress_callback,
                data_source=self.config.data_source,
                csv_files=self.config.csv_files,
            )
            if df is None or df.empty:
                raise ValueError("Failed to fetch historical data")

            is_valid, msg = self.data_provider.validate_data_quality(df)
            if not is_valid:
                raise ValueError(f"Data validation failed: {msg}")

            daily_df = self.data_provider.get_daily_data(
                self.config.symbol,
                self.config.start_date - pd.Timedelta(days=30),
                self.config.end_date,
                data_source=self.config.data_source,
            )

            # Store reference for ML feature extraction (V2/V3 features need df)
            self._df = df

            # Data fingerprint for reproducibility (Task 1.4)
            # Uses pd.util.hash_pandas_object for deterministic hashing across
            # OS line endings, pandas versions, and float formatting differences
            row_hashes = pd.util.hash_pandas_object(df, index=True)
            self._data_hash = hashlib.sha256(
                row_hashes.values.tobytes()
            ).hexdigest()
            logger.info(f"Data hash (SHA-256): {self._data_hash[:12]}...")

            self._update_progress(10, "Data loaded, starting event simulation...", progress_callback)

            if self.config.enable_cross_asset_filter:
                self._update_progress(12, "Initializing cross-asset regime filter...", progress_callback)
                self._initialize_cross_asset_filter(df)

            self.equity_curve = [(self.config.start_date, self.config.initial_balance)]
            trading_days = self.data_provider.get_trading_days(df)
            total_days = len(trading_days)

            self._strategy_uses_orb = (
                self.strategy is None or hasattr(self.strategy, "calculate_bias")
            )

            for day_idx, day in enumerate(trading_days):
                progress = 10 + (day_idx / max(1, total_days) * 80)
                self._update_progress(
                    progress,
                    f"Event loop day {day_idx + 1}/{total_days}: {day.date()}",
                    progress_callback,
                )

                if day.weekday() >= 5:
                    continue

                self._initialize_day(day, df, daily_df)
                if not self._strategy_uses_orb:
                    day_start = self.ny_tz.localize(datetime.combine(day.date(), time(0, 0)))
                    intraday_up_to = df[df.index <= day_start]
                    guarded_intraday = FutureDataGuard(df, len(intraday_up_to))
                    self.day_context = self.strategy.initialize_day(day, daily_df, guarded_intraday)
                    self.day_state.bias = self.day_context.bias
                    self.day_state.bias_strength = self.day_context.bias_strength
                    if self.day_context.atr > 0:
                        self.day_state.atr = self.day_context.atr
                    self.day_state.is_trending = True

                if not self.day_state.is_trending:
                    continue

                self._run_day_event_loop(day, df)

            self._update_progress(95, "Calculating performance metrics...", progress_callback)

            if self.open_position:
                last_bar = df.iloc[-1]
                self._close_position(last_bar, "End of backtest")

            results = self._compile_results()
            if self._trace_enabled:
                results["event_trace"] = self._event_trace
                results["engine_mode"] = "advanced_event_driven"

            self.status = "COMPLETED"
            self._update_progress(100, "Advanced event backtest completed", progress_callback)
            return results

        except Exception as e:
            self.status = "FAILED"
            self.error_message = str(e)
            logger.error(f"Advanced event backtest failed: {e}", exc_info=True)
            raise

        finally:
            self.event_bus.clear()
            self.data_provider.shutdown_mt5()

    def _run_day_event_loop(self, day: datetime, df: pd.DataFrame) -> None:
        """Generate bar events and process the event queue for one day."""
        if not self._strategy_uses_orb and self.strategy is not None:
            strat_start = self.strategy.config.get("trade_start_time", self.config.trade_start_time)
            strat_end = self.strategy.config.get("trade_end_time", self.config.trade_end_time)
            trade_start = self._parse_time(strat_start)
            trade_end = self._parse_time(strat_end)
        else:
            trade_start = self._parse_time(self.config.trade_start_time)
            trade_end = self._parse_time(self.config.trade_end_time)

        day_start = self.ny_tz.localize(datetime.combine(day.date(), time(0, 0)))
        day_end = self.ny_tz.localize(datetime.combine(day.date(), time(23, 59)))
        day_df = df[(df.index >= day_start) & (df.index <= day_end)]
        if day_df.empty:
            return

        # Always compute global offset — needed for ML feature extraction
        day_offset_in_df = 0
        if len(day_df) > 0:
            day_first_ts = day_df.index[0]
            day_offset_in_df = df.index.get_loc(day_first_ts)
            if isinstance(day_offset_in_df, slice):
                day_offset_in_df = day_offset_in_df.start

        self._runtime = {
            "day": day,
            "df": df,
            "day_df": day_df,
            "trade_start": trade_start,
            "trade_end": trade_end,
            "orb_end": self._parse_time(self.config.orb_end_time),
            "is_friday": day.weekday() == 4,
            "friday_close_time": time(self.config.friday_close_hour, self.config.friday_close_minute),
            "orb_calculated": False,
            "friday_closed": False,
            "day_offset_in_df": int(day_offset_in_df),
        }

        for i in range(len(day_df)):
            bar = day_df.iloc[i]
            bar_event = EngineEvent(
                event_type=EventType.BAR,
                timestamp=bar.name,
                symbol=self.config.symbol,
                priority=50,
                payload={"bar_idx": i},
            )
            self.event_bus.emit(bar_event)
            self.event_bus.process_due(bar.name)

        self.event_bus.process_due(day_df.index[-1])

    def _on_bar_event(self, event: EngineEvent) -> None:
        """Bar event -> decide follow-up events."""
        self._trace(event, "dispatch")
        r = self._runtime
        day_df: pd.DataFrame = r["day_df"]
        df: pd.DataFrame = r["df"]
        i = int(event.payload["bar_idx"])
        bar = day_df.iloc[i]
        bar_time = bar.name
        bar_time_only = bar_time.time()

        is_friday = bool(r["is_friday"])
        friday_close_time = r["friday_close_time"]

        if (
            is_friday
            and self.config.close_before_weekend
            and bar_time_only >= friday_close_time
            and not r["friday_closed"]
        ):
            if self.open_position:
                self._close_position(bar, "Friday Close (Weekend)")
            r["friday_closed"] = True
            return

        if self._strategy_uses_orb:
            if not r["orb_calculated"] and bar_time_only >= r["orb_end"]:
                orb_high, orb_low = self.data_provider.get_orb_levels(
                    df,
                    r["day"].date(),
                    self.config.orb_start_time,
                    self.config.orb_end_time,
                )
                self.day_state.orb_high = orb_high
                self.day_state.orb_low = orb_low
                r["orb_calculated"] = True
                self._calculate_bias(bar, day_df.iloc[: i + 1])

                if self.strategy is not None:
                    self.day_context = self._build_day_context()
                    self.day_context = self.strategy.calculate_bias(
                        self.day_context, bar["close"]
                    )
                    self.day_state.bias = self.day_context.bias
                    self.day_state.bias_strength = self.day_context.bias_strength

        trade_start = r["trade_start"]
        trade_end = r["trade_end"]
        if bar_time_only < trade_start or bar_time_only > trade_end:
            return

        if is_friday and self.config.close_before_weekend and bar_time_only >= friday_close_time:
            return

        if self._strategy_uses_orb:
            bars_up_to_now = day_df.iloc[: i + 1]
            signal_bars = day_df.iloc[:i]
            self._current_global_pos = r["day_offset_in_df"] + i + 1  # Global index for ML feature extraction
        else:
            global_pos = r["day_offset_in_df"] + i + 1
            bars_up_to_now = df.iloc[:global_pos]
            signal_bars = df.iloc[: global_pos - 1]
            self._current_global_pos = global_pos  # For ML feature extraction

        if self.open_position:
            self.event_bus.emit(
                EngineEvent(
                    event_type=EventType.POSITION_MANAGE,
                    timestamp=bar.name,
                    symbol=self.config.symbol,
                    priority=20,
                    payload={"bar": bar, "bars_up_to_now": bars_up_to_now},
                )
            )
            return

        if not self._can_open_trade():
            return

        if self._strategy_uses_orb:
            if self.day_state.orb_high is None or self.day_state.orb_low is None:
                return
            orb_range = self.day_state.orb_high - self.day_state.orb_low
            if orb_range < 0.50:
                return

        self.event_bus.emit(
            EngineEvent(
                event_type=EventType.SIGNAL_EVAL,
                timestamp=bar.name,
                symbol=self.config.symbol,
                priority=30,
                payload={
                    "bar": bar,
                    "signal_bars": signal_bars,
                    "bar_idx": i,
                },
            )
        )

    def _on_position_manage_event(self, event: EngineEvent) -> None:
        """Position management handler."""
        self._trace(event, "manage_position")
        bar = event.payload["bar"]
        bars_up_to_now = event.payload["bars_up_to_now"]
        self._manage_position(bar, bars_up_to_now)

    def _on_signal_eval_event(self, event: EngineEvent) -> None:
        """Signal evaluation handler."""
        self._trace(event, "eval_signal")
        bar = event.payload["bar"]
        signal_bars: pd.DataFrame = event.payload["signal_bars"]
        bar_idx = int(event.payload["bar_idx"])

        setup = None
        if self.strategy is not None:
            if len(signal_bars) < 2:
                return
            self.day_context = self._build_day_context()
            # Dynamic bias: recalculate on every bar using the last
            # completed bar's close.  The initial bias at ORB end is often
            # "neutral" because price hasn't broken ORB yet; updating it
            # here captures breakouts that happen later in the session.
            # This matches the legacy BacktestEngine behaviour (line 735).
            if self._strategy_uses_orb and self._runtime.get("orb_calculated"):
                signal_price = signal_bars.iloc[-1]["close"] if len(signal_bars) > 0 else bar["close"]
                self.day_context = self.strategy.calculate_bias(
                    self.day_context, signal_price
                )
                self.day_state.bias = self.day_context.bias
                self.day_state.bias_strength = self.day_context.bias_strength
            try:
                self.day_context.levels["execution_open"] = float(bar["open"])
            except Exception:
                pass
            signal_bar = signal_bars.iloc[-1]
            # Wrap with FutureDataGuard unless strategy opts in to using
            # known-ahead event calendars (e.g., earnings schedule metadata).
            allow_event_lookahead = bool(
                getattr(self.strategy, "config", {}).get("allow_event_lookahead", False)
            )
            if self._strategy_uses_orb:
                guarded_df = FutureDataGuard(self._runtime["day_df"], bar_idx)
            elif allow_event_lookahead:
                guarded_df = self._runtime["df"]
            else:
                guarded_df = FutureDataGuard(self._runtime["df"], self._current_global_pos - 1)
            trade_setup = self.strategy.find_setup(
                signal_bar,
                guarded_df,
                self.day_context,
                bar_idx,
            )
            if trade_setup:
                setup = {
                    "direction": trade_setup.direction,
                    "sl": trade_setup.stop_loss,
                    "tp": trade_setup.take_profit,
                    "setup_type": trade_setup.setup_type,
                    "fvg": trade_setup.metadata.get("fvg"),
                    "ob": trade_setup.metadata.get("ob"),
                    "bias_strength": int(trade_setup.confidence),
                    "metadata": trade_setup.metadata,
                }
        else:
            if len(signal_bars) < 2:
                return
            setup = self._find_trade_setup(signal_bars)

        if not setup:
            return

        if self.cross_asset_filter is not None and self.cross_asset_filter.enabled:
            allowed, risk_mul, decision, reason = self.cross_asset_filter.allow_trade(
                setup["direction"], bar.name
            )
            if not allowed:
                return
            setup["risk_multiplier"] = risk_mul
            setup_meta = setup.setdefault("metadata", {})
            setup_meta["cross_asset_reason"] = reason
            setup_meta["cross_asset_risk_multiplier"] = float(risk_mul)
            setup_meta["cross_asset_decision"] = self.cross_asset_filter.decision_to_metadata(decision)

        self.event_bus.emit(
            EngineEvent(
                event_type=EventType.SIGNAL,
                timestamp=bar.name,
                symbol=self.config.symbol,
                priority=40,
                payload={"setup": setup, "bar": bar},
            )
        )

    def _on_signal_event(self, event: EngineEvent) -> None:
        """Signal -> order conversion handler."""
        self._trace(event, "signal_to_order")
        setup = event.payload["setup"]
        bar = event.payload["bar"]

        self.event_bus.emit(
            EngineEvent(
                event_type=EventType.ORDER,
                timestamp=bar.name,
                symbol=self.config.symbol,
                priority=45,
                payload={"setup": setup, "bar": bar},
            )
        )

    def _on_order_event(self, event: EngineEvent) -> None:
        """Order execution handler."""
        self._trace(event, "execute_order")
        if self.open_position is not None:
            return
        setup = event.payload["setup"]
        bar = event.payload["bar"]
        self._execute_trade(setup, bar)
        # trade_counter increments on close; a fill is confirmed by an open position.
        if self.open_position is not None:
            self.event_bus.emit(
                EngineEvent(
                    event_type=EventType.FILL,
                    timestamp=bar.name,
                    symbol=self.config.symbol,
                    priority=46,
                    payload={"trade_number": self.trade_counter + 1, "direction": setup.get("direction")},
                )
            )

    def _on_fill_event(self, event: EngineEvent) -> None:
        """Fill acknowledgment handler."""
        self._trace(event, "fill_ack")
