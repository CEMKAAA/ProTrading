"""
Bollinger Band Squeeze Breakout Strategy Configuration
"""

import MetaTrader5 as mt5
from datetime import time
from pathlib import Path
import json

# ================= SYMBOL & TIMEFRAME =================
# Runtime-configurable: override via JSON config or API
_DEFAULT_SYMBOL = "XAUUSD"
TIMEFRAME = mt5.TIMEFRAME_M15
MAGIC_NUMBER = 777012
STRATEGY_ID = "bb_squeeze_strategy"
STRATEGY_NAME = "Bollinger Squeeze Breakout Strategy"
STRATEGY_VERSION = "1.0.0"

# ================= RUNTIME CONFIG =================
_RUNTIME_CONFIG = {}
_CONFIG_FILE = Path(__file__).parent.parent.parent / "dashboard" / "data" / "bb_squeeze_strategy_config.json"


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
ALLOWED_SYMBOLS = ["XAUUSD", "GBPUSD", "EURUSD"]
TARGET_SYMBOL = get_config('symbol', _DEFAULT_SYMBOL)
if TARGET_SYMBOL not in ALLOWED_SYMBOLS:
    TARGET_SYMBOL = _DEFAULT_SYMBOL

# ================= RISK MANAGEMENT =================
RISK_PERCENT = get_config('risk_percent', 1.0)

# Per-symbol spread limits (raw ask-bid units)
# Gold: $0.40  |  FX majors: ~3 pips max
_SPREAD_LIMITS = {
    "XAUUSD": 0.40,
    "GBPUSD": 0.00030,
    "EURUSD": 0.00020,
}
MAX_SPREAD_USD = get_config('max_spread', _SPREAD_LIMITS.get(TARGET_SYMBOL, 0.40))

MAX_DAILY_LOSS_USD = -abs(get_config('max_daily_loss', 200.0))
MAX_TOTAL_RISK_USD = get_config('max_total_risk', 250.0)
MAX_DAILY_TRADES = get_config('max_daily_trades', 2)
INITIAL_BALANCE = get_config('initial_balance', 10000.0)

# ================= STOP LOSS =================
MIN_SL_USD = get_config('min_sl', 1.0)
MAX_SL_USD = get_config('max_sl', 15.0)
RR_RATIO = get_config('min_rr', 2.5)

# ================= BOLLINGER SQUEEZE PARAMETERS =================
BB_PERIOD = get_config('bb_period', 20)
BB_STD = get_config('bb_std', 2.0)
SQUEEZE_BANDWIDTH_LOOKBACK = get_config('squeeze_bandwidth_lookback', 120)
SQUEEZE_LOOKBACK = get_config('squeeze_lookback', 6)
MOMENTUM_PERIOD = get_config('momentum_period', 10)
VOLUME_SPIKE_MULT = get_config('volume_spike_mult', 1.3)

# ================= SESSION TIMES (NY Timezone) =================
TRADE_START_TIME = time(8, 0)
TRADE_END_TIME = time(18, 0)

# ================= TRAILING STOP =================
USE_TRAILING = True
TRAILING_ATR_PERIOD = 14
TRAILING_ATR_MULTIPLIER = 2.0

# ================= DATA =================
DATA_CACHE_BARS = 2000
MIN_BARS_FOR_ANALYSIS = 200

# ================= STATE FILE =================
STATE_FILE = Path(__file__).parent.parent.parent / "dashboard" / "data" / "bb_squeeze_state.json"
