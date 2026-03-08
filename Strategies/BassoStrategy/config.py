"""
Basso Mean Reversion Strategy Configuration
"""

import MetaTrader5 as mt5
from datetime import time
from pathlib import Path
import json

# ================= SYMBOL & TIMEFRAME =================
TARGET_SYMBOL = "XAUUSD"
TIMEFRAME = mt5.TIMEFRAME_M15
MAGIC_NUMBER = 777006
STRATEGY_ID = "basso_strategy"
STRATEGY_NAME = "Basso Mean Reversion Strategy"
STRATEGY_VERSION = "1.0.0"

# ================= RUNTIME CONFIG =================
_RUNTIME_CONFIG = {}
_CONFIG_FILE = Path(__file__).parent.parent.parent / "dashboard" / "data" / "basso_strategy_config.json"


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
RR_RATIO = get_config('rr_ratio', 2.0)
SL_ATR_BUFFER = get_config('sl_atr_buffer', 0.5)

# ================= MEAN REVERSION PARAMETERS =================
SMA_PERIOD = get_config('sma_period', 20)
ATR_PERIOD = get_config('atr_period', 14)
RSI_PERIOD = get_config('rsi_period', 14)
OVEREXTENSION_ATR_MULTIPLE = get_config('overextension_atr_multiple', 2.0)
RSI_OVERBOUGHT = get_config('rsi_overbought', 70)
RSI_OVERSOLD = get_config('rsi_oversold', 30)
USE_EMA200_TREND_FILTER = get_config('use_ema200_trend_filter', True)
EMA_TREND_SLOPE_BARS = get_config('ema_trend_slope_bars', 20)

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
STATE_FILE = Path(__file__).parent.parent.parent / "dashboard" / "data" / "basso_state.json"
