"""
Regression test: config_builder must honor contract_size override.
"""

from datetime import datetime

from dashboard.backend.core.config_builder import build_config_from_preset


def test_build_config_from_preset_honors_contract_size_override():
    config, _ = build_config_from_preset(
        strategy_id="orb_strategy",
        preset_id="default",
        symbol="XAUUSD",
        timeframe="M15",
        start_date=datetime(2024, 1, 1),
        end_date=datetime(2024, 1, 31),
        initial_balance=10_000.0,
        data_source="csv_only",
        overrides={"contract_size": 1.0},
    )
    assert config.contract_size == 1.0
