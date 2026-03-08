from __future__ import annotations

from typing import Any, Callable

import numpy as np

from .features import build_snapshot_from_bar
from .models import MicroExecutionDecision


class MicrostructureExecutionSimulator:
    """Microstructure-aware execution model for entry/exit price formation."""

    def __init__(self, config: Any, rng: np.random.Generator, spread_fn: Callable[[Any], float]):
        self.config = config
        self.rng = rng
        self.spread_fn = spread_fn

    def _get(self, name: str, default: float) -> float:
        try:
            return float(getattr(self.config, name, default))
        except Exception:
            return float(default)

    def _side_pressure(self, side: str, flow_imbalance: float, dom_imbalance: float) -> tuple[float, float]:
        # Positive pressure = adverse for this side (worse execution)
        if side == "BUY":
            adverse = max(0.0, flow_imbalance) + max(0.0, dom_imbalance)
            favorable = max(0.0, -flow_imbalance) + max(0.0, -dom_imbalance)
        else:
            adverse = max(0.0, -flow_imbalance) + max(0.0, -dom_imbalance)
            favorable = max(0.0, flow_imbalance) + max(0.0, dom_imbalance)
        return adverse, favorable

    def _fill_probability(self, side: str, snapshot) -> float:
        base = self._get("micro_base_fill_probability", 0.95)
        min_volume = self._get("micro_min_volume", 0.0)

        if min_volume > 0:
            liq_factor = float(np.clip(snapshot.volume / max(min_volume, 1e-9), 0.05, 1.0))
        else:
            liq_factor = 1.0

        adverse, favorable = self._side_pressure(side, snapshot.flow_imbalance, snapshot.dom_imbalance)
        pressure_factor = float(np.clip(1.0 - 0.25 * adverse + 0.15 * favorable, 0.2, 1.4))
        confidence = float(np.clip(0.4 + 0.3 * abs(snapshot.flow_imbalance) + 0.3 * abs(snapshot.dom_imbalance), 0.0, 1.0))

        probability = base * liq_factor * pressure_factor
        probability = confidence * probability + (1.0 - confidence) * 0.7
        return float(np.clip(probability, 0.01, 1.0))

    def _fill_ratio(self, probability: float) -> float:
        low = self._get("micro_partial_fill_min", 0.65)
        high = self._get("micro_partial_fill_max", 1.0)
        if high < low:
            low, high = high, low
        sampled = self.rng.uniform(low, high)
        ratio = sampled * probability
        return float(np.clip(ratio, 0.05, 1.0))

    def _spread_cost(self, bar_time: Any) -> float:
        if not bool(getattr(self.config, "simulate_spread", True)):
            return 0.0
        if bool(getattr(self.config, "use_variable_spread", True)):
            base = float(self.spread_fn(bar_time))
        else:
            base = self._get("max_spread_usd", 0.0) / 2.0
        spread_scale = self._get("micro_spread_scale", 1.0)
        return max(0.0, base * spread_scale)

    def _slippage_cost(self, side: str, snapshot, atr: float) -> float:
        if not bool(getattr(self.config, "simulate_slippage", True)):
            return 0.0

        atr_value = max(float(atr), 1e-9)
        base = atr_value * self._get("slippage_atr_factor", 0.02)
        scale = self._get("micro_slippage_scale", 1.0)
        latency = int(getattr(self.config, "micro_latency_bars", 0) or 0)
        adverse, favorable = self._side_pressure(side, snapshot.flow_imbalance, snapshot.dom_imbalance)

        # LVA velocity > 1 typically implies faster move through low-liquidity zones.
        lva_mult = 1.0 + 0.15 * max(0.0, snapshot.lva_velocity - 1.0)
        pressure_mult = 1.0 + 0.6 * adverse - 0.25 * favorable
        latency_mult = 1.0 + 0.25 * max(0, latency)

        sampled = self.rng.uniform(0.75, 1.5)
        slippage = base * scale * lva_mult * pressure_mult * latency_mult * sampled

        min_slippage = self._get("min_slippage_usd", 0.01)
        max_slippage = self._get("max_slippage_usd", 0.50) + self._get("micro_max_extra_slippage_usd", 1.0)
        return float(np.clip(slippage, min_slippage, max_slippage))

    def _adverse_selection_cost(self, side: str, snapshot, atr: float) -> float:
        scale = self._get("micro_adverse_selection_scale", 0.2)
        if scale <= 0:
            return 0.0
        adverse, _ = self._side_pressure(side, snapshot.flow_imbalance, snapshot.dom_imbalance)
        atr_value = max(float(atr), 1e-9)
        return float(max(0.0, scale * atr_value * adverse))

    def _apply_side_costs(self, side: str, base_price: float, spread: float, slippage: float, adverse: float) -> float:
        total = spread + slippage + adverse
        if side == "BUY":
            return base_price + total
        return base_price - total

    def simulate_entry(self, bar: Any, direction: str, base_price: float, atr: float) -> MicroExecutionDecision:
        side = "BUY" if str(direction).upper() == "BUY" else "SELL"
        snapshot = build_snapshot_from_bar(bar, self.config)

        fill_probability = self._fill_probability(side, snapshot)
        min_fill = self._get("micro_min_fill_probability", 0.15)
        if fill_probability < min_fill:
            return MicroExecutionDecision(
                filled=False,
                adjusted_price=base_price,
                fill_probability=fill_probability,
                fill_ratio=0.0,
                spread_cost=0.0,
                slippage_cost=0.0,
                adverse_selection_cost=0.0,
                latency_bars=int(getattr(self.config, "micro_latency_bars", 0) or 0),
                reason="insufficient_fill_probability",
                diagnostics={
                    "flow_imbalance": snapshot.flow_imbalance,
                    "dom_imbalance": snapshot.dom_imbalance,
                    "lva_velocity": snapshot.lva_velocity,
                    "volume": snapshot.volume,
                },
            )

        fill_ratio = self._fill_ratio(fill_probability)
        spread = self._spread_cost(bar.name)
        slippage = self._slippage_cost(side, snapshot, atr)
        adverse = self._adverse_selection_cost(side, snapshot, atr)
        adjusted_price = self._apply_side_costs(side, base_price, spread, slippage, adverse)

        return MicroExecutionDecision(
            filled=True,
            adjusted_price=adjusted_price,
            fill_probability=fill_probability,
            fill_ratio=fill_ratio,
            spread_cost=spread,
            slippage_cost=slippage,
            adverse_selection_cost=adverse,
            latency_bars=int(getattr(self.config, "micro_latency_bars", 0) or 0),
            reason="ok",
            diagnostics={
                "flow_imbalance": snapshot.flow_imbalance,
                "dom_imbalance": snapshot.dom_imbalance,
                "absorption_score": snapshot.absorption_score,
                "lva_velocity": snapshot.lva_velocity,
                "volume": snapshot.volume,
                "entry_side": 1.0 if side == "BUY" else -1.0,
            },
        )

    def simulate_exit(self, bar: Any, close_side: str, base_price: float, atr: float) -> MicroExecutionDecision:
        side = "BUY" if str(close_side).upper() == "BUY" else "SELL"
        snapshot = build_snapshot_from_bar(bar, self.config)

        fill_probability = self._fill_probability(side, snapshot)
        spread = self._spread_cost(bar.name)
        slippage = self._slippage_cost(side, snapshot, atr)
        adverse = self._adverse_selection_cost(side, snapshot, atr)

        # Exits should always complete: if liquidity looks poor, penalize price instead of rejecting.
        min_fill = self._get("micro_min_fill_probability", 0.15)
        if fill_probability < min_fill:
            penalty = 1.0 + (min_fill - fill_probability) * 3.0
            slippage *= penalty
            adverse *= penalty

        adjusted_price = self._apply_side_costs(side, base_price, spread, slippage, adverse)

        return MicroExecutionDecision(
            filled=True,
            adjusted_price=adjusted_price,
            fill_probability=fill_probability,
            fill_ratio=1.0,
            spread_cost=spread,
            slippage_cost=slippage,
            adverse_selection_cost=adverse,
            latency_bars=int(getattr(self.config, "micro_latency_bars", 0) or 0),
            reason="ok",
            diagnostics={
                "flow_imbalance": snapshot.flow_imbalance,
                "dom_imbalance": snapshot.dom_imbalance,
                "absorption_score": snapshot.absorption_score,
                "lva_velocity": snapshot.lva_velocity,
                "volume": snapshot.volume,
                "exit_side": 1.0 if side == "BUY" else -1.0,
            },
        )
