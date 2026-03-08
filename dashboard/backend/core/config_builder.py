"""
Shared BacktestConfig builder from strategy registry presets.

Both the batch_backtest.py script and the UI backtest_service.py should
use this module to ensure identical BacktestConfig objects for the same
preset + symbol combination.
"""
from datetime import datetime
from typing import Dict, Any, Optional, Tuple

from .backtest_engine import BacktestConfig
from .strategy_registry import StrategyRegistry
from .instrument_specs import get_instrument


def build_config_from_preset(
    strategy_id: str,
    preset_id: str,
    symbol: str,
    timeframe: str,
    start_date: datetime,
    end_date: datetime,
    initial_balance: float = 10000.0,
    data_source: str = "csv_only",
    csv_files: Optional[list] = None,
    overrides: Optional[Dict[str, Any]] = None,
) -> Tuple[BacktestConfig, Dict[str, Any]]:
    """Build a BacktestConfig from a registry preset + instrument specs.

    Returns (BacktestConfig, preset_config_dict) where the dict is the
    full strategy config to pass to ``create_strategy()``.

    Parameters
    ----------
    overrides : dict, optional
        Per-run overrides from the UI (DB model values that differ from preset).
        Only non-None values are applied.
    """
    preset_config = StrategyRegistry.get_preset_config(strategy_id, preset_id, symbol)
    inst = get_instrument(symbol)

    # Helper: read from overrides first, then preset, then fallback
    def _get(key, fallback):
        if overrides and key in overrides and overrides[key] is not None:
            return overrides[key]
        return preset_config.get(key, fallback)

    config = BacktestConfig(
        symbol=symbol,
        timeframe=timeframe,
        start_date=start_date,
        end_date=end_date,
        initial_balance=initial_balance,
        data_source=data_source,
        csv_files=csv_files,

        # Risk
        risk_percent=_get("risk_percent", 1.0),
        max_daily_loss_usd=_get("max_daily_loss_usd", -150.0),
        max_total_risk_usd=_get("max_total_risk_usd", 200.0),

        # Instrument-aware defaults (strategy/preset can override)
        contract_size=_get("contract_size", inst.contract_size),
        max_spread_usd=_get("max_spread_usd", inst.max_spread),
        min_sl_usd=_get("min_sl_usd", inst.min_sl),
        max_sl_usd=_get("max_sl_usd", inst.max_sl),
        gold_rr_threshold=_get("gold_rr_threshold", inst.rr_threshold),
        min_fvg_gap=_get("min_fvg_gap", inst.min_fvg_gap),
        commission_per_lot=_get("commission_per_lot", inst.commission_per_lot),
        swap_long_per_lot=_get("swap_long_per_lot", inst.swap_long),
        swap_short_per_lot=_get("swap_short_per_lot", inst.swap_short),
        triple_swap_day=inst.triple_swap_day,
        slippage_atr_factor=_get("slippage_atr_factor", inst.slippage_atr_factor),
        min_slippage_usd=_get("min_slippage_usd", inst.min_slippage),
        max_slippage_usd=_get("max_slippage_usd", inst.max_slippage),

        # Session times
        trade_start_time=_get("trade_start_time", "09:45"),
        trade_end_time=_get("trade_end_time", "16:00"),
        orb_start_time=_get("orb_start_time", "09:30"),
        orb_end_time=_get("orb_end_time", "09:45"),
        asian_start=_get("asian_start", "20:00"),
        asian_end=_get("asian_end", "02:00"),
        london_start=_get("london_start", "03:00"),
        london_end=_get("london_end", "12:00"),

        # Bias & trading limits
        bias_min_strength=_get("bias_min_strength", 30),
        max_daily_trades=_get("max_daily_trades", 2),
        stop_after_first_win=_get("stop_after_first_win", True),

        # Trailing stop
        use_trailing=_get("use_trailing", True),
        trailing_atr_period=_get("trailing_atr_period", 14),
        trailing_atr_multiplier=_get("trailing_atr_multiplier", 1.5),

        # Trend filter
        min_adr_for_trend=_get("min_adr_for_trend", 12.0),
        adr_period=_get("adr_period", 5),

        # Friday close
        close_before_weekend=_get("close_before_weekend", True),
        friday_close_hour=_get("friday_close_hour", 15),
        friday_close_minute=_get("friday_close_minute", 30),

        # ICT params
        fvg_lookback=_get("fvg_lookback", 50),
        displacement_percentile=_get("displacement_percentile", 75),
        displacement_lookback=_get("displacement_lookback", 20),
        max_opposing_wick_ratio=_get("max_opposing_wick_ratio", 0.4),
        ob_lookback=_get("ob_lookback", 100),
        ob_min_body_percent=_get("ob_min_body_percent", 60),
        ob_validation_bars=_get("ob_validation_bars", 3),
        liquidity_wick_ratio=_get("liquidity_wick_ratio", 0.6),
        sweep_tolerance_usd=_get("sweep_tolerance_usd", 0.20),

        # Simulation realism
        simulate_spread=_get("simulate_spread", True),
        use_variable_spread=_get("use_variable_spread", True),
        simulate_slippage=_get("simulate_slippage", True),
        simulate_swap=_get("simulate_swap", True),
        execution_mode=_get("execution_mode", "bar"),
        micro_latency_bars=_get("micro_latency_bars", 0),
        micro_base_fill_probability=_get("micro_base_fill_probability", 0.95),
        micro_min_fill_probability=_get("micro_min_fill_probability", 0.15),
        micro_partial_fill_min=_get("micro_partial_fill_min", 0.65),
        micro_partial_fill_max=_get("micro_partial_fill_max", 1.00),
        micro_min_volume=_get("micro_min_volume", 0.0),
        micro_spread_scale=_get("micro_spread_scale", 1.0),
        micro_slippage_scale=_get("micro_slippage_scale", 1.0),
        micro_adverse_selection_scale=_get("micro_adverse_selection_scale", 0.2),
        micro_max_extra_slippage_usd=_get("micro_max_extra_slippage_usd", 1.0),
        micro_flow_imbalance_col=_get("micro_flow_imbalance_col", "of_flow_imbalance"),
        micro_dom_imbalance_col=_get("micro_dom_imbalance_col", "dom_imbalance"),
        micro_absorption_col=_get("micro_absorption_col", "dom_absorption_score"),
        micro_lva_velocity_col=_get("micro_lva_velocity_col", "lva_velocity"),

        # Cross-asset regime filter
        enable_cross_asset_filter=_get("enable_cross_asset_filter", False),
        regime_timeframe=_get("regime_timeframe", "M15"),
        regime_lookback_bars=_get("regime_lookback_bars", 96),
        regime_return_bars=_get("regime_return_bars", 8),
        regime_signal_threshold=_get("regime_signal_threshold", 0.18),
        regime_strong_threshold=_get("regime_strong_threshold", 0.40),
        regime_block_countertrend=_get("regime_block_countertrend", True),
        regime_reduce_size_in_headwind=_get("regime_reduce_size_in_headwind", True),
        regime_tailwind_risk_multiplier=_get("regime_tailwind_risk_multiplier", 1.15),
        regime_headwind_risk_multiplier=_get("regime_headwind_risk_multiplier", 0.50),
        regime_neutral_risk_multiplier=_get("regime_neutral_risk_multiplier", 1.00),
        regime_symbol_dxy=_get("regime_symbol_dxy", "DXY,USDX,USDX.i"),
        regime_symbol_yield=_get("regime_symbol_yield", "US10Y,TNX,US10Y.cash"),
        regime_symbol_riskoff=_get("regime_symbol_riskoff", "VIX,VIX.cash,VOLX"),
        regime_symbol_riskon=_get("regime_symbol_riskon", "SPX500,US500,US30"),
        regime_weight_dxy=_get("regime_weight_dxy", 0.40),
        regime_weight_yield=_get("regime_weight_yield", 0.35),
        regime_weight_riskoff=_get("regime_weight_riskoff", 0.15),
        regime_weight_riskon=_get("regime_weight_riskon", 0.10),
        random_seed=_get("random_seed", 42),
    )

    # Strategy-level configuration must also receive run-time overrides.
    # Without this, only BacktestConfig fields change while strategy-specific
    # knobs (e.g. profile filters, orderflow gates) remain stuck at preset
    # defaults, making optimization and campaign overrides ineffective.
    strategy_config = dict(preset_config)
    if overrides:
        for key, value in overrides.items():
            if value is not None:
                strategy_config[key] = value

    return config, strategy_config
