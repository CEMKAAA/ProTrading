"""
Automated ML Model Retraining Service

Periodically retrains ML models with quality gates to keep them fresh
as market conditions change. Uses APScheduler for background scheduling.
"""

import logging
from datetime import datetime
from typing import Dict, List, Optional, Any

from ..models.database import (
    MLModelRecord, RetrainingLogModel, SessionLocal
)

logger = logging.getLogger(__name__)


class AutoRetrainService:
    """Manages automated periodic retraining of ML models."""

    def __init__(self):
        self.scheduler = None
        self.is_running = False
        self._enabled = True
        self._interval_hours = 168  # weekly
        self._quality_gate_tolerance = 0.02  # AUC within 2%
        self._current_job_id = "ml_auto_retrain"

    def start(self, interval_hours: int = 168):
        """Start the auto-retrain scheduler."""
        try:
            from apscheduler.schedulers.background import BackgroundScheduler
        except ImportError:
            logger.warning(
                "APScheduler not installed. Auto-retrain disabled. "
                "Install with: pip install apscheduler"
            )
            return

        if self.scheduler and self.scheduler.running:
            logger.info("Auto-retrain scheduler already running")
            return

        self._interval_hours = interval_hours
        self.scheduler = BackgroundScheduler(
            job_defaults={'max_instances': 1, 'coalesce': True}
        )
        self.scheduler.add_job(
            self._retrain_all_models,
            'interval',
            hours=interval_hours,
            id=self._current_job_id,
            name="ML Auto-Retrain",
            next_run_time=None,  # Don't run immediately on startup
        )
        self.scheduler.start()
        self.is_running = True
        logger.info(
            f"Auto-retrain scheduler started (interval: {interval_hours}h)"
        )

    def stop(self):
        """Stop the scheduler."""
        if self.scheduler and self.scheduler.running:
            self.scheduler.shutdown(wait=False)
            self.is_running = False
            logger.info("Auto-retrain scheduler stopped")

    def update_config(self, interval_hours: Optional[int] = None,
                      enabled: Optional[bool] = None,
                      quality_gate_tolerance: Optional[float] = None):
        """Update scheduler configuration."""
        if enabled is not None:
            self._enabled = enabled

        if quality_gate_tolerance is not None:
            self._quality_gate_tolerance = quality_gate_tolerance

        if interval_hours is not None and interval_hours != self._interval_hours:
            self._interval_hours = interval_hours
            if self.scheduler and self.scheduler.running:
                self.scheduler.reschedule_job(
                    self._current_job_id,
                    trigger='interval',
                    hours=interval_hours,
                )
                logger.info(f"Retrain interval updated to {interval_hours}h")

    def trigger_retrain(self, model_id: int) -> Dict[str, Any]:
        """Manually trigger retrain for a specific model."""
        db = SessionLocal()
        try:
            model = db.query(MLModelRecord).filter(
                MLModelRecord.id == model_id
            ).first()

            if not model:
                return {"status": "error", "message": f"Model {model_id} not found"}

            result = self._retrain_single_model(model, trigger_type="manual")
            return result
        finally:
            db.close()

    def trigger_retrain_all(self) -> Dict[str, Any]:
        """Manually trigger retrain for all models."""
        self._retrain_all_models()
        return {"status": "completed", "message": "Retrain all triggered"}

    def _retrain_all_models(self):
        """Scheduled job: retrain all active models."""
        if not self._enabled:
            logger.info("Auto-retrain is disabled, skipping")
            return

        db = SessionLocal()
        try:
            models = db.query(MLModelRecord).all()
            if not models:
                logger.info("No ML models to retrain")
                return

            logger.info(f"Starting auto-retrain for {len(models)} model(s)")

            for model in models:
                try:
                    self._retrain_single_model(model, trigger_type="scheduled")
                except Exception as e:
                    logger.error(f"Error retraining model {model.id}: {e}")
        finally:
            db.close()

    def _retrain_single_model(self, model_record, trigger_type="scheduled") -> Dict[str, Any]:
        """
        Retrain one model. Returns log entry dict.

        Quality gate: new model must have AUC-ROC >= old AUC-ROC - tolerance
        """
        from .ml_service import MLService

        db = SessionLocal()
        try:
            # Create log entry
            log_entry = RetrainingLogModel(
                model_id=model_record.id,
                strategy_id=model_record.strategy_id,
                symbol=getattr(model_record, 'symbol', None) or 'XAUUSD',
                timeframe=getattr(model_record, 'timeframe', None) or 'M1',
                model_type=getattr(model_record, 'model_type', None) or 'xgboost',
                triggered_at=datetime.utcnow(),
                trigger_type=trigger_type,
                old_auc_roc=model_record.avg_auc_roc,
                old_accuracy=model_record.avg_accuracy,
                status="running",
            )
            db.add(log_entry)
            db.commit()
            db.refresh(log_entry)

            # Check if we have the base_result_id to retrain from
            if not model_record.base_result_id:
                log_entry.status = "failed"
                log_entry.error_message = "No base_result_id - cannot retrain"
                log_entry.completed_at = datetime.utcnow()
                db.commit()
                return {
                    "status": "failed",
                    "message": "No base_result_id for model",
                    "model_id": model_record.id,
                }

            # Train new model using same parameters
            model_type = getattr(model_record, 'model_type', None) or 'xgboost'
            try:
                training_result = MLService.train_from_backtest(
                    result_id=model_record.base_result_id,
                    strategy_id=model_record.strategy_id,
                    model_type=model_type,
                    use_hpo=False,
                )
            except Exception as e:
                log_entry.status = "failed"
                log_entry.error_message = str(e)[:500]
                log_entry.completed_at = datetime.utcnow()
                db.commit()
                logger.error(
                    f"Retrain failed for model {model_record.id}: {e}"
                )
                return {
                    "status": "failed",
                    "message": str(e),
                    "model_id": model_record.id,
                }

            new_auc = training_result.get('avg_auc_roc', 0)
            new_accuracy = training_result.get('avg_accuracy', 0)
            new_model_id = training_result.get('model_id')
            old_auc = model_record.avg_auc_roc or 0

            log_entry.new_auc_roc = new_auc
            log_entry.new_accuracy = new_accuracy
            log_entry.completed_at = datetime.utcnow()

            # Quality gate check
            passes_gate = new_auc >= (old_auc - self._quality_gate_tolerance)

            if passes_gate:
                log_entry.accepted = True
                log_entry.new_model_id = new_model_id
                log_entry.status = "completed"
                db.commit()

                # Delete old model (the new one is already saved by MLService)
                try:
                    MLService.delete_model(db, model_record.id)
                    logger.info(
                        f"Retrain accepted: model {model_record.id} -> {new_model_id} "
                        f"(AUC: {old_auc:.3f} -> {new_auc:.3f})"
                    )
                except Exception as e:
                    logger.warning(f"Could not delete old model {model_record.id}: {e}")

                return {
                    "status": "accepted",
                    "model_id": model_record.id,
                    "new_model_id": new_model_id,
                    "old_auc": old_auc,
                    "new_auc": new_auc,
                }
            else:
                log_entry.accepted = False
                log_entry.status = "completed"
                db.commit()

                # Delete new model since it didn't pass quality gate
                if new_model_id:
                    try:
                        MLService.delete_model(db, new_model_id)
                    except Exception:
                        pass

                logger.info(
                    f"Retrain rejected: model {model_record.id} "
                    f"(AUC: {old_auc:.3f} -> {new_auc:.3f}, "
                    f"gate: -{self._quality_gate_tolerance:.3f})"
                )
                return {
                    "status": "rejected",
                    "model_id": model_record.id,
                    "old_auc": old_auc,
                    "new_auc": new_auc,
                    "reason": f"New AUC {new_auc:.3f} below threshold {old_auc - self._quality_gate_tolerance:.3f}",
                }

        except Exception as e:
            logger.error(f"Unexpected error during retrain of model {model_record.id}: {e}")
            return {
                "status": "error",
                "model_id": model_record.id,
                "message": str(e),
            }
        finally:
            db.close()

    def get_status(self) -> Dict[str, Any]:
        """Return scheduler status + next run time."""
        status = {
            "is_running": self.is_running,
            "enabled": self._enabled,
            "interval_hours": self._interval_hours,
            "quality_gate_tolerance": self._quality_gate_tolerance,
            "next_run_time": None,
        }

        if self.scheduler and self.scheduler.running:
            job = self.scheduler.get_job(self._current_job_id)
            if job and job.next_run_time:
                status["next_run_time"] = job.next_run_time.isoformat()

        return status

    def get_logs(self, limit: int = 50) -> List[Dict[str, Any]]:
        """Return recent retrain logs."""
        db = SessionLocal()
        try:
            logs = db.query(RetrainingLogModel).order_by(
                RetrainingLogModel.triggered_at.desc()
            ).limit(limit).all()

            return [
                {
                    "id": log.id,
                    "model_id": log.model_id,
                    "strategy_id": log.strategy_id,
                    "symbol": log.symbol,
                    "timeframe": log.timeframe,
                    "model_type": log.model_type,
                    "triggered_at": log.triggered_at.isoformat() if log.triggered_at else None,
                    "completed_at": log.completed_at.isoformat() if log.completed_at else None,
                    "trigger_type": log.trigger_type,
                    "old_auc_roc": log.old_auc_roc,
                    "new_auc_roc": log.new_auc_roc,
                    "old_accuracy": log.old_accuracy,
                    "new_accuracy": log.new_accuracy,
                    "accepted": log.accepted,
                    "new_model_id": log.new_model_id,
                    "error_message": log.error_message,
                    "status": log.status,
                }
                for log in logs
            ]
        finally:
            db.close()
