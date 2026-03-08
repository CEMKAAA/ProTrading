"""
Session Liquidity Sweep Reversal - Live Strategy
Registered with StrategyRegistry

Exploits institutional stop-hunting at session levels (Asian H/L,
Previous Day H/L, round numbers) with reversal entries confirmed
by displacement and optional FVG.

Trades only during NY-London overlap (9:30-12:00 NY).
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

import numpy as np
import pandas as pd
from typing import Dict, Any, Optional, List
from Strategies.base import BaseStrategy, StrategyInfo, StrategyRegistry


@StrategyRegistry.register
class LiquiditySweepLiveStrategy(BaseStrategy):
    """
    Session Liquidity Sweep Reversal Strategy for XAUUSD.

    Detects sweeps of key liquidity levels (Asian H/L, Previous Day H/L,
    round numbers) followed by displacement rejections and optional FVG
    confirmation. Enters on the reversal side.

    Runs on M5 timeframe during NY-London overlap (9:30-12:00 NY).
    """

    @classmethod
    def get_info(cls) -> StrategyInfo:
        return StrategyInfo(
            id="liquidity_sweep_strategy",
            name="Session Liquidity Sweep Reversal",
            description=(
                "Detects institutional liquidity sweeps at session levels "
                "(Asian H/L, PD H/L, round numbers) and enters reversals "
                "confirmed by displacement and FVG. Trades NY-London overlap only."
            ),
            version="1.0.0",
            author="ProTrading",
            timeframes=["M5"],
            symbols=["XAUUSD"],
            parameters={
                "risk_percent": 1.0,
                "sweep_min_penetration_atr": 0.3,
                "sweep_max_bars_to_reject": 3,
                "rejection_body_percentile": 60,
                "require_fvg_after_sweep": True,
                "min_rr_ratio": 3.0,
                "sl_buffer_atr": 0.3,
                "trade_start_time": "09:30",
                "trade_end_time": "12:00",
            }
        )

    def __init__(self):
        super().__init__()
        self.mt5 = None
        self.logger = None

    # ------------------------------------------------------------------
    # BaseStrategy interface
    # ------------------------------------------------------------------

    def initialize(self) -> bool:
        try:
            import MetaTrader5 as mt5
            from .config import (
                TARGET_SYMBOL, MAGIC_NUMBER, TIMEFRAME, STRATEGY_ID, STRATEGY_NAME,
                RISK_PERCENT, MAX_SPREAD_USD, MAX_DAILY_LOSS_USD, MAX_TOTAL_RISK_USD,
                MAX_DAILY_TRADES, INITIAL_BALANCE, MIN_SL_USD, MAX_SL_USD,
                USE_TRAILING, TRAILING_ATR_PERIOD, TRAILING_ATR_MULTIPLIER,
                DATA_CACHE_BARS, STATE_FILE, MIN_BARS_FOR_ANALYSIS,
                SWEEP_MIN_PENETRATION_ATR, SWEEP_MAX_BARS_TO_REJECT,
                REJECTION_BODY_PERCENTILE, REQUIRE_FVG_AFTER_SWEEP,
                MIN_RR_RATIO, SL_BUFFER_ATR,
                USE_ROUND_NUMBERS, ROUND_NUMBER_INTERVAL,
                TRADE_START_TIME, TRADE_END_TIME,
            )
            from Strategies.shared import (
                setup_logger, BotStateManager, DataManager,
                RiskManager, TradeExecutor, Indicators, SessionLevelDetector,
            )
            import pytz

            if not mt5.initialize():
                self.error_message = "MT5 Init Failed"
                return False
            if not mt5.symbol_select(TARGET_SYMBOL, True):
                self.error_message = f"Symbol {TARGET_SYMBOL} not available"
                return False

            import time
            time.sleep(1)
            if mt5.symbol_info_tick(TARGET_SYMBOL) is None:
                self.error_message = "No price data"
                return False

            self.mt5 = mt5
            self.symbol = TARGET_SYMBOL
            self.magic = MAGIC_NUMBER
            self.logger = setup_logger(
                'LiquiditySweepStrategy',
                str(os.path.join(os.path.dirname(__file__), 'logs'))
            )
            from Strategies.shared.broker_timezone import detect_broker_timezone, get_ny_timezone
            self.broker_tz = detect_broker_timezone(mt5, TARGET_SYMBOL)
            self.ny_tz = get_ny_timezone()

            self.data_manager = DataManager(
                TARGET_SYMBOL, self.broker_tz, self.ny_tz,
                TIMEFRAME, DATA_CACHE_BARS, self.logger
            )
            self.risk_manager = RiskManager(
                TARGET_SYMBOL, MAGIC_NUMBER, RISK_PERCENT, MAX_SPREAD_USD,
                MAX_DAILY_LOSS_USD, MAX_TOTAL_RISK_USD, MAX_DAILY_TRADES,
                INITIAL_BALANCE, MIN_SL_USD, MAX_SL_USD, self.logger
            )
            self.trade_executor = TradeExecutor(
                TARGET_SYMBOL, MAGIC_NUMBER, use_trailing=USE_TRAILING,
                trailing_atr_period=TRAILING_ATR_PERIOD,
                trailing_atr_multiplier=TRAILING_ATR_MULTIPLIER, logger=self.logger
            )
            self.state_manager = BotStateManager(
                str(STATE_FILE), STRATEGY_ID, STRATEGY_NAME
            )
            self.indicators = Indicators
            self.session_detector = SessionLevelDetector(self.data_manager, self.ny_tz)

            # Strategy-specific config
            self.sweep_min_pen = SWEEP_MIN_PENETRATION_ATR
            self.sweep_max_bars = SWEEP_MAX_BARS_TO_REJECT
            self.body_percentile = REJECTION_BODY_PERCENTILE
            self.require_fvg = REQUIRE_FVG_AFTER_SWEEP
            self.min_rr = MIN_RR_RATIO
            self.sl_buffer_atr = SL_BUFFER_ATR
            self.use_round_numbers = USE_ROUND_NUMBERS
            self.round_interval = ROUND_NUMBER_INTERVAL
            self.min_bars = MIN_BARS_FOR_ANALYSIS
            self.trade_start = TRADE_START_TIME
            self.trade_end = TRADE_END_TIME

            self.current_date = None
            self.last_signal_time = None
            self.session_levels = {}

            self.logger.info("=" * 60)
            self.logger.info("LIQUIDITY SWEEP STRATEGY INITIALIZED")
            self.logger.info(f"Symbol: {TARGET_SYMBOL} | TF: M5")
            self.logger.info(f"Magic: {MAGIC_NUMBER}")
            self.logger.info(f"Trade Window: {TRADE_START_TIME}-{TRADE_END_TIME} NY")
            self.logger.info(f"Sweep Pen: {self.sweep_min_pen} ATR | Max Reject Bars: {self.sweep_max_bars}")
            self.logger.info(f"Min R:R: {self.min_rr} | FVG Required: {self.require_fvg}")
            self.logger.info("=" * 60)

            return True

        except Exception as e:
            self.error_message = str(e)
            return False

    def run(self):
        from datetime import time as dt_time
        import time as time_module

        while self._running:
            try:
                terminal = self.mt5.terminal_info()
                if terminal is None or not terminal.connected:
                    if not self.mt5.initialize():
                        time_module.sleep(10)
                        continue

                now = self._get_current_time_ny()
                if now is None:
                    time_module.sleep(1)
                    continue

                self._update_dashboard_state(now)

                # Handle new day
                if self.current_date != now.date():
                    self._handle_new_day(now.date())

                # Friday close
                if now.weekday() == 4 and now.time() > dt_time(15, 30):
                    self.trade_executor.close_all_positions("Friday Close")
                    self.logger.info("Friday close - sleeping until Monday")
                    time_module.sleep(300)
                    continue

                # Trading hours: NY-London overlap only (9:30-12:00)
                if not (self.trade_start <= now.time() <= self.trade_end):
                    time_module.sleep(30)
                    continue

                # Manage trailing stops
                self.trade_executor.manage_trailing_stops(self.data_manager)

                # Check daily risk limits
                self.risk_manager.check_daily_status()
                if not self.risk_manager.can_trade or not self.risk_manager.can_open_new_position():
                    time_module.sleep(60)
                    continue

                # Get data
                df = self.data_manager.get_data()
                if df.empty or len(df) < self.min_bars:
                    time_module.sleep(10)
                    continue

                # Prevent duplicate signals on same bar
                signal_time = df.index[-2]
                if self.last_signal_time == signal_time:
                    time_module.sleep(5)
                    continue
                self.last_signal_time = signal_time

                # Find trade setup
                setup = self._find_trade_setup(df)
                if setup:
                    self.logger.info(f"SETUP: {setup['reason']}")
                    self._execute_setup(setup)

                time_module.sleep(10)  # M5 timeframe

            except KeyboardInterrupt:
                break
            except Exception as e:
                self.logger.error(f"Loop error: {e}", exc_info=True)
                time_module.sleep(10)

    def shutdown(self):
        if hasattr(self, 'state_manager') and self.state_manager:
            self.state_manager.set_stopped()
        if hasattr(self, 'mt5') and self.mt5:
            self.mt5.shutdown()

    def get_state(self) -> Dict[str, Any]:
        if hasattr(self, 'state_manager') and self.state_manager:
            return self.state_manager.read_state()
        return {"strategy_id": "liquidity_sweep_strategy", "is_running": self._running}

    # ------------------------------------------------------------------
    # Core methods
    # ------------------------------------------------------------------

    def _get_current_time_ny(self):
        from datetime import datetime
        tick = self.mt5.symbol_info_tick(self.symbol)
        if tick is None:
            return None
        return datetime.fromtimestamp(tick.time).replace(tzinfo=self.broker_tz).astimezone(self.ny_tz)

    def _update_dashboard_state(self, now):
        try:
            tick = self.mt5.symbol_info_tick(self.symbol)
            account = self.mt5.account_info()
            positions = self.mt5.positions_get(symbol=self.symbol)
            self.state_manager.update_state(
                is_running=True,
                current_time_ny=now.isoformat(),
                current_price=tick.bid if tick else None,
                spread=round(tick.ask - tick.bid, 3) if tick else None,
                asian_high=self.session_levels.get('asian_high'),
                asian_low=self.session_levels.get('asian_low'),
                daily_trades=self.risk_manager.daily_trades_count,
                daily_pnl=sum(p.profit for p in positions) if positions else 0.0,
                can_trade=self.risk_manager.can_trade,
                balance=account.balance if account else 0.0,
                equity=account.equity if account else 0.0,
                open_positions=len(positions) if positions else 0,
            )
        except Exception:
            pass

    def _handle_new_day(self, today):
        self.current_date = today
        self.last_signal_time = None
        self.data_manager.clear_cache()

        # Fetch session levels for today
        self.session_levels = self.session_detector.get_session_levels(today)

        self.logger.info("=" * 60)
        self.logger.info(f"NEW TRADING DAY: {today}")
        for key, val in self.session_levels.items():
            if val is not None:
                self.logger.info(f"  {key}: {val:.2f}")
        self.logger.info("=" * 60)

    # ------------------------------------------------------------------
    # Signal logic
    # ------------------------------------------------------------------

    def _find_trade_setup(self, df) -> Optional[Dict[str, Any]]:
        """Scan for completed sweep-rejection pattern at any liquidity level."""
        if len(df) < 20:
            return None

        atr = self.indicators.calculate_atr(df, 14)
        if atr <= 0:
            atr = 1.0

        # Build liquidity levels
        current_price = df.iloc[-1]['close']
        liquidity_levels = self._build_liquidity_levels(current_price)
        if not liquidity_levels:
            return None

        # Evaluate each level
        for level_info in liquidity_levels:
            setup = self._check_sweep(
                df=df,
                level=level_info["level"],
                direction=level_info["direction"],
                level_type=level_info["type"],
                atr=atr,
            )
            if setup is not None:
                return setup

        return None

    def _build_liquidity_levels(self, current_price: float) -> List[Dict[str, Any]]:
        """Assemble liquidity levels to monitor from session data and round numbers."""
        levels: List[Dict[str, Any]] = []

        # Session levels
        ah = self.session_levels.get("asian_high")
        al = self.session_levels.get("asian_low")
        ph = self.session_levels.get("pd_high")
        pl = self.session_levels.get("pd_low")

        if ah is not None:
            levels.append({"level": ah, "type": "asian_high", "direction": "SELL"})
        if al is not None:
            levels.append({"level": al, "type": "asian_low", "direction": "BUY"})
        if ph is not None:
            levels.append({"level": ph, "type": "pd_high", "direction": "SELL"})
        if pl is not None:
            levels.append({"level": pl, "type": "pd_low", "direction": "BUY"})

        # Round numbers near current price
        if self.use_round_numbers:
            interval = self.round_interval
            base = int(current_price / interval) * interval
            candidates = [
                base - interval,
                base,
                base + interval,
                base + 2 * interval,
            ]
            for rn in candidates:
                if abs(current_price - rn) < current_price * 0.02:
                    if rn > current_price:
                        levels.append({"level": rn, "type": f"round_{int(rn)}", "direction": "SELL"})
                    else:
                        levels.append({"level": rn, "type": f"round_{int(rn)}", "direction": "BUY"})

        return levels

    def _check_sweep(
        self,
        df: pd.DataFrame,
        level: float,
        direction: str,
        level_type: str,
        atr: float,
    ) -> Optional[Dict[str, Any]]:
        """Check whether a sweep + rejection has occurred at a level."""
        if direction == "SELL":
            return self._check_bearish_sweep(df, level, level_type, atr)
        else:
            return self._check_bullish_sweep(df, level, level_type, atr)

    def _check_bearish_sweep(
        self, df: pd.DataFrame, level: float, level_type: str, atr: float,
    ) -> Optional[Dict[str, Any]]:
        """Detect sweep above level followed by bearish rejection."""
        lookback = min(self.sweep_max_bars + 2, len(df) - 1)
        recent = df.iloc[-lookback:]

        # 1) Find most recent valid sweep+rejection sequence.
        sweep_bar_idx = None
        sweep_high = None
        rejection_bar = None
        for i in range(len(recent) - 1, -1, -1):
            bar_high = recent.iloc[i]["high"]
            if bar_high > level + atr * self.sweep_min_pen:
                for j in range(i, min(i + self.sweep_max_bars + 1, len(recent))):
                    if recent.iloc[j]["close"] < level:
                        sweep_bar_idx = i
                        sweep_high = bar_high
                        rejection_bar = recent.iloc[j]
                        break
                if rejection_bar is not None:
                    break

        if sweep_bar_idx is None or rejection_bar is None:
            return None

        # 3) Displacement: rejection candle body size check
        if not self._has_displacement_body(df, rejection_bar):
            return None

        # 4) Optional FVG confirmation
        if self.require_fvg:
            sweep_bar_timestamp = recent.iloc[sweep_bar_idx].name
            fvg = self.indicators.find_simple_fvg(
                df, "bearish", sweep_timestamp=sweep_bar_timestamp
            )
            if fvg is None:
                return None

        # 5) Build trade setup
        tick = self.mt5.symbol_info_tick(self.symbol)
        entry = tick.bid if tick else df.iloc[-1]["close"]

        sl = sweep_high + atr * self.sl_buffer_atr
        sl_distance = abs(sl - entry)

        # Clamp SL distance
        sl_distance = max(self.risk_manager.min_sl, min(self.risk_manager.max_sl, sl_distance))
        sl = entry + sl_distance

        # TP: opposite session level or min R:R, whichever is further
        target_levels = [
            v for k, v in self.session_levels.items()
            if v is not None and v < entry and "low" in k
        ]
        tp_rr = entry - sl_distance * self.min_rr
        if target_levels:
            tp_target = max(target_levels)
            tp = min(tp_target, tp_rr)
        else:
            tp = tp_rr

        rr = abs(entry - tp) / sl_distance if sl_distance > 0 else self.min_rr
        # Never use 1:1 R:R on Gold
        rr = max(2.0, rr)

        return {
            'direction': 'SELL',
            'entry': entry,
            'sl': sl,
            'tp': tp,
            'rr': rr,
            'reason': f'Liquidity Sweep Reversal (Short) @ {level_type} {level:.2f}',
        }

    def _check_bullish_sweep(
        self, df: pd.DataFrame, level: float, level_type: str, atr: float,
    ) -> Optional[Dict[str, Any]]:
        """Detect sweep below level followed by bullish rejection."""
        lookback = min(self.sweep_max_bars + 2, len(df) - 1)
        recent = df.iloc[-lookback:]

        # 1) Find most recent valid sweep+rejection sequence.
        sweep_bar_idx = None
        sweep_low = None
        rejection_bar = None
        for i in range(len(recent) - 1, -1, -1):
            bar_low = recent.iloc[i]["low"]
            if bar_low < level - atr * self.sweep_min_pen:
                for j in range(i, min(i + self.sweep_max_bars + 1, len(recent))):
                    if recent.iloc[j]["close"] > level:
                        sweep_bar_idx = i
                        sweep_low = bar_low
                        rejection_bar = recent.iloc[j]
                        break
                if rejection_bar is not None:
                    break

        if sweep_bar_idx is None or rejection_bar is None:
            return None

        # 3) Displacement: rejection candle body size check
        if not self._has_displacement_body(df, rejection_bar):
            return None

        # 4) Optional FVG confirmation
        if self.require_fvg:
            sweep_bar_timestamp = recent.iloc[sweep_bar_idx].name
            fvg = self.indicators.find_simple_fvg(
                df, "bullish", sweep_timestamp=sweep_bar_timestamp
            )
            if fvg is None:
                return None

        # 5) Build trade setup
        tick = self.mt5.symbol_info_tick(self.symbol)
        entry = tick.ask if tick else df.iloc[-1]["close"]

        sl = sweep_low - atr * self.sl_buffer_atr
        sl_distance = abs(entry - sl)

        # Clamp SL distance
        sl_distance = max(self.risk_manager.min_sl, min(self.risk_manager.max_sl, sl_distance))
        sl = entry - sl_distance

        # TP: opposite session level or min R:R, whichever is further
        target_levels = [
            v for k, v in self.session_levels.items()
            if v is not None and v > entry and "high" in k
        ]
        tp_rr = entry + sl_distance * self.min_rr
        if target_levels:
            tp_target = min(target_levels)
            tp = max(tp_target, tp_rr)
        else:
            tp = tp_rr

        rr = abs(tp - entry) / sl_distance if sl_distance > 0 else self.min_rr
        # Never use 1:1 R:R on Gold
        rr = max(2.0, rr)

        return {
            'direction': 'BUY',
            'entry': entry,
            'sl': sl,
            'tp': tp,
            'rr': rr,
            'reason': f'Liquidity Sweep Reversal (Long) @ {level_type} {level:.2f}',
        }

    def _has_displacement_body(self, df: pd.DataFrame, rejection_bar) -> bool:
        """
        Check that the rejection candle body is in the top
        body_percentile of recent candle bodies.
        """
        bodies = (df['close'] - df['open']).abs()
        if len(bodies) < 20:
            return True  # Not enough data, skip the filter
        threshold = bodies.iloc[-20:].quantile(self.body_percentile / 100.0)
        rejection_body = abs(rejection_bar['close'] - rejection_bar['open'])
        return rejection_body >= threshold

    # ------------------------------------------------------------------
    # Trade execution
    # ------------------------------------------------------------------

    def _execute_setup(self, setup: Dict[str, Any]):
        """Execute trade from detected setup."""
        if not self.risk_manager.validate_spread():
            self.logger.warning("Spread too wide - skipping trade")
            return

        sl = self.risk_manager.validate_stop_loss(
            setup['entry'], setup['sl'], setup['direction']
        )
        sl_distance = abs(setup['entry'] - sl)
        lot = self.risk_manager.calculate_position_size(sl_distance)
        rr = setup.get('rr', self.min_rr)

        success = self.trade_executor.execute_trade(
            setup['direction'], setup['entry'], sl, lot,
            setup['reason'][:31], rr_ratio=rr
        )

        if success:
            self.logger.info(f"TRADE OPENED: {setup['reason']}")
        else:
            self.logger.error("Trade execution failed")
