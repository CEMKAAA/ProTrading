"""
Base Strategy Class - All strategies inherit from this
"""

from abc import ABC, abstractmethod
from typing import Dict, Any, Optional, List
from dataclasses import dataclass
from enum import Enum
import MetaTrader5 as mt5


class StrategyStatus(Enum):
    STOPPED = "stopped"
    STARTING = "starting"
    RUNNING = "running"
    ERROR = "error"


@dataclass
class StrategyInfo:
    """Strategy metadata"""
    id: str
    name: str
    description: str
    version: str
    author: str
    timeframes: List[str]
    symbols: List[str]
    parameters: Dict[str, Any]


class BaseStrategy(ABC):
    """
    Abstract base class for all trading strategies.

    All strategies must implement:
    - get_info(): Return strategy metadata
    - initialize(): Setup strategy components
    - run(): Main strategy loop
    - shutdown(): Cleanup on stop
    - get_state(): Return current state for dashboard
    """

    def __init__(self):
        self.status = StrategyStatus.STOPPED
        self.error_message: Optional[str] = None
        self._running = False

    @classmethod
    @abstractmethod
    def get_info(cls) -> StrategyInfo:
        """Return strategy metadata"""
        pass

    @abstractmethod
    def initialize(self) -> bool:
        """
        Initialize strategy components.

        Returns:
            bool: True if initialization successful
        """
        pass

    @abstractmethod
    def run(self):
        """
        Main strategy loop.
        Should check self._running flag to allow graceful shutdown.
        """
        pass

    @abstractmethod
    def shutdown(self):
        """Cleanup and shutdown strategy"""
        pass

    @abstractmethod
    def get_state(self) -> Dict[str, Any]:
        """
        Return current strategy state for dashboard display.

        Returns:
            dict with state information
        """
        pass

    def start(self):
        """Start the strategy"""
        self.status = StrategyStatus.STARTING
        self._running = True

        try:
            if self.initialize():
                self.status = StrategyStatus.RUNNING
                self.run()
            else:
                self.status = StrategyStatus.ERROR
                self.error_message = "Initialization failed"
        except Exception as e:
            self.status = StrategyStatus.ERROR
            self.error_message = str(e)
        finally:
            self.shutdown()
            self.status = StrategyStatus.STOPPED

    def stop(self):
        """Signal strategy to stop"""
        self._running = False


class StrategyRegistry:
    """
    Registry for all available strategies.
    Strategies register themselves here for discovery.
    """

    _strategies: Dict[str, type] = {}

    @classmethod
    def register(cls, strategy_class: type):
        """
        Register a strategy class.

        Args:
            strategy_class: Class inheriting from BaseStrategy
        """
        info = strategy_class.get_info()
        cls._strategies[info.id] = strategy_class
        return strategy_class

    @classmethod
    def get(cls, strategy_id: str) -> Optional[type]:
        """Get a strategy class by ID"""
        return cls._strategies.get(strategy_id)

    @classmethod
    def list_all(cls) -> List[StrategyInfo]:
        """List all registered strategies"""
        return [s.get_info() for s in cls._strategies.values()]

    @classmethod
    def get_all(cls) -> Dict[str, type]:
        """Get all registered strategy classes"""
        return cls._strategies.copy()
