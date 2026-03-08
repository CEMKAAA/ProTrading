"""
Advanced ORB Strategy - Production-Level Trading System
Addresses all weaknesses of the basic ORB strategy
"""

from Strategies.base import StrategyRegistry

# Import main class
from .strategy import AdvancedGoldORBStrategy

# Register strategy class (not the info object)
StrategyRegistry.register(AdvancedGoldORBStrategy)

# Export
__all__ = ['AdvancedGoldORBStrategy']
