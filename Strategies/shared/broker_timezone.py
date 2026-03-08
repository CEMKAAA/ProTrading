"""
Centralized broker timezone detection for live strategies.

Detects the broker's UTC offset by comparing the MT5 tick timestamp
(seconds since epoch, always in broker local time via fromtimestamp)
against true UTC.  Returns a pytz.FixedOffset timezone.

This replaces the fragile per-strategy _detect_broker_timezone() pattern.
"""

from datetime import datetime, timezone

import pytz


def detect_broker_timezone(mt5_module, symbol: str) -> pytz.tzinfo:
    """
    Detect broker timezone offset from a live MT5 tick.

    Args:
        mt5_module: The MetaTrader5 module (already initialized).
        symbol: Symbol to query for a tick (e.g. "XAUUSD").

    Returns:
        A pytz.FixedOffset timezone representing the broker's UTC offset.

    Raises:
        RuntimeError: If no tick data is available for the symbol.
    """
    tick = mt5_module.symbol_info_tick(symbol)
    if tick is None:
        raise RuntimeError(
            f"Cannot detect broker timezone: no tick data for {symbol}. "
            "Ensure MT5 is initialized and the symbol is available."
        )

    # tick.time is a Unix timestamp (UTC seconds since epoch).
    # fromtimestamp() without tz gives local (broker) wall-clock time.
    # fromtimestamp() with tz=UTC gives the true UTC time.
    broker_time = datetime.fromtimestamp(tick.time)
    utc_time = datetime.fromtimestamp(tick.time, tz=timezone.utc).replace(tzinfo=None)

    offset_minutes = int((broker_time - utc_time).total_seconds() / 60)
    return pytz.FixedOffset(offset_minutes)


def get_ny_timezone() -> pytz.tzinfo:
    """Return the New York timezone (handles DST automatically)."""
    return pytz.timezone('America/New_York')
