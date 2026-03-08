"""Reinforcement Learning Trading Environment."""

import logging
from typing import Optional, Dict, Any, Tuple
import numpy as np

logger = logging.getLogger(__name__)

try:
    import gymnasium as gym
    from gymnasium import spaces
    HAS_GYM = True
except ImportError:
    HAS_GYM = False

    # Create stub classes so file can be imported
    class spaces:
        @staticmethod
        def Box(*args, **kwargs):
            return None

        @staticmethod
        def Discrete(*args, **kwargs):
            return None


class TradingEnvironment:
    """
    Trading environment for RL agent training.

    State: [price_features(20), account_state(5), position_state(3)] = 28 dimensions
    Actions: {0: Hold, 1: Buy, 2: Sell, 3: Close}
    Reward: Risk-adjusted return (R-multiple of trades)
    """

    def __init__(self, price_data: np.ndarray, config: Dict[str, Any] = None):
        """
        Args:
            price_data: OHLCV array of shape (n_bars, 5) [open, high, low, close, volume]
            config: RL configuration parameters
        """
        self.price_data = price_data
        self.config = config or {}

        self.state_window = self.config.get('state_window', 20)
        self.initial_balance = self.config.get('initial_balance', 10000.0)
        self.contract_size = self.config.get('contract_size', 100)
        self.risk_percent = self.config.get('risk_percent', 1.0)
        self.sl_atr_multiple = self.config.get('sl_atr_multiple', 2.0)
        self.tp_atr_multiple = self.config.get('tp_atr_multiple', 4.0)
        self.max_position_duration = self.config.get('max_position_duration_bars', 300)

        # State dimensions
        self.price_features_dim = 20
        self.account_features_dim = 5
        self.position_features_dim = 3
        self.state_dim = self.price_features_dim + self.account_features_dim + self.position_features_dim

        # Internal state
        self.current_step = 0
        self.balance = self.initial_balance
        self.position = None  # None or dict with entry info
        self.trades = []
        self.done = False

    def reset(self) -> np.ndarray:
        """Reset environment to initial state."""
        self.current_step = self.state_window
        self.balance = self.initial_balance
        self.position = None
        self.trades = []
        self.done = False
        return self._get_state()

    def step(self, action: int) -> Tuple[np.ndarray, float, bool, Dict]:
        """
        Execute action and return (state, reward, done, info).

        Actions: 0=Hold, 1=Buy, 2=Sell, 3=Close
        """
        reward = 0.0
        info = {}

        if self.done:
            return self._get_state(), 0.0, True, info

        current_bar = self.price_data[self.current_step]
        current_price = current_bar[3]  # close

        if action == 1 and self.position is None:  # Buy
            atr = self._calculate_atr()
            sl = current_price - atr * self.sl_atr_multiple
            tp = current_price + atr * self.tp_atr_multiple
            sl_distance = abs(current_price - sl)
            risk_amount = self.balance * self.risk_percent / 100
            lot_size = risk_amount / (sl_distance * self.contract_size) if sl_distance > 0 else 0.01
            lot_size = max(0.01, min(lot_size, 10.0))

            self.position = {
                'direction': 'BUY',
                'entry_price': current_price,
                'entry_step': self.current_step,
                'stop_loss': sl,
                'take_profit': tp,
                'lot_size': lot_size,
                'initial_risk': sl_distance * lot_size * self.contract_size,
            }
            reward = -0.001  # Small cost for entering

        elif action == 2 and self.position is None:  # Sell
            atr = self._calculate_atr()
            sl = current_price + atr * self.sl_atr_multiple
            tp = current_price - atr * self.tp_atr_multiple
            sl_distance = abs(sl - current_price)
            risk_amount = self.balance * self.risk_percent / 100
            lot_size = risk_amount / (sl_distance * self.contract_size) if sl_distance > 0 else 0.01
            lot_size = max(0.01, min(lot_size, 10.0))

            self.position = {
                'direction': 'SELL',
                'entry_price': current_price,
                'entry_step': self.current_step,
                'stop_loss': sl,
                'take_profit': tp,
                'lot_size': lot_size,
                'initial_risk': sl_distance * lot_size * self.contract_size,
            }
            reward = -0.001

        elif action == 3 and self.position is not None:  # Close
            reward = self._close_position(current_price)

        elif self.position is not None:  # Hold with position
            reward = -0.0005  # Small holding penalty

            # Check SL/TP
            bar_high = current_bar[1]
            bar_low = current_bar[2]

            if self.position['direction'] == 'BUY':
                if bar_low <= self.position['stop_loss']:
                    reward = self._close_position(self.position['stop_loss'])
                elif bar_high >= self.position['take_profit']:
                    reward = self._close_position(self.position['take_profit'])
            else:
                if bar_high >= self.position['stop_loss']:
                    reward = self._close_position(self.position['stop_loss'])
                elif bar_low <= self.position['take_profit']:
                    reward = self._close_position(self.position['take_profit'])

            # Check max duration
            if self.position is not None:
                duration = self.current_step - self.position['entry_step']
                if duration >= self.max_position_duration:
                    reward = self._close_position(current_price)

        # Advance step
        self.current_step += 1
        if self.current_step >= len(self.price_data) - 1:
            if self.position is not None:
                reward = self._close_position(current_price)
            self.done = True

        # Bankruptcy check
        if self.balance <= self.initial_balance * 0.1:
            self.done = True
            reward = -10.0  # Large penalty for blowing account

        return self._get_state(), reward, self.done, info

    def _close_position(self, exit_price: float) -> float:
        """Close position and return reward (R-multiple)."""
        if self.position is None:
            return 0.0

        pos = self.position
        if pos['direction'] == 'BUY':
            pnl = (exit_price - pos['entry_price']) * pos['lot_size'] * self.contract_size
        else:
            pnl = (pos['entry_price'] - exit_price) * pos['lot_size'] * self.contract_size

        self.balance += pnl

        # R-multiple reward
        initial_risk = pos['initial_risk']
        r_multiple = pnl / initial_risk if initial_risk > 0 else 0

        self.trades.append({
            'direction': pos['direction'],
            'entry_price': pos['entry_price'],
            'exit_price': exit_price,
            'pnl': pnl,
            'r_multiple': r_multiple,
        })

        self.position = None
        return float(np.clip(r_multiple, -5, 5))  # Clip extreme rewards

    def _get_state(self) -> np.ndarray:
        """Build state vector [price_features, account_state, position_state]."""
        state = np.zeros(self.state_dim, dtype=np.float32)

        if self.current_step >= len(self.price_data):
            return state

        # Price features (20 normalized features from recent bars)
        window = self.price_data[max(0, self.current_step - self.state_window):self.current_step + 1]
        if len(window) > 1:
            closes = window[:, 3]
            current_price = closes[-1]
            atr = self._calculate_atr()
            if atr <= 0:
                atr = 1.0

            # Normalized returns (last 5 bars)
            returns = np.diff(closes[-6:]) / closes[-6:-1] if len(closes) >= 6 else np.zeros(5)
            state[0:5] = returns[:5]

            # Price relative to moving averages
            if len(closes) >= 10:
                sma_10 = np.mean(closes[-10:])
                state[5] = (current_price - sma_10) / atr
            if len(closes) >= 20:
                sma_20 = np.mean(closes[-20:])
                state[6] = (current_price - sma_20) / atr

            # Volatility features
            if len(closes) >= 10:
                state[7] = np.std(closes[-10:]) / atr  # Recent volatility

            # OHLC features of last bar
            bar = window[-1]
            body = abs(bar[3] - bar[0]) / atr  # Body size
            upper_wick = (bar[1] - max(bar[0], bar[3])) / atr
            lower_wick = (min(bar[0], bar[3]) - bar[2]) / atr
            state[8] = body
            state[9] = upper_wick
            state[10] = lower_wick
            state[11] = 1.0 if bar[3] > bar[0] else -1.0  # Candle direction

            # High/Low range
            if len(window) >= 10:
                high_10 = np.max(window[-10:, 1])
                low_10 = np.min(window[-10:, 2])
                state[12] = (current_price - low_10) / (high_10 - low_10) if high_10 > low_10 else 0.5

            # Volume features (if available)
            if window.shape[1] > 4:
                volumes = window[:, 4]
                if len(volumes) >= 10 and np.mean(volumes[-10:]) > 0:
                    state[13] = volumes[-1] / np.mean(volumes[-10:])

            # RSI-like momentum
            if len(closes) >= 14:
                deltas = np.diff(closes[-15:])
                gains = np.mean(deltas[deltas > 0]) if np.any(deltas > 0) else 0
                losses = np.mean(np.abs(deltas[deltas < 0])) if np.any(deltas < 0) else 0
                rs = gains / losses if losses > 0 else 100
                state[14] = 2 * (100 - 100 / (1 + rs)) / 100 - 1  # Normalize to [-1, 1]

            # ATR ratio (current vs average)
            state[15] = atr / current_price * 1000  # Normalized ATR

            # Trend features
            if len(closes) >= 20:
                state[16] = (closes[-1] - closes[-5]) / atr  # 5-bar momentum
                state[17] = (closes[-1] - closes[-10]) / atr  # 10-bar momentum
                state[18] = (closes[-1] - closes[-20]) / atr  # 20-bar momentum

            state[19] = 0  # Reserved

        # Account state (5 features)
        state[20] = self.balance / self.initial_balance - 1  # Return
        state[21] = len(self.trades) / 100  # Normalized trade count
        win_trades = [t for t in self.trades if t['pnl'] > 0]
        state[22] = len(win_trades) / max(1, len(self.trades))  # Win rate
        state[23] = self.trades[-1]['r_multiple'] if self.trades else 0  # Last R-multiple
        state[24] = 0  # Reserved

        # Position state (3 features)
        if self.position is not None:
            current_price = self.price_data[min(self.current_step, len(self.price_data) - 1)][3]
            pos = self.position
            if pos['direction'] == 'BUY':
                unrealized = (current_price - pos['entry_price']) * pos['lot_size'] * self.contract_size
            else:
                unrealized = (pos['entry_price'] - current_price) * pos['lot_size'] * self.contract_size

            state[25] = 1.0 if pos['direction'] == 'BUY' else -1.0
            state[26] = unrealized / pos['initial_risk'] if pos['initial_risk'] > 0 else 0  # Unrealized R
            state[27] = (self.current_step - pos['entry_step']) / self.max_position_duration  # Duration ratio

        return state

    def _calculate_atr(self, period: int = 14) -> float:
        """Calculate ATR from price data."""
        end = min(self.current_step + 1, len(self.price_data))
        start = max(0, end - period - 1)
        window = self.price_data[start:end]

        if len(window) < 2:
            return 1.0

        trs = []
        for i in range(1, len(window)):
            high = window[i][1]
            low = window[i][2]
            prev_close = window[i - 1][3]
            tr = max(high - low, abs(high - prev_close), abs(low - prev_close))
            trs.append(tr)

        return np.mean(trs) if trs else 1.0
