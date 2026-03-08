"""
VWAP Mean Reversion Live Strategy

Trades when price deviates beyond 2 sigma from session VWAP in ranging
markets (ADX < 30). Targets reversion to the VWAP. Designed for M5
timeframe on Gold.
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from typing import Dict, Any
from Strategies.base import BaseStrategy, StrategyInfo, StrategyRegistry, StrategyStatus


@StrategyRegistry.register
class VWAPReversionLiveStrategy(BaseStrategy):
    """
    VWAP Mean Reversion Strategy for live trading.

    Enters when price breaches outer sigma band around VWAP with RSI
    confirmation, only in ranging markets (ADX < threshold). Targets
    reversion to VWAP with minimum 2:1 R:R.
    """

    @classmethod
    def get_info(cls) -> StrategyInfo:
        return StrategyInfo(
            id="vwap_reversion_strategy",
            name="VWAP Mean Reversion Strategy",
            description="Institutional VWAP-based mean reversion on M5. "
                        "Trades 2+ sigma deviation in ranging markets (ADX<30).",
            version="1.0.0",
            author="ProTrading",
            timeframes=["M5"],
            symbols=["XAUUSD"],
            parameters={
                "risk_percent": 1.0,
                "max_spread_usd": 0.40,
                "vwap_std_period": 20,
                "entry_sigma": 2.0,
                "sl_sigma": 3.0,
                "rsi_period": 14,
                "adx_period": 14,
                "max_adx": 30,
                "min_rr": 2.0,
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

            self.logger = setup_logger('VWAPReversionStrategy',
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
                VWAP_STD_PERIOD, ENTRY_SIGMA, SL_SIGMA,
                RSI_PERIOD, ADX_PERIOD, MAX_ADX,
                MIN_BARS_FOR_ANALYSIS, TRADE_START_TIME, TRADE_END_TIME
            )
            self.vwap_std_period = VWAP_STD_PERIOD
            self.entry_sigma = ENTRY_SIGMA
            self.sl_sigma = SL_SIGMA
            self.rsi_period = RSI_PERIOD
            self.adx_period = ADX_PERIOD
            self.max_adx = MAX_ADX
            self.min_bars = MIN_BARS_FOR_ANALYSIS
            self.trade_start = TRADE_START_TIME
            self.trade_end = TRADE_END_TIME

            self.current_date = None
            self.last_signal_time = None

            self.logger.info("=" * 60)
            self.logger.info("VWAP MEAN REVERSION STRATEGY INITIALIZED")
            self.logger.info(f"Symbol: {TARGET_SYMBOL} | TF: M5 | Magic: {MAGIC_NUMBER}")
            self.logger.info(f"Entry Sigma: {ENTRY_SIGMA} | SL Sigma: {SL_SIGMA} | Max ADX: {MAX_ADX}")
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
        return {"strategy_id": "vwap_reversion_strategy", "is_running": self._running}

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
        Scan for VWAP Mean Reversion setups.

        Logic:
        1. Compute session VWAP and sigma bands
        2. Check ADX < max_adx (ranging market)
        3. LONG: close <= VWAP - entry_sigma * sigma AND RSI < 35
        4. SHORT: close >= VWAP + entry_sigma * sigma AND RSI > 65
        5. SL: VWAP +/- sl_sigma * sigma (clamped)
        6. TP: VWAP (the mean), minimum 2:1 R:R enforced
        """
        import pandas as pd
        import numpy as np

        close = df['close']

        # VWAP computation (daily reset)
        vwap, sigma = self._compute_vwap_and_sigma(df)
        if vwap is None or sigma is None or sigma <= 0:
            return None

        # ADX filter
        adx_val = self._calculate_adx(df, self.adx_period)
        if adx_val >= self.max_adx:
            return None

        # RSI
        rsi = self.indicators.calculate_rsi(close, self.rsi_period)
        current_rsi = rsi.iloc[-1] if len(rsi) > 0 and not pd.isna(rsi.iloc[-1]) else 50.0

        # Band levels
        upper_entry = vwap + self.entry_sigma * sigma
        lower_entry = vwap - self.entry_sigma * sigma

        # Signal from the last closed bar; entry at current market price
        current_close = float(close.iloc[-1])  # last closed bar's close
        tick = self.mt5.symbol_info_tick(self.symbol)

        min_sl = self.risk_manager.min_sl
        max_sl = self.risk_manager.max_sl

        # === LONG SETUP ===
        if current_close <= lower_entry and current_rsi < 35:
            if not self._is_bullish_reversal(df):
                return None

            entry = tick.ask if tick else current_close  # BUY at ask
            sl_raw = vwap - self.sl_sigma * sigma
            sl_distance = abs(entry - sl_raw)
            sl_distance = max(min_sl, min(max_sl, sl_distance))
            sl = entry - sl_distance

            tp = vwap
            if abs(tp - entry) < sl_distance * self.rr_ratio:
                tp = entry + sl_distance * self.rr_ratio

            return {
                'direction': 'BUY',
                'entry': entry,
                'sl': sl,
                'rr': abs(tp - entry) / sl_distance if sl_distance > 0 else self.rr_ratio,
                'reason': f'VWAP Reversion Long (dev={((current_close - vwap) / sigma):.1f}σ, RSI={current_rsi:.0f}, ADX={adx_val:.0f})'
            }

        # === SHORT SETUP ===
        elif current_close >= upper_entry and current_rsi > 65:
            if not self._is_bearish_reversal(df):
                return None

            entry = tick.bid if tick else current_close  # SELL at bid
            sl_raw = vwap + self.sl_sigma * sigma
            sl_distance = abs(sl_raw - entry)
            sl_distance = max(min_sl, min(max_sl, sl_distance))
            sl = entry + sl_distance

            tp = vwap
            if abs(entry - tp) < sl_distance * self.rr_ratio:
                tp = entry - sl_distance * self.rr_ratio

            return {
                'direction': 'SELL',
                'entry': entry,
                'sl': sl,
                'rr': abs(entry - tp) / sl_distance if sl_distance > 0 else self.rr_ratio,
                'reason': f'VWAP Reversion Short (dev={((current_close - vwap) / sigma):.1f}σ, RSI={current_rsi:.0f}, ADX={adx_val:.0f})'
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
    # VWAP Computation
    # ------------------------------------------------------------------

    def _compute_vwap_and_sigma(self, df):
        """Compute session VWAP and rolling sigma for today's bars."""
        import pandas as pd

        now = df.index[-1]
        today = now.date() if hasattr(now, 'date') else now

        today_mask = df.index.normalize() == pd.Timestamp(today)
        today_df = df.loc[today_mask]

        if today_df is None or len(today_df) < 5:
            return None, None

        typical_price = (today_df['high'] + today_df['low'] + today_df['close']) / 3.0

        # Try to use volume
        volume = None
        for col in ('tick_volume', 'volume', 'real_volume'):
            if col in today_df.columns and today_df[col].sum() > 0:
                volume = today_df[col]
                break

        if volume is not None:
            cum_tp_vol = (typical_price * volume).cumsum()
            cum_vol = volume.cumsum()
            vwap_series = cum_tp_vol / cum_vol
        else:
            vwap_series = typical_price.expanding().mean()

        current_vwap = vwap_series.iloc[-1]
        if pd.isna(current_vwap):
            return None, None

        deviation = today_df['close'] - vwap_series
        if len(deviation) >= self.vwap_std_period:
            sigma = deviation.rolling(self.vwap_std_period).std().iloc[-1]
        else:
            sigma = deviation.std()

        if pd.isna(sigma) or sigma <= 0:
            return None, None

        return float(current_vwap), float(sigma)

    # ------------------------------------------------------------------
    # Reversal Candle Helpers (matches backtest logic exactly)
    # ------------------------------------------------------------------

    @staticmethod
    def _is_bullish_reversal(df):
        """Detect bullish reversal: close flip, hammer, or bullish pin bar."""
        if len(df) < 2:
            return False
        c = df.iloc[-1]
        p = df.iloc[-2]

        # 1. Close flip (current close > previous close)
        if c["close"] > p["close"]:
            return True

        body = abs(c["close"] - c["open"])
        full_range = c["high"] - c["low"]
        if full_range < 0.01:
            return False

        lower_wick = min(c["open"], c["close"]) - c["low"]
        upper_wick = c["high"] - max(c["open"], c["close"])

        # 2. Hammer: long lower wick, small upper wick
        if lower_wick > full_range * 0.6 and upper_wick < full_range * 0.15:
            return True

        # 3. Bullish pin bar: lower wick > 2x body
        if lower_wick > body * 2 and upper_wick < body * 0.5:
            return True

        return False

    @staticmethod
    def _is_bearish_reversal(df):
        """Detect bearish reversal: close flip, shooting star, or bearish pin bar."""
        if len(df) < 2:
            return False
        c = df.iloc[-1]
        p = df.iloc[-2]

        # 1. Close flip
        if c["close"] < p["close"]:
            return True

        body = abs(c["close"] - c["open"])
        full_range = c["high"] - c["low"]
        if full_range < 0.01:
            return False

        upper_wick = c["high"] - max(c["open"], c["close"])
        lower_wick = min(c["open"], c["close"]) - c["low"]

        # 2. Shooting star: long upper wick, small lower wick
        if upper_wick > full_range * 0.6 and lower_wick < full_range * 0.15:
            return True

        # 3. Bearish pin bar: upper wick > 2x body
        if upper_wick > body * 2 and lower_wick < body * 0.5:
            return True

        return False

    # ------------------------------------------------------------------
    # ADX Helper
    # ------------------------------------------------------------------

    @staticmethod
    def _calculate_adx(df, period):
        """Average Directional Index (Wilder's smoothing)."""
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
