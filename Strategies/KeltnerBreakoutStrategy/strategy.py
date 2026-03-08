"""
Keltner Channel Breakout Live Strategy

Trades volatility breakouts after TTM Squeeze (Bollinger inside Keltner).
Confirmed by ADX trend strength and ROC momentum, filtered by EMA200 slope.
Designed for M15 timeframe on Gold and GBPUSD.
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from typing import Dict, Any
from Strategies.base import BaseStrategy, StrategyInfo, StrategyRegistry, StrategyStatus


@StrategyRegistry.register
class KeltnerBreakoutLiveStrategy(BaseStrategy):
    """
    Keltner Channel Breakout Strategy for live trading.

    Enters on volatility expansion after squeeze fires, confirmed by ADX
    trend strength and ROC momentum, aligned with EMA200 slope.
    """

    @classmethod
    def get_info(cls) -> StrategyInfo:
        return StrategyInfo(
            id="keltner_breakout_strategy",
            name="Keltner Channel Breakout Strategy",
            description="Volatility breakout using TTM Squeeze (BB inside KC) "
                        "with ADX + ROC momentum confirmation on M15.",
            version="1.0.0",
            author="ProTrading",
            timeframes=["M15"],
            symbols=["XAUUSD", "GBPUSD"],
            parameters={
                "risk_percent": 1.0,
                "max_spread_usd": 0.40,
                "kc_ema_period": 20,
                "kc_atr_period": 10,
                "kc_atr_mult": 2.0,
                "bb_period": 20,
                "bb_std": 2.0,
                "squeeze_lookback": 5,
                "roc_period": 12,
                "min_adx": 20,
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
            from Strategies.shared.broker_timezone import detect_broker_timezone, get_ny_timezone

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

            self.logger = setup_logger('KeltnerBreakoutStrategy',
                                       str(os.path.join(os.path.dirname(__file__), 'logs')))

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
                KC_EMA_PERIOD, KC_ATR_PERIOD, KC_ATR_MULT,
                BB_PERIOD, BB_STD, SQUEEZE_LOOKBACK,
                ROC_PERIOD, ADX_PERIOD, MIN_ADX,
                MIN_BARS_FOR_ANALYSIS, TRADE_START_TIME, TRADE_END_TIME
            )
            self.kc_ema_period = KC_EMA_PERIOD
            self.kc_atr_period = KC_ATR_PERIOD
            self.kc_atr_mult = KC_ATR_MULT
            self.bb_period = BB_PERIOD
            self.bb_std = BB_STD
            self.squeeze_lookback = SQUEEZE_LOOKBACK
            self.roc_period = ROC_PERIOD
            self.adx_period = ADX_PERIOD
            self.min_adx = MIN_ADX
            self.min_bars = MIN_BARS_FOR_ANALYSIS
            self.trade_start = TRADE_START_TIME
            self.trade_end = TRADE_END_TIME

            self.current_date = None
            self.last_signal_time = None

            self.logger.info("=" * 60)
            self.logger.info("KELTNER CHANNEL BREAKOUT STRATEGY INITIALIZED")
            self.logger.info(f"Symbol: {TARGET_SYMBOL} | TF: M15 | Magic: {MAGIC_NUMBER}")
            self.logger.info(f"KC EMA: {KC_EMA_PERIOD} | ATR mult: {KC_ATR_MULT} | Min ADX: {MIN_ADX}")
            self.logger.info(f"Squeeze lookback: {SQUEEZE_LOOKBACK} | ROC: {ROC_PERIOD}")
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

                # Look for setup using closed bars only (exclude forming bar)
                # This matches backtest semantics: signal on bar i-1 close, entry at bar i open
                signal_bars = df.iloc[:-1]
                if len(signal_bars) < self.min_bars:
                    time_module.sleep(1)
                    continue
                setup = self._find_trade_setup(signal_bars)
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
        return {"strategy_id": "keltner_breakout_strategy", "is_running": self._running}

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
        Scan for Keltner Channel Breakout setups with TTM Squeeze.

        Logic:
        1. Compute Keltner Channels and Bollinger Bands
        2. Detect squeeze fire (BB was inside KC, now outside)
        3. Require ADX > min_adx (trending)
        4. ROC confirms momentum direction
        5. EMA200 slope filter
        """
        import pandas as pd
        import numpy as np

        close = df['close']
        high = df['high']
        low = df['low']

        # Keltner Channels
        kc_middle = close.ewm(span=self.kc_ema_period, adjust=False).mean()
        kc_atr = self._calculate_atr_series(df, self.kc_atr_period)
        kc_upper = kc_middle + self.kc_atr_mult * kc_atr
        kc_lower = kc_middle - self.kc_atr_mult * kc_atr

        # Bollinger Bands
        bb_middle = close.rolling(self.bb_period).mean()
        bb_std = close.rolling(self.bb_period).std()
        bb_upper = bb_middle + self.bb_std * bb_std
        bb_lower = bb_middle - self.bb_std * bb_std

        # Squeeze detection
        squeeze_on = (bb_upper < kc_upper) & (bb_lower > kc_lower)
        squeeze_fire = squeeze_on.shift(1).fillna(False) & ~squeeze_on

        recent_fired = squeeze_fire.iloc[-(self.squeeze_lookback + 1):].any()
        if not recent_fired:
            return None

        # ADX filter
        adx_val = self._calculate_adx(df, self.adx_period)
        if adx_val < self.min_adx:
            return None

        # ROC momentum
        roc = self._calculate_roc(close, self.roc_period)
        if len(roc) < 2 or pd.isna(roc.iloc[-1]) or pd.isna(roc.iloc[-2]):
            return None

        current_roc = roc.iloc[-1]
        prev_roc = roc.iloc[-2]

        # EMA200 slope
        ema200 = close.ewm(span=200, adjust=False).mean()
        ema200_slope = self._ema_slope(ema200, 20)

        # Signal from the last closed bar; entry at current market price
        current_close = float(close.iloc[-1])  # last closed bar's close
        current_kc_upper = float(kc_upper.iloc[-1])
        current_kc_lower = float(kc_lower.iloc[-1])

        if pd.isna(kc_upper.iloc[-1]) or pd.isna(kc_lower.iloc[-1]):
            return None

        tick = self.mt5.symbol_info_tick(self.symbol)
        atr_14 = self.indicators.calculate_atr(df, 14)
        if atr_14 <= 0:
            atr_14 = 1.0

        min_sl = self.risk_manager.min_sl
        max_sl = self.risk_manager.max_sl

        # === LONG SETUP ===
        if (current_close > current_kc_upper
                and current_roc > 0
                and current_roc > prev_roc
                and ema200_slope != "falling"):

            entry = tick.ask if tick else current_close  # BUY at ask
            sl_raw = current_kc_lower
            sl_distance = abs(entry - sl_raw)

            atr_sl = 2.0 * atr_14
            if sl_distance > atr_sl * 2.0:
                sl_distance = atr_sl

            sl_distance = max(min_sl, min(max_sl, sl_distance))
            sl = entry - sl_distance
            tp = entry + sl_distance * self.rr_ratio

            return {
                'direction': 'BUY',
                'entry': entry,
                'sl': sl,
                'rr': self.rr_ratio,
                'reason': f'Keltner Breakout Long (ADX={adx_val:.0f}, ROC={current_roc:.3f})'
            }

        # === SHORT SETUP ===
        if (current_close < current_kc_lower
                and current_roc < 0
                and current_roc < prev_roc
                and ema200_slope != "rising"):

            entry = tick.bid if tick else current_close  # SELL at bid
            sl_raw = current_kc_upper
            sl_distance = abs(sl_raw - entry)

            atr_sl = 2.0 * atr_14
            if sl_distance > atr_sl * 2.0:
                sl_distance = atr_sl

            sl_distance = max(min_sl, min(max_sl, sl_distance))
            sl = entry + sl_distance
            tp = entry - sl_distance * self.rr_ratio

            return {
                'direction': 'SELL',
                'entry': entry,
                'sl': sl,
                'rr': self.rr_ratio,
                'reason': f'Keltner Breakout Short (ADX={adx_val:.0f}, ROC={current_roc:.3f})'
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

    # ------------------------------------------------------------------
    # Indicator Helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _calculate_roc(close, period):
        shifted = close.shift(period)
        return (close - shifted) / shifted * 100

    @staticmethod
    def _ema_slope(ema, slope_bars):
        import pandas as pd
        if len(ema) <= slope_bars:
            return "flat"
        current = ema.iloc[-1]
        prev = ema.iloc[-1 - slope_bars]
        if pd.isna(current) or pd.isna(prev):
            return "flat"
        diff = current - prev
        threshold = abs(prev) * 0.001 if prev != 0 else 0.01
        if diff > threshold:
            return "rising"
        elif diff < -threshold:
            return "falling"
        return "flat"

    @staticmethod
    def _calculate_atr_series(df, period):
        high = df['high']
        low = df['low']
        close = df['close']
        import pandas as pd
        tr = pd.concat([
            high - low,
            (high - close.shift(1)).abs(),
            (low - close.shift(1)).abs(),
        ], axis=1).max(axis=1)
        return tr.rolling(period).mean()

    @staticmethod
    def _calculate_adx(df, period):
        import pandas as pd
        import numpy as np
        if len(df) < period + 5:
            return 0.0

        high = df['high']
        low = df['low']
        close = df['close']

        plus_dm = high.diff()
        minus_dm = -low.diff()
        plus_dm = plus_dm.where((plus_dm > minus_dm) & (plus_dm > 0), 0.0)
        minus_dm = minus_dm.where((minus_dm > plus_dm) & (minus_dm > 0), 0.0)

        tr = pd.concat([
            high - low,
            (high - close.shift(1)).abs(),
            (low - close.shift(1)).abs(),
        ], axis=1).max(axis=1)

        atr = tr.ewm(span=period, adjust=False).mean()
        plus_di = 100 * (plus_dm.ewm(span=period, adjust=False).mean() / atr)
        minus_di = 100 * (minus_dm.ewm(span=period, adjust=False).mean() / atr)

        di_sum = plus_di + minus_di
        di_sum = di_sum.replace(0, np.nan)
        dx = 100 * (plus_di - minus_di).abs() / di_sum
        adx = dx.ewm(span=period, adjust=False).mean()

        if len(adx) > 0 and not pd.isna(adx.iloc[-1]):
            return float(adx.iloc[-1])
        return 0.0
