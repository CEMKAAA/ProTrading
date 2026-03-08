"""
Trading Bot Configuration
All parameters centralized for easy tuning and backtesting
"""

import MetaTrader5 as mt5
from datetime import time
import pytz

# ================= SYMBOL & TIMEFRAME =================
TARGET_SYMBOL = "XAUUSD"
TIMEFRAME = mt5.TIMEFRAME_M1
MAGIC_NUMBER = 777001

# ================= RISK MANAGEMENT =================
RISK_PERCENT = 1.0              # Risk per trade as % of balance
MAX_SPREAD_USD = 0.40           # Max spread to allow trade execution
MAX_DAILY_LOSS_USD = -150.0     # Stop trading after this loss
MAX_TOTAL_RISK_USD = 200.0      # Max cumulative open position risk

# ================= STOP LOSS PARAMETERS =================
MIN_SL_USD = 1.00               # Minimum stop loss distance
MAX_SL_USD = 10.00              # Maximum stop loss distance
GOLD_RR_THRESHOLD = 3.00        # SL < $3 = 2R target, else 1R

# ================= ICT PARAMETERS =================
# FVG (Fair Value Gap)
MIN_FVG_GAP = 0.30              # Minimum imbalance gap size (USD)
FVG_LOOKBACK = 50               # Candles to scan for FVG formation

# Displacement
DISPLACEMENT_PERCENTILE = 75    # Body size must exceed this percentile
DISPLACEMENT_LOOKBACK = 20      # Period for body size comparison
MAX_OPPOSING_WICK_RATIO = 0.4   # Wick vs body ratio threshold

# Order Blocks
OB_LOOKBACK = 100               # Candles to identify order blocks
OB_MIN_BODY_PERCENT = 60        # Min % body vs total range
OB_VALIDATION_BARS = 3          # Bars for OB validity check

# Liquidity
LIQUIDITY_WICK_RATIO = 0.6      # Min wick/body ratio for liquidity spike
SWEEP_TOLERANCE_USD = 0.20      # Distance beyond high/low for sweep

# ================= SESSION TIMES (NY Timezone) =================
ORB_START_TIME = time(9, 30)    # Opening Range start
ORB_END_TIME = time(9, 45)      # Opening Range end
TRADE_START_TIME = time(9, 45)  # When to start trading
TRADE_END_TIME = time(16, 0)    # When to stop trading

# Session definitions
ASIAN_START = time(20, 0)       # Previous day 8pm NY = 8am Tokyo
ASIAN_END = time(2, 0)          # 2am NY = 2pm Tokyo
LONDON_START = time(3, 0)
LONDON_END = time(12, 0)

# ================= TRAILING STOP =================
USE_TRAILING = True
TRAILING_ATR_PERIOD = 14
TRAILING_ATR_MULTIPLIER = 1.5

# ================= TREND FILTER =================
MIN_ADR_FOR_TREND = 20.0        # Avg Daily Range threshold
ADR_PERIOD = 5                  # Days to calculate ADR

# ================= NEWS FILTER =================
# Add high-impact news events here (UTC-5/NY time)
# Format: (datetime_start, datetime_end)
NO_TRADE_WINDOWS = [
    # Example: FOMC, NFP, etc.
    # (datetime(2026, 2, 5, 14, 0, tzinfo=pytz.timezone('America/New_York')), 
    #  datetime(2026, 2, 5, 15, 0, tzinfo=pytz.timezone('America/New_York'))),
]

# ================= DATA & CACHING =================
DATA_CACHE_BARS = 5000          # Historical bars to cache
MIN_BARS_FOR_ANALYSIS = 200     # Minimum bars needed for indicators

# ================= LOGGING =================
LOG_FILE = 'orb_bot.log'
LOG_MAX_BYTES = 5 * 1024 * 1024  # 5MB
LOG_BACKUP_COUNT = 5
