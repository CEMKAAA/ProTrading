"""
Ichimoku Retracement Live Strategy
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

import pandas as pd
from typing import Dict, Any
from Strategies.base import BaseStrategy, StrategyInfo, StrategyRegistry


@StrategyRegistry.register
class IchimokuLiveStrategy(BaseStrategy):
    """
    Ichimoku Cloud Retracement Strategy for XAUUSD.

    Trades pullbacks to the Kijun-sen within an established cloud trend.
    Runs on H1 timeframe.
    """

    @classmethod
    def get_info(cls) -> StrategyInfo:
        return StrategyInfo(
            id="ichimoku_strategy",
            name="Ichimoku Retracement Strategy",
            description="Trades Kijun-sen pullbacks within Ichimoku cloud trends on H1.",
            version="1.0.0",
            author="ProTrading",
            timeframes=["H1"],
            symbols=["XAUUSD"],
            parameters={
                "risk_percent": 1.0,
                "tenkan_period": 9,
                "kijun_period": 26,
                "senkou_b_period": 52,
                "min_cloud_thickness_atr": 0.2,
                "min_cloud_break_atr": 0.10,
                "max_kijun_distance_atr": 1.25,
                "min_rr_ratio": 2.5,
                "max_rr_ratio": 5.0,
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
                DATA_CACHE_BARS, STATE_FILE, MIN_BARS_FOR_ANALYSIS,
                TENKAN_PERIOD, KIJUN_PERIOD, SENKOU_B_PERIOD, CLOUD_DISPLACEMENT,
                REQUIRE_CLOUD_COLOR, REQUIRE_CHIKOU, KIJUN_TOUCH_TOLERANCE_ATR,
                MIN_CLOUD_THICKNESS_ATR, MIN_CLOUD_BREAK_ATR, MAX_KIJUN_DISTANCE_ATR,
                KIJUN_SLOPE_LOOKBACK, MIN_KIJUN_SLOPE_ATR, SKIP_OUT_OF_BOUNDS_SL,
                SL_BUFFER_ATR, MIN_RR_RATIO, MAX_RR_RATIO, KIJUN_CLOUD_TP_MULTIPLIER,
                TRADE_START_TIME, TRADE_END_TIME
            )
            from Strategies.shared import (
                setup_logger, BotStateManager, DataManager,
                RiskManager, TradeExecutor, Indicators
            )
            import pytz

            if not mt5.initialize():
                self.error_message = f"MT5 Init Failed"
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
            self.logger = setup_logger('IchimokuStrategy',
                                       str(os.path.join(os.path.dirname(__file__), 'logs')))
            self.broker_tz = self._detect_broker_timezone()
            self.ny_tz = pytz.timezone('America/New_York')

            self.data_manager = DataManager(TARGET_SYMBOL, self.broker_tz, self.ny_tz,
                                            TIMEFRAME, DATA_CACHE_BARS, self.logger)
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
            self.state_manager = BotStateManager(str(STATE_FILE), STRATEGY_ID, STRATEGY_NAME)
            self.indicators = Indicators

            # Strategy config
            self.tenkan_period = TENKAN_PERIOD
            self.kijun_period = KIJUN_PERIOD
            self.senkou_b_period = SENKOU_B_PERIOD
            self.displacement = CLOUD_DISPLACEMENT
            self.require_cloud_color = REQUIRE_CLOUD_COLOR
            self.require_chikou = REQUIRE_CHIKOU
            self.kijun_tol_atr = KIJUN_TOUCH_TOLERANCE_ATR
            self.min_cloud_thickness_atr = MIN_CLOUD_THICKNESS_ATR
            self.min_cloud_break_atr = MIN_CLOUD_BREAK_ATR
            self.max_kijun_distance_atr = MAX_KIJUN_DISTANCE_ATR
            self.kijun_slope_lookback = KIJUN_SLOPE_LOOKBACK
            self.min_kijun_slope_atr = MIN_KIJUN_SLOPE_ATR
            self.skip_out_of_bounds_sl = SKIP_OUT_OF_BOUNDS_SL
            self.sl_buffer_atr = SL_BUFFER_ATR
            self.min_rr = MIN_RR_RATIO
            self.max_rr = MAX_RR_RATIO
            self.tp_mult = KIJUN_CLOUD_TP_MULTIPLIER
            self.min_bars = MIN_BARS_FOR_ANALYSIS
            self.trade_start = TRADE_START_TIME
            self.trade_end = TRADE_END_TIME

            self.current_date = None
            self.last_signal_time = None

            self.logger.info("ICHIMOKU STRATEGY INITIALIZED")
            return True

        except Exception as e:
            self.error_message = str(e)
            return False

    def _detect_broker_timezone(self):
        from datetime import datetime, timezone
        import pytz
        tick = self.mt5.symbol_info_tick(self.symbol)
        broker_time = datetime.fromtimestamp(tick.time)
        utc_time = datetime.fromtimestamp(tick.time, tz=timezone.utc).replace(tzinfo=None)
        offset_minutes = int((broker_time - utc_time).total_seconds() / 60)
        return pytz.FixedOffset(offset_minutes)

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

                if self.current_date != now.date():
                    self.current_date = now.date()
                    self.last_signal_time = None
                    self.data_manager.clear_cache()
                    self.logger.info(f"NEW TRADING DAY: {now.date()}")

                if now.weekday() == 4 and now.time() > dt_time(15, 30):
                    self.trade_executor.close_all_positions("Friday Close")
                    time_module.sleep(300)
                    continue

                if not (self.trade_start <= now.time() <= self.trade_end):
                    time_module.sleep(60)
                    continue

                self.trade_executor.manage_trailing_stops(self.data_manager)

                self.risk_manager.check_daily_status()
                if not self.risk_manager.can_trade or not self.risk_manager.can_open_new_position():
                    time_module.sleep(60)
                    continue

                df = self.data_manager.get_data()
                if df.empty or len(df) < self.min_bars:
                    time_module.sleep(10)
                    continue

                signal_time = df.index[-2]
                if self.last_signal_time == signal_time:
                    time_module.sleep(5)
                    continue
                self.last_signal_time = signal_time

                setup = self._find_trade_setup(df)
                if setup:
                    self.logger.info(f"SETUP: {setup['reason']}")
                    self._execute_setup(setup)

                time_module.sleep(30)  # H1 timeframe

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
        return {"strategy_id": "ichimoku_strategy", "is_running": self._running}

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
            )
        except Exception:
            pass

    def _find_trade_setup(self, df):
        """Detect Kijun bounce setups."""
        min_bars = self.senkou_b_period + self.displacement + 5
        if len(df) < min_bars + 1:
            return None

        # Use the last closed candle for signal generation.
        signal_df = df.iloc[:-1]
        tenkan, kijun, senkou_a, senkou_b, chikou = self.indicators.calculate_ichimoku(
            signal_df, self.tenkan_period, self.kijun_period,
            self.senkou_b_period, self.displacement
        )

        close = signal_df.iloc[-1]['close']
        low = signal_df.iloc[-1]['low']
        high = signal_df.iloc[-1]['high']

        t = tenkan.iloc[-1]
        k = kijun.iloc[-1]
        sa = senkou_a.iloc[-1]
        sb = senkou_b.iloc[-1]

        if pd.isna(t) or pd.isna(k) or pd.isna(sa) or pd.isna(sb):
            return None

        cloud_top = max(sa, sb)
        cloud_bottom = min(sa, sb)
        bullish_cloud = sa > sb
        bearish_cloud = sa < sb

        atr = self.indicators.calculate_atr(signal_df, 14)
        if atr <= 0:
            return None
        if atr > 0 and self.min_cloud_thickness_atr > 0:
            cloud_thickness_atr = abs(sa - sb) / atr
            if cloud_thickness_atr < self.min_cloud_thickness_atr:
                return None
        kijun_tol = atr * self.kijun_tol_atr

        # Bullish: price above cloud, Tenkan > Kijun, price touches Kijun
        if close > cloud_top:
            if self.require_cloud_color and not bullish_cloud:
                return None
            if t <= k:
                return None
            if self.min_cloud_break_atr > 0 and ((close - cloud_top) / atr) < self.min_cloud_break_atr:
                return None
            if self.max_kijun_distance_atr > 0 and abs(close - k) / atr > self.max_kijun_distance_atr:
                return None
            if not (low <= k + kijun_tol):
                return None
            if not (close > k):
                return None
            if self.require_chikou and not self._check_chikou(signal_df, chikou, True):
                return None

            slope_lookback = max(1, int(self.kijun_slope_lookback))
            if len(kijun) > slope_lookback and not pd.isna(kijun.iloc[-1 - slope_lookback]):
                kijun_slope_atr = (k - kijun.iloc[-1 - slope_lookback]) / atr
                if kijun_slope_atr < self.min_kijun_slope_atr:
                    return None

            entry = close
            sl_raw = cloud_bottom - atr * self.sl_buffer_atr
            raw_sl_distance = abs(entry - sl_raw)
            if self.skip_out_of_bounds_sl and (
                raw_sl_distance < self.risk_manager.min_sl or raw_sl_distance > self.risk_manager.max_sl
            ):
                return None
            sl_distance = max(self.risk_manager.min_sl,
                              min(self.risk_manager.max_sl, raw_sl_distance))
            sl = entry - sl_distance

            kijun_cloud_dist = abs(k - cloud_top)
            tp_kijun = entry + kijun_cloud_dist * self.tp_mult
            tp_rr = entry + sl_distance * self.min_rr
            tp = max(tp_kijun, tp_rr)
            rr = abs(tp - entry) / sl_distance if sl_distance > 0 else self.min_rr
            if rr > self.max_rr:
                tp = entry + sl_distance * self.max_rr

            return {'direction': 'BUY', 'entry': entry, 'sl': sl, 'tp': tp,
                    'reason': 'Ichimoku Kijun Bounce (Bullish)'}

        # Bearish: price below cloud
        if close < cloud_bottom:
            if self.require_cloud_color and not bearish_cloud:
                return None
            if t >= k:
                return None
            if self.min_cloud_break_atr > 0 and ((cloud_bottom - close) / atr) < self.min_cloud_break_atr:
                return None
            if self.max_kijun_distance_atr > 0 and abs(close - k) / atr > self.max_kijun_distance_atr:
                return None
            if not (high >= k - kijun_tol):
                return None
            if not (close < k):
                return None
            if self.require_chikou and not self._check_chikou(signal_df, chikou, False):
                return None

            slope_lookback = max(1, int(self.kijun_slope_lookback))
            if len(kijun) > slope_lookback and not pd.isna(kijun.iloc[-1 - slope_lookback]):
                kijun_slope_atr = (kijun.iloc[-1 - slope_lookback] - k) / atr
                if kijun_slope_atr < self.min_kijun_slope_atr:
                    return None

            entry = close
            sl_raw = cloud_top + atr * self.sl_buffer_atr
            raw_sl_distance = abs(sl_raw - entry)
            if self.skip_out_of_bounds_sl and (
                raw_sl_distance < self.risk_manager.min_sl or raw_sl_distance > self.risk_manager.max_sl
            ):
                return None
            sl_distance = max(self.risk_manager.min_sl,
                              min(self.risk_manager.max_sl, raw_sl_distance))
            sl = entry + sl_distance

            kijun_cloud_dist = abs(k - cloud_bottom)
            tp_kijun = entry - kijun_cloud_dist * self.tp_mult
            tp_rr = entry - sl_distance * self.min_rr
            tp = min(tp_kijun, tp_rr)
            rr = abs(tp - entry) / sl_distance if sl_distance > 0 else self.min_rr
            if rr > self.max_rr:
                tp = entry - sl_distance * self.max_rr

            return {'direction': 'SELL', 'entry': entry, 'sl': sl, 'tp': tp,
                    'reason': 'Ichimoku Kijun Rejection (Bearish)'}

        return None

    def _check_chikou(self, df, chikou, bullish):
        """Check Chikou Span confirmation."""
        idx = max(0, len(df) - 1 - self.displacement)
        if idx >= len(chikou):
            return True
        val = chikou.iloc[idx]
        if pd.isna(val):
            return True
        price_ago = df.iloc[idx]['close']
        return val > price_ago if bullish else val < price_ago

    def _execute_setup(self, setup):
        if not self.risk_manager.validate_spread():
            return
        sl = self.risk_manager.validate_stop_loss(setup['entry'], setup['sl'], setup['direction'])
        sl_distance = abs(setup['entry'] - sl)
        lot = self.risk_manager.calculate_position_size(sl_distance)
        rr = abs(setup['tp'] - setup['entry']) / sl_distance if sl_distance > 0 else 2.5
        self.trade_executor.execute_trade(
            setup['direction'], setup['entry'], sl, lot,
            setup['reason'][:31], rr_ratio=rr
        )
