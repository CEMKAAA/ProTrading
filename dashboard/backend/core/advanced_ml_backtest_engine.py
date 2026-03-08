"""
Advanced Event-Driven + ML Backtest Engine.

Combines AdvancedEventBacktestEngine orchestration with ML filtering logic.
"""

from __future__ import annotations

import logging
from typing import Dict, Any

from .advanced_backtest_engine import AdvancedEventBacktestEngine
from .ml_backtest_engine import MLBacktestConfig
from .ml_features import FeatureExtractor
from .ml_models import MLModelManager, ModelInfo

logger = logging.getLogger(__name__)


class AdvancedEventMLBacktestEngine(AdvancedEventBacktestEngine):
    """
    Event-driven backtest engine with ML trade filtering.
    """

    def __init__(self, config: MLBacktestConfig, strategy=None):
        super().__init__(config, strategy=strategy)
        self.ml_config = config

        self.model_manager = MLModelManager()
        self.ml_loaded = False

        self.ml_stats = {
            "total_setups_proposed": 0,
            "total_setups_taken": 0,
            "total_setups_filtered": 0,
            "avg_win_probability_taken": 0.0,
            "avg_win_probability_filtered": 0.0,
            "ml_model_loaded": False,
            "filtered_trades": [],
        }
        self._taken_probs = []
        self._filtered_probs = []

        self._load_ml_models()

    def _load_ml_models(self):
        strategy_id = self.ml_config.ml_base_strategy_id
        symbol = getattr(self.config, "symbol", None) or "XAUUSD"
        timeframe = getattr(self.config, "timeframe", None) or "M1"

        if self.ml_config.ml_model_id:
            self.ml_loaded = self._load_model_by_id(
                self.ml_config.ml_model_id, strategy_id
            )
        else:
            self.ml_loaded = self.model_manager.load_models(
                strategy_id, symbol=symbol, timeframe=timeframe
            )

        self.ml_stats["ml_model_loaded"] = self.ml_loaded
        if not self.ml_loaded:
            logger.warning(
                f"ML models not found for '{strategy_id}' ({symbol}/{timeframe}). "
                f"Running without ML filter."
            )

    def _load_model_by_id(self, model_id: int, strategy_id: str) -> bool:
        try:
            from ..models.database import MLModelRecord, SessionLocal

            db = SessionLocal()
            record = db.query(MLModelRecord).filter(
                MLModelRecord.id == model_id
            ).first()
            db.close()

            if not record:
                logger.warning(f"ML model ID {model_id} not found")
                return False

            model_info = ModelInfo(
                strategy_id=record.strategy_id,
                trained_at=record.trained_at.isoformat() if record.trained_at else "",
                total_trades=record.total_trades or 0,
                avg_accuracy=record.avg_accuracy or 0.0,
                avg_auc_roc=record.avg_auc_roc or 0.0,
                avg_f1=record.avg_f1 or 0.0,
                avg_rr_mae=record.avg_rr_mae or 0.0,
                feature_importance=record.feature_importance or {},
                filter_model_path=record.filter_model_path or "",
                rr_model_path=record.rr_model_path or "",
                metadata_path=record.metadata_path or "",
                folds=record.folds or [],
                model_type=getattr(record, "model_type", None) or "xgboost",
                symbol=getattr(record, "symbol", None) or "XAUUSD",
                timeframe=getattr(record, "timeframe", None) or "M1",
            )
            loaded = self.model_manager.load_models(strategy_id, model_info=model_info)
            if loaded:
                logger.info(
                    f"Loaded specific ML model #{model_id} "
                    f"({model_info.model_type}, AUC={model_info.avg_auc_roc:.3f})"
                )
            return loaded
        except Exception as e:
            logger.error(f"Failed to load ML model #{model_id}: {e}")
            return False

    def _execute_trade(self, setup: Dict[str, Any], bar):
        """
        Override: Apply ML filter before executing trade.
        """
        self.ml_stats["total_setups_proposed"] += 1

        if self.ml_loaded and self.ml_config.use_ml_filter:
            try:
                direction = setup["direction"]
                sl = setup["sl"]
                base_entry = bar["open"]
                spread_estimate = self.config.max_spread_usd / 2 if self.config.simulate_spread else 0.0

                sl_distance = abs(base_entry - sl)
                sl_distance = max(self.config.min_sl_usd, min(self.config.max_sl_usd, sl_distance))
                rr_ratio = 3.0 if sl_distance < self.config.gold_rr_threshold else 2.0

                # Pass df slice for V2/V3 features
                df_slice = None
                if hasattr(self, '_df') and hasattr(self, '_current_global_pos'):
                    df_slice = self._df.iloc[:self._current_global_pos]

                features = FeatureExtractor.extract(
                    day_state=self.day_state,
                    setup=setup,
                    bar=bar,
                    config=self.config,
                    balance=self.balance,
                    spread=spread_estimate * 2,
                    entry_price=base_entry,
                    sl_distance=sl_distance,
                    rr_ratio=rr_ratio,
                    df=df_slice,
                    recent_results=self._recent_trade_results,
                )

                win_prob, _ = self.model_manager.predict_trade_filter(
                    self.ml_config.ml_base_strategy_id, features
                )

                if win_prob < self.ml_config.ml_min_win_probability:
                    self.ml_stats["total_setups_filtered"] += 1
                    self._filtered_probs.append(win_prob)
                    self.ml_stats["filtered_trades"].append(
                        {
                            "time": bar.name.isoformat() if hasattr(bar.name, "isoformat") else str(bar.name),
                            "direction": direction,
                            "win_probability": round(win_prob, 4),
                            "threshold": self.ml_config.ml_min_win_probability,
                            "setup_type": setup.get("setup_type", "unknown"),
                        }
                    )
                    return

                self._taken_probs.append(win_prob)
            except Exception as e:
                logger.warning(f"ML filter prediction failed, taking trade anyway: {e}")

        super()._execute_trade(setup, bar)
        if self.open_position is not None:
            self.ml_stats["total_setups_taken"] += 1

        if (
            self.ml_loaded
            and self.ml_config.use_ml_dynamic_rr
            and self.open_position is not None
        ):
            try:
                features = FeatureExtractor.from_dict(self.open_position.ml_features)
                suggested_rr, _ = self.model_manager.predict_optimal_rr(
                    self.ml_config.ml_base_strategy_id, features
                )

                pos = self.open_position
                risk = abs(pos.entry_price - pos.stop_loss)
                current_rr = abs(pos.take_profit - pos.entry_price) / risk if risk > 0 else 2.0

                if abs(suggested_rr - current_rr) > 0.3:
                    sl_dist = abs(pos.entry_price - pos.stop_loss)
                    if pos.direction == "BUY":
                        pos.take_profit = pos.entry_price + sl_dist * suggested_rr
                    else:
                        pos.take_profit = pos.entry_price - sl_dist * suggested_rr
            except Exception as e:
                logger.warning(f"ML R:R override failed: {e}")

    def _compile_results(self) -> Dict[str, Any]:
        results = super()._compile_results()
        if self._taken_probs:
            self.ml_stats["avg_win_probability_taken"] = round(
                sum(self._taken_probs) / len(self._taken_probs), 4
            )
        if self._filtered_probs:
            self.ml_stats["avg_win_probability_filtered"] = round(
                sum(self._filtered_probs) / len(self._filtered_probs), 4
            )
        results["ml_stats"] = self.ml_stats
        return results

