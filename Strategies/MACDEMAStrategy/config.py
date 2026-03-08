"""
MACD + EMA Strategy Configuration
"""

import MetaTrader5 as mt5
from datetime import time
from pathlib import Path
import json

# ================= SYMBOL & TIMEFRAME =================
TARGET_SYMBOL = "XAUUSD"
TIMEFRAME = mt5.TIMEFRAME_M5
MAGIC_NUMBER = 777004
STRATEGY_ID = "macd_ema_strategy"
STRATEGY_NAME = "MACD + EMA Trend Strategy"
STRATEGY_VERSION = "1.0.0"

# ================= RUNTIME CONFIG =================
_RUNTIME_CONFIG = {}
_CONFIG_FILE = Path(__file__).parent.parent.parent / "dashboard" / "data" / "macd_ema_strategy_config.json"


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
RR_RATIO = get_config('rr_ratio', 2.5)
SL_ATR_BUFFER = get_config('sl_atr_buffer', 0.3)

# ================= EMA PARAMETERS =================
EMA_FAST = get_config('ema_fast', 9)
EMA_MID = get_config('ema_mid', 21)
EMA_SLOW = get_config('ema_slow', 50)

# ================= MACD PARAMETERS =================
MACD_FAST = get_config('macd_fast', 12)
MACD_SLOW = get_config('macd_slow', 26)
MACD_SIGNAL = get_config('macd_signal', 9)
HISTOGRAM_CONFIRM_BARS = get_config('histogram_confirmation_bars', 2)
ADX_PERIOD = get_config('adx_period', 14)
MIN_ADX = get_config('min_adx', 25)
MIN_EMA_SEPARATION_PCT = get_config('min_ema_separation_pct', 0.05)
REQUIRE_MACD_ABOVE_ZERO = get_config('require_macd_above_zero', True)
REQUIRE_MACD_BELOW_ZERO = get_config('require_macd_below_zero', True)

# ================= SESSION TIMES (NY Timezone) =================
TRADE_START_TIME = time(9, 30)
TRADE_END_TIME = time(16, 0)

# ================= TRAILING STOP =================
USE_TRAILING = True
TRAILING_ATR_PERIOD = 14
TRAILING_ATR_MULTIPLIER = 1.5

# ================= DATA =================
DATA_CACHE_BARS = 2000
MIN_BARS_FOR_ANALYSIS = 100

# ================= STATE FILE =================
STATE_FILE = Path(__file__).parent.parent.parent / "dashboard" / "data" / "macd_ema_state.json"
