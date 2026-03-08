# ProTradingSystem v2 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Transform the trading system into v2 with reliable backtesting, a pluggable strategy architecture supporting 7+ strategies, and a multi-model ML pipeline (XGBoost, LightGBM, LSTM, 1D-CNN, Ensemble).

**Architecture:** Three-phase approach: (1) Fix critical backtest engine bugs to ensure reliable P&L, (2) Refactor the engine to use a pluggable strategy pattern so new strategies don't require engine modifications, (3) Add new strategies and ML models on top of the clean architecture.

**Tech Stack:** Python 3.10+, XGBoost, LightGBM, PyTorch (LSTM/CNN), scikit-learn, Optuna, SHAP, Flask/Jinja2 frontend, FastAPI backend, SQLite.

---

## Phase 1: Backtest Engine Reliability Fixes

> These bugs MUST be fixed before any new development. Current backtest results are unreliable due to cost tracking errors and metric calculation issues.

---

### Task 1: Fix Spread/Slippage Double-Counting in P&L

The backtest engine applies spread and slippage to entry/exit prices (making them worse), which means gross_pnl already reflects these costs. But the code also calculates spread_cost_usd and slippage_cost_usd separately. Currently, net_pnl only subtracts commission and swap -- the spread/slippage are "double-tracked" but since they're already in the price, they should NOT be subtracted again. The real bug is that the TradeRecord reports spread_cost and slippage_cost as separate line items even though they're already baked into gross_pnl. This is a reporting/accounting clarity issue.

**Files:**
- Modify: `dashboard/backend/core/backtest_engine.py` (lines ~1270-1290)

**Step 1: Verify current behavior by reading the close_position method**

Read `backtest_engine.py` lines 1240-1300. Trace the math:
- `exit_price` is modified by spread (line ~1252)
- `gross_pnl` uses this modified `exit_price` (line ~1261)
- `spread_cost_usd` and `slippage_cost_usd` calculated (line ~1276)
- `net_pnl = gross_pnl - exit_commission - pos.swap_cost` (line ~1282)

Confirm: spread/slippage are already embedded in gross_pnl via modified prices. The separate cost fields are for reporting only, NOT for deduction. If this is correct, the current net_pnl formula is RIGHT. Document this clearly in code comments.

**Step 2: Add clarifying comments to the P&L calculation**

```python
# Gross P&L already includes spread + slippage costs because
# entry_price and exit_price were adjusted at execution time.
# spread_cost_usd and slippage_cost_usd are tracked for REPORTING only.
# Only commission and swap are separate additive costs.
net_pnl = gross_pnl - exit_commission - pos.swap_cost
```

**Step 3: Verify gross_pnl vs net_pnl accounting is consistent**

Add an assertion or debug log to validate:
```python
# Sanity check: gross_pnl should already reflect spread+slippage
# net_pnl = gross_pnl - commission - swap
expected_net = gross_pnl - exit_commission - pos.swap_cost
assert abs(net_pnl - expected_net) < 0.001, f"P&L mismatch: {net_pnl} vs {expected_net}"
```

**Step 4: Commit**
```
git add dashboard/backend/core/backtest_engine.py
git commit -m "fix: clarify P&L calculation - spread/slippage already in gross_pnl"
```

---

### Task 2: Fix Exit Commission Not Applied to Balance

Entry commission is deducted from balance immediately at `_execute_trade()`, but exit commission is only subtracted in the net_pnl formula during `_close_position()`. The balance update at close uses `net_pnl` which includes exit commission, so balance IS correct. But the accounting flow is inconsistent and confusing.

**Files:**
- Modify: `dashboard/backend/core/backtest_engine.py`

**Step 1: Read and trace the commission flow**

Trace in `_execute_trade()`:
```python
entry_commission = (self.config.commission_per_lot * lot_size) / 2
self.balance -= entry_commission  # Deducted immediately
```

Trace in `_close_position()`:
```python
exit_commission = (self.config.commission_per_lot * pos.lot_size) / 2
net_pnl = gross_pnl - exit_commission - pos.swap_cost
self.balance += net_pnl  # Exit commission is subtracted inside net_pnl
```

Verify: `balance_after = balance_before - entry_commission + net_pnl`
= `balance_before - entry_commission + gross_pnl - exit_commission - swap`

This IS correct mathematically. The issue is ONLY clarity, not a bug.

**Step 2: Add comments documenting the commission flow**

In `_execute_trade()`:
```python
# Entry commission: deducted from balance immediately
# Exit commission: deducted at close via net_pnl calculation
entry_commission = (self.config.commission_per_lot * lot_size) / 2
self.balance -= entry_commission
```

In `_close_position()`:
```python
# Exit commission deducted here (entry commission was deducted at open)
exit_commission = (self.config.commission_per_lot * pos.lot_size) / 2
# Total commission for this trade = entry + exit
total_commission = pos.commission_cost + exit_commission
```

**Step 3: Commit**

---

### Task 3: Fix Sharpe and Sortino Ratios to Use Daily Returns

Current implementation calculates Sharpe/Sortino from per-trade returns, which have irregular time intervals. Standard practice uses daily returns from the equity curve.

**Files:**
- Modify: `dashboard/backend/core/metrics_calculator.py`

**Step 1: Read current Sharpe implementation (lines ~306-327)**

Current code:
```python
returns = [(trade.profit_loss / trade.balance_before) * 100 for trade in trades]
mean_return = np.mean(returns)
std_return = np.std(returns, ddof=1)
sharpe = (mean_return - daily_rf) / std_return
return sharpe * np.sqrt(252)
```

Problem: These are trade returns (irregular intervals), annualized as if daily.

**Step 2: Refactor to use daily equity returns**

Replace the Sharpe calculation to use the equity curve:

```python
def _calculate_sharpe_ratio(self, trades: List[TradeRecord]) -> float:
    """Calculate annualized Sharpe ratio from daily equity returns."""
    if len(trades) < 2:
        return 0.0

    # Build daily equity from trades
    daily_equity = self._build_daily_equity(trades)
    if len(daily_equity) < 5:
        return 0.0

    # Calculate daily returns
    returns = np.diff(daily_equity) / daily_equity[:-1]

    mean_return = np.mean(returns)
    std_return = np.std(returns, ddof=1)

    if std_return == 0:
        return 0.0

    daily_rf = self.risk_free_rate / 252
    sharpe = (mean_return - daily_rf) / std_return
    return round(sharpe * np.sqrt(252), 4)

def _build_daily_equity(self, trades: List[TradeRecord]) -> np.ndarray:
    """Build daily equity curve from trade records."""
    if not trades:
        return np.array([self.initial_balance])

    # Group P&L by date
    daily_pnl = {}
    for trade in trades:
        if trade.exit_time:
            date_key = trade.exit_time.date()
            daily_pnl[date_key] = daily_pnl.get(date_key, 0) + trade.profit_loss

    if not daily_pnl:
        return np.array([self.initial_balance])

    # Build cumulative equity
    sorted_dates = sorted(daily_pnl.keys())
    equity = [self.initial_balance]
    for date in sorted_dates:
        equity.append(equity[-1] + daily_pnl[date])

    return np.array(equity)
```

**Step 3: Apply same fix to Sortino ratio**

```python
def _calculate_sortino_ratio(self, trades: List[TradeRecord]) -> float:
    """Calculate annualized Sortino ratio from daily equity returns."""
    if len(trades) < 2:
        return 0.0

    daily_equity = self._build_daily_equity(trades)
    if len(daily_equity) < 5:
        return 0.0

    returns = np.diff(daily_equity) / daily_equity[:-1]
    mean_return = np.mean(returns)

    # Downside deviation: only negative returns
    negative_returns = returns[returns < 0]
    if len(negative_returns) == 0:
        return 0.0

    downside_std = np.std(negative_returns, ddof=1)
    if downside_std == 0:
        return 0.0

    daily_rf = self.risk_free_rate / 252
    sortino = (mean_return - daily_rf) / downside_std
    return round(sortino * np.sqrt(252), 4)
```

**Step 4: Commit**
```
git add dashboard/backend/core/metrics_calculator.py
git commit -m "fix: Sharpe/Sortino use daily equity returns instead of per-trade returns"
```

---

### Task 4: Add Minimum Lot Size Validation

No check that calculated lot size meets broker minimum (typically 0.01 lots for Gold).

**Files:**
- Modify: `dashboard/backend/core/backtest_engine.py` (`_execute_trade` method)

**Step 1: Add lot size validation after position sizing**

After the lot_size calculation:
```python
lot_size = risk_amount / (sl_distance * self.config.contract_size)

# Enforce minimum lot size (broker limit)
min_lot = 0.01
if lot_size < min_lot:
    logger.debug(f"Trade skipped: lot size {lot_size:.4f} below minimum {min_lot}")
    return
# Round to 2 decimal places (broker standard)
lot_size = round(lot_size, 2)
```

**Step 2: Commit**

---

### Task 5: Improve SL/TP Same-Bar Resolution

When both SL and TP are hit within the same bar, use a probabilistic approach rather than always favoring the closer level.

**Files:**
- Modify: `dashboard/backend/core/backtest_engine.py` (`_manage_position` method)

**Step 1: Read current same-bar logic (lines ~1117-1145)**

Current: Uses distance from open to determine which hit first.

**Step 2: Add randomized resolution for ambiguous cases**

When distances are close (within 30% of each other), randomize:
```python
if sl_hit and tp_hit:
    if is_long:
        dist_to_sl = open_price - pos.stop_loss
        dist_to_tp = pos.take_profit - open_price
    else:
        dist_to_sl = pos.stop_loss - open_price
        dist_to_tp = open_price - pos.take_profit

    # If distances are within 30%, it's genuinely ambiguous
    ratio = min(dist_to_sl, dist_to_tp) / max(dist_to_sl, dist_to_tp) if max(dist_to_sl, dist_to_tp) > 0 else 1
    if ratio > 0.7:
        # Ambiguous: assume SL hit first (conservative)
        tp_hit = False
    elif dist_to_tp < dist_to_sl:
        sl_hit = False  # TP was closer, it hit first
    else:
        tp_hit = False  # SL was closer, it hit first
```

**Step 3: Commit**

---

## Phase 2: Strategy Abstraction Refactoring

> Extract strategy logic from the monolithic backtest engine into pluggable strategy classes. This enables adding new strategies without modifying the engine.

---

### Task 6: Create BacktestStrategy Abstract Base Class

**Files:**
- Create: `dashboard/backend/core/strategies/__init__.py`
- Create: `dashboard/backend/core/strategies/base.py`

**Step 1: Create the strategy interface**

```python
"""
Abstract base class for all backtesting strategies.
Strategies implement signal detection logic; the BacktestEngine handles
position management, cost simulation, and metrics.
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import datetime
from typing import Optional, Dict, Any, List, Tuple
import pandas as pd


@dataclass
class DayContext:
    """Context for a trading day, populated by the strategy."""
    date: datetime
    bias: str = "neutral"           # "bullish", "bearish", "neutral"
    bias_strength: int = 0          # 0-100
    atr: float = 0.0
    # Session levels (strategy populates what it needs)
    levels: Dict[str, float] = None  # e.g., {"orb_high": 2050, "asian_low": 2040}

    def __post_init__(self):
        if self.levels is None:
            self.levels = {}


@dataclass
class TradeSetup:
    """A proposed trade setup from the strategy."""
    direction: str                  # "BUY" or "SELL"
    entry_price: float              # Suggested entry (bar open)
    stop_loss: float                # Stop loss price
    take_profit: float              # Take profit price
    setup_type: str                 # Description e.g., "Bullish FVG + ORB Breakout"
    confidence: float = 0.0        # 0-100, strategy's confidence in this setup
    metadata: Dict[str, Any] = None  # Strategy-specific data (FVG size, OB levels, etc.)

    def __post_init__(self):
        if self.metadata is None:
            self.metadata = {}


class BacktestStrategy(ABC):
    """
    Abstract base class for backtesting strategies.

    Subclasses implement:
    - initialize_day(): Set up daily context (bias, levels, indicators)
    - find_setup(): Detect trade setups at each bar
    - should_close_early(): Custom exit logic beyond SL/TP (optional)

    The BacktestEngine handles:
    - Position management (open, close, trailing)
    - Cost simulation (spread, slippage, commission, swap)
    - Metrics calculation
    - Data fetching
    """

    def __init__(self, config: Dict[str, Any]):
        """
        Args:
            config: Strategy parameters merged from
                    optimal_parameters + preset overrides + user overrides
        """
        self.config = config

    @abstractmethod
    def initialize_day(
        self,
        date: datetime,
        daily_df: Optional[pd.DataFrame],
        intraday_df: pd.DataFrame,
    ) -> DayContext:
        """
        Called once per trading day before bar processing.
        Calculate bias, session levels, daily indicators.

        Args:
            date: Current trading date
            daily_df: Daily OHLCV data (for trend analysis, can be None)
            intraday_df: All intraday data up to this date

        Returns:
            DayContext with bias, strength, levels, etc.
        """
        pass

    @abstractmethod
    def find_setup(
        self,
        bar: pd.Series,
        df: pd.DataFrame,
        day_context: DayContext,
        current_bar_index: int,
    ) -> Optional[TradeSetup]:
        """
        Called for each bar during the trading window.
        Detect whether current conditions form a valid trade setup.

        Args:
            bar: Current bar (open, high, low, close, volume)
            df: All bars up to and including current bar
            day_context: Today's context from initialize_day()
            current_bar_index: Index of current bar in df

        Returns:
            TradeSetup if a valid setup is found, None otherwise
        """
        pass

    def should_close_early(
        self,
        bar: pd.Series,
        position: Any,
        day_context: DayContext,
    ) -> Optional[str]:
        """
        Optional: Custom exit logic beyond SL/TP/trailing.
        Called every bar while a position is open.

        Returns:
            Exit reason string if should close, None to keep open.
        """
        return None

    def get_required_lookback_bars(self) -> int:
        """How many bars of history this strategy needs before it can trade."""
        return 100

    def get_required_daily_lookback_days(self) -> int:
        """How many days of daily data this strategy needs."""
        return 30
```

**Step 2: Commit**

---

### Task 7: Extract ORB Logic Into ORBBacktestStrategy

Extract the ICT/ORB-specific logic from `backtest_engine.py` into a concrete strategy class.

**Files:**
- Create: `dashboard/backend/core/strategies/orb_strategy.py`
- Modify: `dashboard/backend/core/backtest_engine.py` (delegate to strategy)

**Step 1: Create ORBBacktestStrategy**

Extract these methods from backtest_engine.py into the new class:
- `_calculate_bias()` -> `initialize_day()`
- `_find_trade_setup()` -> `find_setup()`
- `_find_fvg()` -> internal helper
- `_find_order_block()` -> internal helper
- `_has_displacement()` -> internal helper

The strategy receives all ICT parameters via `self.config` dict.

Key structure:
```python
class ORBBacktestStrategy(BacktestStrategy):
    """ORB Strategy with ICT concepts (FVG, Order Blocks, Displacement)."""

    def initialize_day(self, date, daily_df, intraday_df) -> DayContext:
        # Calculate Asian session levels
        # Calculate London session levels
        # Calculate Previous Day levels
        # Calculate ORB levels
        # Calculate bias and strength (0-100)
        # Calculate ATR
        ctx = DayContext(date=date, bias=bias, bias_strength=strength, atr=atr)
        ctx.levels = {
            "orb_high": orb_high, "orb_low": orb_low,
            "asian_high": asian_high, "asian_low": asian_low,
            "pd_high": pd_high, "pd_low": pd_low,
            "london_high": london_high, "london_low": london_low,
        }
        return ctx

    def find_setup(self, bar, df, day_context, current_bar_index) -> Optional[TradeSetup]:
        # Check if in trading window
        # Check bias strength >= minimum
        # Find FVG
        # Find Order Block (optional confirmation)
        # Calculate SL/TP
        # Return TradeSetup or None
```

**Step 2: Modify BacktestEngine to accept a strategy**

Add strategy parameter to engine:
```python
class BacktestEngine:
    def __init__(self, config: BacktestConfig, strategy: BacktestStrategy = None):
        self.strategy = strategy
        # If no strategy provided, use legacy embedded logic
        if self.strategy is None:
            from .strategies.orb_strategy import ORBBacktestStrategy
            self.strategy = ORBBacktestStrategy(config.__dict__)
```

Update the main loop to delegate to strategy:
```python
# In _process_trading_day():
day_context = self.strategy.initialize_day(date, daily_df, df)

# In the bar loop:
setup = self.strategy.find_setup(bar, df_up_to_bar, day_context, i)
if setup:
    self._execute_trade_from_setup(setup, bar)
```

**Step 3: Ensure backward compatibility**

All existing ORB/Advanced ORB strategies must continue working identically. Run existing backtests and compare results before/after refactoring.

**Step 4: Commit**

---

### Task 8: Create AdvancedORBBacktestStrategy

**Files:**
- Create: `dashboard/backend/core/strategies/advanced_orb_strategy.py`

Inherits from `ORBBacktestStrategy` and overrides with stricter filters (higher bias_min_strength, tighter kill zone, stricter FVG validation). All differences come from config parameters, so this may simply be the same class with different optimal_parameters.

**Step 1: Assess if separate class is needed**

If ORB and Advanced ORB differ ONLY in parameter values, no new class needed -- just different registry entries with different optimal_parameters.

If they differ in LOGIC (e.g., Advanced ORB has additional validation steps), create:
```python
class AdvancedORBBacktestStrategy(ORBBacktestStrategy):
    def find_setup(self, bar, df, day_context, current_bar_index):
        setup = super().find_setup(bar, df, day_context, current_bar_index)
        if setup is None:
            return None
        # Additional validation
        if not self._validate_multi_session_confluence(setup, day_context):
            return None
        return setup
```

**Step 2: Commit**

---

### Task 9: Create Strategy Factory

**Files:**
- Create: `dashboard/backend/core/strategies/factory.py`

```python
"""Factory for creating backtest strategy instances from strategy_id."""

from typing import Dict, Type
from .base import BacktestStrategy
from .orb_strategy import ORBBacktestStrategy

# Registry of strategy_id -> strategy class
STRATEGY_CLASSES: Dict[str, Type[BacktestStrategy]] = {
    "orb_strategy": ORBBacktestStrategy,
    "advanced_orb_strategy": ORBBacktestStrategy,  # Same class, different params
    # New strategies will be added here
}

def create_strategy(strategy_id: str, config: dict) -> BacktestStrategy:
    """Create a strategy instance from registry."""
    cls = STRATEGY_CLASSES.get(strategy_id)
    if cls is None:
        raise ValueError(f"Unknown strategy: {strategy_id}. "
                        f"Available: {list(STRATEGY_CLASSES.keys())}")
    return cls(config)
```

Update `backtest_service.py` to use factory:
```python
from ..core.strategies.factory import create_strategy

strategy = create_strategy(strategy_id, config_dict)
engine = BacktestEngine(config, strategy=strategy)
```

**Step 1: Implement factory**
**Step 2: Update backtest_service.py**
**Step 3: Test with existing ORB strategy**
**Step 4: Commit**

---

## Phase 3: New Trading Strategies

> Each strategy follows the BacktestStrategy interface. Register in factory + strategy_registry.py.

---

### Task 10: MACD + EMA Trend Strategy

**Core Logic:** Trade in the direction of the trend (EMA alignment) when MACD confirms momentum shift.

**Files:**
- Create: `dashboard/backend/core/strategies/macd_ema_strategy.py`
- Modify: `dashboard/backend/core/strategies/factory.py` (register)
- Modify: `dashboard/backend/core/strategy_registry.py` (define params)

**Entry Rules:**
1. **Trend Filter**: EMA 9 > EMA 21 > EMA 50 (bullish) or EMA 9 < EMA 21 < EMA 50 (bearish)
2. **MACD Signal**: MACD line crosses above signal line (bullish) or below (bearish)
3. **MACD Histogram**: Must be increasing in direction of trade
4. **Entry**: At next bar open after crossover
5. **Stop Loss**: Below EMA 50 (bullish) or above EMA 50 (bearish), clamped to config min/max SL
6. **Take Profit**: 2.5x risk distance (configurable R:R)

**Exit Rules:**
- SL/TP hit
- EMA 9 crosses below EMA 21 (opposing cross = trend weakening)
- MACD histogram turns against position for 3 consecutive bars

**Implementation:**
```python
class MACDEMAStrategy(BacktestStrategy):
    def initialize_day(self, date, daily_df, intraday_df):
        # Calculate EMAs (9, 21, 50) on intraday data
        # Calculate MACD (12, 26, 9)
        # Determine trend direction from EMA alignment
        # Store in day_context.levels

    def find_setup(self, bar, df, day_context, idx):
        # Check EMA alignment (all 3 EMAs in order)
        # Check MACD crossover happened at current or previous bar
        # Check histogram is growing
        # Calculate SL below/above EMA 50
        # Calculate TP at configured R:R
        # Return TradeSetup

    def should_close_early(self, bar, position, day_context):
        # Check if EMA 9 crossed against position
        # Check if MACD histogram turned for 3 bars
```

**Parameters for strategy_registry.py:**
```python
optimal_parameters={
    "ema_fast": 9,
    "ema_mid": 21,
    "ema_slow": 50,
    "macd_fast": 12,
    "macd_slow": 26,
    "macd_signal": 9,
    "min_ema_separation_atr": 0.1,  # Minimum gap between EMAs
    "histogram_confirmation_bars": 2,
    "exit_histogram_reversal_bars": 3,
}
```

---

### Task 11: Ichimoku Retracement Strategy

**Core Logic:** Trade pullbacks to the Kijun-sen (base line) within an established Ichimoku cloud trend.

**Files:**
- Create: `dashboard/backend/core/strategies/ichimoku_strategy.py`
- Modify: `dashboard/backend/core/strategies/factory.py`
- Modify: `dashboard/backend/core/strategy_registry.py`

**Entry Rules:**
1. **Cloud Trend**: Price above cloud (bullish) or below cloud (bearish)
2. **Cloud Color**: Senkou Span A > Senkou Span B (bullish cloud color)
3. **Pullback**: Price retraces to Kijun-sen (26-period base line)
4. **Confirmation**: Tenkan-sen (9-period) still above Kijun-sen (bullish)
5. **Chikou Span**: Must be above price from 26 periods ago (bullish)
6. **Entry**: When price bounces off Kijun-sen (close > Kijun after touching it)
7. **Stop Loss**: Below the cloud bottom (Senkou Span B for bullish trades)
8. **Take Profit**: Previous swing high or 2x Kijun-to-cloud distance

**Ichimoku Calculations:**
```python
def _calculate_ichimoku(self, df):
    # Tenkan-sen (Conversion Line): (9-period high + 9-period low) / 2
    high_9 = df['high'].rolling(9).max()
    low_9 = df['low'].rolling(9).min()
    tenkan = (high_9 + low_9) / 2

    # Kijun-sen (Base Line): (26-period high + 26-period low) / 2
    high_26 = df['high'].rolling(26).max()
    low_26 = df['low'].rolling(26).min()
    kijun = (high_26 + low_26) / 2

    # Senkou Span A (Leading Span A): (Tenkan + Kijun) / 2, shifted 26 periods ahead
    senkou_a = ((tenkan + kijun) / 2).shift(26)

    # Senkou Span B (Leading Span B): (52-period high + 52-period low) / 2, shifted 26
    high_52 = df['high'].rolling(52).max()
    low_52 = df['low'].rolling(52).min()
    senkou_b = ((high_52 + low_52) / 2).shift(26)

    # Chikou Span (Lagging Span): Close shifted back 26 periods
    chikou = df['close'].shift(-26)

    return tenkan, kijun, senkou_a, senkou_b, chikou
```

**Parameters:**
```python
optimal_parameters={
    "tenkan_period": 9,
    "kijun_period": 26,
    "senkou_b_period": 52,
    "cloud_displacement": 26,
    "kijun_touch_tolerance_atr": 0.3,  # How close price must get to Kijun
    "require_chikou_confirmation": True,
    "require_cloud_color": True,
}
```

---

### Task 12: Basso Strategy (Mean Reversion)

**Core Logic:** Tom Basso's approach: trade mean reversion when price extends too far from its moving average, combined with volatility-adjusted position sizing.

**Files:**
- Create: `dashboard/backend/core/strategies/basso_strategy.py`
- Modify: factory + registry

**Entry Rules:**
1. **Overextension**: Price > 2 ATR from 20-period SMA (short) or < 2 ATR from 20-period SMA (long)
2. **RSI Confirmation**: RSI(14) > 70 (short) or RSI(14) < 30 (long)
3. **Reversion Signal**: First candle that closes back toward the mean (reversal candle)
4. **Volume**: Volume above 20-period average (optional)
5. **Stop Loss**: Beyond the extreme (overextension peak + 0.5 ATR buffer)
6. **Take Profit**: At the 20-period SMA (the mean)

**Volatility-Adjusted Sizing (Basso's Key Innovation):**
```python
# Position size inversely proportional to volatility
# Higher ATR = smaller position, Lower ATR = larger position
target_dollar_risk = balance * risk_percent / 100
volatility_factor = atr_20 / avg_atr_60  # Current vs average volatility
adjusted_risk = target_dollar_risk / max(volatility_factor, 0.5)
lot_size = adjusted_risk / (sl_distance * contract_size)
```

**Parameters:**
```python
optimal_parameters={
    "sma_period": 20,
    "atr_period": 14,
    "overextension_atr_multiple": 2.0,
    "rsi_period": 14,
    "rsi_overbought": 70,
    "rsi_oversold": 30,
    "volatility_normalization_period": 60,
    "use_volume_filter": False,
}
```

---

### Task 13: Session Liquidity Sweep Reversal Strategy (Custom Pro #1)

**Core Logic (My Design):** Gold consistently sweeps retail stop-losses at obvious session levels (Asian high/low), then reverses. This strategy exploits that institutional behavior.

**Files:**
- Create: `dashboard/backend/core/strategies/liquidity_sweep_strategy.py`
- Modify: factory + registry

**Why This Works for Gold:**
- Institutional traders hunt retail stops placed at Asian session highs/lows
- After the sweep, smart money enters in the opposite direction
- Gold's strong session-based behavior makes this highly repeatable
- Best during NY session (9:30-12:00) when London overlap provides liquidity

**Entry Rules:**
1. **Identify Liquidity Level**: Asian session high/low, Previous Day high/low, or round number ($XX00, $XX50)
2. **Detect Sweep**: Price breaks above the level by at least 0.3 ATR (wicks through)
3. **Rejection**: Within 3 bars of the sweep, price must close back below the level (for short setups)
4. **Displacement**: The rejection candle must have a body > 60th percentile of recent bars
5. **FVG Formation**: A FVG forms in the reversal direction after the sweep
6. **Entry**: On FVG retest or at the swept level (whichever comes first)
7. **Stop Loss**: Above the sweep wick high + 0.3 ATR buffer
8. **Take Profit**: Opposite session level or 3:1 R:R minimum

**Implementation:**
```python
class LiquiditySweepStrategy(BacktestStrategy):
    def initialize_day(self, date, daily_df, intraday_df):
        # Calculate Asian session high/low
        # Calculate Previous Day high/low
        # Identify round numbers near current price
        # Build list of "liquidity levels" to watch
        ctx.levels = {
            "liquidity_targets": [
                {"level": asian_high, "type": "asian_high", "direction": "short"},
                {"level": asian_low, "type": "asian_low", "direction": "long"},
                {"level": pd_high, "type": "pd_high", "direction": "short"},
                {"level": pd_low, "type": "pd_low", "direction": "long"},
            ]
        }

    def find_setup(self, bar, df, day_context, idx):
        # For each liquidity level:
        #   1. Check if sweep occurred (price exceeded level then reversed)
        #   2. Verify rejection candle within 3 bars
        #   3. Check displacement quality
        #   4. Look for FVG in reversal direction
        #   5. Calculate SL above sweep wick + buffer
        #   6. Calculate TP at opposite level or 3:1 R:R
```

**Parameters:**
```python
optimal_parameters={
    "sweep_min_penetration_atr": 0.3,
    "sweep_max_bars_to_reject": 3,
    "rejection_body_percentile": 60,
    "require_fvg_after_sweep": True,
    "fvg_min_gap": 0.15,
    "sl_buffer_atr": 0.3,
    "min_rr_ratio": 3.0,
    "use_round_numbers": True,
    "round_number_interval": 50,  # $50 intervals ($2000, $2050, etc.)
}
```

---

### Task 14: Multi-Timeframe Confluence Zone Strategy (Custom Pro #2)

**Core Logic (My Design):** When multiple technical levels converge within a tight zone (EMA + session level + order block + round number), the probability of a strong bounce is very high. This strategy identifies these confluence zones and trades bounces with precision entries.

**Files:**
- Create: `dashboard/backend/core/strategies/confluence_zone_strategy.py`
- Modify: factory + registry

**Why This Works for Gold:**
- Gold respects technical levels better than most instruments
- When 3+ levels align, institutional order flow concentrates at that zone
- Tight stops possible (below the zone) = excellent R:R
- Works in both trending and ranging markets

**Confluence Scoring System (0-100):**
Each factor adds points:
- EMA 50 within zone: +20
- EMA 200 within zone: +25
- Session level (Asian/London/PD high or low) within zone: +15 each
- Order Block overlapping zone: +20
- Round number ($XX00 or $XX50) within zone: +15
- Previous FVG in zone: +10
- RSI at extremes (>65 or <35): +10

**Entry Rules:**
1. **Zone Definition**: Find price area where 3+ levels converge within 1 ATR width
2. **Confluence Score**: Must be >= 60 (at least 3 strong factors)
3. **Approach**: Price must be moving toward the zone (not already past it)
4. **Trigger**: First reversal candle pattern (pin bar, engulfing, hammer) at the zone
5. **Entry**: Next bar open after trigger candle
6. **Stop Loss**: Other side of the zone + 0.5 ATR buffer
7. **Take Profit**: Next confluence zone in profit direction, or 2.5:1 R:R

**Implementation:**
```python
class ConfluenceZoneStrategy(BacktestStrategy):
    def initialize_day(self, date, daily_df, intraday_df):
        # Calculate EMAs (50, 200) on H1 or H4 data
        # Get session levels
        # Find order blocks
        # Identify round numbers
        # Build confluence zones by clustering nearby levels
        # Score each zone

    def _find_confluence_zones(self, df, day_context):
        """Find areas where 3+ levels cluster within 1 ATR."""
        all_levels = []  # [(price, type, weight)]

        # Collect all levels
        for name, price in day_context.levels.items():
            if price: all_levels.append((price, name, self._get_weight(name)))

        # Add EMAs, round numbers
        # Cluster levels within 1 ATR of each other
        # Score each cluster
        # Return zones sorted by score

    def find_setup(self, bar, df, day_context, idx):
        # Check if price is approaching any confluence zone
        # Detect reversal candle pattern at zone
        # Verify confluence score >= threshold
        # Calculate SL/TP
```

**Parameters:**
```python
optimal_parameters={
    "ema_slow": 50,
    "ema_very_slow": 200,
    "zone_width_atr": 1.0,
    "min_confluence_score": 60,
    "min_levels_in_zone": 3,
    "use_reversal_candle_filter": True,
    "reversal_patterns": ["pin_bar", "engulfing", "hammer"],
    "sl_buffer_atr": 0.5,
    "min_rr_ratio": 2.5,
    "rsi_period": 14,
    "rsi_extreme_threshold": 35,
}
```

---

### Task 15: Reinforcement Learning Trading Strategy

**Core Logic:** An RL agent learns to make trade decisions (buy/sell/hold) by optimizing a reward function based on risk-adjusted returns.

**Files:**
- Create: `dashboard/backend/core/strategies/rl_strategy.py`
- Create: `dashboard/backend/core/rl_trainer.py`
- Create: `dashboard/backend/core/rl_environment.py`
- Modify: factory + registry

**Architecture:**

1. **Environment** (`rl_environment.py`):
   - State: [price_features(20), account_state(5), position_state(3)] = 28 dimensions
   - Actions: {0: Hold, 1: Buy, 2: Sell, 3: Close}
   - Reward: Sharpe-inspired reward
     ```python
     if action == close and position_open:
         reward = pnl / risk_taken  # R-multiple of the trade
     elif holding_position:
         reward = -0.001  # Small penalty for holding (encourages action)
     else:
         reward = 0
     # Add penalty for drawdown
     reward -= max_drawdown_penalty * 0.1
     ```

2. **Agent** (`rl_trainer.py`):
   - Algorithm: PPO (Proximal Policy Optimization) via stable-baselines3 or custom PyTorch
   - Network: 2-layer MLP (128, 64) with tanh activation
   - Training: On historical data with walk-forward episodes
   - Episode: One trading day
   - Training time: ~30 minutes for 6 months of data

3. **Strategy** (`rl_strategy.py`):
   ```python
   class RLStrategy(BacktestStrategy):
       def __init__(self, config):
           super().__init__(config)
           self.agent = self._load_trained_agent()

       def find_setup(self, bar, df, day_context, idx):
           state = self._build_state(bar, df, day_context)
           action = self.agent.predict(state)
           if action == 1:  # Buy
               return TradeSetup(direction="BUY", ...)
           elif action == 2:  # Sell
               return TradeSetup(direction="SELL", ...)
           return None
   ```

**Training Pipeline:**
1. Run base backtest to collect price data
2. Create RL environment from price data
3. Train PPO agent with walk-forward episodes
4. Save trained policy network
5. Use in backtest strategy for inference

**Parameters:**
```python
optimal_parameters={
    "state_window": 20,           # Bars of history in state
    "hidden_layers": [128, 64],
    "learning_rate": 0.0003,
    "gamma": 0.99,                # Discount factor
    "episodes_per_fold": 100,
    "reward_type": "sharpe",      # "sharpe", "pnl", "sortino"
    "max_position_duration_bars": 300,
    "sl_atr_multiple": 2.0,
    "tp_atr_multiple": 4.0,
}
```

**Dependencies to add:** `stable-baselines3`, `gymnasium`

---

### Task 16: Register All New Strategies

**Files:**
- Modify: `dashboard/backend/core/strategy_registry.py`
- Modify: `dashboard/backend/core/strategies/factory.py`

**Step 1: Add StrategyDefinition for each new strategy**

For each of the 5 new strategies (MACD+EMA, Ichimoku, Basso, Liquidity Sweep, Confluence Zone, RL):
- Define parameters (user-facing: symbol, balance, preset, simulation)
- Define presets (conservative/default/aggressive)
- Define optimal_parameters (all technical settings)
- Register in StrategyRegistry

**Step 2: Add to factory STRATEGY_CLASSES dict**

```python
STRATEGY_CLASSES = {
    "orb_strategy": ORBBacktestStrategy,
    "advanced_orb_strategy": ORBBacktestStrategy,
    "macd_ema_strategy": MACDEMAStrategy,
    "ichimoku_strategy": IchimokuStrategy,
    "basso_strategy": BassoStrategy,
    "liquidity_sweep_strategy": LiquiditySweepStrategy,
    "confluence_zone_strategy": ConfluenceZoneStrategy,
    "rl_strategy": RLStrategy,
}
```

**Step 3: Test each strategy appears in the Run Backtest dropdown**

**Step 4: Commit**

---

## Phase 4: ML Pipeline Expansion

> Expand from XGBoost-only to multi-model support with hyperparameter optimization.

---

### Task 17: Create Model Factory Pattern

**Files:**
- Create: `dashboard/backend/core/ml_model_factory.py`

```python
"""Factory for creating ML model instances by type."""

from abc import ABC, abstractmethod
from typing import Dict, Any, Optional, Tuple
import numpy as np


class BaseMLModel(ABC):
    """Abstract base for all ML models used in trade filtering."""

    @abstractmethod
    def train(self, X_train: np.ndarray, y_train: np.ndarray,
              X_val: np.ndarray = None, y_val: np.ndarray = None) -> Dict[str, float]:
        """Train the model. Returns metrics dict."""
        pass

    @abstractmethod
    def predict_proba(self, X: np.ndarray) -> np.ndarray:
        """Return win probabilities for each sample. Shape: (n_samples,)"""
        pass

    @abstractmethod
    def save(self, path: str) -> None:
        """Save model to disk."""
        pass

    @abstractmethod
    def load(self, path: str) -> None:
        """Load model from disk."""
        pass

    @abstractmethod
    def get_feature_importance(self) -> Optional[Dict[str, float]]:
        """Return feature importance dict or None."""
        pass


class XGBoostModel(BaseMLModel):
    """XGBoost classifier for trade filtering."""
    def __init__(self, params: Dict[str, Any] = None):
        from xgboost import XGBClassifier
        default_params = {
            'n_estimators': 200, 'max_depth': 4, 'learning_rate': 0.05,
            'subsample': 0.8, 'colsample_bytree': 0.8, 'min_child_weight': 5,
            'reg_alpha': 0.1, 'reg_lambda': 1.0, 'use_label_encoder': False,
            'eval_metric': 'logloss',
        }
        if params:
            default_params.update(params)
        self.model = XGBClassifier(**default_params)
        self.feature_names = None

    def train(self, X_train, y_train, X_val=None, y_val=None):
        eval_set = [(X_val, y_val)] if X_val is not None else None
        self.model.fit(X_train, y_train, eval_set=eval_set, verbose=False)
        return {}

    def predict_proba(self, X):
        return self.model.predict_proba(X)[:, 1]

    def save(self, path):
        import joblib
        joblib.dump(self.model, path)

    def load(self, path):
        import joblib
        self.model = joblib.load(path)

    def get_feature_importance(self):
        imp = self.model.feature_importances_
        if self.feature_names:
            return dict(zip(self.feature_names, imp.tolist()))
        return None


class LightGBMModel(BaseMLModel):
    """LightGBM classifier - faster training, often comparable accuracy."""
    def __init__(self, params=None):
        import lightgbm as lgb
        default_params = {
            'n_estimators': 200, 'max_depth': 4, 'learning_rate': 0.05,
            'subsample': 0.8, 'colsample_bytree': 0.8, 'min_child_weight': 5,
            'reg_alpha': 0.1, 'reg_lambda': 1.0, 'objective': 'binary',
            'verbose': -1,
        }
        if params:
            default_params.update(params)
        self.model = lgb.LGBMClassifier(**default_params)
        self.feature_names = None

    # ... same interface as XGBoostModel


class LSTMModel(BaseMLModel):
    """LSTM model for sequential trade pattern detection."""
    def __init__(self, params=None):
        self.params = params or {}
        self.model = None
        self.device = 'cpu'  # Use GPU if available
        self.sequence_length = self.params.get('sequence_length', 10)
        self.hidden_size = self.params.get('hidden_size', 64)
        self.num_layers = self.params.get('num_layers', 2)

    def _build_model(self, input_size):
        import torch
        import torch.nn as nn

        class TradeLSTM(nn.Module):
            def __init__(self, input_size, hidden_size, num_layers):
                super().__init__()
                self.lstm = nn.LSTM(input_size, hidden_size, num_layers,
                                   batch_first=True, dropout=0.2)
                self.fc = nn.Sequential(
                    nn.Linear(hidden_size, 32),
                    nn.ReLU(),
                    nn.Dropout(0.3),
                    nn.Linear(32, 1),
                    nn.Sigmoid(),
                )

            def forward(self, x):
                lstm_out, _ = self.lstm(x)
                last_hidden = lstm_out[:, -1, :]
                return self.fc(last_hidden).squeeze(-1)

        self.model = TradeLSTM(input_size, self.hidden_size, self.num_layers)

    def train(self, X_train, y_train, X_val=None, y_val=None):
        import torch
        from torch.utils.data import TensorDataset, DataLoader

        # Reshape X into sequences: (n_samples, seq_len, features)
        X_seq = self._create_sequences(X_train)
        y_seq = y_train[self.sequence_length - 1:]

        if self.model is None:
            self._build_model(X_train.shape[1])

        optimizer = torch.optim.Adam(self.model.parameters(), lr=0.001)
        criterion = torch.nn.BCELoss()

        X_tensor = torch.FloatTensor(X_seq)
        y_tensor = torch.FloatTensor(y_seq)
        dataset = TensorDataset(X_tensor, y_tensor)
        loader = DataLoader(dataset, batch_size=32, shuffle=False)  # No shuffle for time series

        self.model.train()
        for epoch in range(50):
            for X_batch, y_batch in loader:
                optimizer.zero_grad()
                pred = self.model(X_batch)
                loss = criterion(pred, y_batch)
                loss.backward()
                optimizer.step()

        return {}

    def _create_sequences(self, X):
        """Convert flat features into sequences for LSTM."""
        sequences = []
        for i in range(self.sequence_length, len(X) + 1):
            sequences.append(X[i - self.sequence_length:i])
        return np.array(sequences)

    def predict_proba(self, X):
        import torch
        X_seq = self._create_sequences(X)
        self.model.eval()
        with torch.no_grad():
            X_tensor = torch.FloatTensor(X_seq)
            probs = self.model(X_tensor).numpy()
        return probs

    def save(self, path):
        import torch
        torch.save(self.model.state_dict(), path)

    def load(self, path):
        import torch
        if self.model is None:
            raise ValueError("Must build model before loading weights")
        self.model.load_state_dict(torch.load(path))
        self.model.eval()

    def get_feature_importance(self):
        return None  # LSTM doesn't have native feature importance


class CNNModel(BaseMLModel):
    """1D-CNN for local pattern detection in trade features."""
    def __init__(self, params=None):
        self.params = params or {}
        self.model = None
        self.sequence_length = self.params.get('sequence_length', 10)

    def _build_model(self, input_size):
        import torch.nn as nn

        class TradeCNN(nn.Module):
            def __init__(self, input_size, seq_len):
                super().__init__()
                self.conv = nn.Sequential(
                    nn.Conv1d(input_size, 32, kernel_size=3, padding=1),
                    nn.ReLU(),
                    nn.Conv1d(32, 64, kernel_size=3, padding=1),
                    nn.ReLU(),
                    nn.AdaptiveAvgPool1d(1),
                )
                self.fc = nn.Sequential(
                    nn.Linear(64, 32),
                    nn.ReLU(),
                    nn.Dropout(0.3),
                    nn.Linear(32, 1),
                    nn.Sigmoid(),
                )

            def forward(self, x):
                # x: (batch, seq_len, features) -> (batch, features, seq_len)
                x = x.permute(0, 2, 1)
                x = self.conv(x).squeeze(-1)
                return self.fc(x).squeeze(-1)

        self.model = TradeCNN(input_size, self.sequence_length)

    # ... train/predict/save/load same pattern as LSTM


# ========================================================================
# Factory
# ========================================================================

MODEL_TYPES = {
    "xgboost": XGBoostModel,
    "lightgbm": LightGBMModel,
    "lstm": LSTMModel,
    "cnn": CNNModel,
}

def create_ml_model(model_type: str, params: Dict[str, Any] = None) -> BaseMLModel:
    """Create an ML model instance by type name."""
    cls = MODEL_TYPES.get(model_type)
    if cls is None:
        raise ValueError(f"Unknown model type: {model_type}. "
                        f"Available: {list(MODEL_TYPES.keys())}")
    return cls(params)
```

---

### Task 18: Refactor MLTrainingPipeline to Use Model Factory

**Files:**
- Modify: `dashboard/backend/core/ml_trainer.py`

**Step 1: Replace hardcoded XGBoost with factory**

Change training pipeline to accept model_type parameter:
```python
class MLTrainingPipeline:
    def __init__(self, model_type: str = "xgboost", model_params: Dict = None):
        self.model_type = model_type
        self.model_params = model_params

    def train(self, features_df, labels):
        from .ml_model_factory import create_ml_model
        model = create_ml_model(self.model_type, self.model_params)
        # ... rest of walk-forward training
```

**Step 2: Update ml_service.py to accept model_type**

**Step 3: Update frontend to show model type selector in ML Models page**

**Step 4: Update database MLModelRecord to store model_type**

---

### Task 19: Add Hyperparameter Optimization with Optuna

**Files:**
- Create: `dashboard/backend/core/ml_hpo.py`

```python
"""Hyperparameter optimization for ML models using Optuna."""

import optuna
from typing import Dict, Any

def optimize_xgboost(X_train, y_train, X_val, y_val, n_trials=30):
    def objective(trial):
        params = {
            'n_estimators': trial.suggest_int('n_estimators', 50, 300),
            'max_depth': trial.suggest_int('max_depth', 2, 6),
            'learning_rate': trial.suggest_float('learning_rate', 0.01, 0.2, log=True),
            'subsample': trial.suggest_float('subsample', 0.6, 1.0),
            'colsample_bytree': trial.suggest_float('colsample_bytree', 0.6, 1.0),
            'min_child_weight': trial.suggest_int('min_child_weight', 1, 10),
            'reg_alpha': trial.suggest_float('reg_alpha', 0.001, 1.0, log=True),
            'reg_lambda': trial.suggest_float('reg_lambda', 0.1, 5.0),
        }
        from .ml_model_factory import XGBoostModel
        model = XGBoostModel(params)
        model.train(X_train, y_train, X_val, y_val)
        preds = model.predict_proba(X_val)
        from sklearn.metrics import roc_auc_score
        return roc_auc_score(y_val, preds)

    study = optuna.create_study(direction='maximize')
    study.optimize(objective, n_trials=n_trials, show_progress_bar=True)
    return study.best_params

def optimize_lightgbm(X_train, y_train, X_val, y_val, n_trials=30):
    # Similar structure with LightGBM-specific param ranges
    ...

def optimize_model(model_type, X_train, y_train, X_val, y_val, n_trials=30):
    """Dispatch HPO by model type."""
    optimizers = {
        "xgboost": optimize_xgboost,
        "lightgbm": optimize_lightgbm,
    }
    optimizer = optimizers.get(model_type)
    if optimizer:
        return optimizer(X_train, y_train, X_val, y_val, n_trials)
    return {}  # No HPO for LSTM/CNN (use defaults)
```

**Dependencies to add:** `optuna`

---

### Task 20: Add Ensemble/Stacking Model

**Files:**
- Modify: `dashboard/backend/core/ml_model_factory.py`

```python
class EnsembleModel(BaseMLModel):
    """Stacking ensemble: combines XGBoost + LightGBM + optional LSTM."""
    def __init__(self, params=None):
        self.params = params or {}
        self.base_models = [
            XGBoostModel(self.params.get('xgboost_params')),
            LightGBMModel(self.params.get('lightgbm_params')),
        ]
        # Meta-learner: simple logistic regression
        from sklearn.linear_model import LogisticRegression
        self.meta_learner = LogisticRegression()

    def train(self, X_train, y_train, X_val=None, y_val=None):
        # Train base models
        base_preds = []
        for model in self.base_models:
            model.train(X_train, y_train, X_val, y_val)
            base_preds.append(model.predict_proba(X_train))

        # Train meta-learner on base predictions
        stacked_X = np.column_stack(base_preds)
        self.meta_learner.fit(stacked_X, y_train)
        return {}

    def predict_proba(self, X):
        base_preds = [model.predict_proba(X) for model in self.base_models]
        stacked_X = np.column_stack(base_preds)
        return self.meta_learner.predict_proba(stacked_X)[:, 1]
```

Add to MODEL_TYPES: `"ensemble": EnsembleModel`

---

### Task 21: Update ML Models Frontend

**Files:**
- Modify: `dashboard/frontend/templates/ml_models.html`
- Modify: `dashboard/frontend/app.py` (train route)
- Modify: `dashboard/backend/models/database.py` (add model_type column)
- Modify: `dashboard/backend/services/ml_service.py`

**Step 1: Add model type selector to training form**

Add dropdown to ML Models page:
```html
<select name="model_type" class="form-select">
    <option value="xgboost">XGBoost (Fast, Interpretable)</option>
    <option value="lightgbm">LightGBM (Fast, High Accuracy)</option>
    <option value="lstm">LSTM (Temporal Patterns, needs 500+ trades)</option>
    <option value="cnn">1D-CNN (Local Patterns, needs 500+ trades)</option>
    <option value="ensemble">Ensemble (XGBoost + LightGBM Stack)</option>
</select>

<div class="form-check form-switch">
    <input class="form-check-input" type="checkbox" name="use_hpo" id="use_hpo">
    <label class="form-check-label" for="use_hpo">
        Auto-tune hyperparameters (slower, better results)
    </label>
</div>
```

**Step 2: Add model_type to MLModelRecord**
```python
model_type = Column(String(20), default="xgboost")
```

**Step 3: Pass model_type through training pipeline**

**Step 4: Show model type in trained models list**

**Step 5: Commit**

---

### Task 22: Expand ML Feature Set (V2 Features)

**Files:**
- Modify: `dashboard/backend/core/ml_features.py`

Add 8 new features to `MLFeatureVector`:

```python
@dataclass
class MLFeatureVector:
    # ... existing 19 features ...

    # V2 Features
    volatility_regime: float = 0.0        # ATR percentile: 0=low, 50=normal, 100=high
    htf_nearest_level_distance_atr: float = 0.0  # Distance to nearest H4/D1 support/resistance
    confluence_count: int = 0              # Number of levels within 1 ATR
    adx_14: float = 0.0                   # Trend strength (0-100)
    hours_to_session_close: float = 0.0   # Time decay
    consecutive_results: float = 0.0      # Win streak (+) or loss streak (-)
    proximity_to_round_number: float = 0.0 # Distance to $XX00/$XX50 in ATR
    fvg_fill_ratio: float = 0.0           # How much of FVG was filled (0-1)
```

Update `FeatureExtractor.extract()` to calculate these.

---

### Task 23: Update Requirements and Dependencies

**Files:**
- Modify: `requirements.txt` or `dashboard/backend/requirements.txt`

Add new dependencies:
```
lightgbm>=4.0.0
optuna>=3.0.0
torch>=2.0.0
stable-baselines3>=2.0.0
gymnasium>=0.29.0
shap>=0.42.0
```

---

## Phase 5: Integration Testing & Verification

---

### Task 24: End-to-End Strategy Test

For each new strategy:
1. Register in strategy_registry.py
2. Start backend: `python -m uvicorn dashboard.backend.main:app`
3. Start frontend: `cd dashboard/frontend && python app.py`
4. Go to Run Backtest page
5. Verify strategy appears in dropdown
6. Select it, configure dates (use CSV data)
7. Run backtest
8. Verify results page shows trades and metrics
9. Verify no errors in backend logs

### Task 25: ML Model Training Test

For each new model type:
1. Run a 6+ month backtest with ORB strategy
2. Go to ML Models page
3. Select the completed backtest
4. Select model type (XGBoost, LightGBM, etc.)
5. Click Train
6. Verify model trains successfully
7. Verify metrics are displayed
8. Run an ML-filtered backtest using the trained model

---

## Dependency Map

```
Phase 1 (Bug Fixes)     → Independent, do first
Phase 2 (Abstraction)   → Depends on Phase 1
Phase 3 (Strategies)    → Depends on Phase 2 (Tasks 6-9)
Phase 4 (ML Pipeline)   → Independent of Phase 3, depends on Phase 1
Phase 5 (Integration)   → Depends on Phase 3 + Phase 4
```

**Recommended execution order:**
1. Tasks 1-5 (bug fixes) - immediate
2. Tasks 6-9 (abstraction) - foundation
3. Tasks 10-16 (strategies) + Tasks 17-22 (ML) - can be parallelized
4. Tasks 23-25 (integration) - final verification

---

## New Dependencies Summary

| Package | Version | Purpose |
|---------|---------|---------|
| lightgbm | >=4.0.0 | Fast gradient boosting alternative |
| optuna | >=3.0.0 | Hyperparameter optimization |
| torch | >=2.0.0 | LSTM, CNN, RL neural networks |
| stable-baselines3 | >=2.0.0 | RL agent training (PPO) |
| gymnasium | >=0.29.0 | RL environment interface |
| shap | >=0.42.0 | Model explainability |
