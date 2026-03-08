"""
MT5 Connection Health Monitor

Provides:
- Connection check with auto-reconnect and exponential backoff
- Position reconciliation (compare expected vs actual MT5 positions)
- Heartbeat tracking for zombie bot detection
"""

from __future__ import annotations

import logging
import time
from datetime import datetime, timezone
from typing import Dict, List, Optional, Set, Tuple

try:
    import MetaTrader5 as mt5
    HAS_MT5 = True
except ImportError:
    HAS_MT5 = False
    mt5 = None  # type: ignore


class MT5HealthMonitor:
    """
    Monitors MT5 connection health and provides auto-reconnect.

    Usage::

        health = MT5HealthMonitor(logger, symbol="XAUUSD", magic=777001)

        # In main loop, call before any MT5 operations:
        connected = health.ensure_connected()
        if not connected:
            time.sleep(health.get_backoff_delay())
            continue

        # Periodically reconcile positions:
        orphans = health.reconcile_positions(expected_tickets)
    """

    def __init__(
        self,
        logger: logging.Logger,
        symbol: str = "XAUUSD",
        magic_number: int = 777001,
        max_reconnect_attempts: int = 5,
        base_backoff_seconds: float = 2.0,
        max_backoff_seconds: float = 60.0,
        heartbeat_timeout_seconds: float = 120.0,
    ):
        self.logger = logger
        self.symbol = symbol
        self.magic_number = magic_number
        self.max_reconnect_attempts = max_reconnect_attempts
        self.base_backoff = base_backoff_seconds
        self.max_backoff = max_backoff_seconds
        self.heartbeat_timeout = heartbeat_timeout_seconds

        # State tracking
        self._consecutive_failures: int = 0
        self._last_successful_tick: Optional[datetime] = None
        self._last_reconnect_attempt: float = 0.0
        self._total_reconnects: int = 0
        self._is_connected: bool = False

    def ensure_connected(self) -> bool:
        """
        Check MT5 connection and auto-reconnect if needed.

        Returns:
            True if connected and healthy, False if connection failed.
        """
        if not HAS_MT5:
            self.logger.error("MetaTrader5 package not installed")
            return False

        # Quick health check: try to get terminal info
        try:
            terminal = mt5.terminal_info()
            if terminal is not None and terminal.connected:
                # Verify data feed with tick check
                tick = mt5.symbol_info_tick(self.symbol)
                if tick is not None:
                    self._consecutive_failures = 0
                    self._is_connected = True
                    self._last_successful_tick = datetime.now(timezone.utc)
                    return True

                # Terminal connected but no tick data
                self.logger.warning(
                    f"MT5 terminal connected but no tick data for {self.symbol}"
                )
        except Exception as e:
            self.logger.error(f"MT5 health check exception: {e}")

        # Connection is down — attempt reconnect
        self._is_connected = False
        return self._attempt_reconnect()

    def _attempt_reconnect(self) -> bool:
        """Attempt MT5 reconnection with exponential backoff."""
        self._consecutive_failures += 1

        if self._consecutive_failures > self.max_reconnect_attempts:
            self.logger.critical(
                f"MT5 reconnect failed after {self.max_reconnect_attempts} attempts. "
                f"Strategy should halt."
            )
            return False

        # Exponential backoff between reconnect attempts
        delay = min(
            self.base_backoff * (2 ** (self._consecutive_failures - 1)),
            self.max_backoff
        )
        now = time.time()
        if now - self._last_reconnect_attempt < delay:
            return False

        self._last_reconnect_attempt = now

        self.logger.warning(
            f"MT5 reconnect attempt {self._consecutive_failures}/{self.max_reconnect_attempts}"
        )

        try:
            # Shutdown first to clear stale state
            mt5.shutdown()
            time.sleep(0.5)

            if mt5.initialize():
                # Verify the reconnection actually works
                tick = mt5.symbol_info_tick(self.symbol)
                if tick is not None:
                    self._consecutive_failures = 0
                    self._is_connected = True
                    self._total_reconnects += 1
                    self._last_successful_tick = datetime.now(timezone.utc)
                    self.logger.info(
                        f"MT5 reconnected successfully (total reconnects: {self._total_reconnects})"
                    )
                    return True

            self.logger.error("MT5 initialize() succeeded but tick data unavailable")
        except Exception as e:
            self.logger.error(f"MT5 reconnect exception: {e}")

        return False

    def get_backoff_delay(self) -> float:
        """Get current backoff delay based on consecutive failures."""
        if self._consecutive_failures == 0:
            return 1.0
        return min(
            self.base_backoff * (2 ** (self._consecutive_failures - 1)),
            self.max_backoff
        )

    def check_heartbeat(self) -> bool:
        """
        Check if we've received data recently enough.

        Returns:
            True if heartbeat is OK, False if potentially zombie.
        """
        if self._last_successful_tick is None:
            return False

        elapsed = (datetime.now(timezone.utc) - self._last_successful_tick).total_seconds()
        if elapsed > self.heartbeat_timeout:
            self.logger.warning(
                f"MT5 heartbeat timeout: {elapsed:.0f}s since last tick "
                f"(threshold: {self.heartbeat_timeout}s)"
            )
            return False
        return True

    def reconcile_positions(
        self,
        expected_tickets: Optional[Set[int]] = None,
    ) -> Dict[str, List]:
        """
        Compare internal position tracking with actual MT5 positions.

        Args:
            expected_tickets: Set of position tickets we think we have open.
                              If None, just reports all our positions.

        Returns:
            Dict with 'actual', 'orphaned', 'missing' position info.
        """
        if not HAS_MT5 or not self._is_connected:
            return {"actual": [], "orphaned": [], "missing": []}

        try:
            positions = mt5.positions_get(symbol=self.symbol)
        except Exception as e:
            self.logger.error(f"Position reconciliation failed: {e}")
            return {"actual": [], "orphaned": [], "missing": []}

        # Filter our positions only
        our_positions = []
        if positions:
            our_positions = [p for p in positions if p.magic == self.magic_number]

        actual_tickets = {p.ticket for p in our_positions}

        result = {
            "actual": our_positions,
            "orphaned": [],
            "missing": [],
        }

        if expected_tickets is not None:
            # Positions in MT5 but not in our tracking
            orphaned = actual_tickets - expected_tickets
            # Positions in our tracking but not in MT5
            missing = expected_tickets - actual_tickets

            if orphaned:
                result["orphaned"] = [p for p in our_positions if p.ticket in orphaned]
                self.logger.warning(
                    f"POSITION RECONCILIATION: {len(orphaned)} orphaned position(s) "
                    f"found in MT5 but not tracked: {orphaned}"
                )

            if missing:
                result["missing"] = list(missing)
                self.logger.warning(
                    f"POSITION RECONCILIATION: {len(missing)} position(s) "
                    f"tracked but not in MT5: {missing}"
                )

        return result

    def get_state(self) -> Dict:
        """Return health state for dashboard / monitoring."""
        return {
            "is_connected": self._is_connected,
            "consecutive_failures": self._consecutive_failures,
            "total_reconnects": self._total_reconnects,
            "last_successful_tick": (
                self._last_successful_tick.isoformat()
                if self._last_successful_tick else None
            ),
            "heartbeat_ok": self.check_heartbeat(),
        }
