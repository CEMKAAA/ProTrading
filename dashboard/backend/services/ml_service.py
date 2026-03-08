"""
ML Service - Training, model management, and inference
"""

import logging
from datetime import datetime
from typing import Dict, List, Optional, Any

from sqlalchemy.orm import Session

from ..models.database import (
    BacktestResultModel, BacktestTradeModel, BacktestConfigModel,
    MLModelRecord, SessionLocal, BacktestStatus
)
from ..core.ml_trainer import MLTrainingPipeline
from ..core.ml_models import MLModelManager

logger = logging.getLogger(__name__)


class MLService:
    """Service layer for ML model operations."""

    @staticmethod
    def train_from_backtest(
        result_id: int,
        strategy_id: str,
        model_type: str = "xgboost",
        use_hpo: bool = False,
        hpo_trials: int = 30,
        progress_callback=None,
    ) -> Dict[str, Any]:
        """
        Train ML models from a completed backtest's trade data.

        Args:
            result_id: Backtest result ID to train from
            strategy_id: Base strategy ID (e.g., "orb_strategy")
            model_type: Model type ("xgboost", "lightgbm", "lstm", "cnn", "ensemble")
            use_hpo: Whether to run Optuna hyperparameter optimization
            hpo_trials: Number of Optuna trials if use_hpo is True
            progress_callback: Optional callback(progress, status)

        Returns:
            Training result dict with metrics and model paths
        """
        db = SessionLocal()
        try:
            # Verify backtest exists and is completed
            result = db.query(BacktestResultModel).filter(
                BacktestResultModel.id == result_id
            ).first()

            if not result:
                raise ValueError(f"Backtest result {result_id} not found")

            if result.status.value != "COMPLETED":
                raise ValueError(f"Backtest {result_id} is not completed (status: {result.status.value})")

            # Extract symbol/timeframe from backtest config for model scoping
            config = db.query(BacktestConfigModel).filter(
                BacktestConfigModel.id == result.config_id
            ).first()
            symbol = config.symbol if config else "XAUUSD"
            timeframe = config.timeframe if config else "M1"

            # Load trades with ML features
            trades = db.query(BacktestTradeModel).filter(
                BacktestTradeModel.result_id == result_id
            ).all()

            if not trades:
                raise ValueError(f"No trades found for backtest {result_id}")

            # Convert to dicts for trainer
            trade_dicts = []
            for t in trades:
                trade_dicts.append({
                    'trade_number': t.trade_number,
                    'direction': t.direction.value,
                    'entry_time': t.entry_time.isoformat() if t.entry_time else '',
                    'exit_time': t.exit_time.isoformat() if t.exit_time else '',
                    'entry_price': t.entry_price,
                    'exit_price': t.exit_price,
                    'stop_loss': t.stop_loss,
                    'profit_loss': t.profit_loss,
                    'r_multiple': t.r_multiple,
                    'setup_type': t.setup_type,
                    'exit_reason': t.exit_reason,
                    'ml_features': t.ml_features,
                    'max_favorable_excursion': t.max_favorable_excursion or 0.0,
                    'max_adverse_excursion': t.max_adverse_excursion or 0.0,
                })

            # Check that trades have ML features
            trades_with_features = [t for t in trade_dicts if t.get('ml_features')]
            if len(trades_with_features) < 30:
                raise ValueError(
                    f"Only {len(trades_with_features)} trades have ML features. "
                    f"Need at least 30. Re-run the backtest to generate features."
                )

            logger.info(
                f"Training ML models from backtest {result_id}: "
                f"{len(trades_with_features)} trades with features "
                f"[model_type={model_type}, use_hpo={use_hpo}]"
            )

            # Train models -- HPO is handled inside MLTrainingPipeline
            pipeline = MLTrainingPipeline(
                strategy_id=strategy_id,
                model_type=model_type,
                use_hpo=use_hpo,
                hpo_trials=hpo_trials,
                symbol=symbol,
                timeframe=timeframe,
            )
            training_result = pipeline.train(trades_with_features, progress_callback)
            training_result.base_result_id = result_id

            # Save to database
            model_record = MLModelRecord(
                strategy_id=strategy_id,
                symbol=symbol,
                timeframe=timeframe,
                model_type=model_type,
                base_result_id=result_id,
                trained_at=datetime.utcnow(),
                total_trades=training_result.total_trades,
                winning_trades=training_result.winning_trades,
                losing_trades=training_result.losing_trades,
                avg_accuracy=training_result.avg_accuracy,
                avg_precision=training_result.avg_precision,
                avg_recall=training_result.avg_recall,
                avg_f1=training_result.avg_f1,
                avg_auc_roc=training_result.avg_auc_roc,
                avg_rr_mae=training_result.avg_rr_mae,
                avg_rr_r2=training_result.avg_rr_r2,
                feature_importance=training_result.feature_importance,
                filter_model_path=training_result.filter_model_path,
                rr_model_path=training_result.rr_model_path,
                metadata_path=training_result.metadata_path,
                folds=training_result.folds,
            )
            db.add(model_record)
            db.commit()
            db.refresh(model_record)

            logger.info(
                f"ML model saved (ID: {model_record.id}, "
                f"type: {model_type}, {symbol}/{timeframe}, AUC: {training_result.avg_auc_roc:.3f})"
            )

            return {
                'model_id': model_record.id,
                'strategy_id': strategy_id,
                'symbol': symbol,
                'timeframe': timeframe,
                'model_type': model_type,
                'total_trades': training_result.total_trades,
                'avg_accuracy': training_result.avg_accuracy,
                'avg_auc_roc': training_result.avg_auc_roc,
                'avg_f1': training_result.avg_f1,
                'avg_rr_mae': training_result.avg_rr_mae,
                'feature_importance': training_result.feature_importance,
                'folds': training_result.folds,
            }

        finally:
            db.close()

    @staticmethod
    def list_models(db: Session) -> List[Dict[str, Any]]:
        """List all trained ML models."""
        models = db.query(MLModelRecord).order_by(MLModelRecord.trained_at.desc()).all()
        return [
            {
                'id': m.id,
                'strategy_id': m.strategy_id,
                'symbol': getattr(m, 'symbol', None) or 'XAUUSD',
                'timeframe': getattr(m, 'timeframe', None) or 'M1',
                'model_type': getattr(m, 'model_type', None) or 'xgboost',
                'base_result_id': m.base_result_id,
                'trained_at': m.trained_at.isoformat() if m.trained_at else None,
                'total_trades': m.total_trades,
                'winning_trades': m.winning_trades,
                'losing_trades': m.losing_trades,
                'avg_accuracy': m.avg_accuracy,
                'avg_auc_roc': m.avg_auc_roc,
                'avg_f1': m.avg_f1,
                'avg_rr_mae': m.avg_rr_mae,
                'feature_importance': m.feature_importance,
                'folds': m.folds,
            }
            for m in models
        ]

    @staticmethod
    def get_model(db: Session, model_id: int) -> Optional[Dict[str, Any]]:
        """Get a specific ML model's details."""
        m = db.query(MLModelRecord).filter(MLModelRecord.id == model_id).first()
        if not m:
            return None
        return {
            'id': m.id,
            'strategy_id': m.strategy_id,
            'symbol': getattr(m, 'symbol', None) or 'XAUUSD',
            'timeframe': getattr(m, 'timeframe', None) or 'M1',
            'model_type': getattr(m, 'model_type', None) or 'xgboost',
            'base_result_id': m.base_result_id,
            'trained_at': m.trained_at.isoformat() if m.trained_at else None,
            'total_trades': m.total_trades,
            'winning_trades': m.winning_trades,
            'losing_trades': m.losing_trades,
            'avg_accuracy': m.avg_accuracy,
            'avg_precision': m.avg_precision,
            'avg_recall': m.avg_recall,
            'avg_f1': m.avg_f1,
            'avg_auc_roc': m.avg_auc_roc,
            'avg_rr_mae': m.avg_rr_mae,
            'avg_rr_r2': m.avg_rr_r2,
            'feature_importance': m.feature_importance,
            'filter_model_path': m.filter_model_path,
            'rr_model_path': m.rr_model_path,
            'folds': m.folds,
        }

    @staticmethod
    def batch_train_all_strategies(
        model_type: str = "xgboost",
        use_hpo: bool = False,
    ) -> List[Dict[str, Any]]:
        """
        Train ML models for ALL strategies that have completed backtests.

        Finds the most recent completed backtest for each unique
        (strategy_id, symbol, timeframe) combination and trains a model.

        Args:
            model_type: Model type to train ("xgboost", "lightgbm", etc.)
            use_hpo: Whether to run Optuna HPO

        Returns:
            List of training results (one per strategy/symbol/timeframe combo)
        """
        db = SessionLocal()
        results = []
        try:
            from sqlalchemy import desc

            # Find the most recent completed backtest per (strategy, symbol, timeframe)
            configs = db.query(BacktestConfigModel).all()
            strategy_backtests = {}

            for cfg in configs:
                result = db.query(BacktestResultModel).filter(
                    BacktestResultModel.config_id == cfg.id,
                    BacktestResultModel.status == BacktestStatus.COMPLETED,
                ).order_by(desc(BacktestResultModel.created_at)).first()

                if result:
                    key = (cfg.strategy_id, cfg.symbol, cfg.timeframe)
                    # Keep the most recent result per key
                    if key not in strategy_backtests or (
                        result.created_at > strategy_backtests[key][1]
                    ):
                        strategy_backtests[key] = (result.id, result.created_at)

            logger.info(
                f"Batch ML training: found {len(strategy_backtests)} "
                f"strategy/symbol/timeframe combinations"
            )

            for (strat_id, symbol, tf), (result_id, _) in strategy_backtests.items():
                try:
                    training_result = MLService.train_from_backtest(
                        result_id=result_id,
                        strategy_id=strat_id,
                        model_type=model_type,
                        use_hpo=use_hpo,
                    )
                    results.append({"status": "success", **training_result})
                    logger.info(
                        f"Batch train OK: {strat_id}/{symbol}/{tf} "
                        f"AUC={training_result.get('avg_auc_roc', 0):.3f}"
                    )
                except Exception as e:
                    results.append({
                        "status": "error",
                        "strategy_id": strat_id,
                        "symbol": symbol,
                        "timeframe": tf,
                        "error": str(e),
                    })
                    logger.warning(f"Batch train FAIL: {strat_id}/{symbol}/{tf}: {e}")

        finally:
            db.close()

        return results

    @staticmethod
    def delete_model(db: Session, model_id: int) -> bool:
        """Delete a trained ML model."""
        m = db.query(MLModelRecord).filter(MLModelRecord.id == model_id).first()
        if not m:
            return False

        # Delete model files from disk
        manager = MLModelManager()
        if m.metadata_path:
            manager.delete_model(m.strategy_id, m.metadata_path)

        # Delete DB record
        db.delete(m)
        db.commit()
        return True
