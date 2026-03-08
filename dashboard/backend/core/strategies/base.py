"""
Abstract base class for all backtesting strategies.
Strategies implement signal detection logic; the BacktestEngine handles
position management, cost simulation, and metrics.
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional, Dict, Any, List
import pandas as pd


@dataclass
class DayContext:
    """Context for a trading day, populated by the strategy."""
    date: datetime
    bias: str = "neutral"           # "bullish", "bearish", "neutral"
    bias_strength: int = 0          # 0-100
    atr: float = 0.0
    # Session levels (strategy populates what it needs)
    levels: Dict[str, float] = field(default_factory=dict)


@dataclass
class TradeSetup:
    """A proposed trade setup from the strategy."""
    direction: str                  # "BUY" or "SELL"
    entry_price: float              # Suggested entry (bar open)
    stop_loss: float                # Stop loss price
    take_profit: Optional[float]    # Take profit price (None = engine calculates)
    setup_type: str                 # Description e.g., "Bullish FVG + ORB Breakout"
    confidence: float = 0.0        # 0-100, strategy's confidence in this setup
    metadata: Dict[str, Any] = field(default_factory=dict)


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
        df: pd.DataFrame,
        position: Any,
        day_context: DayContext,
    ) -> Optional[str]:
        """
        Optional: Custom exit logic beyond SL/TP/trailing.
        Called every bar while a position is open.

        Args:
            bar: Current bar data
            df: All bars up to and including current bar
            position: Current open position
            day_context: Today's context

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
