"""
Backtest config parity and preset-key consumption tests.

Goals:
1) UI path and batch path must produce identical BacktestConfig.
2) Metric-driver fields must match for all strategy/preset/symbol cases.
3) Registry runtime keys must be consumed by engine or strategy code.
"""

from dataclasses import asdict
from datetime import datetime
import inspect
import re
from typing import Iterable, List, Tuple

import pytest

from dashboard.backend.core.backtest_engine import BacktestConfig
from dashboard.backend.core.config_builder import build_config_from_preset
from dashboard.backend.core.metrics_calculator import MetricsCalculator, TradeRecord
from dashboard.backend.core.strategies.base import BacktestStrategy
from dashboard.backend.core.strategies.factory import _ensure_registered, STRATEGY_CLASSES
from dashboard.backend.core.strategy_registry import StrategyRegistry
from dashboard.backend.models.database import BacktestConfigModel
from dashboard.backend.services.backtest_service import BacktestService


START_DATE = datetime(2024, 1, 1)
END_DATE = datetime(2024, 12, 31)


def _iter_registry_cases() -> Iterable[Tuple[str, str, str, str]]:
    """Yield (strategy_id, preset_id, symbol, timeframe)."""
    for strategy in StrategyRegistry.get_all_strategies():
        for preset in strategy.presets:
            symbols = list(preset.symbols) if preset.symbols else None
            if not symbols:
                symbols = strategy.optimal_parameters.get("symbols") or ["XAUUSD"]
            symbol = symbols[0]
            preset_cfg = StrategyRegistry.get_preset_config(strategy.id, preset.id, symbol)
            timeframe = preset_cfg.get("timeframe", "M1")
            yield strategy.id, preset.id, symbol, timeframe


CASES = list(_iter_registry_cases())


def _make_model(strategy_id: str, preset_id: str, symbol: str, timeframe: str) -> BacktestConfigModel:
    return BacktestConfigModel(
        name=f"parity-{strategy_id}-{preset_id}",
        strategy_id=strategy_id,
        preset_name=preset_id,
        symbol=symbol,
        timeframe=timeframe,
        start_date=START_DATE,
        end_date=END_DATE,
        initial_balance=10000.0,
        data_source="csv_only",
        csv_files=None,
    )


@pytest.mark.parametrize(
    "strategy_id,preset_id,symbol,timeframe",
    CASES,
    ids=[f"{s}:{p}:{sym}:{tf}" for s, p, sym, tf in CASES],
)
def test_ui_and_batch_paths_produce_identical_backtest_config(
    strategy_id: str,
    preset_id: str,
    symbol: str,
    timeframe: str,
) -> None:
    model = _make_model(strategy_id, preset_id, symbol, timeframe)
    ui_cfg = BacktestService._model_to_config(model)
    batch_cfg, _ = build_config_from_preset(
        strategy_id=strategy_id,
        preset_id=preset_id,
        symbol=symbol,
        timeframe=timeframe,
        start_date=START_DATE,
        end_date=END_DATE,
        initial_balance=10000.0,
        data_source="csv_only",
        csv_files=None,
        overrides=None,
    )
    assert asdict(ui_cfg) == asdict(batch_cfg)


@pytest.mark.parametrize(
    "strategy_id,preset_id,symbol,timeframe",
    CASES,
    ids=[f"{s}:{p}:{sym}:{tf}" for s, p, sym, tf in CASES],
)
def test_metric_driver_fields_match_between_ui_and_batch_paths(
    strategy_id: str,
    preset_id: str,
    symbol: str,
    timeframe: str,
) -> None:
    model = _make_model(strategy_id, preset_id, symbol, timeframe)
    ui_cfg = BacktestService._model_to_config(model)
    batch_cfg, _ = build_config_from_preset(
        strategy_id=strategy_id,
        preset_id=preset_id,
        symbol=symbol,
        timeframe=timeframe,
        start_date=START_DATE,
        end_date=END_DATE,
        initial_balance=10000.0,
        data_source="csv_only",
        csv_files=None,
        overrides=None,
    )

    key_fields = [
        "initial_balance",
        "risk_percent",
        "max_spread_usd",
        "min_sl_usd",
        "max_sl_usd",
        "min_fvg_gap",
        "slippage_atr_factor",
        "commission_per_lot",
        "swap_long_per_lot",
        "swap_short_per_lot",
        "enable_cross_asset_filter",
        "regime_signal_threshold",
        "regime_strong_threshold",
    ]
    assert {k: getattr(ui_cfg, k) for k in key_fields} == {
        k: getattr(batch_cfg, k) for k in key_fields
    }

    # Smoke check: matching configs should yield matching metrics on same trades.
    trades = [
        TradeRecord(
            trade_number=1,
            direction="BUY",
            entry_time=datetime(2024, 1, 2, 10, 0),
            exit_time=datetime(2024, 1, 2, 11, 0),
            entry_price=100.0,
            exit_price=110.0,
            stop_loss=95.0,
            take_profit=120.0,
            lot_size=1.0,
            profit_loss=100.0,
            balance_before=10000.0,
            balance_after=10100.0,
            r_multiple=2.0,
            gross_pnl=105.0,
            spread_cost=1.5,
            slippage_cost=0.5,
            commission_cost=2.0,
            swap_cost=-1.0,
        ),
        TradeRecord(
            trade_number=2,
            direction="SELL",
            entry_time=datetime(2024, 1, 3, 10, 0),
            exit_time=datetime(2024, 1, 3, 12, 0),
            entry_price=120.0,
            exit_price=125.0,
            stop_loss=126.0,
            take_profit=108.0,
            lot_size=1.0,
            profit_loss=-40.0,
            balance_before=10100.0,
            balance_after=10060.0,
            r_multiple=-0.8,
            gross_pnl=-36.0,
            spread_cost=1.0,
            slippage_cost=1.0,
            commission_cost=2.0,
            swap_cost=-2.0,
        ),
    ]
    eq_curve = [(t.exit_time, t.balance_after) for t in trades]
    ui_metrics = MetricsCalculator(ui_cfg.initial_balance).calculate_all_metrics(trades, eq_curve)
    batch_metrics = MetricsCalculator(batch_cfg.initial_balance).calculate_all_metrics(trades, eq_curve)
    for key in ("initial_balance", "final_balance", "net_profit", "profit_factor", "total_costs"):
        assert ui_metrics[key] == batch_metrics[key]


IGNORED_KEYS = {
    "symbols",
    "timeframes",
    "symbol",
    "timeframe",
    "preset",
    "initial_balance",
    # ML layer keys (consumed by ML engine/service layer)
    "use_ml_filter",
    "ml_min_win_probability",
    "use_ml_dynamic_rr",
    "ml_base_strategy_id",
    # Orderflow layer keys (consumed outside backtest strategy classes)
    "enable_orderflow_filter",
}
IGNORED_PREFIXES = ("orderflow_",)


def _consumed_strategy_keys(strategy_id: str) -> set[str]:
    """Read keys used via self.config.get(...) across strategy class MRO."""
    _ensure_registered()
    cls = STRATEGY_CLASSES[strategy_id]
    consumed: set[str] = set()

    for klass in cls.mro():
        if klass in (object, BacktestStrategy):
            continue
        try:
            source = inspect.getsource(klass)
        except OSError:
            continue
        consumed.update(
            re.findall(r"""self\.config\.get\(\s*['"]([^'"]+)['"]""", source)
        )
    return consumed


@pytest.mark.parametrize("strategy_id", [s.id for s in StrategyRegistry.get_all_strategies()])
def test_registry_runtime_keys_are_consumed_by_engine_or_strategy(strategy_id: str) -> None:
    strategy = StrategyRegistry.get_strategy(strategy_id)
    assert strategy is not None

    engine_keys = set(BacktestConfig.__dataclass_fields__.keys())
    strategy_keys = _consumed_strategy_keys(strategy_id)

    declared = set(strategy.optimal_parameters.keys())
    for preset in strategy.presets:
        declared.update(preset.parameters.keys())
    for symbol_overrides in strategy.instrument_overrides.values():
        declared.update(symbol_overrides.keys())

    missing: List[str] = []
    for key in sorted(declared):
        if key in IGNORED_KEYS or any(key.startswith(prefix) for prefix in IGNORED_PREFIXES):
            continue
        if key in engine_keys or key in strategy_keys:
            continue
        missing.append(key)

    assert not missing, (
        f"{strategy_id} has runtime keys not consumed by engine or strategy code: {missing}"
    )
