"""
ML Wrapper Strategy Factory.

Creates ML-filtered versions of any live trading strategy.
The wrapper intercepts _execute_setup() to run ML prediction before
allowing the trade through.
"""

import sys
import os
import logging

# Ensure project root in path
_project_root = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from Strategies.base import StrategyInfo, StrategyRegistry

logger = logging.getLogger(__name__)


def create_ml_wrapped_strategy(
    base_class,
    ml_strategy_id: str,
    ml_magic_number: int,
    ml_name: str,
    ml_description: str,
    base_strategy_id: str,
    min_probability: float = 0.55,
):
    """
    Create an ML-wrapped version of any live trading strategy.

    The returned class inherits from base_class and adds ML trade filtering.
    When a trade setup is found, it extracts features and checks the ML model
    before allowing execution.

    Args:
        base_class: The base strategy class to wrap (e.g., MACDEMALiveStrategy)
        ml_strategy_id: Unique ID for the ML strategy (e.g., "macd_ema_ml_strategy")
        ml_magic_number: Unique MT5 magic number for this ML strategy
        ml_name: Display name
        ml_description: Strategy description
        base_strategy_id: ID of the base strategy (for loading ML model)
        min_probability: Minimum win probability threshold

    Returns:
        A new strategy class registered in StrategyRegistry
    """

    class MLWrapped(base_class):
        """ML-filtered version of base strategy."""

        @classmethod
        def get_info(cls):
            base_info = base_class.get_info()
            return StrategyInfo(
                id=ml_strategy_id,
                name=ml_name,
                description=ml_description,
                version=base_info.version,
                author=base_info.author,
                timeframes=base_info.timeframes,
                symbols=base_info.symbols,
                parameters={
                    **base_info.parameters,
                    'ml_min_win_probability': min_probability,
                },
            )

        def initialize(self) -> bool:
            # Call parent initialize first
            if not super().initialize():
                return False

            # Override magic number for ML version
            self.magic = ml_magic_number
            if hasattr(self, 'risk_manager'):
                self.risk_manager.magic_number = ml_magic_number
            if hasattr(self, 'trade_executor'):
                self.trade_executor.magic_number = ml_magic_number

            # Load ML filter
            from Strategies.shared.ml_live_filter import MLLiveFilter

            self.ml_filter = MLLiveFilter(
                base_strategy_id, min_probability=min_probability
            )
            ml_loaded = self.ml_filter.load_model()

            if not ml_loaded and self.logger:
                self.logger.warning(
                    f"ML model not found for '{base_strategy_id}'. "
                    f"Trades will pass through unfiltered."
                )

            # Initialize adaptive filter
            try:
                from Strategies.shared.adaptive_filter import AdaptiveFilter
                self.adaptive_filter = AdaptiveFilter()

                # Register trade close callback for adaptive filter
                if hasattr(self, 'trade_executor'):
                    self.trade_executor.on_trade_close_callback = self._on_trade_close
            except Exception as e:
                self.adaptive_filter = None
                if self.logger:
                    self.logger.debug(f"Adaptive filter init skipped: {e}")

            if self.logger:
                self.logger.info(
                    f"ML WRAPPER initialized: {ml_strategy_id} "
                    f"(base={base_strategy_id}, threshold={min_probability})"
                )

            return True

        def _on_trade_close(self, ticket, pnl, comment=''):
            """Callback when a trade closes - records result for adaptive filter."""
            try:
                if hasattr(self, 'adaptive_filter') and self.adaptive_filter:
                    # Use last known setup type
                    setup_type = getattr(self, '_last_setup_type', 'unknown')
                    won = pnl > 0
                    self.adaptive_filter.record_result(setup_type, won)
            except Exception as e:
                if self.logger:
                    self.logger.debug(f"Adaptive filter record skipped: {e}")

        def _execute_setup(self, *args, **kwargs):
            """Override to add ML filtering and adaptive filter before trade execution."""
            # Extract setup from args
            setup = args[0] if args else kwargs.get('setup')
            df = args[1] if len(args) > 1 else kwargs.get('df')

            # Track setup type for adaptive filter callback
            setup_type = None
            if setup:
                setup_type = setup.get('setup_type', setup.get('reason', 'unknown'))
                self._last_setup_type = setup_type

            # Adaptive filter check
            if hasattr(self, 'adaptive_filter') and self.adaptive_filter and setup_type:
                allowed, info = self.adaptive_filter.should_allow(setup_type)
                if not allowed:
                    if self.logger:
                        self.logger.info(
                            f"ADAPTIVE: Blocked '{setup_type}' "
                            f"(WR: {info['win_rate']:.0%})"
                        )
                    return

            features = None
            prob = None

            if hasattr(self, 'ml_filter') and self.ml_filter.model_loaded:
                try:
                    from Strategies.shared.ml_feature_extractor_live import (
                        LiveFeatureExtractor,
                    )

                    features = LiveFeatureExtractor.extract_from_strategy(
                        self, setup, df
                    )
                    should_take, prob = self.ml_filter.should_take_trade(features)

                    if not should_take:
                        if self.logger:
                            self.logger.info(
                                f"ML FILTER: Skipping trade "
                                f"(prob={prob:.3f} < {min_probability})"
                            )
                        return

                    if self.logger:
                        self.logger.info(
                            f"ML FILTER: Approved trade (prob={prob:.3f})"
                        )

                except Exception as e:
                    if self.logger:
                        self.logger.warning(
                            f"ML filter error, allowing trade: {e}"
                        )

            # Call parent _execute_setup
            super()._execute_setup(*args, **kwargs)

            # Save ML features to DB after trade execution (fail-safe)
            if features is not None and prob is not None:
                try:
                    self._save_live_ml_data(features, prob)
                except Exception as e:
                    if self.logger:
                        self.logger.debug(f"ML data save skipped: {e}")

        def _save_live_ml_data(self, features, prob):
            """Save ML features and probability to the most recent live trade."""
            try:
                import MetaTrader5 as mt5
                from Strategies.shared.trade_journal import TradeJournal

                # Get our most recent position ticket
                positions = mt5.positions_get(symbol=getattr(self, 'symbol', 'XAUUSD'))
                if not positions:
                    return

                our_positions = [
                    p for p in positions
                    if p.magic == getattr(self, 'magic', ml_magic_number)
                ]
                if not our_positions:
                    return

                # Use the most recent ticket
                ticket = our_positions[-1].ticket

                # Convert features to dict
                features_dict = None
                if hasattr(features, '__dict__'):
                    features_dict = {k: float(v) for k, v in vars(features).items()
                                     if isinstance(v, (int, float))}
                elif isinstance(features, dict):
                    features_dict = features
                elif hasattr(features, 'tolist'):
                    features_dict = {'features': features.tolist()}

                journal = TradeJournal()
                journal.record_ml_data(ticket, features_dict, prob)

            except Exception as e:
                if self.logger:
                    self.logger.debug(f"_save_live_ml_data error: {e}")

    # Set class metadata
    MLWrapped.__name__ = f"ML{base_class.__name__}"
    MLWrapped.__qualname__ = f"ML{base_class.__qualname__}"
    MLWrapped.__doc__ = f"ML-filtered version of {base_class.__name__}"

    # Register with StrategyRegistry
    StrategyRegistry.register(MLWrapped)

    return MLWrapped
