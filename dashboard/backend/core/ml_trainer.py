"""
ML Training Pipeline for Trade Filtering

Trains ML models using walk-forward cross-validation on backtest trade data.
Supports multiple model types via the Model Factory (XGBoost, LightGBM, LSTM,
CNN, Ensemble) and optional Optuna-based hyperparameter optimization.

Two models:
  1. Trade Filter: Binary classifier (win=1, loss=0) → predicts win probability
  2. R:R Predictor: XGBoost regressor → predicts optimal R:R based on MFE

Walk-forward validation ensures no look-ahead bias:
  Train on months 1-6, test on 7; train on 1-7, test on 8; etc.
"""

import os
import json
import logging
import numpy as np
import pandas as pd
from datetime import datetime
from typing import Dict, List, Tuple, Optional, Any
from dataclasses import dataclass, asdict, field

import joblib
from sklearn.metrics import (
    accuracy_score, precision_score, recall_score, f1_score,
    roc_auc_score, confusion_matrix, mean_absolute_error, r2_score
)

from .ml_features import MLFeatureVector, FeatureExtractor
from .ml_model_factory import create_ml_model, BaseMLModel

logger = logging.getLogger(__name__)

# Model storage base path
MODEL_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(__file__))),
    "data", "ml_models"
)


@dataclass
class WalkForwardFold:
    """Results from a single walk-forward fold."""
    fold_number: int
    train_start: str
    train_end: str
    test_start: str
    test_end: str
    train_size: int
    test_size: int
    # Filter model metrics
    accuracy: float = 0.0
    precision: float = 0.0
    recall: float = 0.0
    f1: float = 0.0
    auc_roc: float = 0.0
    # R:R predictor metrics
    rr_mae: float = 0.0
    rr_r2: float = 0.0


@dataclass
class TrainingResult:
    """Complete training result with all metrics."""
    strategy_id: str
    base_result_id: int
    trained_at: str
    total_trades: int
    winning_trades: int
    losing_trades: int
    # Walk-forward results
    folds: List[Dict[str, Any]]
    # Averaged metrics across folds
    avg_accuracy: float = 0.0
    avg_precision: float = 0.0
    avg_recall: float = 0.0
    avg_f1: float = 0.0
    avg_auc_roc: float = 0.0
    avg_rr_mae: float = 0.0
    avg_rr_r2: float = 0.0
    # Feature importance (top features)
    feature_importance: Dict[str, float] = None
    # Model file paths
    filter_model_path: str = ""
    rr_model_path: str = ""
    metadata_path: str = ""
    # Model type used for training (xgboost, lightgbm, lstm, cnn, ensemble)
    model_type: str = "xgboost"


class MLTrainingPipeline:
    """
    Trains ML models from backtest trade data using walk-forward validation.

    Supports multiple model types via the Model Factory and optional
    hyperparameter optimization via Optuna.
    """

    def __init__(
        self,
        strategy_id: str,
        model_type: str = "xgboost",
        use_hpo: bool = False,
        hpo_trials: int = 30,
        symbol: str = "XAUUSD",
        timeframe: str = "M1",
    ):
        """
        Args:
            strategy_id: Strategy ID (e.g. "orb_strategy")
            model_type: Model type to use ("xgboost", "lightgbm", "lstm", "cnn", "ensemble")
            use_hpo: Whether to run Optuna hyperparameter optimization before training
            hpo_trials: Number of Optuna trials if use_hpo is True
            symbol: Symbol this model is scoped to
            timeframe: Timeframe this model is scoped to
        """
        self.strategy_id = strategy_id
        self.model_type = model_type
        self.use_hpo = use_hpo
        self.hpo_trials = hpo_trials
        self.symbol = symbol
        self.timeframe = timeframe
        self.model_dir = os.path.join(MODEL_DIR, strategy_id)
        os.makedirs(self.model_dir, exist_ok=True)

    def load_training_data(self, trades: List[Dict]) -> Tuple[pd.DataFrame, np.ndarray, np.ndarray]:
        """
        Load and prepare training data from backtest trades.

        Args:
            trades: List of trade dicts from backtest results (must have ml_features)

        Returns:
            (features_df, win_labels, mfe_targets)
        """
        feature_names = FeatureExtractor.feature_names()
        rows = []
        win_labels = []
        mfe_targets = []
        entry_times = []

        for trade in trades:
            ml_features = trade.get('ml_features')
            if not ml_features:
                continue

            # Extract feature values in correct order
            row = [ml_features.get(name, 0.0) for name in feature_names]
            rows.append(row)

            # Binary label: 1 = win (profit > 0), 0 = loss
            pnl = trade.get('profit_loss', 0.0)
            win_labels.append(1 if pnl > 0 else 0)

            # MFE target for R:R predictor (how far price moved in our favor)
            mfe = trade.get('max_favorable_excursion', 0.0)
            mfe_targets.append(mfe)

            # Entry time for walk-forward splitting
            entry_time = trade.get('entry_time', '')
            entry_times.append(entry_time)

        if not rows:
            raise ValueError("No trades with ML features found. Run a base backtest first.")

        features_df = pd.DataFrame(rows, columns=feature_names)
        features_df['entry_time'] = entry_times

        return features_df, np.array(win_labels), np.array(mfe_targets)

    def walk_forward_split(
        self, features_df: pd.DataFrame, min_train_months: int = 3, test_months: int = 1
    ) -> List[Tuple[np.ndarray, np.ndarray]]:
        """
        Generate walk-forward expanding window splits.

        Train on months 1..N, test on N+1. Then train on 1..N+1, test on N+2. Etc.

        Args:
            features_df: DataFrame with 'entry_time' column
            min_train_months: Minimum months for first training window
            test_months: Months per test window

        Returns:
            List of (train_indices, test_indices) tuples
        """
        df = features_df.copy()
        df['entry_dt'] = pd.to_datetime(df['entry_time'])
        df['month'] = df['entry_dt'].dt.to_period('M')

        unique_months = sorted(df['month'].unique())

        if len(unique_months) < min_train_months + test_months:
            # Not enough months for walk-forward; use single 70/30 split
            logger.warning(
                f"Only {len(unique_months)} months of data. "
                f"Using 70/30 split instead of walk-forward."
            )
            n = len(df)
            split_idx = int(n * 0.7)
            return [(np.arange(split_idx), np.arange(split_idx, n))]

        splits = []
        for i in range(min_train_months, len(unique_months)):
            train_months = unique_months[:i]
            test_end = min(i + test_months, len(unique_months))
            test_months_list = unique_months[i:test_end]

            if not test_months_list:
                break

            train_mask = df['month'].isin(train_months)
            test_mask = df['month'].isin(test_months_list)

            train_idx = np.where(train_mask)[0]
            test_idx = np.where(test_mask)[0]

            if len(train_idx) >= 20 and len(test_idx) >= 10:
                splits.append((train_idx, test_idx))

        if not splits:
            # Fallback to 70/30
            n = len(df)
            split_idx = int(n * 0.7)
            splits = [(np.arange(split_idx), np.arange(split_idx, n))]

        return splits

    def _get_filter_params(self, X_train=None, y_train=None, X_val=None, y_val=None) -> Dict[str, Any]:
        """
        Get hyperparameters for the filter model.

        If HPO is enabled and validation data is available, runs Optuna
        optimization to find the best params. Otherwise returns empty dict
        (the model factory will use its own defaults).
        """
        if self.use_hpo and X_train is not None and X_val is not None:
            from .ml_hpo import optimize_model
            logger.info(
                f"Running HPO for {self.model_type} with {self.hpo_trials} trials..."
            )
            best_params = optimize_model(
                model_type=self.model_type,
                X_train=X_train,
                y_train=y_train,
                X_val=X_val,
                y_val=y_val,
                n_trials=self.hpo_trials,
            )
            if best_params:
                logger.info(f"HPO found best params: {best_params}")
                return best_params
            else:
                logger.info("HPO returned no params, using model defaults")
        return {}

    def train(self, trades: List[Dict], progress_callback=None) -> TrainingResult:
        """
        Full training pipeline: load data, walk-forward validate, train final models.

        Uses the Model Factory to create the appropriate model type (XGBoost,
        LightGBM, LSTM, CNN, or Ensemble). The R:R predictor always uses
        XGBoost (it's a secondary regression model).

        Args:
            trades: List of trade dicts from backtest
            progress_callback: Optional callback(progress: float, status: str)

        Returns:
            TrainingResult with all metrics and model paths
        """
        if progress_callback:
            progress_callback(0.05, "Loading training data...")

        # Load data
        features_df, win_labels, mfe_targets = self.load_training_data(trades)
        feature_names = FeatureExtractor.feature_names()

        total_trades = len(features_df)
        winning = int(win_labels.sum())
        losing = total_trades - winning

        logger.info(
            f"Training data: {total_trades} trades, "
            f"{winning} wins ({100*winning/total_trades:.1f}%), "
            f"{losing} losses "
            f"[model_type={self.model_type}, use_hpo={self.use_hpo}]"
        )

        if total_trades < 30:
            raise ValueError(
                f"Need at least 30 trades for ML training, got {total_trades}. "
                f"Run a longer backtest (6+ months recommended)."
            )

        if progress_callback:
            progress_callback(0.10, "Creating walk-forward splits...")

        # Walk-forward splits
        splits = self.walk_forward_split(features_df)
        logger.info(f"Walk-forward: {len(splits)} folds")

        # Prepare feature matrix (drop non-feature columns)
        X = features_df[feature_names].values

        # Run HPO on the first fold's split if enabled (use first fold for HPO)
        hpo_params = {}
        if self.use_hpo and len(splits) > 0:
            if progress_callback:
                progress_callback(0.12, f"Running hyperparameter optimization ({self.hpo_trials} trials)...")
            first_train_idx, first_test_idx = splits[0]
            hpo_params = self._get_filter_params(
                X_train=X[first_train_idx],
                y_train=win_labels[first_train_idx],
                X_val=X[first_test_idx],
                y_val=win_labels[first_test_idx],
            )

        # R:R predictor always uses XGBoost (secondary regression model)
        from xgboost import XGBRegressor
        rr_params = {
            'n_estimators': 150,
            'max_depth': 3,
            'learning_rate': 0.05,
            'subsample': 0.8,
            'colsample_bytree': 0.8,
            'min_child_weight': 5,
            'reg_alpha': 0.1,
            'reg_lambda': 1.0,
            'eval_metric': 'mae',
            'random_state': 42,
            'verbosity': 0,
        }

        # Walk-forward validation
        fold_results = []
        for fold_num, (train_idx, test_idx) in enumerate(splits):
            if progress_callback:
                pct = 0.15 + 0.55 * (fold_num / len(splits))
                progress_callback(pct, f"Walk-forward fold {fold_num + 1}/{len(splits)}...")

            X_train, X_test = X[train_idx], X[test_idx]
            y_train, y_test = win_labels[train_idx], win_labels[test_idx]
            mfe_train, mfe_test = mfe_targets[train_idx], mfe_targets[test_idx]

            # Train filter model using Model Factory
            filter_model = create_ml_model(self.model_type, hpo_params if hpo_params else None)
            filter_model.feature_names = feature_names
            filter_model.train(X_train, y_train, X_test, y_test)
            y_proba = filter_model.predict_proba(X_test)

            # For sequence-based models (LSTM, CNN), predictions may be shorter
            # than the test set. Align labels accordingly.
            if len(y_proba) < len(y_test):
                offset = len(y_test) - len(y_proba)
                y_test_aligned = y_test[offset:]
                mfe_test_for_rr = mfe_test[offset:]
            else:
                y_test_aligned = y_test
                mfe_test_for_rr = mfe_test

            y_pred = (y_proba >= 0.5).astype(int)

            # Train R:R predictor (always XGBoost regressor)
            rr_model = XGBRegressor(**rr_params)
            rr_model.fit(X_train, mfe_train)
            mfe_pred = rr_model.predict(X_test)
            # Align R:R predictions too if needed
            if len(y_proba) < len(y_test):
                mfe_pred_aligned = mfe_pred[offset:]
            else:
                mfe_pred_aligned = mfe_pred

            # Calculate metrics
            fold = WalkForwardFold(
                fold_number=fold_num + 1,
                train_start=features_df.iloc[train_idx[0]]['entry_time'],
                train_end=features_df.iloc[train_idx[-1]]['entry_time'],
                test_start=features_df.iloc[test_idx[0]]['entry_time'],
                test_end=features_df.iloc[test_idx[-1]]['entry_time'],
                train_size=len(train_idx),
                test_size=len(test_idx),
                accuracy=accuracy_score(y_test_aligned, y_pred),
                precision=precision_score(y_test_aligned, y_pred, zero_division=0),
                recall=recall_score(y_test_aligned, y_pred, zero_division=0),
                f1=f1_score(y_test_aligned, y_pred, zero_division=0),
                auc_roc=roc_auc_score(y_test_aligned, y_proba) if len(np.unique(y_test_aligned)) > 1 else 0.5,
                rr_mae=mean_absolute_error(mfe_test_for_rr, mfe_pred_aligned),
                rr_r2=r2_score(mfe_test_for_rr, mfe_pred_aligned) if len(mfe_test_for_rr) > 1 else 0.0,
            )
            fold_results.append(fold)

            logger.info(
                f"Fold {fold.fold_number}: Acc={fold.accuracy:.3f}, "
                f"AUC={fold.auc_roc:.3f}, F1={fold.f1:.3f}, "
                f"RR_MAE={fold.rr_mae:.3f}"
            )

        if progress_callback:
            progress_callback(0.75, f"Training final {self.model_type} model on all data...")

        # Train final filter model on ALL data using Model Factory
        final_filter = create_ml_model(self.model_type, hpo_params if hpo_params else None)
        final_filter.feature_names = feature_names
        final_filter.train(X, win_labels)

        # Train final R:R predictor on ALL data (always XGBoost)
        final_rr = XGBRegressor(**rr_params)
        final_rr.fit(X, mfe_targets)

        if progress_callback:
            progress_callback(0.85, "Saving models...")

        # Save models
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filter_path = os.path.join(self.model_dir, f"filter_{timestamp}.joblib")
        rr_path = os.path.join(self.model_dir, f"rr_predictor_{timestamp}.joblib")
        meta_path = os.path.join(self.model_dir, f"metadata_{timestamp}.json")

        # Use the model's own save method (handles LSTM/CNN torch serialization etc.)
        final_filter.save(filter_path)
        joblib.dump(final_rr, rr_path)

        # Feature importance (may be None for LSTM/CNN)
        importance_dict = final_filter.get_feature_importance()
        if importance_dict is None:
            # Fallback: no feature importance available for this model type
            importance_dict = {}

        # Exclude degenerate folds from averaging (single-class test sets or tiny folds)
        valid_folds = [
            f for f in fold_results
            if f.auc_roc > 0.0 and f.test_size >= 10
        ]
        if not valid_folds:
            valid_folds = fold_results  # fallback: use all if none qualify

        n_excluded = len(fold_results) - len(valid_folds)
        if n_excluded > 0:
            logger.info(
                f"Excluded {n_excluded} degenerate fold(s) from averaging "
                f"(AUC=0.0 or test_size<10)"
            )

        # Average metrics across valid folds
        avg_acc = np.mean([f.accuracy for f in valid_folds])
        avg_prec = np.mean([f.precision for f in valid_folds])
        avg_rec = np.mean([f.recall for f in valid_folds])
        avg_f1 = np.mean([f.f1 for f in valid_folds])
        avg_auc = np.mean([f.auc_roc for f in valid_folds])
        avg_mae = np.mean([f.rr_mae for f in valid_folds])
        avg_r2 = np.mean([f.rr_r2 for f in valid_folds])

        result = TrainingResult(
            strategy_id=self.strategy_id,
            base_result_id=0,  # Set by caller
            trained_at=datetime.now().isoformat(),
            total_trades=total_trades,
            winning_trades=winning,
            losing_trades=losing,
            folds=[asdict(f) for f in fold_results],
            avg_accuracy=round(avg_acc, 4),
            avg_precision=round(avg_prec, 4),
            avg_recall=round(avg_rec, 4),
            avg_f1=round(avg_f1, 4),
            avg_auc_roc=round(avg_auc, 4),
            avg_rr_mae=round(avg_mae, 4),
            avg_rr_r2=round(avg_r2, 4),
            feature_importance=importance_dict,
            filter_model_path=filter_path,
            rr_model_path=rr_path,
            metadata_path=meta_path,
            model_type=self.model_type,
        )

        # Save metadata
        metadata = {
            'strategy_id': self.strategy_id,
            'symbol': self.symbol,
            'timeframe': self.timeframe,
            'model_type': self.model_type,
            'trained_at': result.trained_at,
            'total_trades': total_trades,
            'feature_names': feature_names,
            'filter_model_path': filter_path,
            'rr_model_path': rr_path,
            'avg_accuracy': result.avg_accuracy,
            'avg_auc_roc': result.avg_auc_roc,
            'avg_f1': result.avg_f1,
            'avg_rr_mae': result.avg_rr_mae,
            'feature_importance': importance_dict,
            'folds': result.folds,
            'use_hpo': self.use_hpo,
            'hpo_trials': self.hpo_trials if self.use_hpo else 0,
            'hpo_params': hpo_params if hpo_params else {},
        }
        with open(meta_path, 'w') as f:
            json.dump(metadata, f, indent=2)

        if progress_callback:
            progress_callback(1.0, "Training complete!")

        logger.info(
            f"Training complete [{self.model_type}]: Avg AUC={avg_auc:.3f}, "
            f"Avg Accuracy={avg_acc:.3f}, Avg F1={avg_f1:.3f}"
        )

        return result
