"""
MACD + EMA Trend-Following Live Strategy
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from typing import Dict, Any
from Strategies.base import BaseStrategy, StrategyInfo, StrategyRegistry, StrategyStatus


@StrategyRegistry.register
class MACDEMALiveStrategy(BaseStrategy):
    """
    MACD + EMA Trend-Following Strategy for XAUUSD.

    Trades in the direction of EMA alignment (9 > 21 > 50 = bullish)
    when MACD confirms momentum shift via crossover + histogram.
    """

    @classmethod
    def get_info(cls) -> StrategyInfo:
        return StrategyInfo(
            id="macd_ema_strategy",
            name="MACD + EMA Trend Strategy",
            description="Trend-following strategy using EMA alignment and MACD crossover confirmation on M5.",
            version="1.0.0",
            author="ProTrading",
            timeframes=["M5"],
            symbols=["XAUUSD"],
            parameters={
                "risk_percent": 1.0,
                "max_spread_usd": 0.40,
                "ema_fast": 9,
                "ema_mid": 21,
                "ema_slow": 50,
                "macd_fast": 12,
                "macd_slow": 26,
                "macd_signal": 9,
                "min_adx": 25,
                "min_ema_separation_pct": 0.05,
                "rr_ratio": 2.5,
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

            self.logger = setup_logger('MACDEMAStrategy',
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
            from .config import (EMA_FAST, EMA_MID, EMA_SLOW,
                                MACD_FAST, MACD_SLOW, MACD_SIGNAL,
                                HISTOGRAM_CONFIRM_BARS, SL_ATR_BUFFER,
                                ADX_PERIOD, MIN_ADX, MIN_EMA_SEPARATION_PCT,
                                REQUIRE_MACD_ABOVE_ZERO, REQUIRE_MACD_BELOW_ZERO,
                                MIN_BARS_FOR_ANALYSIS, TRADE_START_TIME, TRADE_END_TIME)
            self.ema_fast = EMA_FAST
            self.ema_mid = EMA_MID
            self.ema_slow = EMA_SLOW
            self.macd_fast = MACD_FAST
            self.macd_slow = MACD_SLOW
            self.macd_signal = MACD_SIGNAL
            self.histogram_confirm_bars = HISTOGRAM_CONFIRM_BARS
            self.sl_atr_buffer = SL_ATR_BUFFER
            self.adx_period = ADX_PERIOD
            self.min_adx = MIN_ADX
            self.min_ema_sep_pct = MIN_EMA_SEPARATION_PCT
            self.require_macd_above_zero = REQUIRE_MACD_ABOVE_ZERO
            self.require_macd_below_zero = REQUIRE_MACD_BELOW_ZERO
            self.min_bars = MIN_BARS_FOR_ANALYSIS
            self.trade_start = TRADE_START_TIME
            self.trade_end = TRADE_END_TIME

            self.current_date = None
            self.last_signal_time = None

            self.logger.info("=" * 60)
            self.logger.info("MACD + EMA STRATEGY INITIALIZED")
            self.logger.info(f"Symbol: {TARGET_SYMBOL} | TF: M5 | Magic: {MAGIC_NUMBER}")
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

                time_module.sleep(5)  # M5 timeframe, check every 5s

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
        return {"strategy_id": "macd_ema_strategy", "is_running": self._running}

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

    def _find_trade_setup(self, df):
        """Scan for MACD + EMA setups."""
        close = df['close']

        # Trend strength gate (ADX) to avoid choppy periods.
        if self.min_adx > 0:
            adx_val = self.indicators.calculate_adx(df, self.adx_period)
            if adx_val < self.min_adx:
                return None

        ema_f = self.indicators.calculate_ema(close, self.ema_fast)
        ema_m = self.indicators.calculate_ema(close, self.ema_mid)
        ema_s = self.indicators.calculate_ema(close, self.ema_slow)

        ef = ema_f.iloc[-1]
        em = ema_m.iloc[-1]
        es = ema_s.iloc[-1]

        bullish_trend = ef > em > es
        bearish_trend = ef < em < es

        if not bullish_trend and not bearish_trend:
            return None

        # Minimum EMA spread filter to reduce flip-prone structures.
        price = float(df.iloc[-1]['close'])
        if price > 0 and self.min_ema_sep_pct > 0:
            ema_spread_pct = abs(ef - es) / price * 100
            if ema_spread_pct < self.min_ema_sep_pct:
                return None

        macd_line, signal_line, histogram = self.indicators.calculate_macd(
            close, self.macd_fast, self.macd_slow, self.macd_signal
        )

        if len(macd_line) < 3:
            return None

        macd_prev2 = macd_line.iloc[-3]
        signal_prev2 = signal_line.iloc[-3]
        macd_prev = macd_line.iloc[-2]
        signal_prev = signal_line.iloc[-2]

        atr = self.indicators.calculate_atr(df, 14)
        entry = df.iloc[-1]['close']

        if bullish_trend:
            crossover = macd_prev2 <= signal_prev2 and macd_prev > signal_prev
            if not crossover:
                return None
            if self.require_macd_above_zero and macd_prev <= 0:
                return None

            # Histogram increasing
            hist_ok = all(
                histogram.iloc[-i] > histogram.iloc[-i - 1]
                for i in range(1, min(self.histogram_confirm_bars + 1, len(histogram)))
            )
            if not hist_ok:
                return None

            sl_raw = es - atr * self.sl_atr_buffer
            sl_distance = max(self.risk_manager.min_sl, min(self.risk_manager.max_sl, abs(entry - sl_raw)))

            return {
                'direction': 'BUY',
                'entry': entry,
                'sl': entry - sl_distance,
                'rr': self.rr_ratio,
                'reason': 'MACD Bullish Cross + EMA Alignment'
            }

        elif bearish_trend:
            crossover = macd_prev2 >= signal_prev2 and macd_prev < signal_prev
            if not crossover:
                return None
            if self.require_macd_below_zero and macd_prev >= 0:
                return None

            hist_ok = all(
                histogram.iloc[-i] < histogram.iloc[-i - 1]
                for i in range(1, min(self.histogram_confirm_bars + 1, len(histogram)))
            )
            if not hist_ok:
                return None

            sl_raw = es + atr * self.sl_atr_buffer
            sl_distance = max(self.risk_manager.min_sl, min(self.risk_manager.max_sl, abs(sl_raw - entry)))

            return {
                'direction': 'SELL',
                'entry': entry,
                'sl': entry + sl_distance,
                'rr': self.rr_ratio,
                'reason': 'MACD Bearish Cross + EMA Alignment'
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
