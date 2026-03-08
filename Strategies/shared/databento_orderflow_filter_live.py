"""
Live Databento Orderflow Filter (fail-open).

Provides a lightweight microstructure gate for live strategies:
- Uses recent trade prints from Databento historical API
- Computes signed flow imbalance + short-horizon price impulse
- Blocks or scales counterflow trades when enabled

Safety:
- Missing API key/package/network/data -> allow trade (fail-open)
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Dict, Optional, Tuple
import os

import numpy as np


@dataclass
class LiveOrderflowDecision:
    enabled: bool
    score: float
    confidence: float
    bias: str
    risk_multiplier_long: float
    risk_multiplier_short: float
    sample_count: int
    reason: str


class LiveDatabentoOrderflowFilter:
    """Databento-backed orderflow gate for live execution."""

    def __init__(self, logger, settings: Dict[str, object]):
        self.logger = logger
        self.settings = dict(settings or {})
        self._client = None
        self._api_key: Optional[str] = None
        self._last_eval_ts: Optional[datetime] = None
        self._last_decision: Optional[LiveOrderflowDecision] = None

    def update_settings(self, settings: Dict[str, object]):
        self.settings = dict(settings or {})

    def _get_setting(self, key: str, default):
        return self.settings.get(key, default)

    @staticmethod
    def _load_env_api_key() -> Optional[str]:
        key = os.getenv("DATABENTO_API_KEY")
        if key:
            return key.strip()

        env_file = Path(__file__).resolve().parents[2] / "dashboard" / ".env"
        if not env_file.exists():
            return None
        try:
            for line in env_file.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if line.startswith("DATABENTO_API_KEY="):
                    return line.split("=", 1)[1].strip().strip('"').strip("'")
        except Exception:
            return None
        return None

    def _get_client(self):
        if self._client is not None:
            return self._client
        if self._api_key is None:
            self._api_key = self._load_env_api_key()
        if not self._api_key:
            return None
        try:
            import databento as db  # type: ignore
            self._client = db.Historical(self._api_key)
            return self._client
        except Exception as e:
            self.logger.debug(f"Databento client init failed (fail-open): {e}")
            return None

    def _fetch_recent_trades(self):
        client = self._get_client()
        if client is None:
            return None

        mode = str(self._get_setting("orderflow_data_mode", "historical_windowed")).strip().lower()
        if mode not in ("historical_windowed", "live_stream"):
            mode = "historical_windowed"

        dataset = str(self._get_setting("orderflow_dataset", "GLBX.MDP3"))
        schema = str(self._get_setting("orderflow_schema", "trades"))
        stype_in = str(self._get_setting("orderflow_stype_in", "raw_symbol"))
        symbol = str(self._get_setting("orderflow_symbol", "GC.c.0")).strip()
        lookback_min = int(self._get_setting("orderflow_lookback_minutes", 5))

        if not symbol:
            return None

        end = datetime.now(timezone.utc)
        start = end - timedelta(minutes=max(1, lookback_min))
        # v1: recent historical window fetch (not true event-stream live).
        if mode == "historical_windowed":
            try:
                data = client.timeseries.get_range(
                    dataset=dataset,
                    schema=schema,
                    stype_in=stype_in,
                    symbols=[symbol],
                    start=start,
                    end=end,
                )
                df = data.to_df()
                if df is None or len(df) == 0:
                    return None
                return df
            except Exception as e:
                self.logger.debug(f"Databento fetch failed (fail-open): {e}")
                return None

        # Placeholder for future true-streaming mode integration.
        self.logger.debug("Databento orderflow_data_mode=live_stream is not implemented yet; fail-open.")
        return None

    @staticmethod
    def _infer_sign(price: np.ndarray, side: Optional[np.ndarray]) -> np.ndarray:
        if side is not None and len(side) == len(price):
            out = np.zeros(len(side), dtype=float)
            for i, raw in enumerate(side):
                s = str(raw).upper()
                if s in ("B", "BUY", "1"):
                    out[i] = 1.0
                elif s in ("A", "S", "SELL", "-1"):
                    out[i] = -1.0
            if np.any(out != 0.0):
                return out

        diff = np.diff(price, prepend=price[0])
        sign = np.sign(diff)
        sign[sign == 0.0] = 1.0
        return sign

    def _compute_decision(self) -> LiveOrderflowDecision:
        enabled = bool(self._get_setting("enable_orderflow_filter", False))
        if not enabled:
            return LiveOrderflowDecision(
                enabled=False, score=0.0, confidence=0.0, bias="neutral",
                risk_multiplier_long=1.0, risk_multiplier_short=1.0,
                sample_count=0, reason="orderflow_filter_disabled",
            )

        df = self._fetch_recent_trades()
        min_trades = int(self._get_setting("orderflow_min_trades", 30))
        if df is None or len(df) < min_trades:
            return LiveOrderflowDecision(
                enabled=False, score=0.0, confidence=0.0, bias="neutral",
                risk_multiplier_long=1.0, risk_multiplier_short=1.0,
                sample_count=0 if df is None else int(len(df)),
                reason="orderflow_fail_open_insufficient_data",
            )

        cols = {str(c).lower(): c for c in df.columns}
        price_col = cols.get("price")
        size_col = cols.get("size")
        side_col = cols.get("side")
        if price_col is None or size_col is None:
            return LiveOrderflowDecision(
                enabled=False, score=0.0, confidence=0.0, bias="neutral",
                risk_multiplier_long=1.0, risk_multiplier_short=1.0,
                sample_count=int(len(df)),
                reason="orderflow_fail_open_missing_columns",
            )

        price = df[price_col].to_numpy(dtype=float)
        size = df[size_col].to_numpy(dtype=float)
        side = df[side_col].to_numpy() if side_col is not None else None
        sign = self._infer_sign(price, side)

        abs_flow = np.sum(np.abs(size))
        if abs_flow <= 1e-9:
            return LiveOrderflowDecision(
                enabled=False, score=0.0, confidence=0.0, bias="neutral",
                risk_multiplier_long=1.0, risk_multiplier_short=1.0,
                sample_count=int(len(df)),
                reason="orderflow_fail_open_zero_flow",
            )

        imbalance = float(np.sum(sign * size) / abs_flow)
        impulse = float((price[-1] - price[0]) / max(1e-9, price[0]))
        score = float(np.clip(0.75 * imbalance + 0.25 * np.tanh(impulse * 1000.0), -1.0, 1.0))
        confidence = abs(score)
        signal_th = float(self._get_setting("orderflow_signal_threshold", 0.15))

        if score > signal_th:
            bias = "bullish"
        elif score < -signal_th:
            bias = "bearish"
        else:
            bias = "neutral"

        tail = float(self._get_setting("orderflow_tailwind_risk_multiplier", 1.05))
        head = float(self._get_setting("orderflow_headwind_risk_multiplier", 0.80))
        neu = float(self._get_setting("orderflow_neutral_risk_multiplier", 1.00))

        if bias == "bullish":
            long_mul, short_mul = tail, head
        elif bias == "bearish":
            long_mul, short_mul = head, tail
        else:
            long_mul = short_mul = neu

        return LiveOrderflowDecision(
            enabled=True,
            score=score,
            confidence=confidence,
            bias=bias,
            risk_multiplier_long=long_mul,
            risk_multiplier_short=short_mul,
            sample_count=int(len(df)),
            reason=f"orderflow_{bias}_historical_windowed",
        )

    def evaluate(self) -> LiveOrderflowDecision:
        try:
            interval = int(self._get_setting("orderflow_eval_interval_seconds", 60))
            now = datetime.utcnow()
            if self._last_decision is not None and self._last_eval_ts is not None:
                if (now - self._last_eval_ts).total_seconds() < max(1, interval):
                    return self._last_decision
            self._last_decision = self._compute_decision()
            self._last_eval_ts = now
            return self._last_decision
        except Exception as e:
            self.logger.debug(f"Orderflow evaluation failed (fail-open): {e}")
            return LiveOrderflowDecision(
                enabled=False, score=0.0, confidence=0.0, bias="neutral",
                risk_multiplier_long=1.0, risk_multiplier_short=1.0,
                sample_count=0, reason="orderflow_fail_open_exception",
            )

    def allow_trade(self, direction: str) -> Tuple[bool, float, LiveOrderflowDecision, str]:
        decision = self.evaluate()
        is_buy = str(direction).upper() == "BUY"

        if is_buy:
            multiplier = decision.risk_multiplier_long
            aligned = decision.bias in ("bullish", "neutral")
        else:
            multiplier = decision.risk_multiplier_short
            aligned = decision.bias in ("bearish", "neutral")

        block_countertrend = bool(self._get_setting("orderflow_block_countertrend", True))
        reduce_headwind = bool(self._get_setting("orderflow_reduce_size_in_headwind", True))
        signal_th = float(self._get_setting("orderflow_signal_threshold", 0.15))

        if decision.enabled and block_countertrend and decision.confidence >= signal_th and not aligned:
            return False, 0.0, decision, "blocked_countertrend_by_orderflow"

        if not aligned and not reduce_headwind:
            multiplier = 1.0

        return True, float(np.clip(multiplier, 0.05, 2.0)), decision, decision.reason
