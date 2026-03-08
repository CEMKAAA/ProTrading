"""
ML Trade Filter for Live Trading.

Loads trained ML models and provides trade filtering for live strategies.
Uses MLModelManager from the dashboard backend for model loading and inference.
"""

import sys
import os
import logging
from typing import Tuple, Optional

logger = logging.getLogger(__name__)


class MLLiveFilter:
    """
    Filters live trades using trained ML models.

    Usage:
        ml_filter = MLLiveFilter("orb_strategy", min_probability=0.55)
        ml_filter.load_model()

        # On each trade setup:
        features = LiveFeatureExtractor.extract_from_strategy(strategy, setup, df)
        should_take, prob = ml_filter.should_take_trade(features)
    """

    def __init__(self, base_strategy_id: str, min_probability: float = 0.55):
        """
        Args:
            base_strategy_id: ID of the base strategy whose ML model to load
            min_probability: Minimum win probability threshold to take a trade
        """
        self.base_strategy_id = base_strategy_id
        self.min_probability = min_probability
        self.model_loaded = False
        self._model_manager = None

    def load_model(self) -> bool:
        """
        Load the trained ML model for the base strategy.

        Returns:
            True if model loaded successfully
        """
        try:
            # Ensure project root is in path for dashboard imports
            project_root = os.path.dirname(
                os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            )
            if project_root not in sys.path:
                sys.path.insert(0, project_root)

            from dashboard.backend.core.ml_models import MLModelManager

            self._model_manager = MLModelManager()
            self.model_loaded = self._model_manager.load_models(self.base_strategy_id)

            if self.model_loaded:
                logger.info(f"ML model loaded for '{self.base_strategy_id}'")
            else:
                logger.warning(f"No trained ML model found for '{self.base_strategy_id}'")

            return self.model_loaded

        except ImportError as e:
            logger.error(f"Cannot import ML modules (missing dependencies?): {e}")
            return False
        except Exception as e:
            logger.error(f"Failed to load ML model: {e}")
            return False

    def should_take_trade(self, features) -> Tuple[bool, float]:
        """
        Check if a trade should be taken based on ML prediction.

        Args:
            features: MLFeatureVector instance

        Returns:
            (should_take, win_probability)
        """
        if not self.model_loaded or self._model_manager is None:
            return True, 0.5  # Allow trade if no model

        win_prob, loaded = self._model_manager.predict_trade_filter(
            self.base_strategy_id, features
        )

        if not loaded:
            return True, 0.5

        return win_prob >= self.min_probability, win_prob

    def predict_optimal_rr(self, features) -> Tuple[float, bool]:
        """
        Get ML-suggested R:R ratio.

        Args:
            features: MLFeatureVector instance

        Returns:
            (suggested_rr, model_loaded)
        """
        if not self.model_loaded or self._model_manager is None:
            return 2.0, False

        return self._model_manager.predict_optimal_rr(
            self.base_strategy_id, features
        )
