"""Workbench paper-trade cost model (spread + proportional turnover)."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, Optional

INSTRUMENT_SPREAD: Dict[str, float] = {
    "XAUUSD": 0.30,
    "NAS100": 1.5,
    "US500": 0.5,
    "GBPUSD": 0.00015,
    "EURUSD": 0.00012,
}

DEFAULT_TC_RATE: float = 0.0001


@dataclass
class WorkbenchCostModel:
    """Spread + turnover cost model for paper trade fills."""

    symbol: str
    spread: float
    tc_rate: float
    spread_source: str

    def __init__(
        self,
        symbol: str,
        spread: Optional[float] = None,
        tc_rate: Optional[float] = None,
        spread_source: str = "manual",
    ) -> None:
        s = str(symbol or "").upper()
        self.symbol = s
        default_spread = float(INSTRUMENT_SPREAD.get(s, 0.30))
        self.spread = float(default_spread if spread is None else max(0.0, float(spread)))
        self.tc_rate = float(DEFAULT_TC_RATE if tc_rate is None else max(0.0, float(tc_rate)))
        self.spread_source = str(spread_source or "manual")

    def apply_fill_spread(self, mid_price: float, direction: str) -> float:
        """Apply half spread to a fill. direction: buy|sell."""
        m = float(mid_price)
        half = self.spread / 2.0
        d = str(direction or "").strip().lower()
        if d == "buy":
            return float(m + half)
        return float(m - half)

    def compute_turnover_cost(self, position_change: float, price: float) -> float:
        """Proportional turnover cost."""
        return float(abs(float(position_change)) * float(price) * float(self.tc_rate))

    def round_trip_turnover_cost(self, lot_size: float, entry_mid: float, exit_mid: float) -> float:
        return float(
            self.compute_turnover_cost(lot_size, entry_mid)
            + self.compute_turnover_cost(lot_size, exit_mid)
        )

    def cost_summary(
        self,
        entry_mid: float,
        exit_mid: float,
        direction: str,
        lot_size: float,
        contract_size: float,
    ) -> Dict[str, Any]:
        side_open = "buy" if str(direction or "").upper() == "BUY" else "sell"
        side_close = "sell" if side_open == "buy" else "buy"
        entry_fill = self.apply_fill_spread(entry_mid, side_open)
        exit_fill = self.apply_fill_spread(exit_mid, side_close)
        spread_points_total = abs(entry_fill - float(entry_mid)) + abs(exit_fill - float(exit_mid))
        spread_cost_total = float(spread_points_total * float(lot_size) * float(contract_size))
        turnover_cost = self.round_trip_turnover_cost(
            lot_size=float(lot_size),
            entry_mid=float(entry_mid),
            exit_mid=float(exit_mid),
        )
        total_cost = float(spread_cost_total + turnover_cost)
        return {
            "symbol": self.symbol,
            "spread": float(self.spread),
            "spread_source": str(self.spread_source or "manual"),
            "tc_rate": float(self.tc_rate),
            "entry_mid": float(entry_mid),
            "entry_fill": float(entry_fill),
            "exit_mid": float(exit_mid),
            "exit_fill": float(exit_fill),
            "spread_per_side": float(self.spread / 2.0),
            "spread_points_total": float(spread_points_total),
            "spread_cost_total": float(spread_cost_total),
            "turnover_cost": float(turnover_cost),
            "total_cost": float(total_cost),
            "lot_size": float(lot_size),
            "contract_size": float(contract_size),
        }
