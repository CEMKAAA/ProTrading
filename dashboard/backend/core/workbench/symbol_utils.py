"""Symbol normalization helpers for broker-suffixed instrument names."""

from __future__ import annotations

import re
from typing import Any, Dict, Tuple

# Strategy instruments currently calibrated in tool defaults.
_KNOWN_BASES: Tuple[str, ...] = (
    "XAUUSD",
    "NAS100",
    "US500",
    "GBPUSD",
    "EURUSD",
)

_ALIASES: Dict[str, str] = {
    "GOLD": "XAUUSD",
    "XAU": "XAUUSD",
    "SPX500": "US500",
    "USTEC": "NAS100",
}


def normalize_strategy_symbol(symbol: Any) -> str:
    """Map broker-specific symbol variants to strategy base symbols.

    Examples:
    - XAUUSDm -> XAUUSD
    - XAUUSD.r -> XAUUSD
    - NAS100.cash -> NAS100
    - US500_mini -> US500
    """
    raw = str(symbol or "").strip().upper()
    if not raw:
        return ""

    if raw in _ALIASES:
        return _ALIASES[raw]
    if raw in _KNOWN_BASES:
        return raw

    tokens = [tok for tok in re.split(r"[^A-Z0-9]+", raw) if tok]
    for tok in tokens:
        if tok in _ALIASES:
            return _ALIASES[tok]
        if tok in _KNOWN_BASES:
            return tok
        for base in _KNOWN_BASES:
            if tok.startswith(base):
                return base

    compact = re.sub(r"[^A-Z0-9]", "", raw)
    if compact in _ALIASES:
        return _ALIASES[compact]
    if compact in _KNOWN_BASES:
        return compact
    for base in _KNOWN_BASES:
        if compact.startswith(base):
            return base
    for base in _KNOWN_BASES:
        if base in compact:
            return base
    return compact
