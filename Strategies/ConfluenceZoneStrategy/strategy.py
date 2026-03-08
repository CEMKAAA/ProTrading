"""
Multi-TF Confluence Zone Live Strategy

Trades bounces at zones where 3+ technical levels converge within 1 ATR width.
Each confluence factor adds points to a score; minimum 60 required.
Requires a reversal candle pattern at the zone for entry.
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from typing import Dict, Any, List, Tuple, Optional
from Strategies.base import BaseStrategy, StrategyInfo, StrategyRegistry, StrategyStatus


@StrategyRegistry.register
class ConfluenceZoneLiveStrategy(BaseStrategy):
    """
    Multi-TF Confluence Zone Strategy for XAUUSD.

    Scores confluence zones based on EMA 50 (+20), EMA 200 (+25),
    session levels (+15 each), round numbers (+15), and RSI extremes (+10).
    Trades bounces at zones scoring >= 60 with reversal candle confirmation.
    """

    @classmethod
    def get_info(cls) -> StrategyInfo:
        return StrategyInfo(
            id="confluence_zone_strategy",
            name="Multi-TF Confluence Zone Strategy",
            description="Trades bounces at confluence zones where 3+ technical levels converge on M15.",
            version="1.0.0",
            author="ProTrading",
            timeframes=["M15"],
            symbols=["XAUUSD"],
            parameters={
                "risk_percent": 1.0,
                "max_spread_usd": 0.40,
                "ema_slow": 50,
                "ema_very_slow": 200,
                "rsi_period": 14,
                "zone_width_atr": 1.0,
                "min_confluence_score": 60,
                "min_levels_in_zone": 3,
                "min_rr_ratio": 2.5,
            }
        )

    def __init__(self):
        super().__init__()
        self.mt5 = None
        self.logger = None
        self.session_levels = {}

    def initialize(self) -> bool:
        try:
            import MetaTrader5 as mt5
            from .config import (
                TARGET_SYMBOL, MAGIC_NUMBER, TIMEFRAME, STRATEGY_ID, STRATEGY_NAME,
                RISK_PERCENT, MAX_SPREAD_USD, MAX_DAILY_LOSS_USD, MAX_TOTAL_RISK_USD,
                MAX_DAILY_TRADES, INITIAL_BALANCE, MIN_SL_USD, MAX_SL_USD,
                USE_TRAILING, TRAILING_ATR_PERIOD, TRAILING_ATR_MULTIPLIER,
                DATA_CACHE_BARS, STATE_FILE, MIN_RR_RATIO
            )
            from Strategies.shared import (
                setup_logger, BotStateManager, DataManager,
                RiskManager, TradeExecutor, Indicators, SessionLevelDetector
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
            self.min_rr_ratio = MIN_RR_RATIO

            self.logger = setup_logger('ConfluenceZoneStrategy',
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
            self.session_detector = SessionLevelDetector(self.data_manager, self.ny_tz)

            # Strategy-specific config
            from .config import (
                EMA_SLOW, EMA_VERY_SLOW, RSI_PERIOD,
                ZONE_WIDTH_ATR, MIN_CONFLUENCE_SCORE, MIN_LEVELS_IN_ZONE,
                USE_REVERSAL_CANDLE_FILTER, RSI_EXTREME_THRESHOLD,
                SL_BUFFER_ATR, MIN_BARS_FOR_ANALYSIS,
                ROUND_NUMBER_INTERVAL,
                TRADE_START_TIME, TRADE_END_TIME
            )
            self.ema_slow = EMA_SLOW
            self.ema_very_slow = EMA_VERY_SLOW
            self.rsi_period = RSI_PERIOD
            self.zone_width_atr = ZONE_WIDTH_ATR
            self.min_confluence_score = MIN_CONFLUENCE_SCORE
            self.min_levels_in_zone = MIN_LEVELS_IN_ZONE
            self.use_reversal_filter = USE_REVERSAL_CANDLE_FILTER
            self.rsi_extreme_threshold = RSI_EXTREME_THRESHOLD
            self.sl_buffer_atr = SL_BUFFER_ATR
            self.min_bars = MIN_BARS_FOR_ANALYSIS
            self.round_number_interval = ROUND_NUMBER_INTERVAL
            self.trade_start = TRADE_START_TIME
            self.trade_end = TRADE_END_TIME

            self.current_date = None
            self.last_signal_time = None
            self.session_levels = {}

            self.logger.info("=" * 60)
            self.logger.info("CONFLUENCE ZONE STRATEGY INITIALIZED")
            self.logger.info(f"Symbol: {TARGET_SYMBOL} | TF: M15 | Magic: {MAGIC_NUMBER}")
            self.logger.info(f"EMA: {EMA_SLOW}/{EMA_VERY_SLOW} | Min Score: {MIN_CONFLUENCE_SCORE}")
            self.logger.info(f"Zone Width: {ZONE_WIDTH_ATR} ATR | Min Levels: {MIN_LEVELS_IN_ZONE}")
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
        return {"strategy_id": "confluence_zone_strategy", "is_running": self._running}

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

        # Refresh session levels for the new day
        try:
            self.session_levels = self.session_detector.get_session_levels(today)
            self.logger.info(f"Session levels: {self.session_levels}")
        except Exception as e:
            self.logger.warning(f"Could not fetch session levels: {e}")
            self.session_levels = {}

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
        Scan for Confluence Zone setups.

        Logic:
        1. Collect technical levels: EMA 50, EMA 200, session levels, round numbers
        2. Cluster levels within 1 ATR width into zones
        3. Score each zone; need >= 60 points
        4. Add RSI bonus if at extremes
        5. Check for reversal candle (pin bar, engulfing, hammer)
        6. LONG: Price at/near zone bottom with reversal candle
        7. SHORT: Price at/near zone top with reversal candle
        8. SL: Other side of zone + 0.5 ATR buffer
        9. TP: 2.5:1 R:R minimum
        """
        import pandas as pd

        close = df['close']
        current_price = float(close.iloc[-1])
        current_close = current_price

        # ATR
        atr = self.indicators.calculate_atr(df, 14)
        if atr <= 0:
            atr = 1.0

        zone_width = self.zone_width_atr * atr

        # Collect all technical levels with weights
        all_levels = self._collect_levels(df, current_price)

        if len(all_levels) < self.min_levels_in_zone:
            return None

        # Cluster levels into confluence zones
        zones = self._find_zones(all_levels, zone_width, self.min_levels_in_zone)

        if not zones:
            return None

        # RSI for bonus scoring
        rsi = self.indicators.calculate_rsi(close, self.rsi_period)
        current_rsi = float(rsi.iloc[-1]) if len(rsi) > 0 and not pd.isna(rsi.iloc[-1]) else 50.0

        # Trend filter: prefer confluence trades aligned with EMA200 direction.
        ema200 = self.indicators.calculate_ema(close, self.ema_very_slow)
        if len(ema200) >= self.ema_very_slow and not pd.isna(ema200.iloc[-1]):
            above_ema200 = current_close > float(ema200.iloc[-1])
        else:
            above_ema200 = None

        # Evaluate each zone
        for zone in zones:
            zone_center = zone['center']
            zone_top = zone['top']
            zone_bottom = zone['bottom']
            score = zone['score']

            # RSI bonus
            if current_rsi > (100 - self.rsi_extreme_threshold):
                # Overbought - bonus only for sell setup (price above zone)
                if current_price > zone_center:
                    score += 10
            elif current_rsi < self.rsi_extreme_threshold:
                # Oversold - bonus only for buy setup (price below zone)
                if current_price < zone_center:
                    score += 10

            if score < self.min_confluence_score:
                continue

            # Price position relative to zone
            price_at_zone = zone_bottom <= current_price <= zone_top
            price_below_center = current_close <= zone_center
            price_above_center = current_close > zone_center

            if not price_at_zone:
                continue

            entry = current_price

            # === BULLISH: Price in lower half of zone (support bounce) ===
            if price_below_center:
                if above_ema200 is not None and not above_ema200:
                    continue
                if self.use_reversal_filter:
                    reversal = self.indicators.detect_reversal_candle(df, 'bullish')
                else:
                    reversal = {"detected": True, "type": "none"}
                if not reversal.get('detected'):
                    continue

                sl = zone_bottom - atr * self.sl_buffer_atr
                sl_distance = abs(entry - sl)

                # Clamp SL distance
                sl_distance = max(self.risk_manager.min_sl, min(self.risk_manager.max_sl, sl_distance))
                sl = entry - sl_distance

                tp = entry + sl_distance * self.min_rr_ratio

                reversal_type = reversal.get('type', 'unknown')
                return {
                    'direction': 'BUY',
                    'entry': entry,
                    'sl': sl,
                    'rr': self.min_rr_ratio,
                    'reason': f'Confluence Zone Long (score={score}, {reversal_type}, levels={zone["count"]})'
                }

            # === BEARISH: Price in upper half of zone (resistance rejection) ===
            if price_above_center:
                if above_ema200 is not None and above_ema200:
                    continue
                if self.use_reversal_filter:
                    reversal = self.indicators.detect_reversal_candle(df, 'bearish')
                else:
                    reversal = {"detected": True, "type": "none"}
                if not reversal.get('detected'):
                    continue

                sl = zone_top + atr * self.sl_buffer_atr
                sl_distance = abs(sl - entry)

                # Clamp SL distance
                sl_distance = max(self.risk_manager.min_sl, min(self.risk_manager.max_sl, sl_distance))
                sl = entry + sl_distance

                tp = entry - sl_distance * self.min_rr_ratio

                reversal_type = reversal.get('type', 'unknown')
                return {
                    'direction': 'SELL',
                    'entry': entry,
                    'sl': sl,
                    'rr': self.min_rr_ratio,
                    'reason': f'Confluence Zone Short (score={score}, {reversal_type}, levels={zone["count"]})'
                }

        return None

    # ------------------------------------------------------------------
    # Level Collection
    # ------------------------------------------------------------------

    def _collect_levels(self, df, current_price: float) -> List[Tuple[float, str, int]]:
        """
        Collect all technical levels with their weights.

        Returns:
            List of (price, type_label, weight) tuples.
        """
        import pandas as pd

        levels: List[Tuple[float, str, int]] = []
        close = df['close']

        # EMA 50 (+20 points)
        ema_50 = self.indicators.calculate_ema(close, self.ema_slow)
        if not pd.isna(ema_50.iloc[-1]):
            levels.append((float(ema_50.iloc[-1]), "ema_50", 20))

        # EMA 200 (+25 points)
        ema_200 = self.indicators.calculate_ema(close, self.ema_very_slow)
        if not pd.isna(ema_200.iloc[-1]):
            levels.append((float(ema_200.iloc[-1]), "ema_200", 25))

        # Session levels (+15 each)
        session_level_weights = {
            'asian_high': 15,
            'asian_low': 15,
            'london_high': 15,
            'london_low': 15,
            'pd_high': 15,
            'pd_low': 15,
        }
        for name, weight in session_level_weights.items():
            val = self.session_levels.get(name)
            if val is not None:
                levels.append((float(val), name, weight))

        # Round numbers (+15 points, $50 intervals for Gold)
        interval = self.round_number_interval
        base = int(current_price / interval) * interval
        for rn in [base - interval, base, base + interval, base + 2 * interval]:
            levels.append((float(rn), f"round_{rn}", 15))

        return levels

    # ------------------------------------------------------------------
    # Zone Clustering
    # ------------------------------------------------------------------

    def _find_zones(
        self,
        levels: List[Tuple[float, str, int]],
        zone_width: float,
        min_levels: int,
    ) -> List[Dict[str, Any]]:
        """
        Cluster nearby levels into confluence zones.

        Uses sliding-window over price-sorted levels. Overlapping zones
        are deduplicated by keeping the highest-scoring one.
        """
        if not levels:
            return []

        sorted_levels = sorted(levels, key=lambda x: x[0])
        zones: List[Dict[str, Any]] = []

        for i in range(len(sorted_levels)):
            zone_levels = [sorted_levels[i]]
            zone_score = sorted_levels[i][2]
            zone_types = [sorted_levels[i][1]]

            for j in range(i + 1, len(sorted_levels)):
                if sorted_levels[j][0] - sorted_levels[i][0] <= zone_width:
                    zone_levels.append(sorted_levels[j])
                    zone_score += sorted_levels[j][2]
                    zone_types.append(sorted_levels[j][1])
                else:
                    break

            if len(zone_levels) >= min_levels:
                prices = [lev[0] for lev in zone_levels]
                zones.append({
                    'center': sum(prices) / len(prices),
                    'top': max(prices) + zone_width * 0.1,
                    'bottom': min(prices) - zone_width * 0.1,
                    'score': zone_score,
                    'count': len(zone_levels),
                    'types': zone_types,
                })

        # Deduplicate overlapping zones - keep highest scoring
        if len(zones) > 1:
            zones.sort(key=lambda z: z['score'], reverse=True)
            filtered: List[Dict[str, Any]] = [zones[0]]
            for zone in zones[1:]:
                overlaps = any(
                    zone['bottom'] <= existing['top']
                    and zone['top'] >= existing['bottom']
                    for existing in filtered
                )
                if not overlaps:
                    filtered.append(zone)
            zones = filtered

        return zones

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
            rr_ratio=setup.get('rr', self.min_rr_ratio)
        )
