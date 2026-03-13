"""
HTF FVG + Liquidity Reclaim - live strategy adapter.

This runner deliberately reuses the backtest strategy as the signal engine so
the live path does not drift away from the tested setup logic.
"""

from __future__ import annotations

import os
import sys
from dataclasses import dataclass
from datetime import datetime, time as dt_time
from typing import Any, Dict, Optional

import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from Strategies.base import BaseStrategy, StrategyInfo, StrategyRegistry


@dataclass
class _LivePositionProxy:
    direction: str
    entry_price: float
    stop_loss: float
    take_profit: Optional[float]
    entry_time: Any
    fvg_top: Optional[float]
    fvg_bottom: Optional[float]
    strategy_metadata: Dict[str, Any]


@StrategyRegistry.register
class HTFFVGLiquidityReclaimLiveStrategy(BaseStrategy):
    """Live runner for HTF FVG + Liquidity Reclaim."""

    @classmethod
    def get_info(cls) -> StrategyInfo:
        return StrategyInfo(
            id="htf_fvg_liquidity_reclaim_strategy",
            name="HTF FVG + Liquidity Reclaim",
            description=(
                "Trades lower-timeframe reclaims into higher-timeframe FVG zones "
                "after a fresh liquidity sweep rejection confirms the setup."
            ),
            version="1.0.0",
            author="ProTradingSystem",
            timeframes=["M5", "M15", "M30"],
            symbols=["XAUUSD", "NAS100", "US500"],
            parameters={
                "risk_percent": 0.75,
                "min_rejection_ratio": 0.30,
                "min_rr_ratio": 2.5,
                "trade_start_time": "03:00",
                "trade_end_time": "20:00",
            },
        )

    def __init__(self):
        super().__init__()
        self.mt5 = None
        self.logger = None
        self.symbol = ""
        self.magic = 0
        self.current_date = None
        self.last_signal_time = None
        self._position_metadata_by_ticket: Dict[int, Dict[str, Any]] = {}
        self._latest_diagnostics: Dict[str, Any] = {}

    def initialize(self) -> bool:
        try:
            import MetaTrader5 as mt5
            from dashboard.backend.core.strategies.htf_fvg_liquidity_reclaim_strategy import (
                HTFFVGLiquidityReclaimStrategy,
            )
            from Strategies.shared import (
                BotStateManager,
                DataManager,
                RiskManager,
                TradeExecutor,
                setup_logger,
            )
            from Strategies.shared.broker_timezone import (
                detect_broker_timezone,
                get_ny_timezone,
            )
            from .config import (
                BASE_SYMBOL,
                DATA_CACHE_BARS,
                FRIDAY_CLOSE_HOUR,
                FRIDAY_CLOSE_MINUTE,
                INITIAL_BALANCE,
                MAGIC_NUMBER,
                MAX_DAILY_LOSS_USD,
                MAX_DAILY_TRADES,
                MAX_SL_USD,
                MAX_SPREAD_USD,
                MAX_TOTAL_RISK_USD,
                MIN_BARS_FOR_ANALYSIS,
                MIN_RR_RATIO,
                MIN_SL_USD,
                POLL_INTERVAL_SECONDS,
                PRESET_ID,
                RISK_PERCENT,
                STATE_FILE,
                STRATEGY_CONFIG,
                STRATEGY_ID,
                STRATEGY_NAME,
                TARGET_SYMBOL,
                TIMEFRAME,
                TIMEFRAME_LABEL,
                TRADE_END_TIME,
                TRADE_START_TIME,
                TRAILING_ATR_MULTIPLIER,
                TRAILING_ATR_PERIOD,
                USE_TRAILING,
            )

            if not mt5.initialize():
                self.error_message = f"MT5 Init Failed: {mt5.last_error()}"
                return False

            if not mt5.symbol_select(TARGET_SYMBOL, True):
                self.error_message = f"Symbol {TARGET_SYMBOL} not available"
                return False

            import time as time_module

            time_module.sleep(1)
            if mt5.symbol_info_tick(TARGET_SYMBOL) is None:
                self.error_message = f"No price data for {TARGET_SYMBOL}"
                return False

            self.mt5 = mt5
            self.symbol = TARGET_SYMBOL
            self.magic = MAGIC_NUMBER
            self.min_sl = float(MIN_SL_USD)
            self.max_sl = float(MAX_SL_USD)
            self.min_rr_ratio = float(MIN_RR_RATIO)
            self.poll_interval = max(2, int(POLL_INTERVAL_SECONDS))
            self.trade_start = TRADE_START_TIME
            self.trade_end = TRADE_END_TIME
            self.friday_close_hour = int(FRIDAY_CLOSE_HOUR)
            self.friday_close_minute = int(FRIDAY_CLOSE_MINUTE)
            self.min_bars = int(MIN_BARS_FOR_ANALYSIS)
            self.live_cfg = dict(STRATEGY_CONFIG)
            self.base_symbol = str(BASE_SYMBOL)
            self.preset_id = str(PRESET_ID)
            self.timeframe_label = str(TIMEFRAME_LABEL)

            self.logger = setup_logger(
                "HTFFVGLiquidityReclaimStrategy",
                str(os.path.join(os.path.dirname(__file__), "logs")),
            )
            self.broker_tz = detect_broker_timezone(mt5, TARGET_SYMBOL)
            self.ny_tz = get_ny_timezone()

            self.data_manager = DataManager(
                TARGET_SYMBOL,
                self.broker_tz,
                self.ny_tz,
                TIMEFRAME,
                DATA_CACHE_BARS,
                self.logger,
            )
            self.risk_manager = RiskManager(
                TARGET_SYMBOL,
                MAGIC_NUMBER,
                RISK_PERCENT,
                MAX_SPREAD_USD,
                MAX_DAILY_LOSS_USD,
                MAX_TOTAL_RISK_USD,
                MAX_DAILY_TRADES,
                INITIAL_BALANCE,
                MIN_SL_USD,
                MAX_SL_USD,
                self.logger,
            )
            self.trade_executor = TradeExecutor(
                TARGET_SYMBOL,
                MAGIC_NUMBER,
                use_trailing=USE_TRAILING,
                trailing_atr_period=TRAILING_ATR_PERIOD,
                trailing_atr_multiplier=TRAILING_ATR_MULTIPLIER,
                logger=self.logger,
            )
            self.state_manager = BotStateManager(str(STATE_FILE), STRATEGY_ID, STRATEGY_NAME)
            self.strategy = HTFFVGLiquidityReclaimStrategy(dict(STRATEGY_CONFIG))

            self.logger.info("=" * 60)
            self.logger.info("HTF FVG + LIQUIDITY RECLAIM STRATEGY INITIALIZED")
            self.logger.info(
                "Symbol: %s | Base: %s | TF: %s | Preset: %s",
                TARGET_SYMBOL,
                self.base_symbol,
                TIMEFRAME_LABEL,
                self.preset_id,
            )
            self.logger.info(
                "Risk: %.2f%% | Window: %s-%s NY | Bars: %s",
                float(RISK_PERCENT),
                TRADE_START_TIME,
                TRADE_END_TIME,
                DATA_CACHE_BARS,
            )
            self.logger.info("=" * 60)
            return True

        except Exception as exc:
            self.error_message = str(exc)
            return False

    def run(self):
        import time as time_module

        self.logger.info("BOT STARTED - Entering main loop")

        while self._running:
            try:
                terminal = self.mt5.terminal_info()
                if terminal is None or not terminal.connected:
                    self.logger.warning("MT5 disconnected - reconnecting...")
                    if not self.mt5.initialize():
                        time_module.sleep(10)
                        continue

                now = self._get_current_time_ny()
                if now is None:
                    time_module.sleep(1)
                    continue

                if self.current_date != now.date():
                    self._handle_new_day(now.date())

                df = self.data_manager.get_data()
                if df.empty or len(df) < (self.min_bars + 1):
                    self._latest_diagnostics = {
                        "bias": "neutral",
                        "bias_strength": 0,
                        "setup_detected": False,
                        "fvg_detected": False,
                        "sweep_detected": False,
                        "rejection_confirmed": False,
                        "strategy_preset": self.preset_id,
                        "timeframe": self.timeframe_label,
                    }
                    self._update_dashboard_state(now)
                    time_module.sleep(5)
                    continue

                signal_bars = df.iloc[:-1].copy()
                current_live_bar = df.iloc[-1]
                signal_bar_time = signal_bars.index[-1]
                day_context = self._build_day_context(signal_bars, current_live_bar)

                self._sync_position_metadata()
                self.trade_executor.manage_trailing_stops(self.data_manager)
                self._maybe_close_early(signal_bars, day_context)

                if now.weekday() == 4 and now.time() > dt_time(self.friday_close_hour, self.friday_close_minute):
                    self.trade_executor.close_all_positions("Friday Close")
                    self._position_metadata_by_ticket.clear()
                    self._latest_diagnostics["invalidation_reason"] = "friday_close"
                    self._update_dashboard_state(now)
                    time_module.sleep(60)
                    continue

                self.risk_manager.check_daily_status()

                if not (self.trade_start <= now.time() <= self.trade_end):
                    self._latest_diagnostics.update(
                        {
                            "bias": day_context.bias,
                            "bias_strength": day_context.bias_strength,
                            "setup_detected": False,
                            "fvg_detected": False,
                            "sweep_detected": False,
                            "rejection_confirmed": False,
                            "strategy_preset": self.preset_id,
                            "timeframe": self.timeframe_label,
                        }
                    )
                    self._update_dashboard_state(now)
                    time_module.sleep(15)
                    continue

                if self.last_signal_time == signal_bar_time:
                    self._update_dashboard_state(now)
                    time_module.sleep(2)
                    continue
                self.last_signal_time = signal_bar_time

                setup = self._find_trade_setup(signal_bars, day_context)
                positions = self._managed_positions()

                if setup and not positions and self.risk_manager.can_trade and self.risk_manager.can_open_new_position():
                    self._execute_setup(setup)

                self._update_dashboard_state(now)
                time_module.sleep(self.poll_interval)

            except KeyboardInterrupt:
                break
            except Exception as exc:
                self.logger.error("Loop error: %s", exc, exc_info=True)
                self._latest_diagnostics["loop_error"] = str(exc)
                time_module.sleep(5)

    def shutdown(self):
        if hasattr(self, "state_manager") and self.state_manager:
            self.state_manager.set_stopped()
        if hasattr(self, "mt5") and self.mt5:
            self.mt5.shutdown()
        if self.logger:
            self.logger.info("Bot shutdown complete")

    def get_state(self) -> Dict[str, Any]:
        if hasattr(self, "state_manager") and self.state_manager:
            return self.state_manager.read_state()
        return {"strategy_id": "htf_fvg_liquidity_reclaim_strategy", "is_running": self._running}

    def _get_current_time_ny(self):
        tick = self.mt5.symbol_info_tick(self.symbol)
        if tick is None:
            return None
        broker_now = datetime.fromtimestamp(tick.time).replace(tzinfo=self.broker_tz)
        return broker_now.astimezone(self.ny_tz)

    def _handle_new_day(self, today):
        self.current_date = today
        self.last_signal_time = None
        self.data_manager.clear_cache()
        self.trade_executor.last_atr_time = None
        self.trade_executor.cached_atr = None
        self.logger.info("NEW TRADING DAY: %s", today)

    def _managed_positions(self):
        positions = self.mt5.positions_get(symbol=self.symbol)
        if not positions:
            return []
        return [p for p in positions if int(getattr(p, "magic", 0) or 0) == int(self.magic)]

    def _sync_position_metadata(self):
        live_tickets = {int(p.ticket) for p in self._managed_positions()}
        stale = [ticket for ticket in self._position_metadata_by_ticket if ticket not in live_tickets]
        for ticket in stale:
            self._position_metadata_by_ticket.pop(ticket, None)

    def _build_daily_df(self, signal_bars: pd.DataFrame) -> pd.DataFrame:
        if signal_bars.empty:
            return pd.DataFrame(columns=["open", "high", "low", "close", "volume"])
        use_df = signal_bars.copy()
        if "volume" not in use_df.columns:
            use_df["volume"] = 0.0
        return (
            use_df[["open", "high", "low", "close", "volume"]]
            .resample("1D")
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

    def _build_day_context(self, signal_bars: pd.DataFrame, current_live_bar: pd.Series):
        daily_df = self._build_daily_df(signal_bars)
        asof = signal_bars.index[-1].to_pydatetime() if hasattr(signal_bars.index[-1], "to_pydatetime") else signal_bars.index[-1]
        day_context = self.strategy.initialize_day(asof, daily_df, signal_bars)
        day_context.levels["execution_open"] = float(current_live_bar.get("open") or signal_bars.iloc[-1]["close"])
        return day_context

    def _find_trade_setup(self, signal_bars: pd.DataFrame, day_context) -> Optional[Any]:
        bar = signal_bars.iloc[-1]
        setup = self.strategy.find_setup(
            bar=bar,
            df=signal_bars,
            day_context=day_context,
            current_bar_index=len(signal_bars) - 1,
        )
        diagnostics = {
            "bias": day_context.bias,
            "bias_strength": day_context.bias_strength,
            "strategy_preset": self.preset_id,
            "timeframe": self.timeframe_label,
            "setup_detected": bool(setup),
            "fvg_detected": bool(setup),
            "sweep_detected": bool(setup),
            "rejection_confirmed": bool(setup),
        }
        if setup:
            meta = setup.metadata or {}
            fvg = meta.get("fvg") if isinstance(meta.get("fvg"), dict) else {}
            diagnostics.update(
                {
                    "entry_price": float(setup.entry_price),
                    "stop_loss": float(setup.stop_loss),
                    "take_profit": float(setup.take_profit) if setup.take_profit is not None else None,
                    "rr": float(meta.get("expected_rr") or 0.0),
                    "sweep_quality": str(meta.get("sweep_quality") or ""),
                    "fvg_quality": str(fvg.get("quality_label") or ""),
                    "htf_timeframe": str(fvg.get("timeframe") or ""),
                    "confidence": float(setup.confidence),
                    "last_signal": str(setup.setup_type),
                    "invalidation_reason": None,
                }
            )
        self._latest_diagnostics = diagnostics
        return setup

    def _execute_setup(self, setup: Any) -> bool:
        if not self.risk_manager.validate_spread():
            self.logger.info("Setup skipped: spread too high")
            self._latest_diagnostics["invalidation_reason"] = "spread_too_high"
            return False

        tick = self.mt5.symbol_info_tick(self.symbol)
        symbol_info = self.mt5.symbol_info(self.symbol)
        if tick is None or symbol_info is None:
            self._latest_diagnostics["invalidation_reason"] = "market_data_unavailable"
            return False

        entry_price = float(tick.ask if str(setup.direction).upper() == "BUY" else tick.bid)
        stop_loss = float(setup.stop_loss)
        sl_distance = abs(entry_price - stop_loss)
        if sl_distance < float(self.min_sl) or sl_distance > float(self.max_sl):
            self.logger.info(
                "Setup skipped: structural SL %.4f outside live bounds [%.4f, %.4f]",
                sl_distance,
                float(self.min_sl),
                float(self.max_sl),
            )
            self._latest_diagnostics["invalidation_reason"] = "stop_loss_out_of_bounds"
            return False

        min_stop_distance = float(getattr(symbol_info, "trade_stops_level", 0) or 0) * float(getattr(symbol_info, "point", 0) or 0)
        if min_stop_distance > 0.0 and sl_distance < min_stop_distance:
            self.logger.info(
                "Setup skipped: SL %.4f is inside broker stops level %.4f",
                sl_distance,
                min_stop_distance,
            )
            self._latest_diagnostics["invalidation_reason"] = "broker_stops_level_violation"
            return False

        target_price = float(setup.take_profit) if setup.take_profit is not None else None
        rr_ratio = 0.0
        if target_price is not None and sl_distance > 0.0:
            rr_ratio = abs(target_price - entry_price) / sl_distance
        if rr_ratio < float(self.min_rr_ratio):
            self.logger.info(
                "Setup skipped: actual live RR %.2f is below minimum %.2f",
                rr_ratio,
                float(self.min_rr_ratio),
            )
            self._latest_diagnostics["invalidation_reason"] = "rr_below_minimum"
            return False

        lot_size = float(self.risk_manager.calculate_position_size(sl_distance))
        if lot_size <= 0.0:
            self._latest_diagnostics["invalidation_reason"] = "lot_size_invalid"
            return False

        before_tickets = {int(p.ticket) for p in self._managed_positions()}
        comment = f"HTFReclaim {self.preset_id}"[:31]
        ok = self.trade_executor.execute_trade(
            direction=str(setup.direction).upper(),
            entry_price=entry_price,
            sl_price=stop_loss,
            lot_size=lot_size,
            comment=comment,
            rr_ratio=rr_ratio,
        )
        if not ok:
            self._latest_diagnostics["invalidation_reason"] = "order_send_failed"
            return False

        positions = self._managed_positions()
        target_pos = None
        for pos in positions:
            if int(pos.ticket) not in before_tickets:
                target_pos = pos
                break
        if target_pos is None and positions:
            target_pos = max(positions, key=lambda p: int(getattr(p, "time", 0) or 0))

        meta = dict(setup.metadata or {})
        meta["planned_take_profit"] = target_price
        meta["actual_entry_price"] = entry_price
        meta["actual_rr"] = rr_ratio
        meta["lot_size"] = lot_size
        meta["entry_time_live"] = datetime.utcnow().isoformat()
        if target_pos is not None:
            self._position_metadata_by_ticket[int(target_pos.ticket)] = meta

        self.logger.info(
            "TRADE EXECUTED | %s %.2f | SL %.2f | TP %.2f | RR %.2f | Lot %.2f",
            str(setup.direction).upper(),
            float(entry_price),
            float(stop_loss),
            float(target_price or 0.0),
            float(rr_ratio),
            float(lot_size),
        )
        self._latest_diagnostics.update(
            {
                "entry_price": float(entry_price),
                "stop_loss": float(stop_loss),
                "take_profit": float(target_price) if target_price is not None else None,
                "rr": float(rr_ratio),
                "lot_size": float(lot_size),
                "invalidation_reason": None,
            }
        )
        return True

    def _maybe_close_early(self, signal_bars: pd.DataFrame, day_context) -> None:
        positions = self._managed_positions()
        if not positions:
            return
        bar = signal_bars.iloc[-1]
        for pos in positions:
            meta = self._position_metadata_by_ticket.get(int(pos.ticket))
            if not isinstance(meta, dict):
                continue
            proxy = _LivePositionProxy(
                direction="BUY" if int(getattr(pos, "type", 1) or 1) == 0 else "SELL",
                entry_price=float(getattr(pos, "price_open", 0.0) or 0.0),
                stop_loss=float(getattr(pos, "sl", 0.0) or 0.0),
                take_profit=float(getattr(pos, "tp", 0.0) or 0.0) if getattr(pos, "tp", None) else None,
                entry_time=(
                    pd.to_datetime(int(getattr(pos, "time", 0) or 0), unit="s", utc=True).tz_convert(self.ny_tz)
                    if int(getattr(pos, "time", 0) or 0) > 0
                    else meta.get("entry_time_live")
                    or signal_bars.index[-1]
                ),
                fvg_top=float(meta.get("fvg_top")) if meta.get("fvg_top") is not None else None,
                fvg_bottom=float(meta.get("fvg_bottom")) if meta.get("fvg_bottom") is not None else None,
                strategy_metadata=meta,
            )
            reason = self.strategy.should_close_early(bar, signal_bars, proxy, day_context)
            if reason:
                self.logger.info("EARLY EXIT | Ticket %s | Reason: %s", pos.ticket, reason)
                self.trade_executor.close_all_positions(str(reason)[:31])
                self._position_metadata_by_ticket.clear()
                self._latest_diagnostics["invalidation_reason"] = str(reason)
                break

    def _update_dashboard_state(self, now) -> None:
        try:
            tick = self.mt5.symbol_info_tick(self.symbol)
            account = self.mt5.account_info()
            positions = self._managed_positions()
            extras = dict(self._latest_diagnostics or {})
            extras.setdefault("base_symbol", self.base_symbol)
            extras.setdefault("strategy_preset", self.preset_id)
            extras.setdefault("timeframe", self.timeframe_label)
            self.state_manager.update_state(
                is_running=True,
                current_time_ny=now.isoformat() if now else None,
                current_price=tick.bid if tick else None,
                spread=round(tick.ask - tick.bid, 3) if tick else None,
                session_bias=extras.get("bias"),
                is_trending=str(extras.get("bias") or "").lower() in {"bullish", "bearish"},
                daily_trades=self.risk_manager.daily_trades_count,
                daily_pnl=sum(float(getattr(p, "profit", 0.0) or 0.0) for p in positions) if positions else 0.0,
                can_trade=self.risk_manager.can_trade,
                balance=account.balance if account else 0.0,
                equity=account.equity if account else 0.0,
                margin_level=account.margin_level if account else None,
                open_positions=len(positions),
                last_signal=extras.get("last_signal"),
                error_message=self.error_message,
                **extras,
            )
        except Exception:
            pass
