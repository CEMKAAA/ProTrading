"""
Advanced ORB Backtest Strategy.

Keeps a dedicated strategy type for advanced ORB variants so factory mappings
do not alias to the base ORB class. This preserves clean parity boundaries
between base and advanced strategy IDs and allows advanced-only logic to evolve
without touching the base class.
"""

from .orb_strategy import ORBBacktestStrategy


class AdvancedORBBacktestStrategy(ORBBacktestStrategy):
    """
    Advanced ORB strategy class for backtests.

    Current behavior intentionally inherits ORB setup logic; differentiation is
    driven by advanced preset/config values. Keeping a separate class prevents
    strategy-ID aliasing and enables future advanced-only overrides.
    """

    pass

