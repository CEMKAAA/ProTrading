"""
Cross-Asset Regime Filter

Macro-aware filter for gold strategies using external drivers:
- DXY proxy (inverse to gold)
- Yield proxy (inverse to gold)
- Risk-off proxy (positive to gold, e.g. VIX)
- Risk-on proxy (inverse to gold, e.g. SPX500)

The filter is intentionally conservative:
- If drivers are unavailable, it degrades gracefully.
- If confidence is low, it remains neutral.
"""

from __future__ import annotations

from dataclasses import dataclass, asdict
from datetime import datetime
from typing import Dict, Optional, Tuple
import logging

import numpy as np
import pandas as pd

logger = logging.getLogger(__name__)


@dataclass
class RegimeDecision:
    """Decision snapshot for a timestamp."""
    score: float
    confidence: float
    bias: str
    label: str
    risk_multiplier_long: float
    risk_multiplier_short: float
    reason: str
    timestamp: Optional[datetime] = None


class CrossAssetRegimeFilter:
    """
    Cross-asset macro filter for gold setups.

    Produces a continuous regime score in [-1, +1]:
    - Positive score => gold-friendly ("bullish" macro)
    - Negative score => gold-headwind ("bearish" macro)
    """

    def __init__(
        self,
        provider,
        cfg,
        base_df: pd.DataFrame,
        start_date: datetime,
        end_date: datetime,
        data_source: str = "auto",
    ):
        self.provider = provider
        self.cfg = cfg
        self.base_df = base_df
        self.start_date = start_date
        self.end_date = end_date
        self.data_source = data_source

        self._series: Dict[str, pd.Series] = {}
        self._selected_symbols: Dict[str, str] = {}
        self._regime_df: Optional[pd.DataFrame] = None
        self._enabled = bool(getattr(cfg, "enable_cross_asset_filter", False))
        self._coverage = 0.0

        self.stats: Dict[str, object] = {
            "enabled": self._enabled,
            "selected_symbols": {},
            "coverage_ratio": 0.0,
            "activation_valid": False,
            "activation_reason": "not_built",
            "min_required_drivers": 3,
            "min_coverage_activation": 0.90,
            "driver_count": 0,
            "all_core_drivers_available": False,
            "skipped_countertrend": 0,
            "accepted_trades": 0,
            "long_headwind_scaled": 0,
            "short_headwind_scaled": 0,
        }

        if not self._enabled:
            return

        self._build()

    @property
    def enabled(self) -> bool:
        return self._enabled and self._regime_df is not None and not self._regime_df.empty

    def _parse_candidates(self, text: str) -> list[str]:
        if not text:
            return []
        return [x.strip() for x in str(text).split(",") if x.strip()]

    def _load_best_symbol(self, candidates: list[str], timeframe: str) -> Tuple[Optional[str], Optional[pd.Series]]:
        for symbol in candidates:
            try:
                df = self.provider.get_historical_data(
                    symbol=symbol,
                    timeframe=timeframe,
                    start_date=self.start_date,
                    end_date=self.end_date,
                    use_cache=True,
                    data_source=self.data_source,
                    csv_files=None,
                )
            except Exception as e:
                logger.debug(f"Regime candidate {symbol} fetch failed: {e}")
                continue

            if df is None or df.empty or "close" not in df.columns:
                continue

            s = df["close"].copy().dropna()
            if s.empty:
                continue
            return symbol, s
        return None, None

    def _align_to_base(self, s: pd.Series) -> pd.Series:
        # Align driver to strategy timeframe by forward filling.
        aligned = s.reindex(self.base_df.index, method="ffill")
        return aligned

    def _safe_zscore(self, series: pd.Series, window: int) -> pd.Series:
        min_periods = max(8, window // 4)
        mean = series.rolling(window=window, min_periods=min_periods).mean()
        std = series.rolling(window=window, min_periods=min_periods).std()
        z = (series - mean) / std.replace(0, np.nan)
        return z.clip(-4.0, 4.0)

    def _build(self):
        timeframe = getattr(self.cfg, "regime_timeframe", None) or getattr(self.cfg, "timeframe", "M15")
        min_required_drivers = int(getattr(self.cfg, "regime_min_required_drivers", 3))
        min_coverage_activation = float(getattr(self.cfg, "regime_min_coverage_activation", 0.90))
        self.stats["min_required_drivers"] = min_required_drivers
        self.stats["min_coverage_activation"] = min_coverage_activation

        candidates = {
            "dxy": self._parse_candidates(getattr(self.cfg, "regime_symbol_dxy", "")),
            "yield": self._parse_candidates(getattr(self.cfg, "regime_symbol_yield", "")),
            "riskoff": self._parse_candidates(getattr(self.cfg, "regime_symbol_riskoff", "")),
            "riskon": self._parse_candidates(getattr(self.cfg, "regime_symbol_riskon", "")),
        }

        for key, values in candidates.items():
            symbol, series = self._load_best_symbol(values, timeframe)
            if symbol and series is not None:
                self._selected_symbols[key] = symbol
                self._series[key] = self._align_to_base(series)

        self.stats["selected_symbols"] = dict(self._selected_symbols)
        self.stats["driver_count"] = len(self._selected_symbols)
        core_roles = {"dxy", "yield", "riskoff"}
        all_core = core_roles.issubset(set(self._selected_symbols.keys()))
        self.stats["all_core_drivers_available"] = all_core

        if not self._series:
            logger.warning("Cross-asset filter enabled but no driver symbols were available. Disabling filter.")
            self._enabled = False
            self.stats["enabled"] = False
            self.stats["activation_reason"] = "no_driver_symbols"
            return

        if len(self._selected_symbols) < min_required_drivers:
            logger.warning(
                "Cross-asset filter disabled: only %s driver(s) available, minimum required is %s.",
                len(self._selected_symbols),
                min_required_drivers,
            )
            self._enabled = False
            self.stats["enabled"] = False
            self.stats["activation_reason"] = "insufficient_driver_count"
            return

        lookback = int(getattr(self.cfg, "regime_lookback_bars", 96))
        return_bars = int(getattr(self.cfg, "regime_return_bars", 8))

        components = {}
        weights = {}

        # DXY up is typically bearish for gold => invert sign.
        if "dxy" in self._series:
            ret = self._series["dxy"].pct_change(return_bars)
            components["dxy"] = -self._safe_zscore(ret, lookback)
            weights["dxy"] = float(getattr(self.cfg, "regime_weight_dxy", 0.40))

        # Yields up are typically bearish for gold => invert sign.
        if "yield" in self._series:
            ret = self._series["yield"].pct_change(return_bars)
            components["yield"] = -self._safe_zscore(ret, lookback)
            weights["yield"] = float(getattr(self.cfg, "regime_weight_yield", 0.35))

        # Risk-off proxy (e.g. VIX) up is typically bullish for gold.
        if "riskoff" in self._series:
            ret = self._series["riskoff"].pct_change(return_bars)
            components["riskoff"] = self._safe_zscore(ret, lookback)
            weights["riskoff"] = float(getattr(self.cfg, "regime_weight_riskoff", 0.15))

        # Risk-on proxy (e.g. SPX) up is typically bearish for gold => invert sign.
        if "riskon" in self._series:
            ret = self._series["riskon"].pct_change(return_bars)
            components["riskon"] = -self._safe_zscore(ret, lookback)
            weights["riskon"] = float(getattr(self.cfg, "regime_weight_riskon", 0.10))

        if not components:
            logger.warning("Cross-asset filter has no valid components after preprocessing. Disabling filter.")
            self._enabled = False
            self.stats["enabled"] = False
            self.stats["activation_reason"] = "no_valid_components"
            return

        comp_df = pd.DataFrame(components, index=self.base_df.index)
        weight_series = pd.Series(weights)

        valid_mask = comp_df.notna()
        weighted_values = comp_df.mul(weight_series, axis=1)
        weighted_sum = weighted_values.sum(axis=1, skipna=True)
        active_weight = (valid_mask * weight_series).sum(axis=1)
        raw_score = weighted_sum / active_weight.replace(0, np.nan)

        score = np.tanh(raw_score)
        confidence = score.abs()
        signal_threshold = float(getattr(self.cfg, "regime_signal_threshold", 0.18))
        strong_threshold = float(getattr(self.cfg, "regime_strong_threshold", 0.40))

        bias = np.where(score > signal_threshold, "bullish",
                        np.where(score < -signal_threshold, "bearish", "neutral"))
        label = np.where(
            (bias == "bullish") & (confidence >= strong_threshold), "superbid",
            np.where((bias == "bearish") & (confidence >= strong_threshold), "headwind", "neutral"),
        )

        self._regime_df = pd.DataFrame(
            {
                "score": score,
                "confidence": confidence,
                "bias": bias,
                "label": label,
                "active_weight": active_weight,
            },
            index=self.base_df.index,
        )

        self._coverage = float(self._regime_df["score"].notna().mean())
        self.stats["coverage_ratio"] = self._coverage
        self.stats["activation_reason"] = "active"
        self.stats["activation_valid"] = True

        if self._coverage < min_coverage_activation:
            logger.warning(
                "Cross-asset filter disabled: coverage too low (%.2f%%), required >= %.2f%%.",
                self._coverage * 100.0,
                min_coverage_activation * 100.0,
            )
            self._enabled = False
            self.stats["enabled"] = False
            self.stats["activation_valid"] = False
            self.stats["activation_reason"] = "low_coverage"

    def _get_row(self, ts: datetime) -> Optional[pd.Series]:
        if not self.enabled:
            return None

        timestamp = pd.Timestamp(ts)
        idx = self._regime_df.index
        if idx.tz is not None and timestamp.tzinfo is None:
            timestamp = timestamp.tz_localize(idx.tz)
        elif idx.tz is None and timestamp.tzinfo is not None:
            timestamp = timestamp.tz_localize(None)

        row_key = idx.asof(timestamp)
        if pd.isna(row_key):
            return None
        return self._regime_df.loc[row_key]

    def evaluate(self, ts: datetime) -> RegimeDecision:
        if not self.enabled:
            return RegimeDecision(
                score=0.0,
                confidence=0.0,
                bias="neutral",
                label="neutral",
                risk_multiplier_long=1.0,
                risk_multiplier_short=1.0,
                reason="cross_asset_filter_disabled",
                timestamp=ts,
            )

        row = self._get_row(ts)
        if row is None or pd.isna(row["score"]):
            return RegimeDecision(
                score=0.0,
                confidence=0.0,
                bias="neutral",
                label="neutral",
                risk_multiplier_long=float(getattr(self.cfg, "regime_neutral_risk_multiplier", 1.0)),
                risk_multiplier_short=float(getattr(self.cfg, "regime_neutral_risk_multiplier", 1.0)),
                reason="cross_asset_missing_at_timestamp",
                timestamp=ts,
            )

        tailwind = float(getattr(self.cfg, "regime_tailwind_risk_multiplier", 1.15))
        headwind = float(getattr(self.cfg, "regime_headwind_risk_multiplier", 0.50))
        neutral = float(getattr(self.cfg, "regime_neutral_risk_multiplier", 1.00))

        bias = str(row["bias"])
        if bias == "bullish":
            long_mul, short_mul = tailwind, headwind
        elif bias == "bearish":
            long_mul, short_mul = headwind, tailwind
        else:
            long_mul = short_mul = neutral

        return RegimeDecision(
            score=float(row["score"]),
            confidence=float(row["confidence"]),
            bias=bias,
            label=str(row["label"]),
            risk_multiplier_long=long_mul,
            risk_multiplier_short=short_mul,
            reason=f"cross_asset_{bias}",
            timestamp=ts,
        )

    def allow_trade(self, direction: str, ts: datetime) -> Tuple[bool, float, RegimeDecision, str]:
        """
        Decide if a direction is allowed and return risk multiplier.

        Returns:
            (allowed, risk_multiplier, decision, reason)
        """
        decision = self.evaluate(ts)
        direction = direction.upper()
        is_buy = direction == "BUY"

        if is_buy:
            multiplier = decision.risk_multiplier_long
            aligned = decision.bias in ("bullish", "neutral")
        else:
            multiplier = decision.risk_multiplier_short
            aligned = decision.bias in ("bearish", "neutral")

        block_countertrend = bool(getattr(self.cfg, "regime_block_countertrend", True))
        reduce_headwind = bool(getattr(self.cfg, "regime_reduce_size_in_headwind", True))
        signal_threshold = float(getattr(self.cfg, "regime_signal_threshold", 0.18))
        all_core = bool(self.stats.get("all_core_drivers_available", False))

        # Safety guard: never hard-block on partial driver sets.
        if block_countertrend and all_core and decision.confidence >= signal_threshold and not aligned:
            self.stats["skipped_countertrend"] = int(self.stats["skipped_countertrend"]) + 1
            return False, 0.0, decision, "blocked_countertrend_by_cross_asset_regime"

        if not aligned and reduce_headwind:
            if is_buy:
                self.stats["long_headwind_scaled"] = int(self.stats["long_headwind_scaled"]) + 1
            else:
                self.stats["short_headwind_scaled"] = int(self.stats["short_headwind_scaled"]) + 1

        self.stats["accepted_trades"] = int(self.stats["accepted_trades"]) + 1
        return True, multiplier, decision, "allowed_by_cross_asset_regime"

    def summary(self) -> Dict[str, object]:
        out = dict(self.stats)
        if self.enabled and self._regime_df is not None:
            out["regime_distribution"] = (
                self._regime_df["label"].value_counts(normalize=True).round(4).to_dict()
            )
        return out

    @staticmethod
    def decision_to_metadata(decision: RegimeDecision) -> Dict[str, object]:
        data = asdict(decision)
        if isinstance(data.get("timestamp"), datetime):
            data["timestamp"] = data["timestamp"].isoformat()
        return data
