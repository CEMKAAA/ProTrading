from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict


@dataclass
class MicrostructureSnapshot:
    """Single-bar microstructure snapshot used by the execution simulator."""

    spread: float = 0.0
    volume: float = 0.0
    flow_imbalance: float = 0.0
    dom_imbalance: float = 0.0
    absorption_score: float = 0.0
    lva_velocity: float = 0.0
    raw_columns: Dict[str, float] = field(default_factory=dict)


@dataclass
class MicroExecutionDecision:
    """Result of microstructure-aware execution price simulation."""

    filled: bool
    adjusted_price: float
    fill_probability: float
    fill_ratio: float
    spread_cost: float
    slippage_cost: float
    adverse_selection_cost: float
    latency_bars: int
    reason: str
    diagnostics: Dict[str, float] = field(default_factory=dict)

    @property
    def total_impact_cost(self) -> float:
        return self.spread_cost + self.slippage_cost + self.adverse_selection_cost
