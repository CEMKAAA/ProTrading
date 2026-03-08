"""Centralized timezone and session-time configuration.

Every timezone constant, session boundary, and Friday-close rule lives
here.  Strategy code and the backtest engine should import from this
module instead of hardcoding 'America/New_York' or time(15, 30).
"""

from datetime import time
from typing import NamedTuple

import pytz

# =========================================================================
# Canonical timezone objects
# =========================================================================

NY_TZ = pytz.timezone("America/New_York")
UTC_TZ = pytz.UTC
DEFAULT_BROKER_OFFSET_MINUTES = 120   # UTC+2 (common MetaTrader default)

# =========================================================================
# Session definitions  (all times are NY / Eastern)
# =========================================================================


class SessionWindow(NamedTuple):
    """A named session with start/end times (NY timezone)."""
    start: time
    end: time


# ORB (Opening Range Breakout) — first 15 min of NYSE
ORB_SESSION = SessionWindow(start=time(9, 30), end=time(9, 45))

# Primary trading window after ORB
TRADING_SESSION = SessionWindow(start=time(9, 45), end=time(16, 0))

# Asian session (Tokyo/Sydney, expressed in NY time)
ASIAN_SESSION = SessionWindow(start=time(20, 0), end=time(2, 0))

# London session (expressed in NY time)
LONDON_SESSION = SessionWindow(start=time(3, 0), end=time(12, 0))

# =========================================================================
# Friday close (weekend risk management)
# =========================================================================

FRIDAY_CLOSE_HOUR = 15
FRIDAY_CLOSE_MINUTE = 30
FRIDAY_CLOSE_TIME = time(FRIDAY_CLOSE_HOUR, FRIDAY_CLOSE_MINUTE)
FRIDAY_WEEKDAY = 4   # Monday=0 … Friday=4

# =========================================================================
# ML features constant
# =========================================================================

SESSION_CLOSE_HOUR = 16   # 4 PM NY — used for hours_to_session_close feature

# =========================================================================
# Defaults used by BacktestConfig / DB model
# =========================================================================

DEFAULT_ORB_START = "09:30"
DEFAULT_ORB_END = "09:45"
DEFAULT_TRADE_START = "09:45"
DEFAULT_TRADE_END = "16:00"
DEFAULT_ASIAN_START = "20:00"
DEFAULT_ASIAN_END = "02:00"
DEFAULT_LONDON_START = "03:00"
DEFAULT_LONDON_END = "12:00"
