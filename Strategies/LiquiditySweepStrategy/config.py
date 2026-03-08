"""
Liquidity Sweep Strategy Configuration
All parameters centralized for easy tuning.
"""

import MetaTrader5 as mt5
from datetime import time
from pathlib import Path
import json

# ================= SYMBOL & TIMEFRAME =================
TARGET_SYMBOL = "XAUUSD"
TIMEFRAME = mt5.TIMEFRAME_M5
MAGIC_NUMBER = 777008
STRATEGY_ID = "liquidity_sweep_strategy"
STRATEGY_NAME = "Session Liquidity Sweep Reversal"
STRATEGY_VERSION = "1.0.0"

# ================= RUNTIME CONFIG =================
_RUNTIME_CONFIG = {}
_CONFIG_FILE = Path(__file__).parent.parent.parent / "dashboard" / "data" / "liquidity_sweep_strategy_config.json"


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

# ================= RISK MANAGEMENT =================
RISK_PERCENT = get_config('risk_percent', 1.0)
MAX_SPREAD_USD = get_config('max_spread', 0.50)
MAX_DAILY_LOSS_USD = -abs(get_config('max_daily_loss', 150.0))
MAX_TOTAL_RISK_USD = get_config('max_total_risk', 200.0)
MAX_DAILY_TRADES = get_config('max_daily_trades', 2)
INITIAL_BALANCE = get_config('initial_balance', 10000.0)
MIN_SL_USD = get_config('min_sl', 1.0)
MAX_SL_USD = get_config('max_sl', 15.0)

# ================= SWEEP DETECTION =================
SWEEP_MIN_PENETRATION_ATR = get_config('sweep_min_penetration_atr', 0.3)
SWEEP_MAX_BARS_TO_REJECT = get_config('sweep_max_bars_to_reject', 3)
REJECTION_BODY_PERCENTILE = get_config('rejection_body_percentile', 60)
REQUIRE_FVG_AFTER_SWEEP = get_config('require_fvg_after_sweep', True)

# ================= TRADE PARAMETERS =================
MIN_RR_RATIO = get_config('min_rr_ratio', 3.0)
SL_BUFFER_ATR = get_config('sl_buffer_atr', 0.3)

# ================= ROUND NUMBER LEVELS =================
USE_ROUND_NUMBERS = get_config('use_round_numbers', True)
ROUND_NUMBER_INTERVAL = get_config('round_number_interval', 50)

# ================= SESSION TIMES (NY Timezone) =================
# NY-London overlap window only
TRADE_START_TIME = time(9, 30)
TRADE_END_TIME = time(12, 0)

# ================= TRAILING STOP =================
USE_TRAILING = True
TRAILING_ATR_PERIOD = 14
TRAILING_ATR_MULTIPLIER = 1.5

# ================= DATA & CACHING =================
DATA_CACHE_BARS = 2000
MIN_BARS_FOR_ANALYSIS = 100

# ================= STATE FILE =================
STATE_FILE = Path(__file__).parent.parent.parent / "dashboard" / "data" / "liquidity_sweep_state.json"
