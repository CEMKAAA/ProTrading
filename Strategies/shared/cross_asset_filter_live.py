"""
Live Cross-Asset Regime Filter (fail-open).

This module provides a lightweight macro regime gate for live strategies.
It is intentionally resilient:
- Missing symbols/data -> allow trade (fail-open)
- Runtime errors -> allow trade (fail-open)
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Dict, Optional, Tuple

import numpy as np


@dataclass
class LiveRegimeDecision:
    enabled: bool
    score: float
    confidence: float
    bias: str
    risk_multiplier_long: float
    risk_multiplier_short: float
    reason: str


class LiveCrossAssetRegimeFilter:
    """Macro filter for gold live strategies."""

    def __init__(self, mt5_module, logger, timeframe, settings: Dict[str, object]):
        self.mt5 = mt5_module
        self.logger = logger
        self.timeframe = timeframe
        self.settings = dict(settings or {})
        self._selected_symbols: Dict[str, str] = {}
        self._last_eval_ts: Optional[datetime] = None
        self._last_decision: Optional[LiveRegimeDecision] = None

    def update_settings(self, settings: Dict[str, object]):
        self.settings = dict(settings or {})

    @staticmethod
    def _split_candidates(value: object) -> list[str]:
        if value is None:
            return []
        text = str(value).strip()
        if not text:
            return []
        return [x.strip() for x in text.split(",") if x.strip()]

    def _get_setting(self, key: str, default):
        return self.settings.get(key, default)

    def _select_symbol(self, role: str, candidates: list[str]) -> Optional[str]:
        if role in self._selected_symbols:
            return self._selected_symbols[role]
        for symbol in candidates:
            try:
                if not self.mt5.symbol_select(symbol, True):
                    continue
                tick = self.mt5.symbol_info_tick(symbol)
                if tick is not None:
                    self._selected_symbols[role] = symbol
                    return symbol
            except Exception:
                continue
        return None

    def _get_returns_z(self, symbol: str, bars: int, ret_bars: int) -> Optional[float]:
        rates = self.mt5.copy_rates_from_pos(symbol, self.timeframe, 0, bars + ret_bars + 10)
        if rates is None or len(rates) < bars + ret_bars:
            return None
        close = np.array([r["close"] for r in rates], dtype=float)
        if len(close) < bars + ret_bars:
            return None

        rets = close[ret_bars:] / close[:-ret_bars] - 1.0
        if len(rets) < bars:
            return None
        sample = rets[-bars:]
        mean = float(np.mean(sample))
        std = float(np.std(sample))
        if std <= 1e-12:
            return 0.0
        z = (sample[-1] - mean) / std
        return float(np.clip(z, -4.0, 4.0))

    def _compute_decision(self) -> LiveRegimeDecision:
        enabled = bool(self._get_setting("enable_cross_asset_filter", False))
        if not enabled:
            return LiveRegimeDecision(
                enabled=False, score=0.0, confidence=0.0, bias="neutral",
                risk_multiplier_long=1.0, risk_multiplier_short=1.0,
                reason="cross_asset_filter_disabled",
            )

        lookback = int(self._get_setting("regime_lookback_bars", 96))
        ret_bars = int(self._get_setting("regime_return_bars", 8))
        signal_th = float(self._get_setting("regime_signal_threshold", 0.18))

        weights = {
            "dxy": float(self._get_setting("regime_weight_dxy", 0.40)),
            "yield": float(self._get_setting("regime_weight_yield", 0.35)),
            "riskoff": float(self._get_setting("regime_weight_riskoff", 0.15)),
            "riskon": float(self._get_setting("regime_weight_riskon", 0.10)),
        }

        symbols = {
            "dxy": self._select_symbol("dxy", self._split_candidates(self._get_setting("regime_symbol_dxy", ""))),
            "yield": self._select_symbol("yield", self._split_candidates(self._get_setting("regime_symbol_yield", ""))),
            "riskoff": self._select_symbol("riskoff", self._split_candidates(self._get_setting("regime_symbol_riskoff", ""))),
            "riskon": self._select_symbol("riskon", self._split_candidates(self._get_setting("regime_symbol_riskon", ""))),
        }

        values = {}
        active_w = 0.0
        score_num = 0.0

        for role, symbol in symbols.items():
            if not symbol:
                continue
            z = self._get_returns_z(symbol, lookback, ret_bars)
            if z is None:
                continue
            # Gold mapping signs
            if role in ("dxy", "yield", "riskon"):
                z = -z
            w = max(0.0, weights.get(role, 0.0))
            if w <= 0.0:
                continue
            values[role] = z
            active_w += w
            score_num += z * w

        if active_w <= 0.0:
            return LiveRegimeDecision(
                enabled=False, score=0.0, confidence=0.0, bias="neutral",
                risk_multiplier_long=1.0, risk_multiplier_short=1.0,
                reason="cross_asset_fail_open_no_driver_data",
            )

        score = float(np.tanh(score_num / active_w))
        confidence = abs(score)
        if score > signal_th:
            bias = "bullish"
        elif score < -signal_th:
            bias = "bearish"
        else:
            bias = "neutral"

        tail = float(self._get_setting("regime_tailwind_risk_multiplier", 1.15))
        head = float(self._get_setting("regime_headwind_risk_multiplier", 0.50))
        neu = float(self._get_setting("regime_neutral_risk_multiplier", 1.00))

        if bias == "bullish":
            long_mul, short_mul = tail, head
        elif bias == "bearish":
            long_mul, short_mul = head, tail
        else:
            long_mul = short_mul = neu

        return LiveRegimeDecision(
            enabled=True,
            score=score,
            confidence=confidence,
            bias=bias,
            risk_multiplier_long=long_mul,
            risk_multiplier_short=short_mul,
            reason=f"cross_asset_{bias}",
        )

    def evaluate(self) -> LiveRegimeDecision:
        try:
            interval = int(self._get_setting("regime_eval_interval_seconds", 30))
            now = datetime.utcnow()
            if self._last_decision is not None and self._last_eval_ts is not None:
                if (now - self._last_eval_ts).total_seconds() < max(1, interval):
                    return self._last_decision

            self._last_decision = self._compute_decision()
            self._last_eval_ts = now
            return self._last_decision
        except Exception as e:
            self.logger.debug(f"Cross-asset evaluation failed (fail-open): {e}")
            return LiveRegimeDecision(
                enabled=False, score=0.0, confidence=0.0, bias="neutral",
                risk_multiplier_long=1.0, risk_multiplier_short=1.0,
                reason="cross_asset_fail_open_exception",
            )

    def allow_trade(self, direction: str) -> Tuple[bool, float, LiveRegimeDecision, str]:
        decision = self.evaluate()
        direction = str(direction).upper()
        is_buy = direction == "BUY"

        if is_buy:
            multiplier = decision.risk_multiplier_long
            aligned = decision.bias in ("bullish", "neutral")
        else:
            multiplier = decision.risk_multiplier_short
            aligned = decision.bias in ("bearish", "neutral")

        block_countertrend = bool(self._get_setting("regime_block_countertrend", True))
        signal_th = float(self._get_setting("regime_signal_threshold", 0.18))

        if decision.enabled and block_countertrend and decision.confidence >= signal_th and not aligned:
            return False, 0.0, decision, "blocked_countertrend_by_cross_asset_regime"

        # Fail-open and neutral path both arrive here.
        return True, float(np.clip(multiplier, 0.05, 2.0)), decision, decision.reason
