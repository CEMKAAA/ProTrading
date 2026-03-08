"""
Strategy-Level Circuit Breaker

Institutional-grade safety mechanism that halts a strategy when it
detects pathological behaviour patterns:

1. Consecutive losing trades  -> strategy logic may be misaligned with regime
2. Consecutive execution errors -> connectivity / broker issue
3. High error rate in window   -> systemic infrastructure problem
4. Excessive slippage          -> liquidity drought or stale quotes

All thresholds are configurable.  The breaker auto-resets after a
cooldown period, or can be manually reset via API / code.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Dict, List, Optional, Tuple
import logging


@dataclass
class CircuitBreakerConfig:
    """Configurable thresholds for the circuit breaker."""
    max_consecutive_losses: int = 3
    max_consecutive_errors: int = 5
    error_window_seconds: int = 300          # 5-minute sliding window
    max_errors_in_window: int = 10
    cooldown_seconds: int = 300              # 5-minute cooldown after trip
    max_avg_slippage_usd: float = 0.80       # avg slippage threshold
    slippage_window_trades: int = 10         # last N trades for avg


@dataclass
class SlippageRecord:
    timestamp: datetime
    requested_price: float
    actual_price: float
    slippage_usd: float
    direction: str


@dataclass
class CircuitBreakerState:
    consecutive_losses: int = 0
    consecutive_errors: int = 0
    is_tripped: bool = False
    trip_reason: str = ""
    trip_time: Optional[datetime] = None
    cooldown_until: Optional[datetime] = None
    total_trips: int = 0
    error_timestamps: List[datetime] = field(default_factory=list)
    slippage_records: List[SlippageRecord] = field(default_factory=list)


class StrategyCircuitBreaker:
    """
    Per-strategy circuit breaker.

    Usage::

        cb = StrategyCircuitBreaker(logger, config)

        # Before every trade attempt
        tripped, reason = cb.check()
        if tripped:
            logger.warning(f"Circuit breaker tripped: {reason}")
            return

        # After trade result
        cb.record_trade_result(won=True)

        # After execution error
        cb.record_error("requote timeout")

        # After fill
        cb.record_fill(requested=2045.50, actual=2045.72, direction="BUY")
    """

    def __init__(
        self,
        logger: logging.Logger,
        config: Optional[CircuitBreakerConfig] = None,
        strategy_id: str = "unknown",
    ):
        self.logger = logger
        self.config = config or CircuitBreakerConfig()
        self.strategy_id = strategy_id
        self._state = CircuitBreakerState()

    # ------------------------------------------------------------------
    # Public interface
    # ------------------------------------------------------------------

    def check(self) -> Tuple[bool, str]:
        """Check if the breaker is currently tripped.

        Returns:
            (is_tripped, reason)  -- reason is empty string when not tripped.
        """
        # Auto-reset after cooldown
        if self._state.is_tripped and self._state.cooldown_until:
            now = datetime.now(timezone.utc)
            if now >= self._state.cooldown_until:
                self._auto_reset()
                return False, ""

        return self._state.is_tripped, self._state.trip_reason

    def record_trade_result(self, won: bool) -> None:
        """Record a closed trade result."""
        if won:
            self._state.consecutive_losses = 0
        else:
            self._state.consecutive_losses += 1
            if self._state.consecutive_losses >= self.config.max_consecutive_losses:
                self._trip(
                    f"consecutive_losses_{self._state.consecutive_losses}"
                )

    def record_error(self, detail: str = "") -> None:
        """Record an execution or infrastructure error."""
        now = datetime.now(timezone.utc)
        self._state.consecutive_errors += 1
        self._state.error_timestamps.append(now)

        # Check consecutive errors
        if self._state.consecutive_errors >= self.config.max_consecutive_errors:
            self._trip(f"consecutive_errors_{self._state.consecutive_errors}")
            return

        # Check error rate in sliding window
        cutoff = now - timedelta(seconds=self.config.error_window_seconds)
        self._state.error_timestamps = [
            ts for ts in self._state.error_timestamps if ts >= cutoff
        ]
        if len(self._state.error_timestamps) >= self.config.max_errors_in_window:
            self._trip(
                f"error_rate_{len(self._state.error_timestamps)}_in_{self.config.error_window_seconds}s"
            )

    def record_fill(
        self,
        requested: float,
        actual: float,
        direction: str,
    ) -> None:
        """Record fill quality and check slippage health."""
        slippage_usd = abs(actual - requested)
        now = datetime.now(timezone.utc)

        self._state.slippage_records.append(SlippageRecord(
            timestamp=now,
            requested_price=requested,
            actual_price=actual,
            slippage_usd=slippage_usd,
            direction=direction,
        ))

        # Keep only recent records
        window = self.config.slippage_window_trades
        if len(self._state.slippage_records) > window * 2:
            self._state.slippage_records = self._state.slippage_records[-window:]

        # Check average slippage over last N fills
        recent = self._state.slippage_records[-window:]
        if len(recent) >= max(3, window // 2):
            avg_slip = sum(r.slippage_usd for r in recent) / len(recent)
            if avg_slip > self.config.max_avg_slippage_usd:
                self._trip(f"avg_slippage_{avg_slip:.3f}_usd")

        # Successful fill clears consecutive error counter
        self._state.consecutive_errors = 0

    def reset(self) -> None:
        """Full daily reset of the circuit breaker.

        Clears all tracking state so yesterday's data cannot
        cause a false trip on the first trade of a new day.
        ``total_trips`` is preserved as a cumulative monitoring metric.
        """
        was_tripped = self._state.is_tripped
        self._state.is_tripped = False
        self._state.trip_reason = ""
        self._state.trip_time = None
        self._state.cooldown_until = None
        self._state.consecutive_losses = 0
        self._state.consecutive_errors = 0
        self._state.error_timestamps.clear()
        self._state.slippage_records.clear()
        if was_tripped:
            self.logger.info(
                f"[{self.strategy_id}] Circuit breaker manually reset"
            )

    def get_state(self) -> Dict:
        """Return current state for dashboard / monitoring."""
        recent_slippage = self._state.slippage_records[-self.config.slippage_window_trades:]
        avg_slippage = (
            sum(r.slippage_usd for r in recent_slippage) / len(recent_slippage)
            if recent_slippage else 0.0
        )
        # Re-filter error timestamps by window for accurate dashboard count
        now = datetime.now(timezone.utc)
        cutoff = now - timedelta(seconds=self.config.error_window_seconds)
        recent_error_count = sum(1 for ts in self._state.error_timestamps if ts >= cutoff)
        return {
            "strategy_id": self.strategy_id,
            "is_tripped": self._state.is_tripped,
            "trip_reason": self._state.trip_reason,
            "trip_time": self._state.trip_time.isoformat() if self._state.trip_time else None,
            "cooldown_until": self._state.cooldown_until.isoformat() if self._state.cooldown_until else None,
            "consecutive_losses": self._state.consecutive_losses,
            "consecutive_errors": self._state.consecutive_errors,
            "total_trips": self._state.total_trips,
            "avg_slippage_usd": round(avg_slippage, 4),
            "recent_errors_in_window": recent_error_count,
        }

    def update_config(self, **kwargs) -> None:
        """Hot-update thresholds without resetting state."""
        for key, value in kwargs.items():
            if hasattr(self.config, key):
                setattr(self.config, key, value)

    # ------------------------------------------------------------------
    # Internal
    # ------------------------------------------------------------------

    def _trip(self, reason: str) -> None:
        if self._state.is_tripped:
            return  # Already tripped

        now = datetime.now(timezone.utc)
        self._state.is_tripped = True
        self._state.trip_reason = reason
        self._state.trip_time = now
        self._state.cooldown_until = now + timedelta(
            seconds=self.config.cooldown_seconds
        )
        self._state.total_trips += 1

        self.logger.warning(
            f"[{self.strategy_id}] CIRCUIT BREAKER TRIPPED: {reason} | "
            f"Cooldown until: {self._state.cooldown_until.strftime('%H:%M:%S')} UTC | "
            f"Total trips today: {self._state.total_trips}"
        )

    def _auto_reset(self) -> None:
        self.logger.info(
            f"[{self.strategy_id}] Circuit breaker auto-reset after cooldown "
            f"(was: {self._state.trip_reason})"
        )
        self._state.is_tripped = False
        self._state.trip_reason = ""
        self._state.trip_time = None
        self._state.cooldown_until = None
        # Set losses to max-1 to give exactly 1 trade buffer before re-trip.
        # Using config.max-1 (not current-1) ensures consistent headroom
        # even if losses were recorded during cooldown.
        self._state.consecutive_losses = max(
            0, self.config.max_consecutive_losses - 1
        )
        self._state.consecutive_errors = 0
