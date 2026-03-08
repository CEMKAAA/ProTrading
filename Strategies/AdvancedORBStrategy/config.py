"""
Advanced ORB Strategy Configuration
With runtime refresh capability and dynamic parameter support
"""

import MetaTrader5 as mt5
from datetime import time
from pathlib import Path
import json
from typing import Any, Optional, Tuple
from dataclasses import dataclass, field
from threading import Lock

# ================= STRATEGY IDENTITY =================
STRATEGY_ID = "advanced_orb_strategy"
STRATEGY_NAME = "Advanced Gold ORB + ICT Strategy"
STRATEGY_VERSION = "1.0.0"
TARGET_SYMBOL = "XAUUSD"  # Default; overridden at runtime from config JSON
TIMEFRAME = mt5.TIMEFRAME_M1
MAGIC_NUMBER = 777003  # Unique magic for this strategy

# Config file path
_CONFIG_FILE = Path(__file__).parent.parent.parent / "dashboard" / "data" / "advanced_orb_strategy_config.json"


def get_runtime_symbol() -> str:
    """Read the symbol from the runtime config JSON (set by dashboard)."""
    try:
        if _CONFIG_FILE.exists():
            with open(_CONFIG_FILE, 'r') as f:
                data = json.load(f)
            sym = data.get("symbol", TARGET_SYMBOL)
            if isinstance(sym, str) and sym.strip():
                return sym.strip()
    except Exception:
        pass
    return TARGET_SYMBOL
_config_lock = Lock()


@dataclass
class StrategyConfig:
    """
    Strategy configuration with defaults.
    Use get_config() to access - never read directly for runtime values.
    """
    # Risk Management
    risk_percent: float = 1.0
    max_spread_usd: float = 0.40
    max_daily_loss_usd: float = -150.0
    max_total_risk_usd: float = 200.0
    max_daily_trades: int = 3
    stop_after_first_win: bool = False
    initial_balance: float = 10000.0

    # Slippage Protection
    max_slippage_points: int = 10  # Max deviation for order execution
    fill_quality_warn_usd: float = 0.50   # Log WARNING above this slippage
    fill_quality_critical_usd: float = 1.00  # Log CRITICAL above this slippage

    # Commission and Fees (per lot, round trip)
    commission_per_lot: float = 7.0  # Typical broker commission
    estimated_slippage_usd: float = 0.10  # Conservative slippage estimate

    # Stop Loss Parameters
    min_sl_usd: float = 1.00
    max_sl_usd: float = 8.00
    rr_threshold_for_2r: float = 3.00  # Threshold separating tight/wide stop regimes
    rr_tight_sl_target: float = 3.40
    rr_wide_sl_target: float = 2.50
    min_rr_target: float = 2.20
    max_spread_to_sl_ratio: float = 0.30

    # Partial Profit Settings
    enable_partial_tp: bool = True
    partial_tp_percent: int = 50  # Close 50% at first target
    first_tp_rr: float = 1.0  # First target at 1R
    final_tp_rr: float = 2.0  # Let remainder run to 2R

    # Adaptive ORB Settings
    use_adaptive_orb: bool = True
    orb_min_range_usd: float = 0.50  # Minimum valid ORB range
    orb_extend_threshold_usd: float = 1.50  # Extend ORB if range below this
    orb_max_extension_minutes: int = 15  # Max extension (to 10:00)

    # Session Times (NY Timezone)
    orb_start_hour: int = 9
    orb_start_minute: int = 30
    orb_end_hour: int = 9
    orb_end_minute: int = 45
    trade_start_hour: int = 9
    trade_start_minute: int = 45
    trade_end_hour: int = 16
    trade_end_minute: int = 0

    # Asian Session
    asian_start_hour: int = 20
    asian_start_minute: int = 0
    asian_end_hour: int = 2
    asian_end_minute: int = 0

    # London Session
    london_start_hour: int = 3
    london_start_minute: int = 0
    london_end_hour: int = 12
    london_end_minute: int = 0

    # Broker Timezone Offset (hours from UTC)
    # Set to None for auto-detection, or explicit value
    broker_utc_offset: Optional[int] = None

    # ICT Parameters - Dynamic FVG (scales with ATR)
    fvg_atr_multiplier: float = 0.15  # min_fvg = atr * this
    fvg_min_absolute: float = 0.20  # Absolute minimum gap
    fvg_lookback: int = 50

    # ICT Parameters - Displacement
    displacement_percentile: int = 82
    displacement_lookback: int = 20
    max_opposing_wick_ratio: float = 0.32

    # ICT Parameters - Order Blocks
    ob_lookback: int = 100
    ob_min_body_percent: int = 60
    ob_validation_bars: int = 3
    ob_cache_ttl_bars: int = 5  # Recalculate every N new bars

    # ICT Parameters - Liquidity
    use_liquidity_sweeps: bool = True
    liquidity_wick_ratio: float = 0.6
    sweep_tolerance_usd: float = 0.20
    liquidity_lookback: int = 50

    # Bias Strength Settings
    bias_min_strength: int = 30  # Minimum strength (0-100) to take trades
    bias_strong_threshold: int = 70  # Above this = strong bias

    # Trailing Stop
    use_trailing: bool = True
    trailing_atr_period: int = 14
    trailing_atr_multiplier: float = 1.5
    move_to_breakeven_at_rr: float = 0.5  # Move SL to entry at 0.5R profit
    adaptive_trailing: bool = True
    adaptive_trailing_low_vol_factor: float = 0.8   # Tighter trail in low vol
    adaptive_trailing_high_vol_factor: float = 1.3  # Wider trail in high vol

    # Trend Filter
    min_adr_for_trend: float = 20.0
    adr_period: int = 5
    use_ma_confirmation: bool = True
    ma_period: int = 50

    # Cross-Asset Regime Filter
    enable_cross_asset_filter: bool = False
    regime_timeframe: str = "M15"
    regime_lookback_bars: int = 96
    regime_return_bars: int = 8
    regime_signal_threshold: float = 0.18
    regime_strong_threshold: float = 0.40
    regime_block_countertrend: bool = True
    regime_reduce_size_in_headwind: bool = True
    regime_tailwind_risk_multiplier: float = 1.15
    regime_headwind_risk_multiplier: float = 0.50
    regime_neutral_risk_multiplier: float = 1.00
    regime_symbol_dxy: str = "DXY,USDX,USDX.i"
    regime_symbol_yield: str = "US10Y,TNX,US10Y.cash"
    regime_symbol_riskoff: str = "VIX,VIX.cash,VOLX"
    regime_symbol_riskon: str = "SPX500,US500,US30"
    regime_weight_dxy: float = 0.40
    regime_weight_yield: float = 0.35
    regime_weight_riskoff: float = 0.15
    regime_weight_riskon: float = 0.10
    regime_eval_interval_seconds: int = 30

    # Databento Orderflow Filter
    enable_orderflow_filter: bool = False
    orderflow_eval_interval_seconds: int = 60
    orderflow_lookback_minutes: int = 5
    orderflow_min_trades: int = 30
    orderflow_signal_threshold: float = 0.15
    orderflow_block_countertrend: bool = True
    orderflow_reduce_size_in_headwind: bool = True
    orderflow_tailwind_risk_multiplier: float = 1.05
    orderflow_headwind_risk_multiplier: float = 0.80
    orderflow_neutral_risk_multiplier: float = 1.00
    orderflow_dataset: str = "GLBX.MDP3"
    orderflow_schema: str = "trades"
    orderflow_stype_in: str = "raw_symbol"
    orderflow_symbol: str = "GC.c.0"

    # Trade Management
    max_trades_after_win: int = 2  # Allow 2 more trades after first win
    tighten_risk_after_win: bool = True  # Reduce size after win to protect daily gains
    risk_reduction_factor: float = 0.75  # If enabled, mild reduction only

    # End of Session Management
    close_positions_at_session_end: bool = True
    session_end_close_minutes_before: int = 15  # Close 15 min before trade_end

    # Circuit Breaker
    cb_max_consecutive_losses: int = 5
    cb_max_consecutive_errors: int = 5
    cb_error_window_seconds: int = 300
    cb_max_errors_in_window: int = 10
    cb_cooldown_seconds: int = 180
    cb_max_avg_slippage_usd: float = 1.20

    # Data Management
    data_cache_bars: int = 5000
    min_bars_for_analysis: int = 200
    cache_refresh_interval_bars: int = 100  # Force refresh every N bars

    # Logging
    log_file: str = 'advanced_orb_bot.log'
    log_max_bytes: int = 5 * 1024 * 1024
    log_backup_count: int = 5

    def to_dict(self) -> dict:
        """Convert config to dictionary"""
        return {k: v for k, v in self.__dict__.items() if not k.startswith('_')}


# Singleton config instance
_config_instance: Optional[StrategyConfig] = None
_last_load_time: float = 0


def _to_float(value: Any, default: float) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return float(default)


def _to_int(value: Any, default: int) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return int(default)


def _to_bool(value: Any, default: bool) -> bool:
    if value is None:
        return bool(default)
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        v = value.strip().lower()
        if v in ("1", "true", "yes", "on"):
            return True
        if v in ("0", "false", "no", "off"):
            return False
    return bool(value)


def _parse_hhmm(value: Any, default_hour: int, default_minute: int) -> Tuple[int, int]:
    if isinstance(value, str):
        text = value.strip()
        try:
            hh, mm = map(int, text.split(":"))
            if 0 <= hh <= 23 and 0 <= mm <= 59:
                return hh, mm
        except (TypeError, ValueError):
            pass
    return default_hour, default_minute


def _get_with_aliases(raw: dict, primary: str, aliases: list[str], default: Any) -> Any:
    if primary in raw:
        return raw[primary]
    for alias in aliases:
        if alias in raw:
            return raw[alias]
    return default


def load_config(force_refresh: bool = False) -> StrategyConfig:
    """
    Load configuration from file with caching.

    Args:
        force_refresh: Force reload from file even if cached

    Returns:
        StrategyConfig instance
    """
    global _config_instance, _last_load_time

    import time as time_module
    current_time = time_module.time()

    # Return cached if recent and not forcing refresh
    if not force_refresh and _config_instance is not None:
        if current_time - _last_load_time < 5:  # 5 second cache
            return _config_instance

    with _config_lock:
        config = StrategyConfig()

        if _CONFIG_FILE.exists():
            try:
                with open(_CONFIG_FILE, 'r') as f:
                    file_config = json.load(f)
                if not isinstance(file_config, dict):
                    file_config = {}

                # Core numeric/boolean aliases for dashboard + legacy compatibility.
                config.risk_percent = _to_float(
                    _get_with_aliases(file_config, "risk_percent", [], config.risk_percent),
                    config.risk_percent,
                )
                config.max_spread_usd = _to_float(
                    _get_with_aliases(file_config, "max_spread_usd", ["max_spread"], config.max_spread_usd),
                    config.max_spread_usd,
                )
                max_daily_loss = _to_float(
                    _get_with_aliases(file_config, "max_daily_loss_usd", ["max_daily_loss"], abs(config.max_daily_loss_usd)),
                    abs(config.max_daily_loss_usd),
                )
                config.max_daily_loss_usd = -abs(max_daily_loss)
                config.max_total_risk_usd = _to_float(
                    _get_with_aliases(file_config, "max_total_risk_usd", ["max_total_risk"], config.max_total_risk_usd),
                    config.max_total_risk_usd,
                )
                config.max_daily_trades = _to_int(
                    _get_with_aliases(file_config, "max_daily_trades", [], config.max_daily_trades),
                    config.max_daily_trades,
                )
                config.initial_balance = _to_float(
                    _get_with_aliases(file_config, "initial_balance", [], config.initial_balance),
                    config.initial_balance,
                )

                config.min_sl_usd = _to_float(
                    _get_with_aliases(file_config, "min_sl_usd", ["min_sl"], config.min_sl_usd),
                    config.min_sl_usd,
                )
                config.max_sl_usd = _to_float(
                    _get_with_aliases(file_config, "max_sl_usd", ["max_sl"], config.max_sl_usd),
                    config.max_sl_usd,
                )
                config.rr_threshold_for_2r = _to_float(
                    _get_with_aliases(
                        file_config,
                        "rr_threshold_for_2r",
                        ["gold_rr_threshold", "rr_threshold"],
                        config.rr_threshold_for_2r,
                    ),
                    config.rr_threshold_for_2r,
                )

                config.stop_after_first_win = _to_bool(
                    _get_with_aliases(file_config, "stop_after_first_win", ["stop_on_first_win"], config.stop_after_first_win),
                    config.stop_after_first_win,
                )
                config.enable_cross_asset_filter = _to_bool(
                    _get_with_aliases(file_config, "enable_cross_asset_filter", [], config.enable_cross_asset_filter),
                    config.enable_cross_asset_filter,
                )
                config.max_trades_after_win = _to_int(
                    _get_with_aliases(file_config, "max_trades_after_win", [], config.max_trades_after_win),
                    config.max_trades_after_win,
                )
                config.regime_symbol_yield = str(
                    _get_with_aliases(file_config, "regime_symbol_yield", ["regime_symbol_us10y"], config.regime_symbol_yield)
                )
                config.orderflow_symbol = str(
                    _get_with_aliases(file_config, "orderflow_symbol", ["databento_symbol"], config.orderflow_symbol)
                )

                # Dashboard uses min_fvg_gap naming; advanced live uses fvg_min_absolute baseline.
                config.fvg_min_absolute = _to_float(
                    _get_with_aliases(file_config, "fvg_min_absolute", ["min_fvg_gap"], config.fvg_min_absolute),
                    config.fvg_min_absolute,
                )

                # Apply direct keys for all remaining dataclass fields.
                for key, value in file_config.items():
                    if hasattr(config, key):
                        setattr(config, key, value)

                # Time aliases from dashboard string format (HH:MM) to hour/minute fields.
                orb_start_h, orb_start_m = _parse_hhmm(
                    _get_with_aliases(file_config, "orb_start_time", [], f"{config.orb_start_hour:02d}:{config.orb_start_minute:02d}"),
                    config.orb_start_hour,
                    config.orb_start_minute,
                )
                orb_end_h, orb_end_m = _parse_hhmm(
                    _get_with_aliases(file_config, "orb_end_time", [], f"{config.orb_end_hour:02d}:{config.orb_end_minute:02d}"),
                    config.orb_end_hour,
                    config.orb_end_minute,
                )
                trade_start_h, trade_start_m = _parse_hhmm(
                    _get_with_aliases(file_config, "trade_start_time", [], f"{config.trade_start_hour:02d}:{config.trade_start_minute:02d}"),
                    config.trade_start_hour,
                    config.trade_start_minute,
                )
                trade_end_h, trade_end_m = _parse_hhmm(
                    _get_with_aliases(file_config, "trade_end_time", [], f"{config.trade_end_hour:02d}:{config.trade_end_minute:02d}"),
                    config.trade_end_hour,
                    config.trade_end_minute,
                )
                asian_start_h, asian_start_m = _parse_hhmm(
                    _get_with_aliases(
                        file_config,
                        "asian_start_time",
                        ["asian_start"],
                        f"{config.asian_start_hour:02d}:{config.asian_start_minute:02d}",
                    ),
                    config.asian_start_hour,
                    config.asian_start_minute,
                )
                asian_end_h, asian_end_m = _parse_hhmm(
                    _get_with_aliases(
                        file_config,
                        "asian_end_time",
                        ["asian_end"],
                        f"{config.asian_end_hour:02d}:{config.asian_end_minute:02d}",
                    ),
                    config.asian_end_hour,
                    config.asian_end_minute,
                )
                london_start_h, london_start_m = _parse_hhmm(
                    _get_with_aliases(
                        file_config,
                        "london_start_time",
                        ["london_start"],
                        f"{config.london_start_hour:02d}:{config.london_start_minute:02d}",
                    ),
                    config.london_start_hour,
                    config.london_start_minute,
                )
                london_end_h, london_end_m = _parse_hhmm(
                    _get_with_aliases(
                        file_config,
                        "london_end_time",
                        ["london_end"],
                        f"{config.london_end_hour:02d}:{config.london_end_minute:02d}",
                    ),
                    config.london_end_hour,
                    config.london_end_minute,
                )

                config.orb_start_hour, config.orb_start_minute = orb_start_h, orb_start_m
                config.orb_end_hour, config.orb_end_minute = orb_end_h, orb_end_m
                config.trade_start_hour, config.trade_start_minute = trade_start_h, trade_start_m
                config.trade_end_hour, config.trade_end_minute = trade_end_h, trade_end_m
                config.asian_start_hour, config.asian_start_minute = asian_start_h, asian_start_m
                config.asian_end_hour, config.asian_end_minute = asian_end_h, asian_end_m
                config.london_start_hour, config.london_start_minute = london_start_h, london_start_m
                config.london_end_hour, config.london_end_minute = london_end_h, london_end_m

                # Final normalization (guards against mixed/legacy payloads).
                config.max_daily_loss_usd = -abs(_to_float(config.max_daily_loss_usd, -150.0))
                config.max_daily_trades = max(1, _to_int(config.max_daily_trades, 3))
                config.max_trades_after_win = max(0, _to_int(config.max_trades_after_win, 0))
                config.stop_after_first_win = _to_bool(config.stop_after_first_win, False)
                config.min_sl_usd = max(0.01, _to_float(config.min_sl_usd, 1.0))
                config.max_sl_usd = max(config.min_sl_usd, _to_float(config.max_sl_usd, 8.0))
                config.rr_threshold_for_2r = _to_float(config.rr_threshold_for_2r, 3.0)
                config.rr_tight_sl_target = _to_float(config.rr_tight_sl_target, 3.4)
                config.rr_wide_sl_target = _to_float(config.rr_wide_sl_target, 2.5)
                config.min_rr_target = _to_float(config.min_rr_target, 2.2)
                config.max_spread_to_sl_ratio = max(0.0, _to_float(config.max_spread_to_sl_ratio, 0.30))

            except Exception as e:
                print(f"[CONFIG] Error loading config: {e}, using defaults")

        # Log on first load so users can verify the correct preset was applied.
        is_first_load = _config_instance is None or force_refresh
        _config_instance = config
        _last_load_time = current_time

        if is_first_load:
            _runtime_sym = get_runtime_symbol()
            print(f"[CONFIG] AdvancedORB loaded config: "
                  f"symbol={_runtime_sym}, "
                  f"risk={config.risk_percent}%, "
                  f"bias_min={config.bias_min_strength}, "
                  f"max_daily_trades={config.max_daily_trades}, "
                  f"stop_after_win={config.stop_after_first_win}, "
                  f"rr_threshold={config.rr_threshold_for_2r}, "
                  f"rr_tight={config.rr_tight_sl_target}, "
                  f"rr_wide={config.rr_wide_sl_target}, "
                  f"min_rr={config.min_rr_target}, "
                  f"max_daily_loss={config.max_daily_loss_usd}, "
                  f"max_total_risk={config.max_total_risk_usd}, "
                  f"spread_max={config.max_spread_usd}, "
                  f"displacement_pct={config.displacement_percentile}, "
                  f"max_wick_ratio={config.max_opposing_wick_ratio}, "
                  f"fvg_lookback={config.fvg_lookback}, "
                  f"SL_range=[{config.min_sl_usd}-{config.max_sl_usd}]")

    return config


def get_config() -> StrategyConfig:
    """Get current configuration (with auto-refresh)"""
    return load_config()


def save_config(config: StrategyConfig) -> bool:
    """Save configuration to file"""
    try:
        _CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)

        with _config_lock:
            with open(_CONFIG_FILE, 'w') as f:
                json.dump(config.to_dict(), f, indent=2)
        return True
    except Exception as e:
        print(f"[CONFIG] Error saving config: {e}")
        return False


def get_orb_start_time() -> time:
    """Get ORB start time"""
    cfg = get_config()
    return time(cfg.orb_start_hour, cfg.orb_start_minute)


def get_orb_end_time() -> time:
    """Get ORB end time"""
    cfg = get_config()
    return time(cfg.orb_end_hour, cfg.orb_end_minute)


def get_trade_start_time() -> time:
    """Get trade start time"""
    cfg = get_config()
    return time(cfg.trade_start_hour, cfg.trade_start_minute)


def get_trade_end_time() -> time:
    """Get trade end time"""
    cfg = get_config()
    return time(cfg.trade_end_hour, cfg.trade_end_minute)


def get_asian_session() -> tuple:
    """Get Asian session times"""
    cfg = get_config()
    return (
        time(cfg.asian_start_hour, cfg.asian_start_minute),
        time(cfg.asian_end_hour, cfg.asian_end_minute)
    )


def get_london_session() -> tuple:
    """Get London session times"""
    cfg = get_config()
    return (
        time(cfg.london_start_hour, cfg.london_start_minute),
        time(cfg.london_end_hour, cfg.london_end_minute)
    )
