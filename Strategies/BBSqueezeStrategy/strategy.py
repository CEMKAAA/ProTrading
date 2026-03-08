"""
Bollinger Band Squeeze Breakout Live Strategy

Detects volatility compression via Bollinger BandWidth at multi-bar lows,
then enters on a confirmed breakout with linear regression momentum and
volume confirmation. Designed for M15 on Gold, GBPUSD, EURUSD.
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from typing import Dict, Any
from Strategies.base import BaseStrategy, StrategyInfo, StrategyRegistry, StrategyStatus


@StrategyRegistry.register
class BBSqueezeLiveStrategy(BaseStrategy):
    """
    Bollinger Band Squeeze Breakout Strategy for live trading.

    Enters when BandWidth reaches a multi-bar low (squeeze) and price
    breaks out of the bands, confirmed by linear regression momentum
    and volume spike.
    """

    @classmethod
    def get_info(cls) -> StrategyInfo:
        return StrategyInfo(
            id="bb_squeeze_strategy",
            name="Bollinger Squeeze Breakout Strategy",
            description="Volatility contraction breakout on M15. "
                        "BandWidth at 120-bar low + linreg momentum + volume spike.",
            version="1.0.0",
            author="ProTrading",
            timeframes=["M15"],
            symbols=["XAUUSD", "GBPUSD", "EURUSD"],
            parameters={
                "risk_percent": 1.0,
                "max_spread_usd": 0.40,
                "bb_period": 20,
                "bb_std": 2.0,
                "squeeze_bandwidth_lookback": 120,
                "momentum_period": 10,
                "volume_spike_mult": 1.3,
                "min_rr": 2.5,
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

            self.logger = setup_logger('BBSqueezeStrategy',
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
                BB_PERIOD, BB_STD, SQUEEZE_BANDWIDTH_LOOKBACK, SQUEEZE_LOOKBACK,
                MOMENTUM_PERIOD, VOLUME_SPIKE_MULT,
                MIN_BARS_FOR_ANALYSIS, TRADE_START_TIME, TRADE_END_TIME
            )
            self.bb_period = BB_PERIOD
            self.bb_std_mult = BB_STD
            self.bw_lookback = SQUEEZE_BANDWIDTH_LOOKBACK
            self.squeeze_lookback = SQUEEZE_LOOKBACK
            self.momentum_period = MOMENTUM_PERIOD
            self.volume_spike_mult = VOLUME_SPIKE_MULT
            self.min_bars = MIN_BARS_FOR_ANALYSIS
            self.trade_start = TRADE_START_TIME
            self.trade_end = TRADE_END_TIME

            self.current_date = None
            self.last_signal_time = None

            self.logger.info("=" * 60)
            self.logger.info("BOLLINGER SQUEEZE BREAKOUT STRATEGY INITIALIZED")
            self.logger.info(f"Symbol: {TARGET_SYMBOL} | TF: M15 | Magic: {MAGIC_NUMBER}")
            self.logger.info(f"BB: {BB_PERIOD}/{BB_STD} | BW lookback: {SQUEEZE_BANDWIDTH_LOOKBACK}")
            self.logger.info(f"Momentum: {MOMENTUM_PERIOD} | Vol spike: {VOLUME_SPIKE_MULT}x")
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
        return {"strategy_id": "bb_squeeze_strategy", "is_running": self._running}

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
        Scan for BB Squeeze Breakout setups.

        Logic:
        1. Compute Bollinger Bands and BandWidth
        2. Detect squeeze: BW within 5% of N-bar min
        3. Breakout: price closes outside BB
        4. Momentum: linreg slope confirms direction and accelerating
        5. Volume spike: current volume > mult * 20-bar avg
        6. EMA200 slope filter
        """
        import pandas as pd
        import numpy as np

        close = df['close']

        # Bollinger Bands
        sma = close.rolling(self.bb_period).mean()
        std = close.rolling(self.bb_period).std(ddof=0)
        upper_band = sma + self.bb_std_mult * std
        lower_band = sma - self.bb_std_mult * std

        current_upper = upper_band.iloc[-1]
        current_lower = lower_band.iloc[-1]
        current_sma = sma.iloc[-1]

        if pd.isna(current_upper) or pd.isna(current_lower) or pd.isna(current_sma):
            return None

        # BandWidth
        bandwidth = (upper_band - lower_band) / sma * 100
        bandwidth = bandwidth.replace([np.inf, -np.inf], np.nan)

        if pd.isna(bandwidth.iloc[-1]):
            return None

        # Squeeze detection
        bw_min = bandwidth.rolling(self.bw_lookback).min()

        squeeze_was_recent = False
        for lookback_idx in range(1, self.squeeze_lookback + 1):
            idx = -1 - lookback_idx
            if abs(idx) > len(bandwidth) or abs(idx) > len(bw_min):
                break
            bw_val = bandwidth.iloc[idx]
            bw_min_val = bw_min.iloc[idx]
            if pd.isna(bw_val) or pd.isna(bw_min_val) or bw_min_val <= 0:
                continue
            if bw_val <= bw_min_val * 1.05:
                squeeze_was_recent = True
                break

        if not squeeze_was_recent:
            return None

        # Momentum (linear regression slope)
        current_momentum = self._linreg_slope(close, self.momentum_period, 0)
        prev_momentum = self._linreg_slope(close, self.momentum_period, 1)

        if current_momentum is None or prev_momentum is None:
            return None

        # Volume confirmation
        volume_ok = True
        for col in ('tick_volume', 'volume'):
            if col in df.columns and df[col].sum() > 0:
                vol_series = df[col]
                if len(vol_series) >= 21:
                    avg_vol = vol_series.iloc[-21:-1].mean()
                    current_vol = vol_series.iloc[-1]
                    if avg_vol > 0:
                        volume_ok = current_vol > avg_vol * self.volume_spike_mult
                break

        # EMA200 slope
        ema200 = close.ewm(span=200, adjust=False).mean()
        ema200_rising = False
        ema200_falling = False
        slope_bars = 20
        if len(ema200) > slope_bars:
            ema200_current = ema200.iloc[-1]
            ema200_prev = ema200.iloc[-1 - slope_bars]
            if not pd.isna(ema200_current) and not pd.isna(ema200_prev):
                ema200_rising = ema200_current > ema200_prev
                ema200_falling = ema200_current < ema200_prev

        # ATR for SL fallback
        atr = self.indicators.calculate_atr(df, 14)
        if atr <= 0:
            return None

        # Signal from last closed bar; entry at current market price
        signal_close = float(close.iloc[-1])  # last closed bar's close
        tick = self.mt5.symbol_info_tick(self.symbol)
        min_sl = self.risk_manager.min_sl
        max_sl = self.risk_manager.max_sl

        # === LONG SETUP ===
        if (signal_close > float(current_upper)
                and current_momentum > 0
                and current_momentum > prev_momentum
                and volume_ok
                and not ema200_falling):

            entry = tick.ask if tick else signal_close  # BUY at ask
            sl_raw = float(current_sma)
            sl_distance = abs(entry - sl_raw)

            if sl_distance < atr:
                sl_distance = 1.5 * atr

            sl_distance = max(min_sl, min(max_sl, sl_distance))
            sl = entry - sl_distance

            band_spread = abs(float(current_upper) - float(current_lower))
            tp_distance = band_spread * 2.0

            if tp_distance < sl_distance * self.rr_ratio:
                tp_distance = sl_distance * self.rr_ratio

            return {
                'direction': 'BUY',
                'entry': entry,
                'sl': sl,
                'rr': tp_distance / sl_distance if sl_distance > 0 else self.rr_ratio,
                'reason': f'BB Squeeze Breakout Long (BW={bandwidth.iloc[-1]:.2f}, mom={current_momentum:.3f})'
            }

        # === SHORT SETUP ===
        if (signal_close < float(current_lower)
                and current_momentum < 0
                and current_momentum < prev_momentum
                and volume_ok
                and not ema200_rising):

            entry = tick.bid if tick else signal_close  # SELL at bid
            sl_raw = float(current_sma)
            sl_distance = abs(sl_raw - entry)

            if sl_distance < atr:
                sl_distance = 1.5 * atr

            sl_distance = max(min_sl, min(max_sl, sl_distance))
            sl = entry + sl_distance

            band_spread = abs(float(current_upper) - float(current_lower))
            tp_distance = band_spread * 2.0

            if tp_distance < sl_distance * self.rr_ratio:
                tp_distance = sl_distance * self.rr_ratio

            return {
                'direction': 'SELL',
                'entry': entry,
                'sl': sl,
                'rr': tp_distance / sl_distance if sl_distance > 0 else self.rr_ratio,
                'reason': f'BB Squeeze Breakout Short (BW={bandwidth.iloc[-1]:.2f}, mom={current_momentum:.3f})'
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
    def _linreg_slope(series, period, offset=0):
        """Linear regression slope over a window."""
        import numpy as np

        end_idx = len(series) - offset
        start_idx = end_idx - period
        if start_idx < 0 or end_idx <= 0:
            return None

        window = series.iloc[start_idx:end_idx].values
        if len(window) < period:
            return None

        if np.any(np.isnan(window)):
            return None

        x = np.arange(period, dtype=np.float64)
        try:
            slope = np.polyfit(x, window, 1)[0]
        except (np.linalg.LinAlgError, ValueError):
            return None

        return float(slope)
