"""
Basso Mean Reversion Live Strategy

Trades when price overextends from its SMA(20) by 2+ ATR, confirmed by RSI
at extremes and a reversal candle. Targets reversion to the mean (SMA).
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from typing import Dict, Any
from Strategies.base import BaseStrategy, StrategyInfo, StrategyRegistry, StrategyStatus


@StrategyRegistry.register
class BassoLiveStrategy(BaseStrategy):
    """
    Basso Mean Reversion Strategy for XAUUSD.

    Trades overextended price moves away from SMA(20) when RSI confirms
    extreme conditions and a reversal candle appears. Targets the SMA
    as take profit (reversion to the mean), with minimum 2:1 R:R enforced.
    """

    @classmethod
    def get_info(cls) -> StrategyInfo:
        return StrategyInfo(
            id="basso_strategy",
            name="Basso Mean Reversion Strategy",
            description="Mean reversion strategy trading overextension from SMA with RSI confirmation on M15.",
            version="1.0.0",
            author="ProTrading",
            timeframes=["M15"],
            symbols=["XAUUSD"],
            parameters={
                "risk_percent": 1.0,
                "max_spread_usd": 0.40,
                "sma_period": 20,
                "atr_period": 14,
                "rsi_period": 14,
                "overextension_atr_multiple": 2.0,
                "rsi_overbought": 70,
                "rsi_oversold": 30,
                "use_ema200_trend_filter": True,
                "rr_ratio": 2.0,
            }
        )

    def __init__(self):
        super().__init__()
        self.mt5 = None
        self.logger = None

    def initialize(self) -> bool:
        try:
            import MetaTrader5 as mt5
            from .config import (
                TARGET_SYMBOL, MAGIC_NUMBER, TIMEFRAME, STRATEGY_ID, STRATEGY_NAME,
                RISK_PERCENT, MAX_SPREAD_USD, MAX_DAILY_LOSS_USD, MAX_TOTAL_RISK_USD,
                MAX_DAILY_TRADES, INITIAL_BALANCE, MIN_SL_USD, MAX_SL_USD,
                USE_TRAILING, TRAILING_ATR_PERIOD, TRAILING_ATR_MULTIPLIER,
                DATA_CACHE_BARS, STATE_FILE, RR_RATIO
            )
            from Strategies.shared import (
                setup_logger, BotStateManager, DataManager,
                RiskManager, TradeExecutor, Indicators
            )
            import pytz

            if not mt5.initialize():
                self.error_message = f"MT5 Init Failed: {mt5.last_error()}"
                return False

            if not mt5.symbol_select(TARGET_SYMBOL, True):
                self.error_message = f"Symbol {TARGET_SYMBOL} not available"
                return False

            import time
            time.sleep(1)

            if mt5.symbol_info_tick(TARGET_SYMBOL) is None:
                self.error_message = "No price data available"
                return False

            self.mt5 = mt5
            self.symbol = TARGET_SYMBOL
            self.magic = MAGIC_NUMBER
            self.rr_ratio = RR_RATIO

            self.logger = setup_logger('BassoStrategy',
                                       str(os.path.join(os.path.dirname(__file__), 'logs')))

            from Strategies.shared.broker_timezone import detect_broker_timezone, get_ny_timezone
            self.broker_tz = detect_broker_timezone(mt5, TARGET_SYMBOL)
            self.ny_tz = get_ny_timezone()

            self.data_manager = DataManager(TARGET_SYMBOL, self.broker_tz, self.ny_tz,
                                            TIMEFRAME, DATA_CACHE_BARS, self.logger)
            self.risk_manager = RiskManager(
                TARGET_SYMBOL, MAGIC_NUMBER, RISK_PERCENT, MAX_SPREAD_USD,
                MAX_DAILY_LOSS_USD, MAX_TOTAL_RISK_USD, MAX_DAILY_TRADES,
                INITIAL_BALANCE, MIN_SL_USD, MAX_SL_USD, self.logger
            )
            self.trade_executor = TradeExecutor(
                TARGET_SYMBOL, MAGIC_NUMBER, rr_threshold=3.0,
                use_trailing=USE_TRAILING, trailing_atr_period=TRAILING_ATR_PERIOD,
                trailing_atr_multiplier=TRAILING_ATR_MULTIPLIER, logger=self.logger
            )
            self.state_manager = BotStateManager(str(STATE_FILE), STRATEGY_ID, STRATEGY_NAME)
            self.indicators = Indicators

            # Strategy-specific config
            from .config import (
                SMA_PERIOD, ATR_PERIOD, RSI_PERIOD,
                OVEREXTENSION_ATR_MULTIPLE, RSI_OVERBOUGHT, RSI_OVERSOLD,
                USE_EMA200_TREND_FILTER, EMA_TREND_SLOPE_BARS,
                SL_ATR_BUFFER, MIN_BARS_FOR_ANALYSIS,
                TRADE_START_TIME, TRADE_END_TIME
            )
            self.sma_period = SMA_PERIOD
            self.atr_period = ATR_PERIOD
            self.rsi_period = RSI_PERIOD
            self.overextension_mult = OVEREXTENSION_ATR_MULTIPLE
            self.rsi_overbought = RSI_OVERBOUGHT
            self.rsi_oversold = RSI_OVERSOLD
            self.use_ema200_filter = USE_EMA200_TREND_FILTER
            self.ema_trend_slope_bars = EMA_TREND_SLOPE_BARS
            self.sl_atr_buffer = SL_ATR_BUFFER
            self.min_bars = MIN_BARS_FOR_ANALYSIS
            self.trade_start = TRADE_START_TIME
            self.trade_end = TRADE_END_TIME

            self.current_date = None
            self.last_signal_time = None

            self.logger.info("=" * 60)
            self.logger.info("BASSO MEAN REVERSION STRATEGY INITIALIZED")
            self.logger.info(f"Symbol: {TARGET_SYMBOL} | TF: M15 | Magic: {MAGIC_NUMBER}")
            self.logger.info(f"SMA: {SMA_PERIOD} | ATR mult: {OVEREXTENSION_ATR_MULTIPLE} | RSI: {RSI_PERIOD}")
            self.logger.info(f"RSI OB/OS: {RSI_OVERBOUGHT}/{RSI_OVERSOLD}")
            self.logger.info("=" * 60)
            return True

        except Exception as e:
            self.error_message = str(e)
            return False

    def run(self):
        from datetime import time as dt_time
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

                self._update_dashboard_state(now)

                if self.current_date != now.date():
                    self._handle_new_day(now.date())

                # Friday close
                if now.weekday() == 4 and now.time() > dt_time(15, 30):
                    self.trade_executor.close_all_positions("Friday Close")
                    time_module.sleep(300)
                    continue

                # Trading hours
                if not (self.trade_start <= now.time() <= self.trade_end):
                    time_module.sleep(30)
                    continue

                # Trailing stops
                if self.trade_executor.manage_trailing_stops(self.data_manager):
                    time_module.sleep(1)
                    continue

                # Risk check
                self.risk_manager.check_daily_status()
                if not self.risk_manager.can_trade:
                    time_module.sleep(60)
                    continue

                if not self.risk_manager.can_open_new_position():
                    time_module.sleep(30)
                    continue

                # Get data
                df = self.data_manager.get_data()
                if df.empty or len(df) < self.min_bars:
                    time_module.sleep(5)
                    continue

                # Prevent duplicate signals
                signal_time = df.index[-2]
                if self.last_signal_time == signal_time:
                    time_module.sleep(1)
                    continue
                self.last_signal_time = signal_time

                # Look for setup
                setup = self._find_trade_setup(df)
                if setup:
                    self.logger.info(f"SETUP FOUND: {setup['reason']}")
                    self._execute_setup(setup, df)

                time_module.sleep(10)  # M15 timeframe, check every 10s

            except KeyboardInterrupt:
                self.logger.info("Bot stopped by user")
                break
            except Exception as e:
                self.logger.error(f"Loop error: {e}", exc_info=True)
                time_module.sleep(5)

    def shutdown(self):
        if hasattr(self, 'state_manager') and self.state_manager:
            self.state_manager.set_stopped()
        if hasattr(self, 'mt5') and self.mt5:
            self.mt5.shutdown()
        if self.logger:
            self.logger.info("Bot shutdown complete")

    def get_state(self) -> Dict[str, Any]:
        if hasattr(self, 'state_manager') and self.state_manager:
            return self.state_manager.read_state()
        return {"strategy_id": "basso_strategy", "is_running": self._running}

    def _get_current_time_ny(self):
        from datetime import datetime
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
        self.logger.info(f"NEW TRADING DAY: {today}")

    def _update_dashboard_state(self, now):
        try:
            tick = self.mt5.symbol_info_tick(self.symbol)
            account = self.mt5.account_info()
            positions = self.mt5.positions_get(symbol=self.symbol)

            self.state_manager.update_state(
                is_running=True,
                current_time_ny=now.isoformat() if now else None,
                current_price=tick.bid if tick else None,
                spread=round(tick.ask - tick.bid, 3) if tick else None,
                daily_trades=self.risk_manager.daily_trades_count,
                daily_pnl=sum(p.profit for p in positions) if positions else 0.0,
                can_trade=self.risk_manager.can_trade,
                balance=account.balance if account else 0.0,
                equity=account.equity if account else 0.0,
                open_positions=len(positions) if positions else 0,
            )
        except Exception:
            pass

    # ------------------------------------------------------------------
    # Signal Logic
    # ------------------------------------------------------------------

    def _find_trade_setup(self, df):
        """
        Scan for Basso Mean Reversion setups.

        Logic:
        1. Calculate SMA(20) and distance from SMA in ATR units
        2. Calculate RSI(14)
        3. LONG: distance < -2.0 ATR AND RSI < 30 AND reversal candle
        4. SHORT: distance > 2.0 ATR AND RSI > 70 AND reversal candle
        5. SL: Beyond recent 10-bar extreme + 0.5 ATR buffer
        6. TP: At the SMA (the mean), minimum 2:1 R:R enforced
        """
        close = df['close']

        # SMA
        sma = self.indicators.calculate_sma(close, self.sma_period)
        current_sma = sma.iloc[-1]
        if current_sma is None or (hasattr(current_sma, '__class__') and str(current_sma) == 'nan'):
            return None

        import pandas as pd
        if pd.isna(current_sma):
            return None

        # ATR
        atr = self.indicators.calculate_atr(df, self.atr_period)
        if atr <= 0:
            return None

        # RSI
        rsi = self.indicators.calculate_rsi(close, self.rsi_period)
        current_rsi = rsi.iloc[-1] if len(rsi) > 0 and not pd.isna(rsi.iloc[-1]) else 50.0

        # Distance from SMA in ATR units
        current_close = float(close.iloc[-1])
        prev_close = float(close.iloc[-2])
        distance_from_sma = (current_close - float(current_sma)) / atr

        # Trend guardrail: avoid fading strong EMA200 slope.
        ema200_rising = False
        ema200_falling = False
        if self.use_ema200_filter:
            ema200 = self.indicators.calculate_ema(close, 200)
            slope_bars = max(1, int(self.ema_trend_slope_bars))
            if len(ema200) > slope_bars and not pd.isna(ema200.iloc[-1]) and not pd.isna(ema200.iloc[-1 - slope_bars]):
                ema200_rising = ema200.iloc[-1] > ema200.iloc[-1 - slope_bars]
                ema200_falling = ema200.iloc[-1] < ema200.iloc[-1 - slope_bars]

        entry = current_close

        # === LONG SETUP (price overextended below SMA) ===
        if distance_from_sma < -self.overextension_mult and current_rsi < self.rsi_oversold and not ema200_falling:
            # Reversal candle: current bar closes higher than previous
            if current_close <= prev_close:
                return None

            # SL below recent 10-bar low + buffer
            recent_low = float(df['low'].iloc[-10:].min())
            sl = recent_low - atr * self.sl_atr_buffer
            sl_distance = abs(entry - sl)

            # Clamp SL distance
            sl_distance = max(self.risk_manager.min_sl, min(self.risk_manager.max_sl, sl_distance))
            sl = entry - sl_distance

            # TP at the SMA (the mean)
            tp = float(current_sma)
            # Enforce minimum 2:1 R:R
            if abs(tp - entry) < sl_distance * 2.0:
                tp = entry + sl_distance * 2.0

            return {
                'direction': 'BUY',
                'entry': entry,
                'sl': sl,
                'rr': abs(tp - entry) / sl_distance if sl_distance > 0 else self.rr_ratio,
                'reason': f'Basso Mean Reversion Long (dist={distance_from_sma:.1f}ATR, RSI={current_rsi:.0f})'
            }

        # === SHORT SETUP (price overextended above SMA) ===
        elif distance_from_sma > self.overextension_mult and current_rsi > self.rsi_overbought and not ema200_rising:
            # Reversal candle: current bar closes lower than previous
            if current_close >= prev_close:
                return None

            # SL above recent 10-bar high + buffer
            recent_high = float(df['high'].iloc[-10:].max())
            sl = recent_high + atr * self.sl_atr_buffer
            sl_distance = abs(sl - entry)

            # Clamp SL distance
            sl_distance = max(self.risk_manager.min_sl, min(self.risk_manager.max_sl, sl_distance))
            sl = entry + sl_distance

            # TP at the SMA (the mean)
            tp = float(current_sma)
            # Enforce minimum 2:1 R:R
            if abs(entry - tp) < sl_distance * 2.0:
                tp = entry - sl_distance * 2.0

            return {
                'direction': 'SELL',
                'entry': entry,
                'sl': sl,
                'rr': abs(entry - tp) / sl_distance if sl_distance > 0 else self.rr_ratio,
                'reason': f'Basso Mean Reversion Short (dist={distance_from_sma:.1f}ATR, RSI={current_rsi:.0f})'
            }

        return None

    def _execute_setup(self, setup, df):
        if not self.risk_manager.validate_spread():
            self.logger.warning("Spread too wide - skipping")
            return

        sl = self.risk_manager.validate_stop_loss(setup['entry'], setup['sl'], setup['direction'])
        sl_distance = abs(setup['entry'] - sl)
        lot_size = self.risk_manager.calculate_position_size(sl_distance)

        self.trade_executor.execute_trade(
            direction=setup['direction'],
            entry_price=setup['entry'],
            sl_price=sl,
            lot_size=lot_size,
            comment=setup['reason'][:31],
            rr_ratio=setup.get('rr', self.rr_ratio)
        )
