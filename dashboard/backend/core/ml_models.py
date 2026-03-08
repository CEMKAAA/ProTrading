"""
ML Model Manager - Loading, Caching, and Inference

Handles loading trained ML models (XGBoost, LightGBM, LSTM, CNN, Ensemble)
and running predictions. Uses the Model Factory for loading the correct
model type based on metadata. Caches models in memory to avoid reloading
from disk on every trade.

Backward compatible: legacy models without a model_type in their metadata
are treated as XGBoost.
"""

import os
import json
import logging
from typing import Dict, Optional, Tuple, List, Any
from dataclasses import dataclass, field

import numpy as np
import joblib

from .ml_features import MLFeatureVector, FeatureExtractor
from .ml_model_factory import create_ml_model, BaseMLModel

logger = logging.getLogger(__name__)

MODEL_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(__file__))),
    "data", "ml_models"
)


@dataclass
class ModelInfo:
    """Information about a trained model."""
    strategy_id: str
    trained_at: str
    total_trades: int
    avg_accuracy: float
    avg_auc_roc: float
    avg_f1: float
    avg_rr_mae: float
    feature_importance: Dict[str, float]
    filter_model_path: str
    rr_model_path: str
    metadata_path: str
    folds: List[Dict[str, Any]]
    model_type: str = "xgboost"  # xgboost, lightgbm, lstm, cnn, ensemble
    symbol: str = "XAUUSD"
    timeframe: str = "M1"


class MLModelManager:
    """
    Manages ML model loading, caching, and inference.

    Usage:
        manager = MLModelManager()
        manager.load_models("orb_strategy")

        # During backtest:
        should_take, win_prob = manager.predict_trade_filter("orb_strategy", features)
        suggested_rr = manager.predict_optimal_rr("orb_strategy", features)
    """

    def __init__(self):
        # Cache: strategy_id -> (filter_model, rr_model, metadata)
        self._cache: Dict[str, Tuple[Any, Any, Dict]] = {}

    def list_available_models(self) -> List[ModelInfo]:
        """List all trained models across all strategies."""
        models = []
        if not os.path.exists(MODEL_DIR):
            return models

        for strategy_id in os.listdir(MODEL_DIR):
            strategy_dir = os.path.join(MODEL_DIR, strategy_id)
            if not os.path.isdir(strategy_dir):
                continue

            # Find all metadata files (there may be multiple versions)
            meta_files = sorted(
                [f for f in os.listdir(strategy_dir) if f.startswith("metadata_") and f.endswith(".json")],
                reverse=True  # Most recent first
            )

            for meta_file in meta_files:
                meta_path = os.path.join(strategy_dir, meta_file)
                try:
                    with open(meta_path, 'r') as f:
                        meta = json.load(f)

                    models.append(ModelInfo(
                        strategy_id=meta.get('strategy_id', strategy_id),
                        trained_at=meta.get('trained_at', ''),
                        total_trades=meta.get('total_trades', 0),
                        avg_accuracy=meta.get('avg_accuracy', 0.0),
                        avg_auc_roc=meta.get('avg_auc_roc', 0.0),
                        avg_f1=meta.get('avg_f1', 0.0),
                        avg_rr_mae=meta.get('avg_rr_mae', 0.0),
                        feature_importance=meta.get('feature_importance', {}),
                        filter_model_path=meta.get('filter_model_path', ''),
                        rr_model_path=meta.get('rr_model_path', ''),
                        metadata_path=meta_path,
                        folds=meta.get('folds', []),
                        model_type=meta.get('model_type', 'xgboost'),
                        symbol=meta.get('symbol', 'XAUUSD'),
                        timeframe=meta.get('timeframe', 'M1'),
                    ))
                except Exception as e:
                    logger.warning(f"Failed to load model metadata {meta_path}: {e}")

        return models

    def get_latest_model(
        self,
        strategy_id: str,
        symbol: Optional[str] = None,
        timeframe: Optional[str] = None,
    ) -> Optional[ModelInfo]:
        """Get the most recently trained model for a strategy, optionally filtered by symbol/timeframe."""
        models = [m for m in self.list_available_models() if m.strategy_id == strategy_id]
        # Filter by symbol/timeframe if provided
        if symbol:
            models = [m for m in models if m.symbol == symbol]
        if timeframe:
            models = [m for m in models if m.timeframe == timeframe]
        if not models:
            return None
        # Sort by trained_at descending
        models.sort(key=lambda m: m.trained_at, reverse=True)
        return models[0]

    def load_models(
        self,
        strategy_id: str,
        model_info: Optional[ModelInfo] = None,
        symbol: Optional[str] = None,
        timeframe: Optional[str] = None,
    ) -> bool:
        """
        Load models for a strategy into cache.

        Uses the Model Factory to instantiate the correct model type based on
        metadata. Legacy models (without model_type in metadata) are loaded
        as XGBoost via joblib for backward compatibility.

        Args:
            strategy_id: Strategy to load models for
            model_info: Specific model to load. If None, loads latest.
            symbol: Filter models by symbol (e.g. "XAUUSD")
            timeframe: Filter models by timeframe (e.g. "M5")

        Returns:
            True if models loaded successfully
        """
        if model_info is None:
            model_info = self.get_latest_model(strategy_id, symbol=symbol, timeframe=timeframe)

        if model_info is None:
            logger.warning(f"No trained models found for strategy '{strategy_id}'")
            return False

        try:
            with open(model_info.metadata_path, 'r') as f:
                metadata = json.load(f)

            model_type = metadata.get('model_type', model_info.model_type)

            # Load the filter model using the Model Factory
            filter_model = create_ml_model(model_type)
            filter_model.feature_names = metadata.get(
                'feature_names', FeatureExtractor.feature_names()
            )
            filter_model.load(model_info.filter_model_path)

            # R:R predictor is always XGBoost (loaded via joblib)
            rr_model = joblib.load(model_info.rr_model_path)

            self._cache[strategy_id] = (filter_model, rr_model, metadata)

            logger.info(
                f"Loaded ML models for '{strategy_id}' "
                f"(type={model_type}, trained {model_info.trained_at}, "
                f"AUC={model_info.avg_auc_roc:.3f})"
            )
            return True

        except Exception as e:
            logger.error(f"Failed to load models for '{strategy_id}': {e}")
            return False

    def is_loaded(self, strategy_id: str) -> bool:
        """Check if models are loaded for a strategy."""
        return strategy_id in self._cache

    def predict_trade_filter(
        self, strategy_id: str, features: MLFeatureVector
    ) -> Tuple[float, bool]:
        """
        Predict win probability for a trade setup.

        Works with all model types via the BaseMLModel interface.
        predict_proba returns a 1D array of win probabilities.

        Args:
            strategy_id: Strategy ID to use models for
            features: ML feature vector extracted at trade time

        Returns:
            (win_probability, model_loaded) - probability 0.0-1.0
        """
        if strategy_id not in self._cache:
            return 0.5, False  # Default: neutral prediction

        filter_model, _, metadata = self._cache[strategy_id]

        # Convert features to array in correct order
        feature_names = metadata.get('feature_names', FeatureExtractor.feature_names())
        X = np.array([[getattr(features, name, 0.0) for name in feature_names]])

        try:
            # BaseMLModel.predict_proba returns 1D array of win probabilities
            proba = filter_model.predict_proba(X)
            win_prob = float(proba[0]) if proba.ndim == 1 else float(proba[0, 1])
            return win_prob, True
        except Exception as e:
            logger.warning(f"Trade filter prediction failed: {e}")
            return 0.5, False

    def predict_optimal_rr(
        self, strategy_id: str, features: MLFeatureVector
    ) -> Tuple[float, bool]:
        """
        Predict optimal R:R ratio based on MFE prediction.

        Args:
            strategy_id: Strategy ID
            features: ML feature vector

        Returns:
            (suggested_rr, model_loaded) - suggested R:R ratio
        """
        if strategy_id not in self._cache:
            return 2.0, False  # Default: 2:1

        _, rr_model, metadata = self._cache[strategy_id]

        feature_names = metadata.get('feature_names', FeatureExtractor.feature_names())
        X = np.array([[getattr(features, name, 0.0) for name in feature_names]])

        try:
            # MFE prediction is in R-multiples
            predicted_mfe = float(rr_model.predict(X)[0])

            # Convert MFE to practical R:R
            # Use 70% of predicted MFE as target (conservative)
            suggested_rr = predicted_mfe * 0.7

            # Clamp to reasonable range (never below 1.5, never above 5.0)
            suggested_rr = max(1.5, min(5.0, suggested_rr))

            return round(suggested_rr, 2), True
        except Exception as e:
            logger.warning(f"R:R prediction failed: {e}")
            return 2.0, False

    def delete_model(self, strategy_id: str, metadata_path: str) -> bool:
        """Delete a specific trained model and its files.

        Handles cleanup for all model types:
        - XGBoost/LightGBM: single .joblib file
        - LSTM/CNN: .joblib file + .joblib.meta.json
        - Ensemble: .joblib file + .joblib.ensemble/ directory
        """
        import shutil

        try:
            with open(metadata_path, 'r') as f:
                meta = json.load(f)

            # Delete model files and their associated artifacts
            for key in ['filter_model_path', 'rr_model_path']:
                path = meta.get(key, '')
                if not path:
                    continue

                # Delete the main model file
                if os.path.exists(path):
                    os.remove(path)

                # Delete LSTM/CNN meta file (e.g., filter_xxx.joblib.meta.json)
                torch_meta = path + ".meta.json"
                if os.path.exists(torch_meta):
                    os.remove(torch_meta)

                # Delete Ensemble directory (e.g., filter_xxx.joblib.ensemble/)
                ensemble_dir = path + ".ensemble"
                if os.path.exists(ensemble_dir) and os.path.isdir(ensemble_dir):
                    shutil.rmtree(ensemble_dir)

            # Delete metadata
            if os.path.exists(metadata_path):
                os.remove(metadata_path)

            # Clear cache
            if strategy_id in self._cache:
                del self._cache[strategy_id]

            logger.info(f"Deleted model for '{strategy_id}' at {metadata_path}")
            return True
        except Exception as e:
            logger.error(f"Failed to delete model: {e}")
            return False

    def clear_cache(self):
        """Clear all cached models from memory."""
        self._cache.clear()
