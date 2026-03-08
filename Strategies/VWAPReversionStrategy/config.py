"""
VWAP Mean Reversion Strategy Configuration
"""

import MetaTrader5 as mt5
from datetime import time
from pathlib import Path
import json

# ================= SYMBOL & TIMEFRAME =================
# Runtime-configurable: override via JSON config or API
_DEFAULT_SYMBOL = "XAUUSD"
TIMEFRAME = mt5.TIMEFRAME_M5
MAGIC_NUMBER = 777010
STRATEGY_ID = "vwap_reversion_strategy"
STRATEGY_NAME = "VWAP Mean Reversion Strategy"
STRATEGY_VERSION = "1.0.0"

# ================= RUNTIME CONFIG =================
_RUNTIME_CONFIG = {}
_CONFIG_FILE = Path(__file__).parent.parent.parent / "dashboard" / "data" / "vwap_reversion_strategy_config.json"


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

# Symbol is runtime-configurable (JSON config or API override)
ALLOWED_SYMBOLS = ["XAUUSD"]
TARGET_SYMBOL = get_config('symbol', _DEFAULT_SYMBOL)
if TARGET_SYMBOL not in ALLOWED_SYMBOLS:
    TARGET_SYMBOL = _DEFAULT_SYMBOL

# ================= RISK MANAGEMENT =================
RISK_PERCENT = get_config('risk_percent', 1.0)
MAX_SPREAD_USD = get_config('max_spread', 0.40)
MAX_DAILY_LOSS_USD = -abs(get_config('max_daily_loss', 200.0))
MAX_TOTAL_RISK_USD = get_config('max_total_risk', 250.0)
MAX_DAILY_TRADES = get_config('max_daily_trades', 2)
INITIAL_BALANCE = get_config('initial_balance', 10000.0)

# ================= STOP LOSS =================
MIN_SL_USD = get_config('min_sl', 1.0)
MAX_SL_USD = get_config('max_sl', 15.0)
RR_RATIO = get_config('min_rr', 2.0)

# ================= VWAP PARAMETERS =================
VWAP_STD_PERIOD = get_config('vwap_std_period', 20)
ENTRY_SIGMA = get_config('entry_sigma', 2.0)
SL_SIGMA = get_config('sl_sigma', 3.0)
RSI_PERIOD = get_config('rsi_period', 14)
ADX_PERIOD = get_config('adx_period', 14)
MAX_ADX = get_config('max_adx', 30)

# ================= SESSION TIMES (NY Timezone) =================
TRADE_START_TIME = time(3, 0)
TRADE_END_TIME = time(20, 0)

# ================= TRAILING STOP =================
USE_TRAILING = True
TRAILING_ATR_PERIOD = 14
TRAILING_ATR_MULTIPLIER = 1.5

# ================= DATA =================
DATA_CACHE_BARS = 2000
MIN_BARS_FOR_ANALYSIS = 50

# ================= STATE FILE =================
STATE_FILE = Path(__file__).parent.parent.parent / "dashboard" / "data" / "vwap_reversion_state.json"
