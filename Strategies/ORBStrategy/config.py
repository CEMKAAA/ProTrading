"""
ORB Strategy Configuration
All parameters centralized for easy tuning and backtesting
"""

import MetaTrader5 as mt5
from datetime import time
from pathlib import Path
import json

# ================= SYMBOL & TIMEFRAME =================
TARGET_SYMBOL = "XAUUSD"  # Default; overridden at runtime from config JSON
MAGIC_NUMBER = 777001
STRATEGY_ID = "orb_strategy"
STRATEGY_NAME = "Gold ORB + ICT Strategy"
STRATEGY_VERSION = "2.0.0"

# ================= RUNTIME CONFIG =================
# Load runtime config from dashboard if available
_RUNTIME_CONFIG = {}
_CONFIG_FILE = Path(__file__).parent.parent.parent / "dashboard" / "data" / "orb_strategy_config.json"


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

# Backward/forward-compatible key aliases between live strategy and dashboard config
_CONFIG_ALIASES = {
    "max_spread_usd": ["max_spread"],
    "max_daily_loss_usd": ["max_daily_loss"],
    "max_total_risk_usd": ["max_total_risk"],
    "min_sl_usd": ["min_sl"],
    "max_sl_usd": ["max_sl"],
    "gold_rr_threshold": ["rr_threshold"],
    "stop_after_first_win": ["stop_on_first_win"],
    "regime_symbol_yield": ["regime_symbol_us10y"],
    "orderflow_symbol": ["databento_symbol"],
}

def load_runtime_config():
    """Load runtime configuration from dashboard"""
    global _RUNTIME_CONFIG
    if _CONFIG_FILE.exists():
        try:
            with open(_CONFIG_FILE, 'r') as f:
                _RUNTIME_CONFIG = json.load(f)
                print(f"[CONFIG] Loaded runtime config: {_RUNTIME_CONFIG}")
        except Exception as e:
            print(f"[CONFIG] Error loading runtime config: {e}")
    return _RUNTIME_CONFIG

def get_config(key: str, default):
    """Get config value with runtime override"""
    if not _RUNTIME_CONFIG:
        load_runtime_config()
    if key in _RUNTIME_CONFIG:
        return _RUNTIME_CONFIG[key]
    for alias in _CONFIG_ALIASES.get(key, []):
        if alias in _RUNTIME_CONFIG:
            return _RUNTIME_CONFIG[alias]
    return default


def _to_float(value, default):
    try:
        return float(value)
    except (TypeError, ValueError):
        return float(default)


def _to_int(value, default):
    try:
        return int(value)
    except (TypeError, ValueError):
        return int(default)


def _to_bool(value, default):
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


def _parse_hhmm(value, default_hhmm):
    text = value if isinstance(value, str) else default_hhmm
    try:
        hh, mm = map(int, text.split(":"))
        return time(hh, mm)
    except (ValueError, AttributeError):
        hh, mm = map(int, default_hhmm.split(":"))
        return time(hh, mm)

# Load config on module import
load_runtime_config()

# ================= RISK MANAGEMENT =================
RISK_PERCENT = _to_float(get_config('risk_percent', 1.0), 1.0)  # Risk per trade as % of balance
MAX_SPREAD_USD = _to_float(get_config('max_spread_usd', 0.40), 0.40)  # Max spread to allow trade execution
MAX_DAILY_LOSS_USD = -abs(_to_float(get_config('max_daily_loss_usd', 150.0), 150.0))  # Stop trading after this loss
MAX_TOTAL_RISK_USD = _to_float(get_config('max_total_risk_usd', 200.0), 200.0)  # Max cumulative open position risk
MAX_DAILY_TRADES = _to_int(get_config('max_daily_trades', 3), 3)  # Maximum trades per day
INITIAL_BALANCE = _to_float(get_config('initial_balance', 10000.0), 10000.0)  # Starting balance for position sizing
STOP_AFTER_FIRST_WIN = _to_bool(get_config('stop_after_first_win', False), False)
TIGHTEN_RISK_AFTER_WIN = _to_bool(get_config('tighten_risk_after_win', True), True)  # Reduce size after win
RISK_REDUCTION_FACTOR = _to_float(get_config('risk_reduction_factor', 0.75), 0.75)  # 25% size reduction
BIAS_MIN_STRENGTH = _to_int(get_config('bias_min_strength', 30), 30)

# ================= STOP LOSS PARAMETERS =================
MIN_SL_USD = _to_float(get_config('min_sl_usd', 1.00), 1.00)  # Minimum stop loss distance
MAX_SL_USD = _to_float(get_config('max_sl_usd', 10.00), 10.00)  # Maximum stop loss distance
GOLD_RR_THRESHOLD = _to_float(get_config('gold_rr_threshold', 3.00), 3.00)  # Threshold separating tight/wide stop regimes
RR_TIGHT_SL_TARGET = _to_float(get_config('rr_tight_sl_target', 3.00), 3.00)  # Target when SL is tight
RR_WIDE_SL_TARGET = _to_float(get_config('rr_wide_sl_target', 2.00), 2.00)  # Target when SL is wider
MIN_RR_TARGET = _to_float(get_config('min_rr_target', 2.00), 2.00)  # Hard floor to protect expectancy
MAX_SPREAD_TO_SL_RATIO = _to_float(get_config('max_spread_to_sl_ratio', 0.35), 0.35)

# ================= ICT PARAMETERS =================
# FVG (Fair Value Gap)
MIN_FVG_GAP = _to_float(get_config('min_fvg_gap', 0.30), 0.30)  # Minimum imbalance gap size (USD)
FVG_LOOKBACK = _to_int(get_config('fvg_lookback', 50), 50)  # Candles to scan for FVG formation
FVG_SCAN_WINDOW = _to_int(get_config('fvg_scan_window', 25), 25)  # Backward scan window in completed 3-candle groups

# Displacement
DISPLACEMENT_PERCENTILE = _to_int(get_config('displacement_percentile', 75), 75)  # Body size must exceed this percentile
DISPLACEMENT_LOOKBACK = _to_int(get_config('displacement_lookback', 20), 20)  # Period for body size comparison
MAX_OPPOSING_WICK_RATIO = _to_float(get_config('max_opposing_wick_ratio', 0.4), 0.4)  # Wick vs body ratio threshold

# Order Blocks
OB_LOOKBACK = _to_int(get_config('ob_lookback', 100), 100)  # Candles to identify order blocks
OB_MIN_BODY_PERCENT = _to_int(get_config('ob_min_body_percent', 60), 60)  # Min % body vs total range
OB_VALIDATION_BARS = _to_int(get_config('ob_validation_bars', 3), 3)  # Bars for OB validity check

# Liquidity
LIQUIDITY_WICK_RATIO = _to_float(get_config('liquidity_wick_ratio', 0.6), 0.6)  # Min wick/body ratio for liquidity spike
SWEEP_TOLERANCE_USD = _to_float(get_config('sweep_tolerance_usd', 0.20), 0.20)  # Distance beyond high/low for sweep

# ================= SESSION TIMES (NY Timezone) =================
ORB_START_TIME = _parse_hhmm(get_config('orb_start_time', "09:30"), "09:30")  # Opening Range start
ORB_END_TIME = _parse_hhmm(get_config('orb_end_time', "09:45"), "09:45")  # Opening Range end
TRADE_START_TIME = _parse_hhmm(get_config('trade_start_time', "09:45"), "09:45")  # When to start trading
TRADE_END_TIME = _parse_hhmm(get_config('trade_end_time', "16:00"), "16:00")  # When to stop trading

# Session definitions
ASIAN_START = _parse_hhmm(get_config('asian_start', "20:00"), "20:00")  # Previous day 8pm NY = 8am Tokyo
ASIAN_END = _parse_hhmm(get_config('asian_end', "02:00"), "02:00")  # 2am NY = 2pm Tokyo
LONDON_START = _parse_hhmm(get_config('london_start', "03:00"), "03:00")
LONDON_END = _parse_hhmm(get_config('london_end', "12:00"), "12:00")

# ================= EXECUTION QUALITY =================
MAX_SLIPPAGE_POINTS = _to_int(get_config('max_slippage_points', 10), 10)  # MT5 deviation (points)
FILL_QUALITY_WARN_USD = _to_float(get_config('fill_quality_warn_usd', 0.50), 0.50)
FILL_QUALITY_CRITICAL_USD = _to_float(get_config('fill_quality_critical_usd', 1.00), 1.00)

# ================= FEES & COSTS =================
COMMISSION_PER_LOT = _to_float(get_config('commission_per_lot', 7.0), 7.0)
ESTIMATED_SLIPPAGE_USD = _to_float(get_config('estimated_slippage_usd', 0.10), 0.10)

# ================= TRAILING STOP =================
USE_TRAILING = _to_bool(get_config('use_trailing', True), True)
TRAILING_ATR_PERIOD = _to_int(get_config('trailing_atr_period', 14), 14)
TRAILING_ATR_MULTIPLIER = _to_float(get_config('trailing_atr_multiplier', 1.5), 1.5)
ADAPTIVE_TRAILING = _to_bool(get_config('adaptive_trailing', True), True)
ADAPTIVE_TRAILING_LOW_VOL_FACTOR = _to_float(get_config('adaptive_trailing_low_vol_factor', 0.8), 0.8)
ADAPTIVE_TRAILING_HIGH_VOL_FACTOR = _to_float(get_config('adaptive_trailing_high_vol_factor', 1.3), 1.3)

# ================= SESSION MANAGEMENT =================
CLOSE_AT_SESSION_END = _to_bool(get_config('close_at_session_end', True), True)
SESSION_END_MINUTES_BEFORE = _to_int(get_config('session_end_minutes_before', 15), 15)

# ================= CIRCUIT BREAKER =================
CB_MAX_CONSECUTIVE_LOSSES = _to_int(get_config('cb_max_consecutive_losses', 5), 5)
CB_MAX_CONSECUTIVE_ERRORS = _to_int(get_config('cb_max_consecutive_errors', 5), 5)
CB_ERROR_WINDOW_SECONDS = _to_int(get_config('cb_error_window_seconds', 300), 300)
CB_MAX_ERRORS_IN_WINDOW = _to_int(get_config('cb_max_errors_in_window', 10), 10)
CB_COOLDOWN_SECONDS = _to_int(get_config('cb_cooldown_seconds', 180), 180)
CB_MAX_AVG_SLIPPAGE_USD = _to_float(get_config('cb_max_avg_slippage_usd', 1.20), 1.20)

# ================= TREND FILTER =================
MIN_ADR_FOR_TREND = _to_float(get_config('min_adr_for_trend', 20.0), 20.0)  # Avg Daily Range threshold
ADR_PERIOD = _to_int(get_config('adr_period', 5), 5)  # Days to calculate ADR

# ORB quality filter (ATR-normalized). Helps avoid very tight/noisy ORB days
# and overly expanded ORB days that are prone to fade.
MIN_ORB_RANGE_ATR = _to_float(get_config('min_orb_range_atr', 0.5), 0.5)
MAX_ORB_RANGE_ATR = _to_float(get_config('max_orb_range_atr', 3.0), 3.0)

# ================= CROSS-ASSET REGIME FILTER =================
ENABLE_CROSS_ASSET_FILTER = _to_bool(get_config('enable_cross_asset_filter', False), False)
REGIME_TIMEFRAME = str(get_config('regime_timeframe', 'M15')).upper()
REGIME_LOOKBACK_BARS = _to_int(get_config('regime_lookback_bars', 96), 96)
REGIME_RETURN_BARS = _to_int(get_config('regime_return_bars', 8), 8)
REGIME_SIGNAL_THRESHOLD = _to_float(get_config('regime_signal_threshold', 0.18), 0.18)
REGIME_STRONG_THRESHOLD = _to_float(get_config('regime_strong_threshold', 0.40), 0.40)
REGIME_BLOCK_COUNTERTREND = _to_bool(get_config('regime_block_countertrend', True), True)
REGIME_REDUCE_SIZE_IN_HEADWIND = _to_bool(get_config('regime_reduce_size_in_headwind', True), True)
REGIME_TAILWIND_RISK_MULTIPLIER = _to_float(get_config('regime_tailwind_risk_multiplier', 1.15), 1.15)
REGIME_HEADWIND_RISK_MULTIPLIER = _to_float(get_config('regime_headwind_risk_multiplier', 0.50), 0.50)
REGIME_NEUTRAL_RISK_MULTIPLIER = _to_float(get_config('regime_neutral_risk_multiplier', 1.00), 1.00)
REGIME_SYMBOL_DXY = str(get_config('regime_symbol_dxy', 'DXY,USDX,USDX.i'))
REGIME_SYMBOL_YIELD = str(get_config('regime_symbol_yield', 'US10Y,TNX,US10Y.cash'))
REGIME_SYMBOL_RISKOFF = str(get_config('regime_symbol_riskoff', 'VIX,VIX.cash,VOLX'))
REGIME_SYMBOL_RISKON = str(get_config('regime_symbol_riskon', 'SPX500,US500,US30'))
REGIME_WEIGHT_DXY = _to_float(get_config('regime_weight_dxy', 0.40), 0.40)
REGIME_WEIGHT_YIELD = _to_float(get_config('regime_weight_yield', 0.35), 0.35)
REGIME_WEIGHT_RISKOFF = _to_float(get_config('regime_weight_riskoff', 0.15), 0.15)
REGIME_WEIGHT_RISKON = _to_float(get_config('regime_weight_riskon', 0.10), 0.10)
REGIME_EVAL_INTERVAL_SECONDS = _to_int(get_config('regime_eval_interval_seconds', 30), 30)

# ================= DATABENTO ORDERFLOW FILTER =================
ENABLE_ORDERFLOW_FILTER = _to_bool(get_config('enable_orderflow_filter', False), False)
ORDERFLOW_EVAL_INTERVAL_SECONDS = _to_int(get_config('orderflow_eval_interval_seconds', 60), 60)
ORDERFLOW_LOOKBACK_MINUTES = _to_int(get_config('orderflow_lookback_minutes', 5), 5)
ORDERFLOW_MIN_TRADES = _to_int(get_config('orderflow_min_trades', 30), 30)
ORDERFLOW_SIGNAL_THRESHOLD = _to_float(get_config('orderflow_signal_threshold', 0.15), 0.15)
ORDERFLOW_BLOCK_COUNTERTREND = _to_bool(get_config('orderflow_block_countertrend', True), True)
ORDERFLOW_REDUCE_SIZE_IN_HEADWIND = _to_bool(get_config('orderflow_reduce_size_in_headwind', True), True)
ORDERFLOW_TAILWIND_RISK_MULTIPLIER = _to_float(get_config('orderflow_tailwind_risk_multiplier', 1.05), 1.05)
ORDERFLOW_HEADWIND_RISK_MULTIPLIER = _to_float(get_config('orderflow_headwind_risk_multiplier', 0.80), 0.80)
ORDERFLOW_NEUTRAL_RISK_MULTIPLIER = _to_float(get_config('orderflow_neutral_risk_multiplier', 1.00), 1.00)
ORDERFLOW_DATASET = str(get_config('orderflow_dataset', 'GLBX.MDP3'))
ORDERFLOW_SCHEMA = str(get_config('orderflow_schema', 'trades'))
ORDERFLOW_STYPE_IN = str(get_config('orderflow_stype_in', 'raw_symbol'))
ORDERFLOW_SYMBOL = str(get_config('orderflow_symbol', 'GC.c.0'))

# ================= TIMEFRAME =================
_TIMEFRAME_MAP = {
    "M1": mt5.TIMEFRAME_M1,
    "M5": mt5.TIMEFRAME_M5,
    "M15": mt5.TIMEFRAME_M15,
    "M30": mt5.TIMEFRAME_M30,
    "H1": mt5.TIMEFRAME_H1,
    "H4": mt5.TIMEFRAME_H4,
    "D1": mt5.TIMEFRAME_D1,
}
TIMEFRAME = _TIMEFRAME_MAP.get(str(get_config('timeframe', 'M1')).upper(), mt5.TIMEFRAME_M1)

# ================= NEWS FILTER =================
# Add high-impact news events here (UTC-5/NY time)
# Format: (datetime_start, datetime_end)
NO_TRADE_WINDOWS = [
    # Example: FOMC, NFP, etc.
]

# ================= DATA & CACHING =================
DATA_CACHE_BARS = 5000          # Historical bars to cache
MIN_BARS_FOR_ANALYSIS = 200     # Minimum bars needed for indicators

# ================= LOGGING =================
LOG_FILE = 'orb_bot.log'
LOG_MAX_BYTES = 5 * 1024 * 1024  # 5MB
LOG_BACKUP_COUNT = 5
