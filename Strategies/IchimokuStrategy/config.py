"""
Ichimoku Retracement Strategy Configuration
"""

import MetaTrader5 as mt5
from datetime import time
from pathlib import Path
import json

TARGET_SYMBOL = "XAUUSD"
TIMEFRAME = mt5.TIMEFRAME_H1
MAGIC_NUMBER = 777005
STRATEGY_ID = "ichimoku_strategy"
STRATEGY_NAME = "Ichimoku Retracement Strategy"
STRATEGY_VERSION = "1.0.0"

_RUNTIME_CONFIG = {}
_CONFIG_FILE = Path(__file__).parent.parent.parent / "dashboard" / "data" / "ichimoku_strategy_config.json"


def load_runtime_config():
    global _RUNTIME_CONFIG
    if _CONFIG_FILE.exists():
        try:
            with open(_CONFIG_FILE, 'r') as f:
                _RUNTIME_CONFIG = json.load(f)
        except Exception:
            pass
    return _RUNTIME_CONFIG


def get_config(key, default):
    if not _RUNTIME_CONFIG:
        load_runtime_config()
    return _RUNTIME_CONFIG.get(key, default)


load_runtime_config()

RISK_PERCENT = get_config('risk_percent', 1.0)
MAX_SPREAD_USD = get_config('max_spread', 0.40)
MAX_DAILY_LOSS_USD = -abs(get_config('max_daily_loss', 150.0))
MAX_TOTAL_RISK_USD = get_config('max_total_risk', 200.0)
MAX_DAILY_TRADES = get_config('max_daily_trades', 2)
INITIAL_BALANCE = get_config('initial_balance', 10000.0)
MIN_SL_USD = get_config('min_sl', 1.0)
MAX_SL_USD = get_config('max_sl', 40.0)

# Ichimoku Parameters
TENKAN_PERIOD = get_config('tenkan_period', 9)
KIJUN_PERIOD = get_config('kijun_period', 26)
SENKOU_B_PERIOD = get_config('senkou_b_period', 52)
CLOUD_DISPLACEMENT = get_config('cloud_displacement', 26)
REQUIRE_CLOUD_COLOR = get_config('require_cloud_color', True)
REQUIRE_CHIKOU = get_config('require_chikou_confirmation', True)
KIJUN_TOUCH_TOLERANCE_ATR = get_config('kijun_touch_tolerance_atr', 0.3)
MIN_CLOUD_THICKNESS_ATR = get_config('min_cloud_thickness_atr', 0.18)
MIN_CLOUD_BREAK_ATR = get_config('min_cloud_break_atr', 0.06)
MAX_KIJUN_DISTANCE_ATR = get_config('max_kijun_distance_atr', 1.8)
KIJUN_SLOPE_LOOKBACK = get_config('kijun_slope_lookback', 3)
MIN_KIJUN_SLOPE_ATR = get_config('min_kijun_slope_atr', 0.005)
SKIP_OUT_OF_BOUNDS_SL = get_config('skip_out_of_bounds_sl', False)
SL_BUFFER_ATR = get_config('sl_buffer_atr', 0.3)
MIN_RR_RATIO = get_config('min_rr_ratio', 2.5)
MAX_RR_RATIO = get_config('max_rr_ratio', 3.5)
KIJUN_CLOUD_TP_MULTIPLIER = get_config('kijun_cloud_tp_multiplier', 2.0)

TRADE_START_TIME = time(2, 0)   # Earlier for H1
TRADE_END_TIME = time(16, 0)

USE_TRAILING = True
TRAILING_ATR_PERIOD = 14
TRAILING_ATR_MULTIPLIER = 2.0

DATA_CACHE_BARS = 500
MIN_BARS_FOR_ANALYSIS = 90

STATE_FILE = Path(__file__).parent.parent.parent / "dashboard" / "data" / "ichimoku_state.json"
