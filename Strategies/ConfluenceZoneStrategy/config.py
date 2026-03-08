"""
Multi-TF Confluence Zone Strategy Configuration
"""

import MetaTrader5 as mt5
from datetime import time
from pathlib import Path
import json

# ================= SYMBOL & TIMEFRAME =================
TARGET_SYMBOL = "XAUUSD"
TIMEFRAME = mt5.TIMEFRAME_M15
MAGIC_NUMBER = 777007
STRATEGY_ID = "confluence_zone_strategy"
STRATEGY_NAME = "Multi-TF Confluence Zone Strategy"
STRATEGY_VERSION = "1.0.0"

# ================= RUNTIME CONFIG =================
_RUNTIME_CONFIG = {}
_CONFIG_FILE = Path(__file__).parent.parent.parent / "dashboard" / "data" / "confluence_zone_strategy_config.json"


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
MAX_SPREAD_USD = get_config('max_spread', 0.40)
MAX_DAILY_LOSS_USD = -abs(get_config('max_daily_loss', 150.0))
MAX_TOTAL_RISK_USD = get_config('max_total_risk', 200.0)
MAX_DAILY_TRADES = get_config('max_daily_trades', 3)
INITIAL_BALANCE = get_config('initial_balance', 10000.0)

# ================= STOP LOSS =================
MIN_SL_USD = get_config('min_sl', 1.0)
MAX_SL_USD = get_config('max_sl', 15.0)
SL_BUFFER_ATR = get_config('sl_buffer_atr', 0.5)
MIN_RR_RATIO = get_config('min_rr_ratio', 2.5)

# ================= CONFLUENCE ZONE PARAMETERS =================
EMA_SLOW = get_config('ema_slow', 50)
EMA_VERY_SLOW = get_config('ema_very_slow', 200)
RSI_PERIOD = get_config('rsi_period', 14)
ZONE_WIDTH_ATR = get_config('zone_width_atr', 1.0)
MIN_CONFLUENCE_SCORE = get_config('min_confluence_score', 60)
MIN_LEVELS_IN_ZONE = get_config('min_levels_in_zone', 3)
USE_REVERSAL_CANDLE_FILTER = get_config('use_reversal_candle_filter', True)
RSI_EXTREME_THRESHOLD = get_config('rsi_extreme_threshold', 35)
ROUND_NUMBER_INTERVAL = get_config('round_number_interval', 50)

# ================= SESSION TIMES (NY Timezone) =================
TRADE_START_TIME = time(9, 30)
TRADE_END_TIME = time(16, 0)

# ================= TRAILING STOP =================
USE_TRAILING = True
TRAILING_ATR_PERIOD = 14
TRAILING_ATR_MULTIPLIER = 1.5

# ================= DATA =================
DATA_CACHE_BARS = 2000
MIN_BARS_FOR_ANALYSIS = 210  # Need 200+ bars for EMA 200

# ================= STATE FILE =================
STATE_FILE = Path(__file__).parent.parent.parent / "dashboard" / "data" / "confluence_zone_state.json"
