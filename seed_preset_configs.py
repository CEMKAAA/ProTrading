"""
Seed script: Delete all existing backtest configs and create 33 preset configurations
(3 presets x 11 strategies) with pro trader parameters from strategy_registry.

Usage:
    python seed_preset_configs.py
"""

import sys
import os

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from datetime import datetime
from dashboard.backend.models.database import (
    engine, SessionLocal, Base,
    BacktestConfigModel, BacktestResultModel, BacktestTradeModel,
)
from dashboard.backend.core.strategy_registry import StrategyRegistry


# Columns that exist on BacktestConfigModel (excluding id, created_at, results)
CONFIG_COLUMNS = {
    "name", "description", "strategy_id", "preset_name",
    "symbol", "timeframe",
    "start_date", "end_date",
    "initial_balance", "risk_percent",
    "max_spread_usd", "max_daily_loss_usd", "max_total_risk_usd",
    "contract_size",
    "simulate_spread", "use_variable_spread",
    "simulate_slippage", "slippage_atr_factor",
    "min_slippage_usd", "max_slippage_usd", "avg_slippage_usd",
    "commission_per_lot",
    "simulate_swap", "swap_long_per_lot", "swap_short_per_lot", "triple_swap_day",
    "bias_min_strength",
    "close_before_weekend", "friday_close_hour", "friday_close_minute",
    "min_sl_usd", "max_sl_usd", "gold_rr_threshold",
    "min_fvg_gap", "fvg_lookback",
    "displacement_percentile", "displacement_lookback", "max_opposing_wick_ratio",
    "ob_lookback", "ob_min_body_percent", "ob_validation_bars",
    "liquidity_wick_ratio", "sweep_tolerance_usd",
    "orb_start_time", "orb_end_time", "trade_start_time", "trade_end_time",
    "asian_start", "asian_end",
    "london_start", "london_end",
    "use_trailing", "trailing_atr_period", "trailing_atr_multiplier",
    "min_adr_for_trend", "adr_period",
    "max_daily_trades",
    "data_source", "csv_files",
    "use_ml_filter", "ml_min_win_probability", "use_ml_dynamic_rr",
    "ml_base_strategy_id", "ml_model_id",
}

PRESET_IDS = ["conservative", "default", "aggressive"]
PRESET_LABELS = {
    "conservative": "Conservative",
    "default": "Default",
    "aggressive": "Aggressive",
}


def main():
    # Ensure tables exist
    Base.metadata.create_all(bind=engine)

    db = SessionLocal()
    try:
        # --- Step 1: Delete all existing data (respecting FK order) ---
        trade_count = db.query(BacktestTradeModel).count()
        result_count = db.query(BacktestResultModel).count()
        config_count = db.query(BacktestConfigModel).count()

        print(f"Deleting {trade_count} trades, {result_count} results, {config_count} configs...")

        db.query(BacktestTradeModel).delete()
        db.query(BacktestResultModel).delete()
        db.query(BacktestConfigModel).delete()
        db.commit()
        print("All existing configurations deleted.")

        # --- Step 2: Create 33 preset configs ---
        strategies = StrategyRegistry.get_all_strategies()
        created = 0

        for strategy in strategies:
            for preset_id in PRESET_IDS:
                # Get full config from registry (defaults + optimal + preset overrides)
                config = strategy.get_preset_config(preset_id)

                # Find preset description
                preset_desc = ""
                for p in strategy.presets:
                    if p.id == preset_id:
                        preset_desc = p.description
                        break

                # Build DB record kwargs from config, only using known columns
                kwargs = {}
                for key, value in config.items():
                    if key in CONFIG_COLUMNS:
                        kwargs[key] = value

                # Set metadata fields
                kwargs["name"] = f"{strategy.name} - {PRESET_LABELS[preset_id]}"
                kwargs["description"] = preset_desc
                kwargs["strategy_id"] = strategy.id
                kwargs["preset_name"] = preset_id

                # Placeholder date range
                kwargs["start_date"] = datetime(2025, 1, 1)
                kwargs["end_date"] = datetime(2025, 12, 31)

                record = BacktestConfigModel(**kwargs)
                db.add(record)
                created += 1
                print(f"  Created: {kwargs['name']}")

        db.commit()
        print(f"\nDone! Created {created} preset configurations ({len(strategies)} strategies x {len(PRESET_IDS)} presets).")

    except Exception as e:
        db.rollback()
        print(f"Error: {e}")
        raise
    finally:
        db.close()


if __name__ == "__main__":
    main()
