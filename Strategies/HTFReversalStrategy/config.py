"""
HTF Reversal Strategy Configuration
Multi-Timeframe Key Level Reversal Trading
"""

import MetaTrader5 as mt5
from datetime import time
from pathlib import Path
import json

# ================= SYMBOL & TIMEFRAME =================
TARGET_SYMBOL = "XAUUSD"
MAGIC_NUMBER = 777002
STRATEGY_ID = "htf_reversal_strategy"
STRATEGY_NAME = "HTF Reversal Strategy"
STRATEGY_VERSION = "1.0.0"

# ================= RUNTIME CONFIG =================
# Load runtime config from dashboard if available
_RUNTIME_CONFIG = {}
_CONFIG_FILE = Path(__file__).parent.parent.parent / "dashboard" / "data" / "htf_reversal_strategy_config.json"

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
    return _RUNTIME_CONFIG.get(key, default)

# Load config on module import
load_runtime_config()

# Timeframes for analysis
HTF_TIMEFRAMES = {
    "monthly": mt5.TIMEFRAME_MN1,
    "weekly": mt5.TIMEFRAME_W1,
    "daily": mt5.TIMEFRAME_D1,
}

# Execution timeframe
EXECUTION_TIMEFRAME = mt5.TIMEFRAME_H4
ENTRY_TIMEFRAME = mt5.TIMEFRAME_H1

# ================= RISK MANAGEMENT =================
RISK_PERCENT = get_config('risk_percent', 1.0)                # Risk per trade as % of balance
MAX_SPREAD_USD = get_config('max_spread', 0.50)               # Max spread to allow trade execution
MAX_DAILY_LOSS_USD = -abs(get_config('max_daily_loss', 200.0))  # Stop trading after this loss
MAX_TOTAL_RISK_USD = get_config('max_total_risk', 300.0)      # Max cumulative open position risk
MAX_DAILY_TRADES = get_config('max_daily_trades', 2)          # Maximum trades per day
INITIAL_BALANCE = get_config('initial_balance', 10000.0)      # Starting balance for position sizing

# ================= STOP LOSS PARAMETERS =================
MIN_SL_USD = get_config('min_sl', 2.00)               # Minimum stop loss distance (larger for swing trades)
MAX_SL_USD = get_config('max_sl', 25.00)              # Maximum stop loss distance
DEFAULT_RR_RATIO = get_config('rr_threshold', 2.0)    # Default risk/reward ratio for TP

# ================= KEY LEVEL PARAMETERS =================
# HTF Level Detection
SWING_LOOKBACK_MONTHLY = 12     # Months to look back for key levels
SWING_LOOKBACK_WEEKLY = 52      # Weeks to look back
SWING_LOOKBACK_DAILY = 90       # Days to look back

# Level validation - how close price must be to level
LEVEL_PROXIMITY_USD = 3.00      # Price must be within $3 of a key level
LEVEL_TOUCH_TOLERANCE = 1.00    # How much price can exceed level and still count

# ================= CONSOLIDATION PARAMETERS =================
CONSOLIDATION_LOOKBACK = 20     # H4 bars to analyze for consolidation
MIN_CONSOLIDATION_BARS = 5      # Minimum bars in consolidation
MAX_CONSOLIDATION_RANGE_USD = 8.00  # Max range for consolidation pattern
MIN_CONSOLIDATION_RANGE_USD = 2.00  # Min range (not too tight)

# Breakout detection
BREAKOUT_THRESHOLD_PERCENT = 0.3  # Price must exceed range by this % to be breakout
SPIKE_VOLUME_MULTIPLIER = 1.5     # Volume must be X times average for spike

# ================= REVERSAL PATTERN PARAMETERS =================
# Candle patterns
DOJI_BODY_RATIO = 0.15          # Max body/range ratio for doji
HAMMER_WICK_RATIO = 2.0         # Min wick/body ratio for hammer
ENGULFING_OVERLAP_PERCENT = 10  # Body must overlap prev by this %
INSIDE_BAR_TOLERANCE = 0.1      # Tolerance for inside bar detection

# ================= DIVERGENCE PARAMETERS =================
RSI_PERIOD = 14
RSI_OVERBOUGHT = 70
RSI_OVERSOLD = 30
DIVERGENCE_LOOKBACK = 20        # Bars to look for divergence

# ================= TRENDLINE PARAMETERS =================
TRENDLINE_MIN_TOUCHES = 3       # Minimum touches for valid trendline
TRENDLINE_LOOKBACK = 50         # Bars to analyze for trendline

# ================= EXIT PARAMETERS =================
# H4 candle close below wick = exit
EXIT_CHECK_TIMEFRAME = mt5.TIMEFRAME_H4
TRAILING_ENABLED = True
TRAILING_START_RR = 1.0         # Start trailing after 1R profit
TRAILING_LOCK_PERCENT = 50      # Lock 50% of profit when trailing

# Take profit at retest areas
TP_AT_BROKEN_SR = True          # Take profit at broken S/R levels
PARTIAL_TP_PERCENT = 50         # Take 50% profit at first target

# ================= SESSION TIMES (NY Timezone) =================
TRADE_START_TIME = time(2, 0)   # Start trading at 2am NY (London open)
TRADE_END_TIME = time(20, 0)    # Stop trading at 8pm NY

# ================= DATA & CACHING =================
DATA_CACHE_BARS = 5000          # Historical bars to cache
MIN_BARS_FOR_ANALYSIS = 100     # Minimum bars needed for analysis

# ================= LOGGING =================
LOG_FILE = 'htf_reversal_bot.log'
LOG_MAX_BYTES = 5 * 1024 * 1024  # 5MB
LOG_BACKUP_COUNT = 5
