"""Options volatility edge scanner core module."""

from .scan_engine import (
    OptionsEdgeScanEngine,
    DEFAULT_GATE_CONFIG,
    DEFAULT_SCORE_WEIGHTS,
    normalize_universe_dataframe,
)
from .strategy_builder import (
    OptionsStrategyBuilder,
    DEFAULT_BUILDER_CONFIG,
    normalize_option_chain_dataframe,
)
from .connectors import (
    PolygonOptionsConnector,
    LiveOptionsDataset,
    resolve_polygon_api_key,
)
from .backtest_engine import OptionsEdgeBacktestEngine
from .llm_reporter import OptionsEdgeReporter
from .csp_pricing import bs_put_price, bs_put_delta, estimate_pop
from .csp_models import (
    RollEvent,
    CSPCandidate,
    CSPTrade,
    CSPScreenConfig,
    CSPBacktestConfig,
)
from .csp_screener import CSPScreener, CSPScreenResult, detect_regime
from .csp_engine import CSPLifecycleEngine
from .csp_execution_bridge import CSPExecutionBridge

__all__ = [
    "OptionsEdgeScanEngine",
    "DEFAULT_GATE_CONFIG",
    "DEFAULT_SCORE_WEIGHTS",
    "normalize_universe_dataframe",
    "OptionsStrategyBuilder",
    "DEFAULT_BUILDER_CONFIG",
    "normalize_option_chain_dataframe",
    "PolygonOptionsConnector",
    "LiveOptionsDataset",
    "resolve_polygon_api_key",
    "OptionsEdgeBacktestEngine",
    "OptionsEdgeReporter",
    "bs_put_price",
    "bs_put_delta",
    "estimate_pop",
    "RollEvent",
    "CSPCandidate",
    "CSPTrade",
    "CSPScreenConfig",
    "CSPBacktestConfig",
    "CSPScreener",
    "CSPScreenResult",
    "detect_regime",
    "CSPLifecycleEngine",
    "CSPExecutionBridge",
]
