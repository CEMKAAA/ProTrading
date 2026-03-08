"""
Reinforcement Learning Live Strategy
Registered with StrategyRegistry

Uses a trained PPO agent to make trade decisions based on a 28-dimensional
state vector built from live market data. Falls back to no-trade mode
gracefully when no model is loaded.
"""

import sys
import os
import shutil
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

import numpy as np
import pandas as pd
from typing import Dict, Any, Optional
from datetime import datetime
from Strategies.base import BaseStrategy, StrategyInfo, StrategyRegistry


@StrategyRegistry.register
class RLLiveStrategy(BaseStrategy):
    """
    Reinforcement Learning Trading Strategy for XAUUSD.

    Loads a trained PPO agent and uses it to decide on trade actions
    (hold, buy, sell, close) based on a 28-dimensional state vector
    constructed from live market data.

    If no model is loaded, the strategy does nothing (safe fallback).

    Runs on M5 timeframe.
    """

    @classmethod
    def get_info(cls) -> StrategyInfo:
        return StrategyInfo(
            id="rl_strategy",
            name="Reinforcement Learning Strategy",
            description=(
                "Uses a trained PPO agent to make trade decisions based on "
                "a 28-dim state vector from live market data. Requires a "
                "trained model file to operate."
            ),
            version="1.0.0",
            author="ProTrading",
            timeframes=["M5"],
            symbols=["XAUUSD"],
            parameters={
                "risk_percent": 1.0,
                "sl_atr_multiple": 1.5,
                "tp_atr_multiple": 3.0,
                "rl_model_path": "",
                "trade_start_time": "09:30",
                "trade_end_time": "16:00",
            }
        )

    def __init__(self):
        super().__init__()
        self.mt5 = None
        self.logger = None
        self.agent = None

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
                RL_MODEL_PATH, SL_ATR_MULTIPLE, TP_ATR_MULTIPLE,
                TRADE_START_TIME, TRADE_END_TIME,
                RL_ONLINE_LEARNING, RL_ONLINE_BUFFER_SIZE,
                RL_ONLINE_MIN_BATCH, RL_ONLINE_UPDATE_INTERVAL_HOURS,
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
                'RLStrategy',
                str(os.path.join(os.path.dirname(__file__), 'logs'))
            )
            self.broker_tz = self._detect_broker_timezone()
            self.ny_tz = pytz.timezone('America/New_York')

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
            self.rl_model_path = RL_MODEL_PATH
            self.sl_atr_mult = SL_ATR_MULTIPLE
            self.tp_atr_mult = TP_ATR_MULTIPLE
            self.min_bars = MIN_BARS_FOR_ANALYSIS
            self.trade_start = TRADE_START_TIME
            self.trade_end = TRADE_END_TIME

            self.current_date = None
            self.last_signal_time = None
            self.session_levels = {}

            # Load RL agent
            self._load_agent()

            # Online learning setup
            self.online_learning_enabled = RL_ONLINE_LEARNING
            self._last_online_update = None
            self._online_update_interval_hours = RL_ONLINE_UPDATE_INTERVAL_HOURS
            self._tracked_positions = set()  # Track our open position tickets
            self._last_entry_sl_dist = 0  # SL distance of last entry for reward calc
            self.experience_buffer = None

            if self.online_learning_enabled:
                try:
                    from Strategies.shared.rl_experience_buffer import RLExperienceBuffer
                    self.experience_buffer = RLExperienceBuffer(
                        max_buffer_size=RL_ONLINE_BUFFER_SIZE
                    )
                    self.logger.info(
                        f"RL Online Learning: ENABLED "
                        f"(buffer: {RL_ONLINE_BUFFER_SIZE}, batch: {RL_ONLINE_MIN_BATCH})"
                    )
                except Exception as e:
                    self.logger.warning(f"RL Online Learning init failed: {e}")
                    self.online_learning_enabled = False

            self.logger.info("=" * 60)
            self.logger.info("RL STRATEGY INITIALIZED")
            self.logger.info(f"Symbol: {TARGET_SYMBOL} | TF: M5")
            self.logger.info(f"Magic: {MAGIC_NUMBER}")
            self.logger.info(f"Model: {self.rl_model_path or 'NOT LOADED'}")
            self.logger.info(f"Agent: {'LOADED' if self.agent is not None else 'NONE (no trades)'}")
            self.logger.info(f"SL: {self.sl_atr_mult} ATR | TP: {self.tp_atr_mult} ATR")
            self.logger.info(f"Online Learning: {'ON' if self.online_learning_enabled else 'OFF'}")
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

                # Trading hours check
                if not (self.trade_start <= now.time() <= self.trade_end):
                    time_module.sleep(30)
                    continue

                # No agent = no trades (safe fallback)
                if self.agent is None:
                    time_module.sleep(60)
                    continue

                # Manage trailing stops
                self.trade_executor.manage_trailing_stops(self.data_manager)

                # Detect position closure for online learning
                if self.online_learning_enabled:
                    self._check_position_closure()

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

                # Get agent action
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
        return {"strategy_id": "rl_strategy", "is_running": self._running}

    # ------------------------------------------------------------------
    # Core methods
    # ------------------------------------------------------------------

    def _detect_broker_timezone(self):
        from datetime import datetime, timezone
        import pytz
        tick = self.mt5.symbol_info_tick(self.symbol)
        broker_time = datetime.fromtimestamp(tick.time)
        utc_time = datetime.fromtimestamp(tick.time, tz=timezone.utc).replace(tzinfo=None)
        offset_minutes = int((broker_time - utc_time).total_seconds() / 60)
        return pytz.FixedOffset(offset_minutes)

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
                daily_trades=self.risk_manager.daily_trades_count,
                daily_pnl=sum(p.profit for p in positions) if positions else 0.0,
                can_trade=self.risk_manager.can_trade,
                balance=account.balance if account else 0.0,
                equity=account.equity if account else 0.0,
                open_positions=len(positions) if positions else 0,
                last_signal=f"Agent: {'LOADED' if self.agent else 'NONE'}",
            )
        except Exception:
            pass

    def _handle_new_day(self, today):
        self.current_date = today
        self.last_signal_time = None
        self.data_manager.clear_cache()

        # Fetch session levels for state vector
        self.session_levels = self.session_detector.get_session_levels(today)

        self.logger.info("=" * 60)
        self.logger.info(f"NEW TRADING DAY: {today}")
        self.logger.info(f"Agent: {'LOADED' if self.agent else 'NOT LOADED'}")
        self.logger.info("=" * 60)

    # ------------------------------------------------------------------
    # RL Agent
    # ------------------------------------------------------------------

    def _load_agent(self):
        """Load trained RL agent from model path. Safe fallback if missing."""
        model_path = self.rl_model_path
        if not model_path:
            self.logger.warning("No RL model path configured - strategy will not trade")
            self.agent = None
            return

        try:
            from dashboard.backend.core.rl_trainer import RLTrainer
            self.agent = RLTrainer({})
            self.agent.load(model_path)
            self.logger.info(f"RL model loaded from: {model_path}")
        except Exception as e:
            self.logger.warning(f"Could not load RL model: {e}")
            self.agent = None

    # ------------------------------------------------------------------
    # Signal logic
    # ------------------------------------------------------------------

    def _find_trade_setup(self, df) -> Optional[Dict[str, Any]]:
        """Use RL agent to decide on trade action."""
        if self.agent is None:
            return None

        if len(df) < 25:
            return None

        bar = df.iloc[-2]  # Use confirmed bar, not forming bar

        # Build state vector
        state = self._build_state(bar, df)

        # Get action from agent (with log_prob and value for online learning)
        if self.online_learning_enabled and hasattr(self.agent, 'policy') and self.agent.policy:
            action, log_prob, value = self.agent.policy.get_action(state)
        else:
            action = self.agent.predict(state)
            log_prob, value = 0.0, 0.0

        # action: 0=hold, 1=buy, 2=sell, 3=close
        if action == 3:
            # Close all positions
            positions = self.mt5.positions_get(symbol=self.symbol)
            if positions:
                our_positions = [p for p in positions if p.magic == self.magic]
                if our_positions:
                    self.trade_executor.close_all_positions("RL Agent Close")
                    self.logger.info("RL Agent: CLOSE signal")
            return None

        if action not in (1, 2):
            return None  # Hold

        atr = self.indicators.calculate_atr(df, 14)
        if atr <= 0:
            atr = 1.0

        entry_tick = self.mt5.symbol_info_tick(self.symbol)
        if entry_tick is None:
            return None

        if action == 1:  # Buy
            entry = entry_tick.ask

            sl = entry - atr * self.sl_atr_mult
            sl_distance = abs(entry - sl)

            # Clamp SL distance
            sl_distance = max(self.risk_manager.min_sl, min(self.risk_manager.max_sl, sl_distance))
            sl = entry - sl_distance

            tp = entry + sl_distance * (self.tp_atr_mult / self.sl_atr_mult)
            rr = abs(tp - entry) / sl_distance if sl_distance > 0 else self.tp_atr_mult / self.sl_atr_mult
            # Never use 1:1 R:R on Gold
            rr = max(2.0, rr)

            # Record entry experience for online learning
            if self.online_learning_enabled and self.experience_buffer:
                self.experience_buffer.record_entry(state, action, log_prob, value)
                self._last_entry_sl_dist = sl_distance

            return {
                'direction': 'BUY',
                'entry': entry,
                'sl': sl,
                'tp': tp,
                'rr': rr,
                'reason': 'RL Agent (Buy)',
            }

        else:  # action == 2, Sell
            entry = entry_tick.bid

            sl = entry + atr * self.sl_atr_mult
            sl_distance = abs(sl - entry)

            # Clamp SL distance
            sl_distance = max(self.risk_manager.min_sl, min(self.risk_manager.max_sl, sl_distance))
            sl = entry + sl_distance

            tp = entry - sl_distance * (self.tp_atr_mult / self.sl_atr_mult)
            rr = abs(entry - tp) / sl_distance if sl_distance > 0 else self.tp_atr_mult / self.sl_atr_mult
            # Never use 1:1 R:R on Gold
            rr = max(2.0, rr)

            # Record entry experience for online learning
            if self.online_learning_enabled and self.experience_buffer:
                self.experience_buffer.record_entry(state, action, log_prob, value)
                self._last_entry_sl_dist = sl_distance

            return {
                'direction': 'SELL',
                'entry': entry,
                'sl': sl,
                'tp': tp,
                'rr': rr,
                'reason': 'RL Agent (Sell)',
            }

    def _build_state(self, bar, df) -> np.ndarray:
        """
        Build 28-dimensional state vector from live market data.

        Dimensions:
          0-4:   5-bar close returns (normalized)
          5-6:   Price vs SMA10, SMA20 (in ATR units)
          7:     10-bar volatility / ATR
          8-11:  Current bar features (body, upper wick, lower wick, direction)
          12:    Price position in 10-bar range
          13:    Volume relative to 10-bar average
          14:    RSI-like momentum (scaled -1 to 1)
          15:    ATR / price * 1000 (normalized volatility)
          16-18: Momentum over 5, 10, 20 bars (in ATR units)
          19:    Spread / ATR
          20:    Position state (0=none, 1=long, -1=short)
          21-22: Time features (hour/24, day_of_week/5)
          23-26: Session level distances (asian_high, asian_low, pd_high, pd_low) in ATR
          27:    Padding (zero)
        """
        state = np.zeros(28, dtype=np.float32)

        closes = df['close'].values
        atr = self.indicators.calculate_atr(df, 14)
        if atr <= 0:
            atr = 1.0
        current_price = closes[-1]

        # 0-4: Returns
        if len(closes) >= 6:
            returns = np.diff(closes[-6:]) / closes[-6:-1]
            state[0:5] = returns[:5]

        # 5-6: Price vs SMAs
        if len(closes) >= 10:
            sma_10 = np.mean(closes[-10:])
            state[5] = (current_price - sma_10) / atr
        if len(closes) >= 20:
            sma_20 = np.mean(closes[-20:])
            state[6] = (current_price - sma_20) / atr

        # 7: Volatility
        if len(closes) >= 10:
            state[7] = np.std(closes[-10:]) / atr

        # 8-11: Current bar features
        body = abs(bar['close'] - bar['open']) / atr
        upper_wick = (bar['high'] - max(bar['open'], bar['close'])) / atr
        lower_wick = (min(bar['open'], bar['close']) - bar['low']) / atr
        state[8] = body
        state[9] = upper_wick
        state[10] = lower_wick
        state[11] = 1.0 if bar['close'] > bar['open'] else -1.0

        # 12: Price position in 10-bar range
        if len(df) >= 10:
            high_10 = df['high'].iloc[-10:].max()
            low_10 = df['low'].iloc[-10:].min()
            state[12] = (current_price - low_10) / (high_10 - low_10) if high_10 > low_10 else 0.5

        # 13: Volume ratio
        if 'tick_volume' in df.columns and len(df) >= 10:
            vol_col = 'tick_volume'
        elif 'volume' in df.columns and len(df) >= 10:
            vol_col = 'volume'
        else:
            vol_col = None

        if vol_col and len(df) >= 10:
            vol_mean = df[vol_col].iloc[-10:].mean()
            if vol_mean > 0:
                state[13] = bar.get(vol_col, 0) / vol_mean

        # 14: RSI-like momentum
        if len(closes) >= 15:
            deltas = np.diff(closes[-15:])
            gains = np.mean(deltas[deltas > 0]) if np.any(deltas > 0) else 0
            losses = np.mean(np.abs(deltas[deltas < 0])) if np.any(deltas < 0) else 0
            rs = gains / losses if losses > 0 else 100
            state[14] = 2 * (100 - 100 / (1 + rs)) / 100 - 1

        # 15: Normalized ATR
        state[15] = atr / current_price * 1000

        # 16-18: Multi-period momentum
        if len(closes) >= 20:
            state[16] = (closes[-1] - closes[-5]) / atr
            state[17] = (closes[-1] - closes[-10]) / atr
            state[18] = (closes[-1] - closes[-20]) / atr

        # 19: Spread / ATR
        tick = self.mt5.symbol_info_tick(self.symbol)
        if tick is not None:
            spread = tick.ask - tick.bid
            state[19] = spread / atr

        # 20: Position state
        positions = self.mt5.positions_get(symbol=self.symbol)
        if positions:
            our_positions = [p for p in positions if p.magic == self.magic]
            if our_positions:
                pos = our_positions[0]
                state[20] = 1.0 if pos.type == 0 else -1.0  # 0=buy, 1=sell

        # 21-22: Time features
        now = self._get_current_time_ny()
        if now is not None:
            state[21] = now.hour / 24.0
            state[22] = now.weekday() / 5.0

        # 23-26: Session level distances in ATR
        if self.session_levels:
            ah = self.session_levels.get('asian_high')
            al = self.session_levels.get('asian_low')
            ph = self.session_levels.get('pd_high')
            pl = self.session_levels.get('pd_low')
            if ah is not None:
                state[23] = (current_price - ah) / atr
            if al is not None:
                state[24] = (current_price - al) / atr
            if ph is not None:
                state[25] = (current_price - ph) / atr
            if pl is not None:
                state[26] = (current_price - pl) / atr

        # 27: Padding (zero) - already initialized

        return state

    # ------------------------------------------------------------------
    # Trade execution
    # ------------------------------------------------------------------

    def _execute_setup(self, setup: Dict[str, Any]):
        """Execute trade from RL agent decision."""
        if not self.risk_manager.validate_spread():
            self.logger.warning("Spread too wide - skipping trade")
            return

        sl = self.risk_manager.validate_stop_loss(
            setup['entry'], setup['sl'], setup['direction']
        )
        sl_distance = abs(setup['entry'] - sl)
        lot = self.risk_manager.calculate_position_size(sl_distance)
        rr = setup.get('rr', self.tp_atr_mult / self.sl_atr_mult)

        success = self.trade_executor.execute_trade(
            setup['direction'], setup['entry'], sl, lot,
            setup['reason'][:31], rr_ratio=rr
        )

        if success:
            self.logger.info(f"TRADE OPENED: {setup['reason']}")
            # Track our positions for online learning
            if self.online_learning_enabled:
                positions = self.mt5.positions_get(symbol=self.symbol)
                if positions:
                    self._tracked_positions = {
                        p.ticket for p in positions if p.magic == self.magic
                    }
        else:
            self.logger.error("Trade execution failed")

    # ------------------------------------------------------------------
    # Online Learning
    # ------------------------------------------------------------------

    def _check_position_closure(self):
        """Detect when our positions close and record exit experience."""
        if not self.online_learning_enabled or not self.experience_buffer:
            return

        try:
            positions = self.mt5.positions_get(symbol=self.symbol)
            current_tickets = set()
            if positions:
                current_tickets = {
                    p.ticket for p in positions if p.magic == self.magic
                }

            closed_tickets = self._tracked_positions - current_tickets

            for ticket in closed_tickets:
                # Try to get deal info for PnL
                try:
                    from datetime import timedelta
                    now = datetime.utcnow()
                    deals = self.mt5.history_deals_get(
                        now - timedelta(hours=24), now,
                        group=self.symbol,
                    )
                    if deals:
                        deal = next(
                            (d for d in deals
                             if d.position_id == ticket and d.entry == 1),
                            None
                        )
                        if deal:
                            # Compute R-multiple reward
                            sl_dist = self._last_entry_sl_dist or 1.0
                            lot_size = deal.volume
                            contract_size = 100  # Gold
                            pnl = deal.profit
                            risk_amount = sl_dist * lot_size * contract_size
                            if risk_amount > 0:
                                reward = pnl / risk_amount
                            else:
                                reward = 0.0
                            reward = float(np.clip(reward, -5, 5))
                            self.experience_buffer.record_exit(reward)
                            self.logger.info(
                                f"RL Online: Trade {ticket} closed, "
                                f"reward={reward:.2f}R, PnL=${pnl:.2f}"
                            )
                except Exception as e:
                    self.logger.debug(f"Could not process closed ticket {ticket}: {e}")

            self._tracked_positions = current_tickets

            # Try online update
            self._try_online_update()

        except Exception as e:
            self.logger.debug(f"Position closure check error: {e}")

    def _try_online_update(self):
        """Attempt a mini PPO update if enough experiences are buffered."""
        if not self.online_learning_enabled or not self.experience_buffer:
            return
        if self.agent is None:
            return

        from .config import RL_ONLINE_MIN_BATCH

        batch = self.experience_buffer.get_batch(min_size=RL_ONLINE_MIN_BATCH)
        if not batch:
            return

        # Rate limit: max 1 update per configured interval
        now = datetime.utcnow()
        if self._last_online_update:
            hours_since = (now - self._last_online_update).total_seconds() / 3600
            if hours_since < self._online_update_interval_hours:
                return

        # Backup model before update
        backup_path = None
        if self.rl_model_path:
            backup_path = f"{self.rl_model_path}.backup"
            try:
                shutil.copy(self.rl_model_path, backup_path)
            except Exception as e:
                self.logger.warning(f"Could not backup model: {e}")
                return

        # Run mini PPO update
        result = self.agent.online_ppo_update(batch)

        if result.get('status') == 'success':
            # Save updated model
            if self.rl_model_path:
                self.agent.save(self.rl_model_path)
            self.experience_buffer.clear_batch(len(batch))
            self._last_online_update = now

            self.logger.info(
                f"RL ONLINE UPDATE: {result.get('experiences', 0)} experiences, "
                f"avg_reward={result.get('avg_reward', 0):.3f}"
            )

            # Log to DB
            self._log_online_update(result, backup_path)
        else:
            self.logger.warning(f"Online PPO update failed: {result.get('message')}")
            # Rollback
            if backup_path and os.path.exists(backup_path):
                try:
                    shutil.copy(backup_path, self.rl_model_path)
                    self._load_agent()
                    self.logger.info("Model rolled back after failed update")
                except Exception:
                    pass

    def _log_online_update(self, result, backup_path=None):
        """Log online update to database."""
        try:
            import sqlite3
            db_path = os.path.join(
                os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
                'dashboard', 'data', 'trading.db'
            )
            conn = sqlite3.connect(db_path)
            cursor = conn.cursor()
            cursor.execute("""
                INSERT INTO rl_online_logs
                    (updated_at, experiences_count, avg_reward, model_path, backup_path, status)
                VALUES (?, ?, ?, ?, ?, ?)
            """, (
                datetime.utcnow().isoformat(),
                result.get('experiences', 0),
                result.get('avg_reward', 0.0),
                self.rl_model_path or '',
                backup_path or '',
                result.get('status', 'unknown'),
            ))
            conn.commit()
            conn.close()
        except Exception as e:
            self.logger.debug(f"Online update logging failed: {e}")
