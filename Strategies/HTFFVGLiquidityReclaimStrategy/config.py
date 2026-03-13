"""
HTF FVG + Liquidity Reclaim live strategy configuration.

The dashboard stores runtime config at ``dashboard/data/<strategy>_config.json``.
This module merges that runtime payload with the product strategy registry preset
so live execution, backtest, and Workbench agent all draw from the same base
configuration surface.
"""

from __future__ import annotations

import json
import math
from datetime import time
from pathlib import Path
from typing import Any, Dict

import MetaTrader5 as mt5

from dashboard.backend.core.instrument_specs import get_instrument
from dashboard.backend.core.strategy_registry import StrategyRegistry
from dashboard.backend.core.workbench.analysis_utils import timeframe_to_minutes
from dashboard.backend.core.workbench.symbol_utils import normalize_strategy_symbol


STRATEGY_ID = "htf_fvg_liquidity_reclaim_strategy"
STRATEGY_NAME = "HTF FVG + Liquidity Reclaim"
STRATEGY_VERSION = "1.0.0"
MAGIC_NUMBER = 777109

_CONFIG_FILE = (
    Path(__file__).parent.parent.parent
    / "dashboard"
    / "data"
    / f"{STRATEGY_ID}_config.json"
)
STATE_FILE = (
    Path(__file__).parent.parent.parent
    / "dashboard"
    / "data"
    / f"{STRATEGY_ID}_state.json"
)

_RUNTIME_CONFIG: Dict[str, Any] = {}

_CONFIG_ALIASES: Dict[str, tuple[str, ...]] = {
    "preset": ("preset_name",),
    "max_spread_usd": ("max_spread",),
    "max_daily_loss_usd": ("max_daily_loss",),
    "max_total_risk_usd": ("max_total_risk",),
    "min_sl_usd": ("min_sl",),
    "max_sl_usd": ("max_sl",),
}

_TIMEFRAME_MAP = {
    "M1": mt5.TIMEFRAME_M1,
    "M5": mt5.TIMEFRAME_M5,
    "M15": mt5.TIMEFRAME_M15,
    "M30": mt5.TIMEFRAME_M30,
    "H1": mt5.TIMEFRAME_H1,
    "H4": mt5.TIMEFRAME_H4,
    "D1": mt5.TIMEFRAME_D1,
}


def _to_float(value: Any, default: float) -> float:
    try:
        out = float(value)
    except (TypeError, ValueError):
        return float(default)
    if not math.isfinite(out):
        return float(default)
    return float(out)


def _to_int(value: Any, default: int) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return int(default)


def _to_bool(value: Any, default: bool) -> bool:
    if value is None:
        return bool(default)
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        txt = value.strip().lower()
        if txt in {"1", "true", "yes", "on"}:
            return True
        if txt in {"0", "false", "no", "off"}:
            return False
    return bool(value)


def _parse_hhmm(value: Any, default_hhmm: str) -> time:
    txt = str(value or default_hhmm).strip()
    try:
        hh, mm = map(int, txt.split(":"))
        return time(hh, mm)
    except (TypeError, ValueError):
        hh, mm = map(int, default_hhmm.split(":"))
        return time(hh, mm)


def load_runtime_config() -> Dict[str, Any]:
    global _RUNTIME_CONFIG
    if _CONFIG_FILE.exists():
        try:
            with open(_CONFIG_FILE, "r", encoding="utf-8") as f:
                raw = json.load(f)
            _RUNTIME_CONFIG = raw if isinstance(raw, dict) else {}
        except Exception:
            _RUNTIME_CONFIG = {}
    else:
        _RUNTIME_CONFIG = {}
    return dict(_RUNTIME_CONFIG)


def _canonicalize_runtime_config(runtime_config: Dict[str, Any]) -> Dict[str, Any]:
    out: Dict[str, Any] = {}
    for key, value in (runtime_config or {}).items():
        if value is None:
            continue
        out[str(key)] = value
    for canonical, aliases in _CONFIG_ALIASES.items():
        if canonical in out:
            continue
        for alias in aliases:
            if alias in out:
                out[canonical] = out[alias]
                break
    return out


def _compute_data_cache_bars(cfg: Dict[str, Any]) -> int:
    exec_tf_min = max(1, timeframe_to_minutes(cfg.get("timeframe"), 15))
    htf_minutes = [
        timeframe_to_minutes(cfg.get("htf_timeframe"), 240),
        timeframe_to_minutes(cfg.get("secondary_htf_timeframe"), 60),
    ]
    bars_for_htf_bias = max(60, int(math.ceil((max(htf_minutes) * 60.0) / float(exec_tf_min))))
    required = max(200, _to_int(cfg.get("required_lookback_bars"), 500))
    liq_lookback = max(120, _to_int(cfg.get("ltf_pool_lookback_bars"), 420))
    return max(required + 50, liq_lookback + 50, bars_for_htf_bias + 100)


def build_live_strategy_config(runtime_config: Dict[str, Any] | None = None) -> Dict[str, Any]:
    runtime = _canonicalize_runtime_config(runtime_config or load_runtime_config())
    exact_symbol = str(runtime.get("symbol") or "XAUUSD").strip() or "XAUUSD"
    base_symbol = normalize_strategy_symbol(exact_symbol) or exact_symbol.strip().upper() or "XAUUSD"
    requested_preset = str(runtime.get("preset") or "default").strip().lower() or "default"

    preset_cfg = StrategyRegistry.get_preset_config(STRATEGY_ID, requested_preset, base_symbol)
    preset_id = requested_preset
    if not isinstance(preset_cfg, dict) or not preset_cfg:
        preset_cfg = StrategyRegistry.get_preset_config(STRATEGY_ID, "default", base_symbol)
        preset_id = "default"

    merged: Dict[str, Any] = dict(preset_cfg or {})
    merged.update(runtime)

    inst = get_instrument(base_symbol)
    merged["symbol"] = exact_symbol
    merged["base_symbol"] = base_symbol
    merged["preset_id"] = preset_id
    merged["timeframe"] = str(merged.get("timeframe") or "M15").strip().upper() or "M15"
    merged["initial_balance"] = _to_float(merged.get("initial_balance"), 10000.0)
    merged.setdefault("contract_size", inst.contract_size)
    merged.setdefault("max_spread_usd", inst.max_spread)
    merged.setdefault("min_sl_usd", inst.min_sl)
    merged.setdefault("max_sl_usd", inst.max_sl)
    merged.setdefault("commission_per_lot", inst.commission_per_lot)
    merged.setdefault("slippage_atr_factor", inst.slippage_atr_factor)
    merged.setdefault("friday_close_hour", 15)
    merged.setdefault("friday_close_minute", 30)
    merged.setdefault("trade_start_time", "03:00")
    merged.setdefault("trade_end_time", "20:00")
    merged.setdefault("use_trailing", True)
    merged.setdefault("trailing_atr_period", 14)
    merged.setdefault("trailing_atr_multiplier", 2.0)
    merged.setdefault("required_lookback_bars", 500)
    merged["data_cache_bars"] = _compute_data_cache_bars(merged)
    merged["min_bars_for_analysis"] = max(
        _to_int(merged.get("required_lookback_bars"), 500),
        200,
    )
    return merged


STRATEGY_CONFIG = build_live_strategy_config()

TARGET_SYMBOL = str(STRATEGY_CONFIG.get("symbol") or "XAUUSD")
BASE_SYMBOL = str(STRATEGY_CONFIG.get("base_symbol") or normalize_strategy_symbol(TARGET_SYMBOL) or TARGET_SYMBOL)
PRESET_ID = str(STRATEGY_CONFIG.get("preset_id") or "default")
TIMEFRAME_LABEL = str(STRATEGY_CONFIG.get("timeframe") or "M15").upper()
TIMEFRAME = _TIMEFRAME_MAP.get(TIMEFRAME_LABEL, mt5.TIMEFRAME_M15)

RISK_PERCENT = _to_float(STRATEGY_CONFIG.get("risk_percent"), 0.75)
MAX_SPREAD_USD = _to_float(STRATEGY_CONFIG.get("max_spread_usd"), 0.40)
MAX_DAILY_LOSS_USD = -abs(_to_float(STRATEGY_CONFIG.get("max_daily_loss_usd"), 100.0))
MAX_TOTAL_RISK_USD = _to_float(STRATEGY_CONFIG.get("max_total_risk_usd"), 150.0)
MAX_DAILY_TRADES = _to_int(STRATEGY_CONFIG.get("max_daily_trades"), 2)
INITIAL_BALANCE = _to_float(STRATEGY_CONFIG.get("initial_balance"), 10000.0)
MIN_SL_USD = _to_float(STRATEGY_CONFIG.get("min_sl_usd"), 1.0)
MAX_SL_USD = _to_float(STRATEGY_CONFIG.get("max_sl_usd"), 15.0)
MIN_RR_RATIO = _to_float(STRATEGY_CONFIG.get("min_rr_ratio"), 2.5)
USE_TRAILING = _to_bool(STRATEGY_CONFIG.get("use_trailing"), True)
TRAILING_ATR_PERIOD = _to_int(STRATEGY_CONFIG.get("trailing_atr_period"), 14)
TRAILING_ATR_MULTIPLIER = _to_float(STRATEGY_CONFIG.get("trailing_atr_multiplier"), 2.0)
DATA_CACHE_BARS = _to_int(STRATEGY_CONFIG.get("data_cache_bars"), 1200)
MIN_BARS_FOR_ANALYSIS = _to_int(STRATEGY_CONFIG.get("min_bars_for_analysis"), 500)
TRADE_START_TIME = _parse_hhmm(STRATEGY_CONFIG.get("trade_start_time"), "03:00")
TRADE_END_TIME = _parse_hhmm(STRATEGY_CONFIG.get("trade_end_time"), "20:00")
FRIDAY_CLOSE_HOUR = _to_int(STRATEGY_CONFIG.get("friday_close_hour"), 15)
FRIDAY_CLOSE_MINUTE = _to_int(STRATEGY_CONFIG.get("friday_close_minute"), 30)
POLL_INTERVAL_SECONDS = max(2, _to_int(STRATEGY_CONFIG.get("poll_interval_seconds"), 10))
