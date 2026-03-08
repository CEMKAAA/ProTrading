"""
LiveDataRetrainService - Retrains ML models using combined backtest + live trade data.

When enough live trades accumulate with ML features, this service combines them
with the original backtest training data to retrain the model. Live trades are
weighted more heavily (duplicated) to emphasize recent market behavior.
"""

import logging
from datetime import datetime
from typing import Dict, List, Any, Optional

from ..models.database import (
    BacktestTradeModel, BacktestResultModel, BacktestConfigModel,
    LiveTradeModel, MLModelRecord, RetrainingLogModel, SessionLocal
)
from ..core.ml_trainer import MLTrainingPipeline

logger = logging.getLogger(__name__)


class LiveDataRetrainService:
    """Retrains ML models using combined backtest + live trade data."""

    LIVE_TRADE_THRESHOLD = 50  # Min live trades before triggering retrain
    LIVE_WEIGHT = 2            # Duplicate live trades N times for weighting

    def retrain_with_live_data(self, model_id: int) -> dict:
        """
        Retrain a model using combined backtest + live trade data.

        Steps:
        1. Load original model record from DB (strategy_id, base_result_id, model_type)
        2. Query backtest trades from base_result_id
        3. Query live trades with ml_features IS NOT NULL for same strategy/symbol/timeframe
        4. Duplicate live trades LIVE_WEIGHT times for emphasis
        5. Train new model with combined dataset
        6. Quality gate: new AUC >= old - 0.02
        7. Log to RetrainingLogModel

        Returns:
            Result dict with status, metrics, and new model info
        """
        db = SessionLocal()
        try:
            # 1. Load original model record
            model = db.query(MLModelRecord).filter(
                MLModelRecord.id == model_id
            ).first()
            if not model:
                return {'status': 'error', 'message': f'Model {model_id} not found'}

            strategy_id = model.strategy_id
            symbol = getattr(model, 'symbol', None) or 'XAUUSD'
            timeframe = getattr(model, 'timeframe', None) or 'M1'
            model_type = getattr(model, 'model_type', None) or 'xgboost'
            old_auc = model.avg_auc_roc or 0.0

            # Create retrain log
            log_entry = RetrainingLogModel(
                model_id=model_id,
                strategy_id=strategy_id,
                symbol=symbol,
                timeframe=timeframe,
                model_type=model_type,
                trigger_type='live_data',
                old_auc_roc=old_auc,
                old_accuracy=model.avg_accuracy or 0.0,
                status='running',
            )
            db.add(log_entry)
            db.commit()
            db.refresh(log_entry)

            # 2. Query backtest trades
            backtest_trades = self._query_backtest_trades(db, model.base_result_id)
            logger.info(f"Backtest trades: {len(backtest_trades)}")

            # 3. Query live trades with ML features
            live_trades = self._query_live_trades(db, strategy_id, symbol, timeframe)
            logger.info(f"Live trades with ML features: {len(live_trades)}")

            if len(live_trades) < self.LIVE_TRADE_THRESHOLD:
                log_entry.status = 'failed'
                log_entry.error_message = (
                    f"Only {len(live_trades)} live trades with ML features. "
                    f"Need at least {self.LIVE_TRADE_THRESHOLD}."
                )
                log_entry.completed_at = datetime.utcnow()
                db.commit()
                return {
                    'status': 'error',
                    'message': log_entry.error_message,
                    'live_trade_count': len(live_trades),
                }

            # 4. Duplicate live trades for weighting
            weighted_live = live_trades * self.LIVE_WEIGHT

            # 5. Combine datasets
            combined = backtest_trades + weighted_live
            logger.info(
                f"Combined dataset: {len(combined)} trades "
                f"({len(backtest_trades)} backtest + {len(weighted_live)} live weighted)"
            )

            # Check minimum feature count
            trades_with_features = [t for t in combined if t.get('ml_features')]
            if len(trades_with_features) < 30:
                log_entry.status = 'failed'
                log_entry.error_message = f"Only {len(trades_with_features)} trades with features"
                log_entry.completed_at = datetime.utcnow()
                db.commit()
                return {'status': 'error', 'message': log_entry.error_message}

            # 6. Train new model
            pipeline = MLTrainingPipeline(
                strategy_id=strategy_id,
                model_type=model_type,
                symbol=symbol,
                timeframe=timeframe,
            )
            training_result = pipeline.train(trades_with_features)
            new_auc = training_result.avg_auc_roc

            log_entry.new_auc_roc = new_auc
            log_entry.new_accuracy = training_result.avg_accuracy

            # 7. Quality gate: new AUC >= old - 0.02
            quality_tolerance = 0.02
            if new_auc < old_auc - quality_tolerance:
                log_entry.accepted = False
                log_entry.status = 'completed'
                log_entry.completed_at = datetime.utcnow()
                log_entry.error_message = (
                    f"Quality gate failed: new AUC {new_auc:.3f} < "
                    f"old {old_auc:.3f} - {quality_tolerance}"
                )
                db.commit()
                return {
                    'status': 'rejected',
                    'reason': log_entry.error_message,
                    'old_auc': old_auc,
                    'new_auc': new_auc,
                }

            # Accept and save new model
            new_model = MLModelRecord(
                strategy_id=strategy_id,
                symbol=symbol,
                timeframe=timeframe,
                model_type=model_type,
                base_result_id=model.base_result_id,
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
            db.add(new_model)
            db.commit()
            db.refresh(new_model)

            log_entry.accepted = True
            log_entry.new_model_id = new_model.id
            log_entry.status = 'completed'
            log_entry.completed_at = datetime.utcnow()
            db.commit()

            logger.info(
                f"Live data retrain accepted: model #{model_id} -> #{new_model.id} "
                f"(AUC: {old_auc:.3f} -> {new_auc:.3f})"
            )

            return {
                'status': 'accepted',
                'old_model_id': model_id,
                'new_model_id': new_model.id,
                'old_auc': old_auc,
                'new_auc': new_auc,
                'backtest_trades': len(backtest_trades),
                'live_trades': len(live_trades),
                'combined_trades': len(combined),
            }

        except Exception as e:
            logger.error(f"Live data retrain failed: {e}", exc_info=True)
            try:
                log_entry.status = 'failed'
                log_entry.error_message = str(e)[:500]
                log_entry.completed_at = datetime.utcnow()
                db.commit()
            except Exception:
                pass
            return {'status': 'error', 'message': str(e)}
        finally:
            db.close()

    def get_live_trade_count(self, strategy_id: str, symbol: str, timeframe: str) -> dict:
        """
        Count live trades with ml_features for a strategy scope.

        Symbol is enforced directly in SQL. Strategy/timeframe are matched
        from feature metadata when present.
        """
        db = SessionLocal()
        try:
            trades = db.query(LiveTradeModel).filter(
                LiveTradeModel.ml_features.isnot(None),
                LiveTradeModel.symbol == symbol,
            ).all()

            count = 0
            for t in trades:
                ml_features = t.ml_features
                if isinstance(ml_features, str):
                    import json
                    try:
                        ml_features = json.loads(ml_features)
                    except Exception:
                        continue

                if self._live_trade_matches_scope(
                    strategy_id=strategy_id,
                    symbol=symbol,
                    timeframe=timeframe,
                    trade=t,
                    ml_features=ml_features,
                ):
                    count += 1

            return {
                'strategy_id': strategy_id,
                'symbol': symbol,
                'timeframe': timeframe,
                'live_trade_count': count,
                'threshold': self.LIVE_TRADE_THRESHOLD,
                'ready': count >= self.LIVE_TRADE_THRESHOLD,
            }
        finally:
            db.close()

    def _live_trade_matches_scope(
        self,
        strategy_id: str,
        symbol: str,
        timeframe: str,
        trade: LiveTradeModel,
        ml_features: Optional[Dict[str, Any]],
    ) -> bool:
        """
        Best-effort scope filtering for live trades.

        Older live records may not include strategy/timeframe metadata in
        ml_features. In those cases we keep the record (symbol-scoped) to
        avoid silently dropping historical data.
        """
        if (getattr(trade, 'symbol', None) or symbol) != symbol:
            return False

        if not isinstance(ml_features, dict):
            return True

        feature_strategy = (
            ml_features.get('strategy_id')
            or ml_features.get('ml_base_strategy_id')
        )
        if feature_strategy and feature_strategy != strategy_id:
            return False

        feature_timeframe = ml_features.get('timeframe')
        if feature_timeframe and feature_timeframe != timeframe:
            return False

        feature_symbol = ml_features.get('symbol')
        if feature_symbol and feature_symbol != symbol:
            return False

        return True

    def _query_backtest_trades(self, db, result_id: int) -> List[Dict[str, Any]]:
        """Query backtest trades and convert to dict format matching MLService."""
        if not result_id:
            return []

        trades = db.query(BacktestTradeModel).filter(
            BacktestTradeModel.result_id == result_id
        ).all()

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

        return trade_dicts

    def _query_live_trades(self, strategy_id: str, symbol: str,
                           timeframe: str) -> List[Dict[str, Any]]:
        """Overloaded: called without db, creates its own session."""
        db = SessionLocal()
        try:
            return self._query_live_trades_with_db(db, strategy_id, symbol, timeframe)
        finally:
            db.close()

    def _query_live_trades_with_db(self, db, strategy_id: str, symbol: str,
                                    timeframe: str) -> List[Dict[str, Any]]:
        """
        Query live trades with ml_features IS NOT NULL.
        Convert to same dict format as backtest trades.
        """
        trades = db.query(LiveTradeModel).filter(
            LiveTradeModel.ml_features.isnot(None),
            LiveTradeModel.symbol == symbol,
        ).all()

        trade_dicts = []
        for t in trades:
            # Parse ml_features from JSON
            ml_features = t.ml_features
            if isinstance(ml_features, str):
                import json
                try:
                    ml_features = json.loads(ml_features)
                except Exception:
                    continue

            if not self._live_trade_matches_scope(
                strategy_id=strategy_id,
                symbol=symbol,
                timeframe=timeframe,
                trade=t,
                ml_features=ml_features,
            ):
                continue

            # Compute r_multiple from trade data
            entry = t.entry_price or 0
            exit_p = t.exit_price or entry
            sl = t.stop_loss or entry
            sl_dist = abs(entry - sl) if entry and sl else 1.0
            if sl_dist == 0:
                sl_dist = 1.0
            pnl = t.profit_loss or 0
            # Approximate r_multiple from P&L direction
            if t.direction and t.direction.value == 'BUY':
                price_diff = exit_p - entry
            else:
                price_diff = entry - exit_p
            r_multiple = price_diff / sl_dist if sl_dist > 0 else 0

            trade_dicts.append({
                'trade_number': t.id,
                'direction': t.direction.value if t.direction else 'BUY',
                'entry_time': t.entry_time.isoformat() if t.entry_time else '',
                'exit_time': t.exit_time.isoformat() if t.exit_time else '',
                'entry_price': entry,
                'exit_price': exit_p,
                'stop_loss': sl,
                'profit_loss': pnl,
                'r_multiple': r_multiple,
                'setup_type': t.setup_type,
                'exit_reason': 'live',
                'ml_features': ml_features,
                'max_favorable_excursion': t.max_favorable_excursion or 0.0,
                'max_adverse_excursion': t.max_adverse_excursion or 0.0,
            })

        return trade_dicts
