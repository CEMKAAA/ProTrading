"""
RL Strategy Configuration
All parameters centralized for easy tuning.
"""

import MetaTrader5 as mt5
from datetime import time
from pathlib import Path
import json

# ================= SYMBOL & TIMEFRAME =================
TARGET_SYMBOL = "XAUUSD"
TIMEFRAME = mt5.TIMEFRAME_M5
MAGIC_NUMBER = 777009
STRATEGY_ID = "rl_strategy"
STRATEGY_NAME = "Reinforcement Learning Strategy"
STRATEGY_VERSION = "1.0.0"

# ================= RUNTIME CONFIG =================
_RUNTIME_CONFIG = {}
_CONFIG_FILE = Path(__file__).parent.parent.parent / "dashboard" / "data" / "rl_strategy_config.json"


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
MAX_DAILY_TRADES = get_config('max_daily_trades', 3)
INITIAL_BALANCE = get_config('initial_balance', 10000.0)
MIN_SL_USD = get_config('min_sl', 1.0)
MAX_SL_USD = get_config('max_sl', 15.0)

# ================= RL PARAMETERS =================
RL_MODEL_PATH = get_config('rl_model_path', '')
SL_ATR_MULTIPLE = get_config('sl_atr_multiple', 1.5)
TP_ATR_MULTIPLE = get_config('tp_atr_multiple', 3.0)

# ================= SESSION TIMES (NY Timezone) =================
TRADE_START_TIME = time(9, 30)
TRADE_END_TIME = time(16, 0)

# ================= TRAILING STOP =================
USE_TRAILING = True
TRAILING_ATR_PERIOD = 14
TRAILING_ATR_MULTIPLIER = 1.5

# ================= DATA & CACHING =================
DATA_CACHE_BARS = 2000
MIN_BARS_FOR_ANALYSIS = 50

# ================= ONLINE LEARNING =================
RL_ONLINE_LEARNING = get_config('rl_online_learning', False)  # OFF by default
RL_ONLINE_BUFFER_SIZE = get_config('rl_online_buffer_size', 200)
RL_ONLINE_MIN_BATCH = get_config('rl_online_min_batch', 20)
RL_ONLINE_UPDATE_INTERVAL_HOURS = get_config('rl_online_update_interval', 24)

# ================= STATE FILE =================
STATE_FILE = Path(__file__).parent.parent.parent / "dashboard" / "data" / "rl_state.json"
