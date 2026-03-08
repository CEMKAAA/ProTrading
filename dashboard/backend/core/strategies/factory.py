"""
Strategy Factory - Creates BacktestStrategy instances from a strategy_id.

The factory lazily loads strategy classes to avoid circular imports and maps
each registered strategy_id to the appropriate class.  Unknown IDs return
``None`` so the engine can fall back to its legacy (inline) behaviour.
"""

from typing import Dict, Type, Optional

from .base import BacktestStrategy

# Lazy-populated registry:  strategy_id -> strategy class
STRATEGY_CLASSES: Dict[str, Type[BacktestStrategy]] = {}


def _ensure_registered() -> None:
    """Import and register strategy classes on first use."""
    if STRATEGY_CLASSES:
        return

    from .orb_strategy import ORBBacktestStrategy
    from .advanced_orb_strategy import AdvancedORBBacktestStrategy
    from .liquidity_sweep_strategy import LiquiditySweepStrategy
    from .keltner_breakout_strategy import KeltnerBreakoutStrategy
    from .earnings_volatility_strategy import EarningsVolatilityStrategy
    from .b_profile_reversion_strategy import BProfileReversionStrategy

    STRATEGY_CLASSES.update(
        {
            # Both ORB variants use the same class — differentiation is via
            # preset configs (bias_min_strength, max_daily_trades, etc.) in
            # strategy_registry.py.  The live AdvancedORBStrategy adds minor
            # refinements (~1.4 KB diff) that do NOT affect signal logic.
            "orb_strategy": ORBBacktestStrategy,
            "advanced_orb_strategy": AdvancedORBBacktestStrategy,
            # ML variants also delegate ICT signal logic to the ORB class;
            # the ML filtering layer is handled by MLBacktestEngine which
            # wraps the engine, not the strategy.
            "orb_ml_strategy": ORBBacktestStrategy,
            "advanced_orb_ml_strategy": AdvancedORBBacktestStrategy,
            # Session Liquidity Sweep Reversal Strategy
            "liquidity_sweep_strategy": LiquiditySweepStrategy,
            # Keltner Channel Breakout Strategy
            "keltner_breakout_strategy": KeltnerBreakoutStrategy,
            # Earnings IV Crush Strategy (options proxy model)
            "earnings_volatility_strategy": EarningsVolatilityStrategy,
            # B-Profile failed-auction mean reversion strategy
            "b_profile_reversion_strategy": BProfileReversionStrategy,
        }
    )


def create_strategy(
    strategy_id: str, config: dict
) -> Optional[BacktestStrategy]:
    """
    Create a strategy instance for *strategy_id*.

    Args:
        strategy_id: Registered strategy identifier (e.g. ``"orb_strategy"``).
        config: Merged parameter dict (optimal_parameters + preset overrides
                + user overrides).

    Returns:
        A ``BacktestStrategy`` subclass instance, or ``None`` if the
        strategy_id has no registered class (the engine should then use its
        legacy inline code path).
    """
    _ensure_registered()
    cls = STRATEGY_CLASSES.get(strategy_id)
    if cls is None:
        return None
    return cls(config)
