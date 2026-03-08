"""Centralized instrument metadata registry.

Every symbol-specific constant (contract size, pip value, spread model,
lot limits, round-number interval, etc.) lives here.  Strategy code and
the backtest engine should look up values from ``get_instrument()``
instead of hardcoding Gold assumptions.
"""

from dataclasses import dataclass, field
from typing import Dict, Optional


@dataclass(frozen=True)
class InstrumentSpec:
    """Immutable specification for a single trading instrument."""

    symbol: str

    # --- Contract ---
    contract_size: float          # units per standard lot (Gold: 100 oz, FX: 100_000)
    point_value: float            # smallest price increment (Gold: 0.01, EURUSD: 0.00001)
    digits: int                   # decimal places for display (Gold: 2, FX5: 5)

    # --- Spread (base, in price units — NOT pips) ---
    spread_base: float            # typical spread in price terms
    max_spread: float             # reject-trade threshold

    # --- Lot sizing ---
    min_lot: float = 0.01
    max_lot: float = 10.0
    lot_step: float = 0.01

    # --- Stop-loss bounds (price units) ---
    min_sl: float = 1.0
    max_sl: float = 15.0

    # --- Commission (USD round-trip per lot) ---
    commission_per_lot: float = 3.50

    # --- Swap (per lot per night, USD) ---
    swap_long: float = -8.50
    swap_short: float = -3.20
    triple_swap_day: int = 2      # 0=Mon … 4=Fri

    # --- Slippage model ---
    slippage_atr_factor: float = 0.02
    min_slippage: float = 0.01
    max_slippage: float = 0.50

    # --- Round numbers ---
    round_number_interval: float = 100.0   # Gold=$100, FX=0.0100

    # --- R:R threshold ---
    rr_threshold: float = 3.0     # minimum R:R for Gold; 2.0 for FX

    # --- FVG gap minimum (price units) ---
    min_fvg_gap: float = 0.30


# =========================================================================
# Built-in instrument definitions
# =========================================================================

XAUUSD = InstrumentSpec(
    symbol="XAUUSD",
    contract_size=100.0,
    point_value=0.01,
    digits=2,
    spread_base=0.20,
    max_spread=0.40,
    min_lot=0.01,
    max_lot=10.0,
    lot_step=0.01,
    min_sl=1.0,
    max_sl=15.0,
    commission_per_lot=3.50,
    swap_long=-8.50,
    swap_short=-3.20,
    triple_swap_day=2,
    slippage_atr_factor=0.02,
    min_slippage=0.01,
    max_slippage=0.50,
    round_number_interval=100.0,
    rr_threshold=3.0,
    min_fvg_gap=0.30,
)

XAGUSD = InstrumentSpec(
    symbol="XAGUSD",
    contract_size=5000.0,
    point_value=0.001,
    digits=3,
    spread_base=0.020,
    max_spread=0.040,
    min_lot=0.01,
    max_lot=10.0,
    lot_step=0.01,
    min_sl=0.10,
    max_sl=1.50,
    commission_per_lot=3.50,
    swap_long=-4.00,
    swap_short=-1.50,
    triple_swap_day=2,
    slippage_atr_factor=0.02,
    min_slippage=0.002,
    max_slippage=0.050,
    round_number_interval=1.0,
    rr_threshold=2.5,
    min_fvg_gap=0.030,
)

EURUSD = InstrumentSpec(
    symbol="EURUSD",
    contract_size=100_000.0,
    point_value=0.00001,
    digits=5,
    spread_base=0.00010,
    max_spread=0.00020,
    min_lot=0.01,
    max_lot=50.0,
    lot_step=0.01,
    min_sl=0.00050,
    max_sl=0.00500,
    commission_per_lot=3.00,
    swap_long=-6.50,
    swap_short=1.20,
    triple_swap_day=2,
    slippage_atr_factor=0.015,
    min_slippage=0.00002,
    max_slippage=0.00030,
    round_number_interval=0.0100,
    rr_threshold=2.0,
    min_fvg_gap=0.00020,
)

GBPUSD = InstrumentSpec(
    symbol="GBPUSD",
    contract_size=100_000.0,
    point_value=0.00001,
    digits=5,
    spread_base=0.00012,
    max_spread=0.00030,
    min_lot=0.01,
    max_lot=50.0,
    lot_step=0.01,
    min_sl=0.00060,
    max_sl=0.00600,
    commission_per_lot=3.00,
    swap_long=-5.00,
    swap_short=0.50,
    triple_swap_day=2,
    slippage_atr_factor=0.015,
    min_slippage=0.00003,
    max_slippage=0.00040,
    round_number_interval=0.0100,
    rr_threshold=2.0,
    min_fvg_gap=0.00025,
)

USDJPY = InstrumentSpec(
    symbol="USDJPY",
    contract_size=100_000.0,
    point_value=0.001,
    digits=3,
    spread_base=0.012,
    max_spread=0.030,
    min_lot=0.01,
    max_lot=50.0,
    lot_step=0.01,
    min_sl=0.050,
    max_sl=0.500,
    commission_per_lot=3.00,
    swap_long=3.50,
    swap_short=-8.00,
    triple_swap_day=2,
    slippage_atr_factor=0.015,
    min_slippage=0.003,
    max_slippage=0.030,
    round_number_interval=1.0,
    rr_threshold=2.0,
    min_fvg_gap=0.020,
)

US500 = InstrumentSpec(
    symbol="US500",
    contract_size=1.0,            # 1 contract = $1 per point
    point_value=0.01,
    digits=2,
    spread_base=0.40,             # ~0.4 points typical
    max_spread=1.00,              # reject above 1 point
    min_lot=0.01,
    max_lot=100.0,
    lot_step=0.01,
    min_sl=5.0,                   # 5 points minimum SL
    max_sl=50.0,                  # 50 points max SL
    commission_per_lot=2.00,
    swap_long=-12.00,
    swap_short=2.50,
    triple_swap_day=2,
    slippage_atr_factor=0.015,
    min_slippage=0.05,
    max_slippage=1.00,
    round_number_interval=100.0,  # $100 round numbers (5800, 5900, etc.)
    rr_threshold=2.0,
    min_fvg_gap=1.00,
)

NAS100 = InstrumentSpec(
    symbol="NAS100",
    contract_size=1.0,            # 1 contract = $1 per point (CFD)
    point_value=0.01,
    digits=2,
    spread_base=1.00,             # ~1 point typical spread
    max_spread=3.00,              # reject above 3 points
    min_lot=0.01,
    max_lot=100.0,
    lot_step=0.01,
    min_sl=10.0,                  # 10 points minimum SL
    max_sl=100.0,                 # 100 points max SL
    commission_per_lot=2.00,
    swap_long=-15.00,
    swap_short=3.00,
    triple_swap_day=2,
    slippage_atr_factor=0.015,
    min_slippage=0.10,
    max_slippage=2.00,
    round_number_interval=500.0,  # $500 round numbers (20000, 20500, etc.)
    rr_threshold=2.0,
    min_fvg_gap=2.00,             # NQ moves bigger than Gold, needs wider FVG gap
)

# Liquid equities (for earnings-event strategies)
AAPL = InstrumentSpec(
    symbol="AAPL",
    contract_size=1.0,
    point_value=0.01,
    digits=2,
    spread_base=0.02,
    max_spread=0.20,
    min_lot=1.0,
    max_lot=5000.0,
    lot_step=1.0,
    min_sl=0.50,
    max_sl=25.0,
    commission_per_lot=1.00,
    swap_long=-0.02,
    swap_short=-0.02,
    triple_swap_day=2,
    slippage_atr_factor=0.0,
    min_slippage=0.0,
    max_slippage=0.05,
    round_number_interval=10.0,
    rr_threshold=2.0,
    min_fvg_gap=0.05,
)

MSFT = InstrumentSpec(
    symbol="MSFT",
    contract_size=1.0,
    point_value=0.01,
    digits=2,
    spread_base=0.02,
    max_spread=0.25,
    min_lot=1.0,
    max_lot=5000.0,
    lot_step=1.0,
    min_sl=0.50,
    max_sl=25.0,
    commission_per_lot=1.00,
    swap_long=-0.02,
    swap_short=-0.02,
    triple_swap_day=2,
    slippage_atr_factor=0.0,
    min_slippage=0.0,
    max_slippage=0.05,
    round_number_interval=10.0,
    rr_threshold=2.0,
    min_fvg_gap=0.05,
)

NVDA = InstrumentSpec(
    symbol="NVDA",
    contract_size=1.0,
    point_value=0.01,
    digits=2,
    spread_base=0.04,
    max_spread=0.40,
    min_lot=1.0,
    max_lot=5000.0,
    lot_step=1.0,
    min_sl=1.00,
    max_sl=35.0,
    commission_per_lot=1.00,
    swap_long=-0.02,
    swap_short=-0.02,
    triple_swap_day=2,
    slippage_atr_factor=0.0,
    min_slippage=0.0,
    max_slippage=0.08,
    round_number_interval=10.0,
    rr_threshold=2.0,
    min_fvg_gap=0.10,
)

AMZN = InstrumentSpec(
    symbol="AMZN",
    contract_size=1.0,
    point_value=0.01,
    digits=2,
    spread_base=0.03,
    max_spread=0.25,
    min_lot=1.0,
    max_lot=5000.0,
    lot_step=1.0,
    min_sl=0.50,
    max_sl=25.0,
    commission_per_lot=1.00,
    swap_long=-0.02,
    swap_short=-0.02,
    triple_swap_day=2,
    slippage_atr_factor=0.0,
    min_slippage=0.0,
    max_slippage=0.06,
    round_number_interval=10.0,
    rr_threshold=2.0,
    min_fvg_gap=0.05,
)

META = InstrumentSpec(
    symbol="META",
    contract_size=1.0,
    point_value=0.01,
    digits=2,
    spread_base=0.03,
    max_spread=0.30,
    min_lot=1.0,
    max_lot=5000.0,
    lot_step=1.0,
    min_sl=0.75,
    max_sl=30.0,
    commission_per_lot=1.00,
    swap_long=-0.02,
    swap_short=-0.02,
    triple_swap_day=2,
    slippage_atr_factor=0.0,
    min_slippage=0.0,
    max_slippage=0.06,
    round_number_interval=10.0,
    rr_threshold=2.0,
    min_fvg_gap=0.08,
)

TSLA = InstrumentSpec(
    symbol="TSLA",
    contract_size=1.0,
    point_value=0.01,
    digits=2,
    spread_base=0.05,
    max_spread=0.40,
    min_lot=1.0,
    max_lot=5000.0,
    lot_step=1.0,
    min_sl=1.00,
    max_sl=40.0,
    commission_per_lot=1.00,
    swap_long=-0.02,
    swap_short=-0.02,
    triple_swap_day=2,
    slippage_atr_factor=0.0,
    min_slippage=0.0,
    max_slippage=0.10,
    round_number_interval=10.0,
    rr_threshold=2.0,
    min_fvg_gap=0.10,
)

# =========================================================================
# Registry
# =========================================================================

_INSTRUMENTS: Dict[str, InstrumentSpec] = {
    spec.symbol: spec
    for spec in [
        XAUUSD, XAGUSD, EURUSD, GBPUSD, USDJPY, US500, NAS100,
        AAPL, MSFT, NVDA, AMZN, META, TSLA,
    ]
}


def get_instrument(symbol: str) -> InstrumentSpec:
    """Return the spec for *symbol*, falling back to XAUUSD if unknown."""
    return _INSTRUMENTS.get(symbol, XAUUSD)


def get_all_instruments() -> Dict[str, InstrumentSpec]:
    """Return the full instrument catalogue (read-only view)."""
    return dict(_INSTRUMENTS)


def register_instrument(spec: InstrumentSpec) -> None:
    """Add or override an instrument at runtime (e.g. from broker API)."""
    _INSTRUMENTS[spec.symbol] = spec
