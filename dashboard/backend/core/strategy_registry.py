"""
Strategy Registry - Defines available trading strategies and their parameters.

Each strategy defines:
- Metadata (id, name, description)
- Minimal user-configurable parameters (balance, preset)
- Hard-coded optimal parameters for technical settings
"""

from typing import Dict, List, Any, Optional
from dataclasses import dataclass, field
from enum import Enum


class ParameterType(str, Enum):
    """Supported parameter types"""
    STRING = "string"
    NUMBER = "number"
    INTEGER = "integer"
    BOOLEAN = "boolean"
    TIME = "time"  # HH:MM format
    SELECT = "select"  # Dropdown with options


@dataclass
class ParameterDefinition:
    """Definition of a single configuration parameter"""
    name: str
    label: str
    type: ParameterType
    default: Any
    description: str = ""
    min_value: Optional[float] = None
    max_value: Optional[float] = None
    step: Optional[float] = None
    options: Optional[List[Dict[str, str]]] = None  # For SELECT type
    required: bool = True
    group: str = "general"  # Parameter group for UI organization


@dataclass
class ParameterGroup:
    """A group of related parameters"""
    id: str
    label: str
    icon: str  # Icon name
    description: str = ""


@dataclass
class StrategyPreset:
    """A preset configuration for a strategy"""
    id: str
    name: str
    description: str
    parameters: Dict[str, Any]  # Parameter values for this preset
    symbols: Optional[List[str]] = None  # If set, preset is only shown for these instruments


@dataclass
class StrategyDefinition:
    """Complete definition of a trading strategy"""
    id: str
    name: str
    description: str
    version: str = "1.0.0"
    author: str = "System"
    parameter_groups: List[ParameterGroup] = field(default_factory=list)
    parameters: List[ParameterDefinition] = field(default_factory=list)
    presets: List[StrategyPreset] = field(default_factory=list)
    # Hard-coded optimal parameters (not shown in UI)
    optimal_parameters: Dict[str, Any] = field(default_factory=dict)
    # Per-instrument parameter overrides (symbol -> {param: value})
    instrument_overrides: Dict[str, Dict[str, Any]] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for API response"""
        return {
            "id": self.id,
            "name": self.name,
            "description": self.description,
            "version": self.version,
            "author": self.author,
            "parameter_groups": [
                {"id": g.id, "label": g.label, "icon": g.icon, "description": g.description}
                for g in self.parameter_groups
            ],
            "parameters": [
                {
                    "name": p.name,
                    "label": p.label,
                    "type": p.type.value,
                    "default": p.default,
                    "description": p.description,
                    "min_value": p.min_value,
                    "max_value": p.max_value,
                    "step": p.step,
                    "options": p.options,
                    "required": p.required,
                    "group": p.group,
                }
                for p in self.parameters
            ],
            "presets": [
                {"id": p.id, "name": p.name, "description": p.description, "symbols": p.symbols}
                for p in self.presets
            ],
            "instrument_overrides": self.instrument_overrides,
            "symbols": self.optimal_parameters.get("symbols", []),
        }

    def get_defaults(self) -> Dict[str, Any]:
        """Get default values for all parameters including optimal ones"""
        defaults = {p.name: p.default for p in self.parameters}
        # Merge with optimal parameters
        defaults.update(self.optimal_parameters)
        return defaults

    def get_preset_config(self, preset_id: str, symbol: str = None) -> Dict[str, Any]:
        """Get full configuration for a preset, optionally adjusted for instrument.

        Layering order (lowest to highest priority):
        1. InstrumentSpec defaults (fallback for missing values)
        2. Parameter defaults + optimal_parameters
        3. Preset overrides (conservative / default / aggressive)
        4. Strategy-specific instrument_overrides (highest priority)
        """
        config = self.get_defaults()
        # Layer 1: preset overrides
        for preset in self.presets:
            if preset.id == preset_id:
                config.update(preset.parameters)
                break
        # Layer 2: instrument-spec fallback defaults (only if not already set)
        if symbol:
            config["symbol"] = symbol
            from .instrument_specs import get_instrument
            spec = get_instrument(symbol)
            # Use setdefault to NOT override strategy/preset values
            config.setdefault("max_spread_usd", spec.max_spread)
            config.setdefault("min_sl_usd", spec.min_sl)
            config.setdefault("max_sl_usd", spec.max_sl)
            config.setdefault("min_fvg_gap", spec.min_fvg_gap)
            # Always use instrument specs for broker/swap params
            config["commission_per_lot"] = spec.commission_per_lot
            config["contract_size"] = spec.contract_size
            config.setdefault("rr_ratio", spec.rr_threshold)
            config.setdefault("slippage_atr_factor", spec.slippage_atr_factor)
        # Layer 3: strategy-specific instrument overrides (highest priority)
        if symbol and symbol in self.instrument_overrides:
            config.update(self.instrument_overrides[symbol])
        return config


# =============================================================================
# COMMON PARAMETER GROUPS
# =============================================================================

BASIC_GROUPS = [
    ParameterGroup("basic", "Basic Settings", "Settings", "Essential configuration"),
    ParameterGroup("simulation", "Simulation", "FlaskConical", "Backtest simulation settings"),
]


# =============================================================================
# ORB STRATEGY DEFINITION
# =============================================================================

ORB_STRATEGY = StrategyDefinition(
    id="orb_strategy",
    name="ORB Strategy",
    description="Opening Range Breakout strategy with ICT concepts (FVG, Order Blocks, Displacement). "
                "Trades breakouts of the opening range with confirmation from smart money concepts.",
    version="1.0.0",
    author="System",
    parameter_groups=BASIC_GROUPS,
    parameters=[
        # Basic - User configurable
        ParameterDefinition("symbol", "Symbol", ParameterType.STRING, "XAUUSD",
                           "Trading symbol", group="basic"),
        ParameterDefinition("timeframe", "Timeframe", ParameterType.SELECT, "M1",
                           "Chart timeframe", group="basic",
                           options=[
                               {"value": "M1", "label": "M1 (1 Minute) - Recommended"},
                           ]),
        ParameterDefinition("initial_balance", "Initial Balance ($)", ParameterType.NUMBER, 10000.0,
                           "Starting account balance", min_value=100, step=100, group="basic"),
        ParameterDefinition("preset", "Risk Preset", ParameterType.SELECT, "default",
                           "Predefined risk configuration", group="basic",
                           options=[
                               {"value": "conservative", "label": "Conservative (0.5% risk)"},
                               {"value": "default", "label": "Default (1% risk)"},
                               {"value": "aggressive", "label": "Aggressive (2% risk)"},
                           ]),

        # Simulation settings - visible but with defaults
        ParameterDefinition("contract_size", "Contract Size", ParameterType.NUMBER, 100.0,
                           "Contract size (Gold: 100 oz/lot)", min_value=1, step=1, group="simulation"),
        ParameterDefinition("simulate_spread", "Simulate Spread", ParameterType.BOOLEAN, True,
                           "Enable spread simulation", group="simulation"),
        ParameterDefinition("use_variable_spread", "Variable Spread", ParameterType.BOOLEAN, True,
                           "Use time-of-day spread model", group="simulation"),
        ParameterDefinition("simulate_slippage", "Simulate Slippage", ParameterType.BOOLEAN, True,
                           "Enable slippage simulation", group="simulation"),
        ParameterDefinition("commission_per_lot", "Commission Per Lot ($)", ParameterType.NUMBER, 3.50,
                           "Round-trip commission per lot", min_value=0, max_value=20, step=0.5, group="simulation"),
        ParameterDefinition("simulate_swap", "Simulate Swap", ParameterType.BOOLEAN, True,
                           "Enable overnight swap charges", group="simulation"),
        ParameterDefinition("close_before_weekend", "Close Before Weekend", ParameterType.BOOLEAN, True,
                           "Auto-close positions on Friday", group="simulation"),
    ],
    presets=[
        StrategyPreset("conservative", "Conservative", "Sniper: 0.5% risk, 1 trade/day, strict bias (60+), stop after win", {
            "risk_percent": 0.5,
            "max_daily_loss_usd": -75.0,
            "max_total_risk_usd": 100.0,
            "bias_min_strength": 60,
            "gold_rr_threshold": 3.00,
            "max_daily_trades": 1,
            "stop_after_first_win": True,
        }),
        StrategyPreset("default", "Default", "Winning model: 1% risk, 2 trades max, stop after win, tight window", {
            "risk_percent": 1.0,
            "max_daily_loss_usd": -200.0,
            "max_total_risk_usd": 250.0,
            "bias_min_strength": 30,
            "gold_rr_threshold": 3.00,
            "max_daily_trades": 2,
            "stop_after_first_win": True,
        }),
        StrategyPreset("aggressive", "Aggressive", "Growth: 2% risk, 2 trades max, stop after win, wider bias", {
            "risk_percent": 2.0,
            "max_daily_loss_usd": -400.0,
            "max_total_risk_usd": 500.0,
            "bias_min_strength": 20,
            "gold_rr_threshold": 3.00,
            "max_daily_trades": 2,
            "stop_after_first_win": True,
            "enable_orderflow_filter": True,
        }),
        StrategyPreset("nas100_tuned", "NAS100 Tuned",
                       "NQ v5: both dirs, bias 70+, quality, 1.1% risk, 2 max", {
            "risk_percent": 1.1,
            "max_daily_loss_usd": -165.0,
            "max_total_risk_usd": 220.0,
            "gold_rr_threshold": 3.00,
            "max_daily_trades": 2,
            "stop_after_first_win": False,
            # --- Both directions ---
            "bias_min_strength": 70,
            # --- Quality filters ---
            "displacement_percentile": 82,
            "max_opposing_wick_ratio": 0.30,
            "fvg_scan_window": 7,
            "min_orb_range_daily": 0.05,
            "max_orb_range_daily": 0.50,
            "min_breakout_distance_atr": 0.01,
            "min_breakout_body_atr": 0.005,
            "min_fvg_size_atr": 0.01,
        }, symbols=["NAS100"]),
        StrategyPreset("advanced_aggressive", "Advanced Aggressive",
                       "v8: long-only, strict filters, 0.5% risk (scale via overrides)", {
            "risk_percent": 0.5,
            "max_daily_loss_usd": -75.0,
            "max_total_risk_usd": 100.0,
            "gold_rr_threshold": 3.00,
            "max_daily_trades": 2,
            "stop_after_first_win": True,
            # --- Direction: long-only (proven: LONG WR=44.5% vs SHORT 32.1%) ---
            "allowed_directions": "long_only",
            # --- Bias: min 40, no cap ---
            "bias_min_strength": 40,
            # --- Quality filters (proven strict values) ---
            "displacement_percentile": 85,
            "max_opposing_wick_ratio": 0.25,
            "fvg_scan_window": 10,                 # Up from 7: wider FVG search window
            "min_orb_range_daily": 0.05,
            "max_orb_range_daily": 0.50,
            "min_breakout_distance_atr": 0.02,
            "min_breakout_body_atr": 0.01,
            "min_fvg_size_atr": 0.02,
        }, symbols=["XAUUSD"]),
    ],
    # Hard-coded optimal parameters (tested values, pro trader settings)
    # Modeled after: 15-min ORB + Imbalance breakout, 1-2R target,
    # 1-2 trades/day, stop after first win, tight trade window.
    optimal_parameters={
        # Risk Management
        "max_spread_usd": 0.40,
        "min_sl_usd": 1.00,
        "max_sl_usd": 10.00,
        "stop_after_first_win": True,   # "If first trade is green, I'm done"
        "max_spread_to_sl_ratio": 0.35,
        "rr_tight_sl_target": 2.00,   # Tight SL (<$3) → 2R target
        "rr_wide_sl_target": 1.50,    # Wide SL (>$3) → 1.5R target (covers cost drag)
        "min_rr_target": 1.50,        # Floor at 1.5R (1R gets eaten by spread on Gold)
        "rr_bias_bonus": 0.0,         # No bonus — keep R:R simple
        "bias_strong_threshold": 70,

        # ICT Parameters - FVG (Imbalance)
        "min_fvg_gap": 0.20,      # Gold moves fast, $0.20 gap is significant on M1
        "fvg_lookback": 20,        # Tighter: only 20 min lookback (fresh FVGs near breakout)
        "fvg_scan_window": 10,     # Only scan last 10 bar groups (FVG must be fresh)
        "require_unfilled_fvg": True,

        # ICT Parameters - Displacement
        "displacement_percentile": 75,  # 75th percentile — not too strict
        "displacement_lookback": 20,
        "max_opposing_wick_ratio": 0.40,  # Slightly relaxed wick tolerance

        # ICT Parameters - Order Blocks
        "ob_lookback": 50,          # 50 bars for M1 = ~50 min, keeps OBs fresh
        "ob_min_body_percent": 65,  # Strong-bodied candles only
        "ob_validation_bars": 3,

        # ICT Parameters - Liquidity
        "liquidity_wick_ratio": 0.6,
        "sweep_tolerance_usd": 0.20,

        # Session Times (NY Time) - Tight AM Kill Zone
        "orb_start_time": "09:30",
        "orb_end_time": "09:45",
        "trade_start_time": "09:45",
        "trade_end_time": "10:30",    # Proven: 45 min tight window (late entries degrade edge)
        "asian_start": "20:00",
        "asian_end": "02:00",
        "london_start": "03:00",
        "london_end": "12:00",

        # Trailing Stop — BE at 1R, then give room (winning model: "move stop to BE once structure clears")
        "use_trailing": True,
        "trailing_atr_period": 14,
        "trailing_atr_multiplier": 3.0,  # Wider trail: let winners run to TP instead of trailing out early

        # Trend / ORB quality filter
        "min_adr_for_trend": 12.0,  # Gold is almost always trending; 12.0 matches proven DEPLOY config
        "adr_period": 5,
        "min_orb_range_daily": 0.03,  # ORB must be at least 3% of daily ATR (skip dead ranges)
        "max_orb_range_daily": 0.70,  # ORB > 70% of daily ATR = likely exhausted
        "min_orb_range_atr": 0.03,    # Fallback when no daily ATR
        "max_orb_range_atr": 0.80,

        # Simulation defaults
        "slippage_atr_factor": 0.02,
        "friday_close_hour": 15,
        "friday_close_minute": 30,

        # Cross-Asset Regime Filter (Phase 1)
        "enable_cross_asset_filter": True,
        "regime_timeframe": "M15",
        "regime_lookback_bars": 96,
        "regime_return_bars": 8,
        "regime_signal_threshold": 0.18,
        "regime_strong_threshold": 0.40,
        "regime_block_countertrend": True,
        "regime_reduce_size_in_headwind": True,
        "regime_tailwind_risk_multiplier": 1.15,
        "regime_headwind_risk_multiplier": 0.50,
        "regime_neutral_risk_multiplier": 1.00,
        "regime_symbol_dxy": "DXY,USDX,USDX.i",
        "regime_symbol_yield": "US10Y,TNX,US10Y.cash",
        "regime_symbol_riskoff": "VIX,VIX.cash,VOLX",
        "regime_symbol_riskon": "SPX500,US500,US30",
        "regime_weight_dxy": 0.40,
        "regime_weight_yield": 0.35,
        "regime_weight_riskoff": 0.15,
        "regime_weight_riskon": 0.10,
        # Databento Orderflow Filter (Phase 3 prep, fail-open by default)
        "enable_orderflow_filter": False,
        "orderflow_eval_interval_seconds": 60,
        "orderflow_lookback_minutes": 5,
        "orderflow_min_trades": 30,
        "orderflow_signal_threshold": 0.15,
        "orderflow_block_countertrend": True,
        "orderflow_reduce_size_in_headwind": True,
        "orderflow_tailwind_risk_multiplier": 1.05,
        "orderflow_headwind_risk_multiplier": 0.80,
        "orderflow_neutral_risk_multiplier": 1.00,
        "orderflow_dataset": "GLBX.MDP3",
        "orderflow_schema": "trades",
        "orderflow_stype_in": "raw_symbol",
        "orderflow_symbol": "GC.c.0",

        # Strategy metadata
        "timeframes": ["M1"],
        "symbols": ["XAUUSD", "NAS100", "US500"],
    },
    instrument_overrides={
        # Keep ORB moderately permissive but bounded for M1 noise.
        "XAUUSD": {
            "max_sl_usd": 10.00,
        },
        # NAS100 (NASDAQ 100 E-mini) — 2R minimum (1R unprofitable per baseline)
        "NAS100": {
            "max_spread_usd": 3.00,        # NQ spread ~1-2 points
            "min_sl_usd": 5.00,            # 5 points minimum SL
            "max_sl_usd": 100.00,          # 100 points max SL
            "gold_rr_threshold": 30.00,    # Threshold for adaptive R:R
            "rr_tight_sl_target": 2.00,    # <30 pts → 2R
            "rr_wide_sl_target": 2.00,     # >30 pts → ALSO 2R (1R unprofitable)
            "min_rr_target": 2.00,         # Force 2R min on NQ
            "min_fvg_gap": 2.00,           # NQ moves bigger, needs wider FVG gap
            "max_spread_to_sl_ratio": 0.20,
            "trailing_atr_multiplier": 2.5,
        },
        # US500 (S&P 500 E-mini) — 2R minimum (1R net 0.68R after costs = broken)
        "US500": {
            "max_spread_usd": 1.50,        # ES spread ~0.25-0.50 points
            "min_sl_usd": 2.00,            # 2 points minimum SL
            "max_sl_usd": 30.00,           # 30 points max SL
            "gold_rr_threshold": 8.00,     # Threshold for adaptive R:R
            "rr_tight_sl_target": 2.00,    # <8 pts → 2R
            "rr_wide_sl_target": 2.00,     # >8 pts → 2R (1R = 0.68R net after costs)
            "min_rr_target": 2.00,         # Force 2R min on ES
            "min_fvg_gap": 0.50,
            "max_spread_to_sl_ratio": 0.20,
            "trailing_atr_multiplier": 2.5,
        },
    },
)


# =============================================================================
# ADVANCED ORB STRATEGY DEFINITION
# =============================================================================

ADVANCED_ORB_STRATEGY = StrategyDefinition(
    id="advanced_orb_strategy",
    name="Advanced ORB Strategy",
    description="Enhanced Opening Range Breakout with stricter filters, multi-session bias analysis, "
                "and improved Order Block detection. Higher accuracy, fewer trades.",
    version="2.0.0",
    author="System",
    parameter_groups=BASIC_GROUPS,
    parameters=[
        # Basic - User configurable
        ParameterDefinition("symbol", "Symbol", ParameterType.STRING, "XAUUSD",
                           "Trading symbol", group="basic"),
        ParameterDefinition("timeframe", "Timeframe", ParameterType.SELECT, "M1",
                           "Chart timeframe", group="basic",
                           options=[
                               {"value": "M1", "label": "M1 (1 Minute) - Recommended"},
                           ]),
        ParameterDefinition("initial_balance", "Initial Balance ($)", ParameterType.NUMBER, 10000.0,
                           "Starting account balance", min_value=100, step=100, group="basic"),
        ParameterDefinition("preset", "Risk Preset", ParameterType.SELECT, "default",
                           "Predefined risk configuration", group="basic",
                           options=[
                               {"value": "conservative", "label": "Conservative (0.5% risk)"},
                               {"value": "default", "label": "Default (1% risk)"},
                               {"value": "aggressive", "label": "Aggressive (2% risk)"},
                           ]),

        # Simulation settings
        ParameterDefinition("contract_size", "Contract Size", ParameterType.NUMBER, 100.0,
                           "Contract size (Gold: 100 oz/lot)", min_value=1, step=1, group="simulation"),
        ParameterDefinition("simulate_spread", "Simulate Spread", ParameterType.BOOLEAN, True,
                           "Enable spread simulation", group="simulation"),
        ParameterDefinition("use_variable_spread", "Variable Spread", ParameterType.BOOLEAN, True,
                           "Use time-of-day spread model", group="simulation"),
        ParameterDefinition("simulate_slippage", "Simulate Slippage", ParameterType.BOOLEAN, True,
                           "Enable slippage simulation", group="simulation"),
        ParameterDefinition("commission_per_lot", "Commission Per Lot ($)", ParameterType.NUMBER, 3.50,
                           "Round-trip commission per lot", min_value=0, max_value=20, step=0.5, group="simulation"),
        ParameterDefinition("simulate_swap", "Simulate Swap", ParameterType.BOOLEAN, True,
                           "Enable overnight swap charges", group="simulation"),
        ParameterDefinition("close_before_weekend", "Close Before Weekend", ParameterType.BOOLEAN, True,
                           "Auto-close positions on Friday", group="simulation"),
    ],
    presets=[
        StrategyPreset("conservative", "Conservative", "Ultra-sniper: 0.5% risk, 1 trade/day, strict bias (60+)", {
            "risk_percent": 0.5,
            "max_daily_loss_usd": -75.0,
            "max_total_risk_usd": 100.0,
            "bias_min_strength": 60,
            "gold_rr_threshold": 3.00,
            "max_daily_trades": 1,
            "stop_after_first_win": True,
        }),
        StrategyPreset("default", "Default", "Winning model: 1% risk, 2 trades max, stop after win, strict filters", {
            "risk_percent": 1.0,
            "max_daily_loss_usd": -200.0,
            "max_total_risk_usd": 250.0,
            "bias_min_strength": 30,
            "gold_rr_threshold": 3.00,
            "max_daily_trades": 2,
            "stop_after_first_win": True,
        }),
        StrategyPreset("aggressive", "Aggressive", "Growth: 2% risk, 2 trades max, stop after win, wider bias", {
            "risk_percent": 2.0,
            "max_daily_loss_usd": -400.0,
            "max_total_risk_usd": 500.0,
            "bias_min_strength": 20,
            "gold_rr_threshold": 3.00,
            "max_daily_trades": 2,
            "stop_after_first_win": True,
            "enable_orderflow_filter": True,
        }),
        StrategyPreset("us500_tuned", "US500 Tuned",
                       "ES: bias 80+, 2R, 1.6% risk, quality filters", {
            "risk_percent": 1.6,
            "max_daily_loss_usd": -213.0,
            "max_total_risk_usd": 320.0,
            "gold_rr_threshold": 3.00,
            "max_daily_trades": 1,
            "stop_after_first_win": True,
            # --- Bias: 80+ (filters toxic 61-80 range at 33.3% WR) ---
            "bias_min_strength": 80,
            # --- Quality filters ---
            "displacement_percentile": 82,
            "max_opposing_wick_ratio": 0.30,
            "fvg_scan_window": 7,
            "min_breakout_distance_atr": 0.01,
            "min_breakout_body_atr": 0.005,
            "min_fvg_size_atr": 0.01,
        }, symbols=["US500"]),
    ],
    # Hard-coded optimal parameters (matching winning model + stricter quality filters)
    optimal_parameters={
        # Risk Management — same R:R as winning model
        "max_spread_usd": 0.40,
        "min_sl_usd": 1.00,
        "max_sl_usd": 8.00,         # Stricter max SL than base ORB
        "stop_after_first_win": True,
        "max_spread_to_sl_ratio": 0.30,
        "rr_tight_sl_target": 2.00,   # Tight SL → 2R (matches winning model)
        "rr_wide_sl_target": 1.50,    # Wide SL → 1.5R
        "min_rr_target": 1.50,        # Floor at 1.5R
        "rr_bias_bonus": 0.0,
        "bias_strong_threshold": 70,

        # ICT Parameters - FVG (fresh imbalances only, stricter displacement)
        "min_fvg_gap": 0.20,
        "fvg_lookback": 20,        # Tight: only 20 bar lookback
        "fvg_scan_window": 10,     # Only scan last 10 bar groups
        "require_unfilled_fvg": True,

        # ICT Parameters - Displacement (stricter than base ORB — Advanced's edge)
        "displacement_percentile": 80,
        "displacement_lookback": 20,
        "max_opposing_wick_ratio": 0.32,  # Cleaner candles

        # ICT Parameters - Order Blocks
        "ob_lookback": 50,
        "ob_min_body_percent": 65,
        "ob_validation_bars": 3,

        # ICT Parameters - Liquidity
        "liquidity_wick_ratio": 0.55,
        "sweep_tolerance_usd": 0.25,

        # Session Times (NY Time) - Tight window matching winning model
        "orb_start_time": "09:30",
        "orb_end_time": "09:45",
        "trade_start_time": "09:45",
        "trade_end_time": "10:30",    # Proven: 45 min tight window
        "asian_start": "20:00",
        "asian_end": "02:00",
        "london_start": "03:00",
        "london_end": "12:00",

        # Trailing Stop — wider trail to let winners hit TP
        "use_trailing": True,
        "trailing_atr_period": 14,
        "trailing_atr_multiplier": 3.0,

        # Trend / ORB quality filter
        "min_adr_for_trend": 12.0,  # Matches proven DEPLOY config
        "adr_period": 5,
        "min_orb_range_daily": 0.03,
        "max_orb_range_daily": 0.70,
        "min_orb_range_atr": 0.03,
        "max_orb_range_atr": 0.80,

        # Simulation defaults
        "slippage_atr_factor": 0.02,
        "friday_close_hour": 15,
        "friday_close_minute": 30,

        # Cross-Asset Regime Filter (Phase 1)
        "enable_cross_asset_filter": True,
        "regime_timeframe": "M15",
        "regime_lookback_bars": 96,
        "regime_return_bars": 8,
        "regime_signal_threshold": 0.25,
        "regime_strong_threshold": 0.40,
        "regime_block_countertrend": True,
        "regime_reduce_size_in_headwind": True,
        "regime_tailwind_risk_multiplier": 1.15,
        "regime_headwind_risk_multiplier": 0.50,
        "regime_neutral_risk_multiplier": 1.00,
        "regime_symbol_dxy": "DXY,USDX,USDX.i",
        "regime_symbol_yield": "US10Y,TNX,US10Y.cash",
        "regime_symbol_riskoff": "VIX,VIX.cash,VOLX",
        "regime_symbol_riskon": "SPX500,US500,US30",
        "regime_weight_dxy": 0.40,
        "regime_weight_yield": 0.35,
        "regime_weight_riskoff": 0.15,
        "regime_weight_riskon": 0.10,
        # Databento Orderflow Filter (Phase 3 prep, fail-open by default)
        "enable_orderflow_filter": False,
        "orderflow_eval_interval_seconds": 60,
        "orderflow_lookback_minutes": 5,
        "orderflow_min_trades": 30,
        "orderflow_signal_threshold": 0.15,
        "orderflow_block_countertrend": True,
        "orderflow_reduce_size_in_headwind": True,
        "orderflow_tailwind_risk_multiplier": 1.05,
        "orderflow_headwind_risk_multiplier": 0.80,
        "orderflow_neutral_risk_multiplier": 1.00,
        "orderflow_dataset": "GLBX.MDP3",
        "orderflow_schema": "trades",
        "orderflow_stype_in": "raw_symbol",
        "orderflow_symbol": "GC.c.0",

        # Strategy metadata
        "timeframes": ["M1"],
        "symbols": ["XAUUSD", "NAS100", "US500"],
    },
    instrument_overrides={
        # Advanced ORB keeps tighter structural risk bounds.
        "XAUUSD": {
            "max_sl_usd": 8.00,
        },
        # NAS100 — 2R minimum (1R unprofitable per baseline testing)
        "NAS100": {
            "max_spread_usd": 3.00,
            "min_sl_usd": 5.00,
            "max_sl_usd": 80.00,
            "gold_rr_threshold": 30.00,
            "rr_tight_sl_target": 2.00,
            "rr_wide_sl_target": 2.00,     # Force 2R for wide SL too
            "min_rr_target": 2.00,         # 2R minimum
            "min_fvg_gap": 2.00,
            "max_spread_to_sl_ratio": 0.20,
            "trailing_atr_multiplier": 2.5,
        },
        # US500 — 2R minimum (1R = 0.68R net after costs = broken)
        "US500": {
            "max_spread_usd": 1.50,
            "min_sl_usd": 2.00,
            "max_sl_usd": 25.00,
            "gold_rr_threshold": 8.00,
            "rr_tight_sl_target": 2.00,    # <8 pts → 2R
            "rr_wide_sl_target": 2.00,     # >8 pts → 2R (1R = 0.68R net)
            "min_rr_target": 2.00,         # Force 2R min on ES
            "min_fvg_gap": 0.50,
            "max_spread_to_sl_ratio": 0.20,
            "trailing_atr_multiplier": 2.5,
        },
    },
)


# =============================================================================
# ML PARAMETER GROUPS (basic + ml + simulation)
# =============================================================================

ML_GROUPS = [
    ParameterGroup("basic", "Basic Settings", "Settings", "Essential configuration"),
    ParameterGroup("ml", "ML Settings", "Cpu", "Machine Learning filter configuration"),
    ParameterGroup("simulation", "Simulation", "FlaskConical", "Backtest simulation settings"),
]


# =============================================================================
# ORB + ML FILTER STRATEGY DEFINITION
# =============================================================================

ORB_ML_STRATEGY = StrategyDefinition(
    id="orb_ml_strategy",
    name="ORB + ML Filter",
    description="ORB Strategy enhanced with Machine Learning trade filter. "
                "Uses XGBoost model trained on past trades to skip low-probability setups. "
                "Requires a trained ML model from a base ORB backtest.",
    version="1.0.0",
    author="System",
    parameter_groups=ML_GROUPS,
    parameters=[
        # Basic - User configurable
        ParameterDefinition("symbol", "Symbol", ParameterType.STRING, "XAUUSD",
                           "Trading symbol", group="basic"),
        ParameterDefinition("timeframe", "Timeframe", ParameterType.SELECT, "M1",
                           "Chart timeframe", group="basic",
                           options=[
                               {"value": "M1", "label": "M1 (1 Minute) - Recommended"},
                               {"value": "M5", "label": "M5 (5 Minutes)"},
                           ]),
        ParameterDefinition("initial_balance", "Initial Balance ($)", ParameterType.NUMBER, 10000.0,
                           "Starting account balance", min_value=100, step=100, group="basic"),
        ParameterDefinition("preset", "Risk Preset", ParameterType.SELECT, "default",
                           "Predefined risk configuration", group="basic",
                           options=[
                               {"value": "conservative", "label": "Conservative (strict ML filter)"},
                               {"value": "default", "label": "Default (balanced ML filter)"},
                               {"value": "aggressive", "label": "Aggressive (loose ML filter)"},
                           ]),

        # ML Settings - User configurable
        ParameterDefinition("use_ml_filter", "ML Trade Filter", ParameterType.BOOLEAN, True,
                           "Filter trades using ML win probability prediction", group="ml"),
        ParameterDefinition("ml_min_win_probability", "Min Win Probability", ParameterType.NUMBER, 0.55,
                           "Skip trades with win probability below this threshold (0.50 = 50%)",
                           min_value=0.40, max_value=0.90, step=0.05, group="ml"),
        ParameterDefinition("use_ml_dynamic_rr", "ML Dynamic R:R", ParameterType.BOOLEAN, False,
                           "Let ML model adjust R:R ratio per trade based on predicted MFE", group="ml"),

        # Simulation settings
        ParameterDefinition("contract_size", "Contract Size", ParameterType.NUMBER, 100.0,
                           "Contract size (Gold: 100 oz/lot)", min_value=1, step=1, group="simulation"),
        ParameterDefinition("simulate_spread", "Simulate Spread", ParameterType.BOOLEAN, True,
                           "Enable spread simulation", group="simulation"),
        ParameterDefinition("use_variable_spread", "Variable Spread", ParameterType.BOOLEAN, True,
                           "Use time-of-day spread model", group="simulation"),
        ParameterDefinition("simulate_slippage", "Simulate Slippage", ParameterType.BOOLEAN, True,
                           "Enable slippage simulation", group="simulation"),
        ParameterDefinition("commission_per_lot", "Commission Per Lot ($)", ParameterType.NUMBER, 3.50,
                           "Round-trip commission per lot", min_value=0, max_value=20, step=0.5, group="simulation"),
        ParameterDefinition("simulate_swap", "Simulate Swap", ParameterType.BOOLEAN, True,
                           "Enable overnight swap charges", group="simulation"),
        ParameterDefinition("close_before_weekend", "Close Before Weekend", ParameterType.BOOLEAN, True,
                           "Auto-close positions on Friday", group="simulation"),
    ],
    presets=[
        StrategyPreset("conservative", "Conservative", "Strict ML gate (65%+), sniper bias (60+), 1 trade/day", {
            "risk_percent": 0.5,
            "max_daily_loss_usd": -75.0,
            "max_total_risk_usd": 100.0,
            "bias_min_strength": 60,
            "gold_rr_threshold": 2.50,
            "max_daily_trades": 1,
            "use_ml_filter": True,
            "ml_min_win_probability": 0.65,
            "use_ml_dynamic_rr": False,
        }),
        StrategyPreset("default", "Default", "Balanced ML filter (55%+), quality bias (40+), 2 trades/day", {
            "risk_percent": 1.0,
            "max_daily_loss_usd": -200.0,
            "max_total_risk_usd": 250.0,
            "bias_min_strength": 40,
            "gold_rr_threshold": 3.00,
            "max_daily_trades": 2,
            "use_ml_filter": True,
            "ml_min_win_probability": 0.55,
            "use_ml_dynamic_rr": False,
        }),
        StrategyPreset("aggressive", "Aggressive", "Loose ML gate (50%+), 2% risk, dynamic R:R, 3 trades/day", {
            "risk_percent": 2.0,
            "max_daily_loss_usd": -400.0,
            "max_total_risk_usd": 500.0,
            "bias_min_strength": 25,
            "gold_rr_threshold": 3.50,
            "max_daily_trades": 3,
            "use_ml_filter": True,
            "ml_min_win_probability": 0.50,
            "use_ml_dynamic_rr": True,
        }),
    ],
    # Inherits ALL optimal parameters from base ORB strategy
    optimal_parameters={
        **ORB_STRATEGY.optimal_parameters,
        # ML-specific
        "ml_base_strategy_id": "orb_strategy",
    }
)


# =============================================================================
# ADVANCED ORB + ML FILTER STRATEGY DEFINITION
# =============================================================================

ADVANCED_ORB_ML_STRATEGY = StrategyDefinition(
    id="advanced_orb_ml_strategy",
    name="Advanced ORB + ML Filter",
    description="Advanced ORB Strategy enhanced with Machine Learning trade filter. "
                "Combines the strictest ICT filters with ML win probability prediction. "
                "Requires a trained ML model from a base Advanced ORB backtest.",
    version="1.0.0",
    author="System",
    parameter_groups=ML_GROUPS,
    parameters=[
        # Basic - User configurable
        ParameterDefinition("symbol", "Symbol", ParameterType.STRING, "XAUUSD",
                           "Trading symbol", group="basic"),
        ParameterDefinition("timeframe", "Timeframe", ParameterType.SELECT, "M1",
                           "Chart timeframe", group="basic",
                           options=[
                               {"value": "M1", "label": "M1 (1 Minute) - Recommended"},
                               {"value": "M5", "label": "M5 (5 Minutes)"},
                           ]),
        ParameterDefinition("initial_balance", "Initial Balance ($)", ParameterType.NUMBER, 10000.0,
                           "Starting account balance", min_value=100, step=100, group="basic"),
        ParameterDefinition("preset", "Risk Preset", ParameterType.SELECT, "default",
                           "Predefined risk configuration", group="basic",
                           options=[
                               {"value": "conservative", "label": "Conservative (strict ML filter)"},
                               {"value": "default", "label": "Default (balanced ML filter)"},
                               {"value": "aggressive", "label": "Aggressive (loose ML filter)"},
                           ]),

        # ML Settings
        ParameterDefinition("use_ml_filter", "ML Trade Filter", ParameterType.BOOLEAN, True,
                           "Filter trades using ML win probability prediction", group="ml"),
        ParameterDefinition("ml_min_win_probability", "Min Win Probability", ParameterType.NUMBER, 0.55,
                           "Skip trades with win probability below this threshold",
                           min_value=0.40, max_value=0.90, step=0.05, group="ml"),
        ParameterDefinition("use_ml_dynamic_rr", "ML Dynamic R:R", ParameterType.BOOLEAN, False,
                           "Let ML model adjust R:R ratio per trade based on predicted MFE", group="ml"),

        # Simulation settings
        ParameterDefinition("contract_size", "Contract Size", ParameterType.NUMBER, 100.0,
                           "Contract size (Gold: 100 oz/lot)", min_value=1, step=1, group="simulation"),
        ParameterDefinition("simulate_spread", "Simulate Spread", ParameterType.BOOLEAN, True,
                           "Enable spread simulation", group="simulation"),
        ParameterDefinition("use_variable_spread", "Variable Spread", ParameterType.BOOLEAN, True,
                           "Use time-of-day spread model", group="simulation"),
        ParameterDefinition("simulate_slippage", "Simulate Slippage", ParameterType.BOOLEAN, True,
                           "Enable slippage simulation", group="simulation"),
        ParameterDefinition("commission_per_lot", "Commission Per Lot ($)", ParameterType.NUMBER, 3.50,
                           "Round-trip commission per lot", min_value=0, max_value=20, step=0.5, group="simulation"),
        ParameterDefinition("simulate_swap", "Simulate Swap", ParameterType.BOOLEAN, True,
                           "Enable overnight swap charges", group="simulation"),
        ParameterDefinition("close_before_weekend", "Close Before Weekend", ParameterType.BOOLEAN, True,
                           "Auto-close positions on Friday", group="simulation"),
    ],
    presets=[
        StrategyPreset("conservative", "Conservative", "Ultra-strict: bias 70+ & ML 65%+, sniper only", {
            "risk_percent": 0.5,
            "max_daily_loss_usd": -75.0,
            "max_total_risk_usd": 100.0,
            "bias_min_strength": 70,
            "gold_rr_threshold": 2.50,
            "max_daily_trades": 1,
            "use_ml_filter": True,
            "ml_min_win_probability": 0.65,
            "use_ml_dynamic_rr": False,
        }),
        StrategyPreset("default", "Default", "Balanced: bias 55+ & ML 55%+, 2 trades/day", {
            "risk_percent": 1.0,
            "max_daily_loss_usd": -200.0,
            "max_total_risk_usd": 250.0,
            "bias_min_strength": 55,
            "gold_rr_threshold": 3.00,
            "max_daily_trades": 2,
            "use_ml_filter": True,
            "ml_min_win_probability": 0.55,
            "use_ml_dynamic_rr": False,
        }),
        StrategyPreset("aggressive", "Aggressive", "Growth: 2% risk, bias 35+ & ML 50%+, dynamic R:R", {
            "risk_percent": 2.0,
            "max_daily_loss_usd": -400.0,
            "max_total_risk_usd": 500.0,
            "bias_min_strength": 35,
            "gold_rr_threshold": 3.50,
            "max_daily_trades": 3,
            "use_ml_filter": True,
            "ml_min_win_probability": 0.50,
            "use_ml_dynamic_rr": True,
        }),
    ],
    # Inherits ALL optimal parameters from base Advanced ORB strategy
    optimal_parameters={
        **ADVANCED_ORB_STRATEGY.optimal_parameters,
        # ML-specific
        "ml_base_strategy_id": "advanced_orb_strategy",
    }
)


# =============================================================================
# KELTNER CHANNEL BREAKOUT STRATEGY DEFINITION
# =============================================================================

KELTNER_BREAKOUT_STRATEGY = StrategyDefinition(
    id="keltner_breakout_strategy",
    name="Keltner Channel Breakout",
    description="Volatility breakout using Keltner Channels with TTM Squeeze detection. "
                "Enters when price breaks out of ATR-based volatility bands after a squeeze "
                "(Bollinger inside Keltner). Popularized by Linda Raschke and John Carter.",
    version="1.0.0",
    author="System",
    parameter_groups=BASIC_GROUPS,
    parameters=[
        ParameterDefinition("symbol", "Symbol", ParameterType.STRING, "XAUUSD",
                           "Trading symbol", group="basic"),
        ParameterDefinition("timeframe", "Timeframe", ParameterType.SELECT, "M15",
                           "Chart timeframe", group="basic",
                           options=[
                               {"value": "M5", "label": "M5 (5 Minutes)"},
                               {"value": "M15", "label": "M15 (15 Minutes) - Recommended"},
                               {"value": "H1", "label": "H1 (1 Hour)"},
                           ]),
        ParameterDefinition("initial_balance", "Initial Balance ($)", ParameterType.NUMBER, 10000.0,
                           "Starting account balance", min_value=100, step=100, group="basic"),
        ParameterDefinition("preset", "Risk Preset", ParameterType.SELECT, "default",
                           "Predefined risk configuration", group="basic",
                           options=[
                               {"value": "conservative", "label": "Conservative (0.5% risk)"},
                               {"value": "default", "label": "Default (1% risk)"},
                               {"value": "aggressive", "label": "Aggressive (2% risk)"},
                           ]),
        ParameterDefinition("contract_size", "Contract Size", ParameterType.NUMBER, 100.0,
                           "Contract size (Gold: 100 oz/lot)", min_value=1, step=1, group="simulation"),
        ParameterDefinition("simulate_spread", "Simulate Spread", ParameterType.BOOLEAN, True,
                           "Enable spread simulation", group="simulation"),
        ParameterDefinition("use_variable_spread", "Variable Spread", ParameterType.BOOLEAN, True,
                           "Use time-of-day spread model", group="simulation"),
        ParameterDefinition("simulate_slippage", "Simulate Slippage", ParameterType.BOOLEAN, True,
                           "Enable slippage simulation", group="simulation"),
        ParameterDefinition("commission_per_lot", "Commission Per Lot ($)", ParameterType.NUMBER, 3.50,
                           "Round-trip commission per lot", min_value=0, max_value=20, step=0.5, group="simulation"),
        ParameterDefinition("simulate_swap", "Simulate Swap", ParameterType.BOOLEAN, True,
                           "Enable overnight swap charges", group="simulation"),
        ParameterDefinition("close_before_weekend", "Close Before Weekend", ParameterType.BOOLEAN, True,
                           "Auto-close positions on Friday", group="simulation"),
    ],
    presets=[
        StrategyPreset("conservative", "Conservative", "Strong breakouts: ADX 30+, tight squeeze, 3:1 R:R", {
            "risk_percent": 0.5,
            "max_daily_loss_usd": -75.0,
            "max_total_risk_usd": 100.0,
            "max_daily_trades": 1,
            "min_adx": 30,
            "rr_ratio": 3.0,
            "kc_atr_mult": 2.5,
        }),
        StrategyPreset("default", "Default", "Balanced: ADX 20+, standard squeeze, 2.5:1 R:R", {
            "risk_percent": 1.0,
            "max_daily_loss_usd": -200.0,
            "max_total_risk_usd": 250.0,
            "max_daily_trades": 2,
            "min_adx": 20,
            "rr_ratio": 2.5,
            "kc_atr_mult": 2.0,
        }),
        StrategyPreset("aggressive", "Aggressive", "Growth: 2% risk, ADX 15+, wider bands, 2:1 R:R", {
            "risk_percent": 2.0,
            "max_daily_loss_usd": -400.0,
            "max_total_risk_usd": 500.0,
            "max_daily_trades": 3,
            "min_adx": 15,
            "rr_ratio": 2.0,
            "kc_atr_mult": 1.5,
        }),
        StrategyPreset("xauusd_scaled", "XAUUSD Scaled",
                       "Gold profit: 1.25% risk, ADX 20+, 2.5R (scaled default)", {
            "risk_percent": 1.25,
            "max_daily_loss_usd": -250.0,
            "max_total_risk_usd": 300.0,
            "max_daily_trades": 2,
            "min_adx": 20,
            "rr_ratio": 2.5,
            "kc_atr_mult": 2.0,
        }, symbols=["XAUUSD"]),
        StrategyPreset("nas100_scaled", "NAS100 Scaled",
                       "NAS100 profit: 2% risk, ADX 30+, 3R (scaled conservative)", {
            "risk_percent": 2.0,
            "max_daily_loss_usd": -400.0,
            "max_total_risk_usd": 500.0,
            "max_daily_trades": 1,
            "min_adx": 30,
            "rr_ratio": 3.0,
            "kc_atr_mult": 2.5,
        }, symbols=["NAS100"]),
    ],
    optimal_parameters={
        "max_spread_usd": 0.40,
        "min_sl_usd": 3.00,
        "max_sl_usd": 15.00,
        "kc_reentry_grace_bars": 3,
        "kc_ema_period": 20,
        "kc_atr_period": 10,
        "kc_atr_mult": 2.0,
        "bb_period": 20,
        "bb_std": 2.0,
        "squeeze_lookback": 8,
        "roc_period": 12,
        "adx_period": 14,
        "min_adx": 20,
        "rr_ratio": 2.5,
        "require_roc_acceleration": False,
        "trade_start_time": "03:00",
        "trade_end_time": "20:00",
        "use_trailing": True,
        "trailing_atr_period": 14,
        "trailing_atr_multiplier": 2.0,
        "slippage_atr_factor": 0.02,
        "friday_close_hour": 15,
        "friday_close_minute": 30,
        "timeframes": ["M5", "M15", "H1"],
        "symbols": ["XAUUSD", "GBPUSD", "US500", "NAS100"],
    },
    instrument_overrides={
        "US500": {
            "kc_atr_mult": 1.5,
            "min_adx": 15,
            "rr_ratio": 2.0,
            "trade_start_time": "09:30",
            "trade_end_time": "16:00",
        },
        "NAS100": {
            "kc_atr_mult": 1.5,
            "min_adx": 25,
            "rr_ratio": 2.5,
            "trade_start_time": "09:30",
            "trade_end_time": "16:00",
        },
        "GBPUSD": {
            "kc_atr_mult": 2.0,
            "rr_ratio": 2.0,
            "trade_start_time": "08:00",
            "trade_end_time": "17:00",
        },
    },
)


# =============================================================================
# LIQUIDITY SWEEP STRATEGY DEFINITION
# =============================================================================

LIQUIDITY_SWEEP_STRATEGY = StrategyDefinition(
    id="liquidity_sweep_strategy",
    name="Session Liquidity Sweep",
    description="Exploits institutional stop-hunting at session levels (Asian H/L, Previous Day H/L). "
                "Enters on reversal after price sweeps a liquidity level with displacement confirmation.",
    version="1.0.0",
    parameter_groups=BASIC_GROUPS,
    parameters=[
        ParameterDefinition("symbol", "Symbol", ParameterType.STRING, "XAUUSD",
                           "Trading symbol", group="basic"),
        ParameterDefinition("timeframe", "Timeframe", ParameterType.SELECT, "M1",
                           "Chart timeframe", group="basic",
                           options=[
                               {"value": "M1", "label": "M1 (1 Minute) - Recommended"},
                               {"value": "M5", "label": "M5 (5 Minutes)"},
                               {"value": "M15", "label": "M15 (15 Minutes)"},
                           ]),
        ParameterDefinition("initial_balance", "Initial Balance ($)", ParameterType.NUMBER, 10000.0,
                           "Starting account balance", min_value=100, step=100, group="basic"),
        ParameterDefinition("preset", "Risk Preset", ParameterType.SELECT, "default",
                           "Predefined risk configuration", group="basic",
                           options=[
                               {"value": "conservative", "label": "Conservative (0.5% risk)"},
                               {"value": "default", "label": "Default (1% risk)"},
                               {"value": "aggressive", "label": "Aggressive (2% risk)"},
                           ]),
        ParameterDefinition("contract_size", "Contract Size", ParameterType.NUMBER, 100.0,
                           "Contract size (Gold: 100 oz/lot)", min_value=1, step=1, group="simulation"),
        ParameterDefinition("simulate_spread", "Simulate Spread", ParameterType.BOOLEAN, True,
                           "Enable spread simulation", group="simulation"),
        ParameterDefinition("use_variable_spread", "Variable Spread", ParameterType.BOOLEAN, True,
                           "Use time-of-day spread model", group="simulation"),
        ParameterDefinition("simulate_slippage", "Simulate Slippage", ParameterType.BOOLEAN, True,
                           "Enable slippage simulation", group="simulation"),
        ParameterDefinition("commission_per_lot", "Commission Per Lot ($)", ParameterType.NUMBER, 3.50,
                           "Round-trip commission per lot", min_value=0, max_value=20, step=0.5, group="simulation"),
        ParameterDefinition("simulate_swap", "Simulate Swap", ParameterType.BOOLEAN, True,
                           "Enable overnight swap charges", group="simulation"),
        ParameterDefinition("close_before_weekend", "Close Before Weekend", ParameterType.BOOLEAN, True,
                           "Auto-close positions on Friday", group="simulation"),
    ],
    presets=[
        StrategyPreset("conservative", "Conservative", "Sniper sweeps: 0.6 ATR penetration, FVG required, 4:1 R:R", {
            "risk_percent": 0.5,
            "max_daily_loss_usd": -75.0,
            "max_total_risk_usd": 100.0,
            "max_daily_trades": 1,
            "sweep_min_penetration_atr": 0.6,
            "require_fvg_after_sweep": True,
            "min_rr_ratio": 4.0,
            "rejection_body_percentile": 75,
        }),
        StrategyPreset("default", "Default", "Balanced sweeps: 0.3 ATR, FVG required, 3:1 R:R", {
            "risk_percent": 1.0,
            "max_daily_loss_usd": -200.0,
            "max_total_risk_usd": 250.0,
            "max_daily_trades": 2,
            "sweep_min_penetration_atr": 0.3,
            "require_fvg_after_sweep": True,
            "min_rr_ratio": 3.0,
            "rejection_body_percentile": 60,
        }),
        StrategyPreset("aggressive", "Aggressive", "Growth: 2% risk, shallow sweeps (0.15 ATR), no FVG gate", {
            "risk_percent": 2.0,
            "max_daily_loss_usd": -400.0,
            "max_total_risk_usd": 500.0,
            "max_daily_trades": 3,
            "sweep_min_penetration_atr": 0.15,
            "require_fvg_after_sweep": False,
            "min_rr_ratio": 2.5,
            "rejection_body_percentile": 50,
        }),
        StrategyPreset("xauusd_tuned", "XAUUSD Tuned",
                       "Gold sniper: 0.6 ATR sweep, FVG gate, 3R target, 0.75% risk", {
            "risk_percent": 0.75,
            "max_daily_loss_usd": -100.0,
            "max_total_risk_usd": 150.0,
            "max_daily_trades": 2,
            "sweep_min_penetration_atr": 0.6,
            "require_fvg_after_sweep": True,
            "min_rr_ratio": 3.0,
            "rejection_body_percentile": 75,
        }, symbols=["XAUUSD"]),
        StrategyPreset("xauusd_profit", "XAUUSD Profit",
                       "Gold scaled: 0.5 ATR sweep, FVG gate, 3R target, 1.25% risk", {
            "risk_percent": 1.25,
            "max_daily_loss_usd": -175.0,
            "max_total_risk_usd": 200.0,
            "max_daily_trades": 2,
            "sweep_min_penetration_atr": 0.5,
            "require_fvg_after_sweep": True,
            "min_rr_ratio": 3.0,
            "rejection_body_percentile": 70,
        }, symbols=["XAUUSD"]),
        StrategyPreset("nas100_tuned_v1", "NAS100 Tuned v1",
                       "NAS100 quality: 0.25 ATR sweep, FVG gate, 2.5R, 1.25% risk", {
            "risk_percent": 1.25,
            "max_daily_loss_usd": -200.0,
            "max_total_risk_usd": 250.0,
            "max_daily_trades": 3,
            "sweep_min_penetration_atr": 0.25,
            "require_fvg_after_sweep": True,
            "min_rr_ratio": 2.5,
            "rejection_body_percentile": 55,
        }, symbols=["NAS100"]),
        StrategyPreset("nas100_tuned_v2", "NAS100 Tuned v2",
                       "NAS100 growth: 0.2 ATR sweep, FVG gate, 2.5R, 1.75% risk", {
            "risk_percent": 1.75,
            "max_daily_loss_usd": -350.0,
            "max_total_risk_usd": 400.0,
            "max_daily_trades": 3,
            "sweep_min_penetration_atr": 0.2,
            "require_fvg_after_sweep": True,
            "min_rr_ratio": 2.5,
            "rejection_body_percentile": 50,
        }, symbols=["NAS100"]),
        StrategyPreset("nas100_tuned_v3", "NAS100 Tuned v3",
                       "NAS100 strict: 0.35 ATR sweep, FVG gate, 3R, 1.5% risk", {
            "risk_percent": 1.5,
            "max_daily_loss_usd": -250.0,
            "max_total_risk_usd": 300.0,
            "max_daily_trades": 2,
            "sweep_min_penetration_atr": 0.35,
            "require_fvg_after_sweep": True,
            "min_rr_ratio": 3.0,
            "rejection_body_percentile": 65,
        }, symbols=["NAS100"]),
        StrategyPreset("nas100_m15_safe", "NAS100 M15 Safe",
                       "NAS100 M15: 0.3 ATR sweep, FVG gate, 3R, 0.8% risk (DD-controlled)", {
            "risk_percent": 0.8,
            "max_daily_loss_usd": -160.0,
            "max_total_risk_usd": 200.0,
            "max_daily_trades": 2,
            "sweep_min_penetration_atr": 0.3,
            "require_fvg_after_sweep": True,
            "min_rr_ratio": 3.0,
            "rejection_body_percentile": 60,
            "timeframe": "M15",  # Explicit timeframe for DEPLOY config
        }, symbols=["NAS100"]),
        StrategyPreset("nas100_m15_profit", "NAS100 M15 Profit",
                       "NAS100 M15: 0.3 ATR sweep, FVG gate, 3R, 1.25% risk (profit target)", {
            "risk_percent": 1.25,
            "max_daily_loss_usd": -250.0,
            "max_total_risk_usd": 300.0,
            "max_daily_trades": 2,
            "sweep_min_penetration_atr": 0.3,
            "require_fvg_after_sweep": True,
            "min_rr_ratio": 3.0,
            "rejection_body_percentile": 60,
            "timeframe": "M15",  # Explicit timeframe for DEPLOY config
        }, symbols=["NAS100"]),
    ],
    optimal_parameters={
        # Risk Management
        "max_spread_usd": 0.40,
        "min_sl_usd": 1.00,
        "max_sl_usd": 15.00,

        # Sweep Detection
        "sweep_min_penetration_atr": 0.3,
        "sweep_max_bars_to_reject": 3,
        "rejection_body_percentile": 60,
        "require_fvg_after_sweep": True,
        "min_fvg_gap": 0.15,
        "min_rr_ratio": 3.0,
        "sl_buffer_atr": 0.3,

        # Round Numbers
        "use_round_numbers": True,
        "round_number_interval": 100,

        # Session Times (NY session - best for sweep reversals)
        "trade_start_time": "09:30",
        "trade_end_time": "12:00",

        # Trailing Stop
        "use_trailing": True,
        "trailing_atr_period": 14,
        "trailing_atr_multiplier": 2.0,

        # Simulation defaults
        "slippage_atr_factor": 0.02,
        "friday_close_hour": 15,
        "friday_close_minute": 30,

        # Strategy metadata
        "timeframes": ["M5", "M15"],
        "symbols": ["XAUUSD", "NAS100"],
    }
)


# =============================================================================
# HTF FVG + LIQUIDITY RECLAIM STRATEGY DEFINITION
# =============================================================================

HTF_FVG_LIQUIDITY_RECLAIM_STRATEGY = StrategyDefinition(
    id="htf_fvg_liquidity_reclaim_strategy",
    name="HTF FVG + Liquidity Reclaim",
    description="Enters on lower-timeframe retracement into higher-timeframe fair value gaps "
                "after liquidity sweep rejection confirms the reclaim setup.",
    version="1.0.0",
    author="ProTradingSystem",
    parameter_groups=BASIC_GROUPS,
    parameters=[
        ParameterDefinition("symbol", "Symbol", ParameterType.STRING, "XAUUSD",
                           "Trading symbol", group="basic"),
        ParameterDefinition("timeframe", "Timeframe", ParameterType.SELECT, "M15",
                           "Execution timeframe", group="basic",
                           options=[
                               {"value": "M5", "label": "M5 (Aggressive)"},
                               {"value": "M15", "label": "M15 (Recommended)"},
                               {"value": "M30", "label": "M30 (Conservative)"},
                           ]),
        ParameterDefinition("initial_balance", "Initial Balance ($)", ParameterType.NUMBER, 10000.0,
                           "Starting account balance", min_value=100, step=100, group="basic"),
        ParameterDefinition("preset", "Risk Preset", ParameterType.SELECT, "default",
                           "Predefined risk configuration", group="basic",
                           options=[
                               {"value": "conservative", "label": "Conservative"},
                               {"value": "default", "label": "Default"},
                               {"value": "aggressive", "label": "Aggressive"},
                               {"value": "xauusd_m15", "label": "XAUUSD M15 Tuned"},
                               {"value": "nas100_m15", "label": "NAS100 M15 Tuned"},
                           ]),
        ParameterDefinition("contract_size", "Contract Size", ParameterType.NUMBER, 100.0,
                           "Contract size per lot", min_value=1, step=1, group="simulation"),
        ParameterDefinition("simulate_spread", "Simulate Spread", ParameterType.BOOLEAN, True,
                           "Enable spread simulation", group="simulation"),
        ParameterDefinition("use_variable_spread", "Variable Spread", ParameterType.BOOLEAN, True,
                           "Use time-of-day spread model", group="simulation"),
        ParameterDefinition("simulate_slippage", "Simulate Slippage", ParameterType.BOOLEAN, True,
                           "Enable slippage simulation", group="simulation"),
        ParameterDefinition("commission_per_lot", "Commission Per Lot ($)", ParameterType.NUMBER, 3.50,
                           "Round-trip commission per lot", min_value=0, max_value=20, step=0.5, group="simulation"),
        ParameterDefinition("simulate_swap", "Simulate Swap", ParameterType.BOOLEAN, True,
                           "Enable overnight swap charges", group="simulation"),
        ParameterDefinition("close_before_weekend", "Close Before Weekend", ParameterType.BOOLEAN, True,
                           "Auto-close positions on Friday", group="simulation"),
    ],
    presets=[
        StrategyPreset("conservative", "Conservative", "Strict sweep quality + single daily trade", {
            "risk_percent": 0.5,
            "max_daily_loss_usd": -75.0,
            "max_total_risk_usd": 100.0,
            "max_daily_trades": 1,
            "min_rejection_ratio": 0.45,
            "min_rr_ratio": 3.0,
            "sweep_freshness_hours": 3.0,
            "min_pool_touches": 3,
            "bias_min_strength": 40,
            "fvg_max_fill_ratio": 0.60,
        }),
        StrategyPreset("default", "Default", "Balanced sweep + FVG reclaim", {
            "risk_percent": 0.75,
            "max_daily_loss_usd": -100.0,
            "max_total_risk_usd": 150.0,
            "max_daily_trades": 2,
            "min_rejection_ratio": 0.30,
            "min_rr_ratio": 2.5,
            "sweep_freshness_hours": 4.0,
            "min_pool_touches": 2,
            "bias_min_strength": 30,
        }),
        StrategyPreset("aggressive", "Aggressive", "Looser reclaim gate with more setups", {
            "risk_percent": 1.0,
            "max_daily_loss_usd": -150.0,
            "max_total_risk_usd": 200.0,
            "max_daily_trades": 3,
            "min_rejection_ratio": 0.25,
            "min_rr_ratio": 2.0,
            "sweep_freshness_hours": 6.0,
            "min_pool_touches": 2,
            "bias_min_strength": 20,
            "fvg_max_fill_ratio": 0.80,
        }),
        StrategyPreset("xauusd_m15", "XAUUSD M15 Tuned", "Gold-specific reclaim settings", {
            "timeframe": "M15",
            "risk_percent": 0.75,
            "max_daily_loss_usd": -100.0,
            "max_total_risk_usd": 150.0,
            "max_daily_trades": 2,
            "min_rejection_ratio": 0.35,
            "sweep_distance_atr": 0.50,
            "htf_timeframe": "H4",
            "secondary_htf_timeframe": "H1",
            "sl_buffer_atr": 0.25,
            "min_rr_ratio": 2.5,
        }, symbols=["XAUUSD"]),
        StrategyPreset("nas100_m15", "NAS100 M15 Tuned", "Index-specific reclaim settings", {
            "timeframe": "M15",
            "risk_percent": 0.75,
            "max_daily_loss_usd": -150.0,
            "max_total_risk_usd": 200.0,
            "max_daily_trades": 2,
            "min_rejection_ratio": 0.30,
            "sweep_distance_atr": 0.30,
            "htf_timeframe": "H1",
            "secondary_htf_timeframe": "M30",
            "sl_buffer_atr": 0.30,
            "min_rr_ratio": 3.0,
        }, symbols=["NAS100"]),
    ],
    optimal_parameters={
        "htf_timeframe": "H4",
        "secondary_htf_timeframe": "H1",
        "htf_fvg_lookback_bars": 100,
        "htf_fvg_min_gap_atr": 0.15,
        "ltf_pool_lookback_bars": 420,
        "ltf_pool_pivot_span": 3,
        "min_pool_touches": 2,
        "sweep_lookahead_bars": 120,
        "pool_tolerance_atr_mult": 0.12,
        "sweep_freshness_hours": 4.0,
        "sweep_freshness_min_bars": 4,
        "sweep_distance_atr": 0.50,
        "min_rejection_ratio": 0.30,
        "sl_buffer_atr": 0.25,
        "min_rr_ratio": 2.5,
        "max_rr_cap": 8.0,
        "fvg_max_age_bars": 200,
        "fvg_max_fill_ratio": 0.70,
        "fvg_proximity_atr": 2.0,
        "momentum_fade_bars": 30,
        "momentum_fade_min_r": 0.5,
        "max_hold_bars": 60,
        "fvg_reclaim_depth": 0.30,
        "fvg_invalidation_buffer_atr": 0.15,
        "sweep_invalidation_buffer_atr": 0.10,
        "sweep_fvg_structural_atr": 0.75,
        "bias_ema_fast": 20,
        "bias_ema_slow": 50,
        "required_lookback_bars": 500,
        "bias_min_strength": 30,
        "require_bias_alignment": True,
        "trade_start_time": "03:00",
        "trade_end_time": "20:00",
        "use_trailing": True,
        "trailing_atr_period": 14,
        "trailing_atr_multiplier": 2.0,
        "max_spread_usd": 0.40,
        "min_sl_usd": 1.0,
        "max_sl_usd": 15.0,
        "slippage_atr_factor": 0.02,
        "friday_close_hour": 15,
        "friday_close_minute": 30,
        "timeframes": ["M5", "M15", "M30"],
        "symbols": ["XAUUSD", "NAS100", "US500"],
    },
    instrument_overrides={
        "XAUUSD": {
            "max_sl_usd": 12.0,
            "sweep_distance_atr": 0.50,
            "htf_fvg_min_gap_atr": 0.10,
        },
        "NAS100": {
            "max_spread_usd": 3.0,
            "min_sl_usd": 5.0,
            "max_sl_usd": 25.0,
            "sweep_distance_atr": 0.30,
            "htf_timeframe": "H1",
            "secondary_htf_timeframe": "M30",
            "fvg_max_age_bars": 48,
        },
        "US500": {
            "max_spread_usd": 2.0,
            "min_sl_usd": 3.0,
            "max_sl_usd": 15.0,
            "sweep_distance_atr": 0.30,
            "htf_timeframe": "H1",
            "secondary_htf_timeframe": "M30",
        },
    },
)


# =============================================================================
# B-PROFILE FAILED AUCTION REVERSION STRATEGY DEFINITION
# =============================================================================

B_PROFILE_REVERSION_STRATEGY = StrategyDefinition(
    id="b_profile_reversion_strategy",
    name="B-Profile Failed Auction Reversion",
    description="Fades failed breakouts above previous value area high after b-shape liquidation context. "
                "Targets mean reversion back into prior value with asymmetric RR.",
    version="1.0.0",
    parameter_groups=BASIC_GROUPS,
    parameters=[
        ParameterDefinition("symbol", "Symbol", ParameterType.STRING, "NAS100",
                           "Index symbol for profile mean-reversion setup", group="basic"),
        ParameterDefinition("timeframe", "Timeframe", ParameterType.SELECT, "M30",
                           "30-minute profile timeframe for key-level detection and failed-auction signals", group="basic",
                           options=[
                               {"value": "M30", "label": "M30 (30 Minutes) - Recommended"},
                           ]),
        ParameterDefinition("initial_balance", "Initial Balance ($)", ParameterType.NUMBER, 10000.0,
                           "Starting account balance", min_value=100, step=100, group="basic"),
        ParameterDefinition("preset", "Risk Preset", ParameterType.SELECT, "default",
                           "B-profile strategy preset", group="basic",
                           options=[
                               {"value": "conservative", "label": "Conservative (tight risk)"},
                               {"value": "default", "label": "Default (balanced)"},
                               {"value": "aggressive", "label": "Aggressive (higher risk)"},
                               {"value": "databento_edge", "label": "Databento Edge (orderflow-confirmed)"},
                               {"value": "max7_gapdown", "label": "Max7 Gap-Down Edge (NVDA event filter)"},
                           ]),
        ParameterDefinition("contract_size", "Contract Size", ParameterType.NUMBER, 1.0,
                           "Underlying units per lot", min_value=0.01, step=0.01, group="simulation"),
        ParameterDefinition("execution_mode", "Execution Mode", ParameterType.SELECT, "bar",
                           "Bar model (legacy) or microstructure-aware execution simulation", group="simulation",
                           options=[
                               {"value": "bar", "label": "Bar (Legacy)"},
                               {"value": "microstructure", "label": "Microstructure (Databento)"},
                           ]),
        ParameterDefinition("simulate_spread", "Simulate Spread", ParameterType.BOOLEAN, True,
                           "Enable spread simulation", group="simulation"),
        ParameterDefinition("use_variable_spread", "Variable Spread", ParameterType.BOOLEAN, True,
                           "Use time-of-day spread model", group="simulation"),
        ParameterDefinition("simulate_slippage", "Simulate Slippage", ParameterType.BOOLEAN, True,
                           "Enable slippage simulation", group="simulation"),
        ParameterDefinition("commission_per_lot", "Commission Per Lot ($)", ParameterType.NUMBER, 2.0,
                           "Round-trip commission estimate", min_value=0, max_value=20, step=0.1, group="simulation"),
        ParameterDefinition("simulate_swap", "Simulate Swap", ParameterType.BOOLEAN, True,
                           "Enable overnight swap simulation", group="simulation"),
        ParameterDefinition("close_before_weekend", "Close Before Weekend", ParameterType.BOOLEAN, True,
                           "Auto-close positions on Friday", group="simulation"),
    ],
    presets=[
        StrategyPreset("conservative", "Conservative", "Lower risk with stricter confirmation", {
            "risk_percent": 0.6,
            "max_daily_loss_usd": -150.0,
            "max_total_risk_usd": 200.0,
            "max_daily_trades": 1,
            "min_rr_ratio": 4.5,
            "stretch_rr_ratio": 6.0,
            "min_b_shape_score": 0.62,
            "constituent_confirmation_mode": "required",
            "require_both_constituents": True,
        }),
        StrategyPreset("default", "Default", "Balanced profile fade with optional constituent confirmation", {
            "risk_percent": 1.0,
            "max_daily_loss_usd": -220.0,
            "max_total_risk_usd": 300.0,
            "max_daily_trades": 1,
            "min_rr_ratio": 4.5,
            "stretch_rr_ratio": 6.0,
            "min_b_shape_score": 0.58,
            "constituent_confirmation_mode": "required",
            "require_both_constituents": True,
        }),
        StrategyPreset("aggressive", "Aggressive", "Higher allocation and looser context filters", {
            "risk_percent": 1.5,
            "max_daily_loss_usd": -350.0,
            "max_total_risk_usd": 450.0,
            "max_daily_trades": 2,
            "min_rr_ratio": 4.5,
            "stretch_rr_ratio": 6.0,
            "min_b_shape_score": 0.54,
            "constituent_confirmation_mode": "required",
            "require_both_constituents": True,
        }),
        StrategyPreset("databento_edge", "Databento Edge", "Strict short-only profile fade with orderflow+correlation confirmation", {
            "execution_mode": "microstructure",
            "risk_percent": 1.0,
            "max_daily_loss_usd": -250.0,
            "max_total_risk_usd": 350.0,
            "max_daily_trades": 2,
            "simulate_spread": False,
            "max_spread_usd": 3.0,
            "min_rr_ratio": 3.0,
            "stretch_rr_ratio": 4.5,
            "micro_latency_bars": 1,
            "micro_base_fill_probability": 0.92,
            "micro_min_fill_probability": 0.12,
            "micro_partial_fill_min": 0.70,
            "micro_partial_fill_max": 1.00,
            "micro_spread_scale": 1.0,
            "micro_slippage_scale": 1.25,
            "micro_adverse_selection_scale": 0.25,
            "micro_max_extra_slippage_usd": 1.5,
            "min_profile_bars": 10,
            "profile_bins": 24,
            "volume_lookback_bars": 12,
            "min_b_shape_score": 0.48,
            "min_lower_distribution_share": 0.50,
            "max_upper_tail_share": 0.30,
            "breakout_buffer_atr": 0.04,
            "reentry_buffer_atr": 0.01,
            "trade_start_time": "09:35",
            "trade_end_time": "15:00",
            "constituent_confirmation_mode": "auto",
            "correlation_confirmation_mode": "required",
            "correlation_return_col": "es_ret_5m",
            "correlation_max_ret_short": 0.0005,
            "orderflow_confirmation_mode": "required",
            "orderflow_flow_col": "of_flow_imbalance",
            "orderflow_dom_col": "dom_imbalance",
            "orderflow_absorption_col": "dom_absorption_score",
            "orderflow_lva_velocity_col": "lva_velocity",
            "max_flow_imbalance_short": -0.02,
            "max_dom_imbalance_short": -0.02,
            "min_absorption_score_short": 0.0,
            "min_lva_velocity": 0.9,
        }),
        StrategyPreset("max7_gapdown", "Max7 Gap-Down Edge", "Orderflow-confirmed short setup requiring NVDA gap-down context", {
            "execution_mode": "microstructure",
            "risk_percent": 1.0,
            "max_daily_loss_usd": -250.0,
            "max_total_risk_usd": 350.0,
            "max_daily_trades": 2,
            "simulate_spread": False,
            "max_spread_usd": 3.0,
            "min_rr_ratio": 3.0,
            "stretch_rr_ratio": 4.5,
            "micro_latency_bars": 1,
            "micro_base_fill_probability": 0.92,
            "micro_min_fill_probability": 0.12,
            "micro_partial_fill_min": 0.70,
            "micro_partial_fill_max": 1.00,
            "micro_spread_scale": 1.0,
            "micro_slippage_scale": 1.20,
            "micro_adverse_selection_scale": 0.25,
            "micro_max_extra_slippage_usd": 1.5,
            "min_profile_bars": 10,
            "profile_bins": 24,
            "volume_lookback_bars": 12,
            "min_b_shape_score": 0.45,
            "min_lower_distribution_share": 0.48,
            "max_upper_tail_share": 0.32,
            "breakout_buffer_atr": 0.02,
            "reentry_buffer_atr": 0.00,
            "min_bear_body_atr": 0.08,
            "max_close_to_low_ratio": 0.55,
            "min_upper_wick_ratio": 0.10,
            "trade_start_time": "09:35",
            "trade_end_time": "15:00",
            "constituent_confirmation_mode": "required",
            "require_both_constituents": False,
            "constituent_gap_mode": "required",
            "require_nvda_gap_down": True,
            "require_tsla_gap_down": False,
            "gap_down_threshold_pct": 0.20,
            "correlation_confirmation_mode": "required",
            "correlation_return_col": "es_ret_5m",
            "correlation_max_ret_short": 0.0005,
            "orderflow_confirmation_mode": "required",
            "orderflow_flow_col": "of_flow_imbalance",
            "orderflow_dom_col": "dom_imbalance",
            "orderflow_absorption_col": "dom_absorption_score",
            "orderflow_lva_velocity_col": "lva_velocity",
            "max_flow_imbalance_short": -0.01,
            "max_dom_imbalance_short": -0.02,
            "min_absorption_score_short": 0.0,
            "min_lva_velocity": 0.8,
        }),
    ],
    optimal_parameters={
        # Session timing and trade limits
        "trade_start_time": "09:35",
        "trade_end_time": "13:00",
        "flat_time": "15:55",
        "one_trade_per_day": False,
        "stop_after_first_win": False,
        "max_daily_trades": 1,

        # Profile construction
        "profile_use_volume": True,
        "profile_bins": 48,
        "value_area_pct": 0.70,
        "min_profile_bars": 30,
        "min_lower_distribution_share": 0.58,
        "max_upper_tail_share": 0.22,
        "min_b_shape_score": 0.58,

        # Failed auction + re-entry logic
        "breakout_buffer_atr": 0.08,
        "reentry_buffer_atr": 0.02,
        "failed_auction_lookback_bars": 6,

        # Exhaustion / pressure filters
        "volume_lookback_bars": 24,
        "max_top_volume_ratio": 0.90,
        "min_bear_body_atr": 0.12,
        "max_close_to_low_ratio": 0.45,
        "min_upper_wick_ratio": 0.20,

        # Constituent divergence (optional inputs from CSV columns)
        "constituent_confirmation_mode": "required",   # off / auto / required
        "constituent_lookback_bars": 6,
        "constituent_weakness_threshold": -0.001,
        "require_both_constituents": True,
        "nvda_return_col": "nvda_ret",
        "tsla_return_col": "tsla_ret",
        "nvda_close_col": "nvda_close",
        "tsla_close_col": "tsla_close",
        "constituent_gap_mode": "off",              # off / auto / required
        "require_nvda_gap_down": False,
        "require_tsla_gap_down": False,
        "gap_down_threshold_pct": 0.20,

        # Cross-asset correlation confirmation (ES proxy)
        "correlation_confirmation_mode": "auto",       # off / auto / required
        "correlation_return_col": "es_ret_5m",
        "correlation_max_ret_short": 0.0005,
        "correlation_require_negative": True,

        # Databento orderflow/depth confirmations
        "orderflow_confirmation_mode": "auto",         # off / auto / required
        "orderflow_flow_col": "of_flow_imbalance",
        "orderflow_dom_col": "dom_imbalance",
        "orderflow_absorption_col": "dom_absorption_score",
        "orderflow_lva_velocity_col": "lva_velocity",
        "max_flow_imbalance_short": -0.02,
        "max_dom_imbalance_short": -0.02,
        "min_absorption_score_short": 0.0,
        "min_lva_velocity": 0.0,

        # Risk model
        "risk_percent": 1.0,
        "max_daily_loss_usd": -220.0,
        "max_total_risk_usd": 300.0,
        "min_sl_usd": 2.0,
        "max_sl_usd": 40.0,
        "sl_buffer_atr": 0.15,
        "min_rr_ratio": 4.5,
        "stretch_rr_ratio": 6.0,
        "stretch_rr_bshape_score": 0.70,
        "use_trailing": True,

        # Simulation defaults
        "max_spread_usd": 1.50,
        "slippage_atr_factor": 0.02,
        "friday_close_hour": 15,
        "friday_close_minute": 30,

        # Metadata for UI filtering
        "timeframes": ["M30"],
        "symbols": ["NAS100", "US500"],
        "execution_mode": "bar",
    },
    instrument_overrides={
        "NAS100": {"contract_size": 1.0, "max_spread_usd": 3.0, "commission_per_lot": 2.0},
        "US500": {"contract_size": 1.0, "max_spread_usd": 1.0, "commission_per_lot": 2.0},
    },
)


# =============================================================================
# EARNINGS VOLATILITY CRUSH STRATEGY DEFINITION
# =============================================================================

EARNINGS_VOLATILITY_STRATEGY = StrategyDefinition(
    id="earnings_volatility_strategy",
    name="Earnings IV Crush",
    description="Sells pre-earnings volatility via strict event filters and timed exits. "
                "Supports short straddle and preferred long-calendar proxy structures.",
    version="1.0.0",
    parameter_groups=BASIC_GROUPS,
    parameters=[
        ParameterDefinition("symbol", "Symbol", ParameterType.STRING, "AAPL",
                           "Equity ticker for earnings event dataset", group="basic"),
        ParameterDefinition("timeframe", "Timeframe", ParameterType.SELECT, "M15",
                           "Intraday timeframe for timed earnings entries", group="basic",
                           options=[
                               {"value": "M15", "label": "M15 (15 Minutes) - Recommended"},
                               {"value": "M5", "label": "M5 (5 Minutes)"},
                           ]),
        ParameterDefinition("initial_balance", "Initial Balance ($)", ParameterType.NUMBER, 10000.0,
                           "Starting account balance", min_value=100, step=100, group="basic"),
        ParameterDefinition("preset", "Risk Preset", ParameterType.SELECT, "default",
                           "Earnings-volatility preset", group="basic",
                           options=[
                               {"value": "conservative", "label": "Conservative (Calendar / lower risk)"},
                               {"value": "default", "label": "Default (Calendar / 10% Kelly proxy)"},
                               {"value": "aggressive", "label": "Aggressive (Calendar / higher sizing)"},
                               {"value": "edge_portfolio", "label": "Edge Portfolio (Aggressive + tuned penalties)"},
                               {"value": "straddle", "label": "Straddle (High variance)"},
                           ]),
        ParameterDefinition("contract_size", "Contract Size", ParameterType.NUMBER, 1.0,
                           "Underlying units per lot", min_value=0.01, step=0.01, group="simulation"),
        ParameterDefinition("simulate_spread", "Simulate Spread", ParameterType.BOOLEAN, True,
                           "Enable bid/ask spread cost modeling", group="simulation"),
        ParameterDefinition("use_variable_spread", "Variable Spread", ParameterType.BOOLEAN, False,
                           "Use time-of-day spread model", group="simulation"),
        ParameterDefinition("simulate_slippage", "Simulate Slippage", ParameterType.BOOLEAN, True,
                           "Enable execution slippage modeling", group="simulation"),
        ParameterDefinition("commission_per_lot", "Commission Per Lot ($)", ParameterType.NUMBER, 1.0,
                           "Round-trip commission estimate", min_value=0, max_value=20, step=0.1, group="simulation"),
        ParameterDefinition("simulate_swap", "Simulate Swap", ParameterType.BOOLEAN, True,
                           "Enable overnight carry-cost simulation", group="simulation"),
        ParameterDefinition("close_before_weekend", "Close Before Weekend", ParameterType.BOOLEAN, True,
                           "Still enforce Friday close protections", group="simulation"),
    ],
    presets=[
        StrategyPreset("conservative", "Conservative", "Calendar-first with strict filters and reduced sizing", {
            "vol_structure": "long_calendar",
            "risk_percent": 4.0,
            "max_daily_loss_usd": -200.0,
            "max_total_risk_usd": 300.0,
            "max_daily_trades": 1,
            "stop_after_first_win": False,
            "term_structure_max_slope": -0.06,
            "min_avg_volume30": 8_000_000,
            "min_iv30_rv30_ratio": 1.35,
            "entry_time": "15:45",
            "exit_time": "09:45",
        }),
        StrategyPreset("default", "Default", "Calendar-first with 10% Kelly-style sizing proxy (~6%/trade)", {
            "vol_structure": "long_calendar",
            "risk_percent": 6.0,
            "max_daily_loss_usd": -300.0,
            "max_total_risk_usd": 450.0,
            "max_daily_trades": 1,
            "stop_after_first_win": False,
            "term_structure_max_slope": -0.05,
            "min_avg_volume30": 5_000_000,
            "min_iv30_rv30_ratio": 1.25,
            "entry_time": "15:45",
            "exit_time": "09:45",
        }),
        StrategyPreset("aggressive", "Aggressive", "Calendar structure with looser filters and higher allocation", {
            "vol_structure": "long_calendar",
            "risk_percent": 8.0,
            "max_daily_loss_usd": -450.0,
            "max_total_risk_usd": 600.0,
            "max_daily_trades": 1,
            "stop_after_first_win": False,
            "term_structure_max_slope": -0.04,
            "min_avg_volume30": 4_000_000,
            "min_iv30_rv30_ratio": 1.18,
            "entry_time": "15:45",
            "exit_time": "09:45",
        }),
        StrategyPreset(
            "edge_portfolio",
            "Edge Portfolio",
            "Campaign winner for basket deployment: aggressive calendar + tuned move/breach penalties.",
            {
                "vol_structure": "long_calendar",
                "risk_percent": 8.0,
                "max_daily_loss_usd": -450.0,
                "max_total_risk_usd": 600.0,
                "max_daily_trades": 1,
                "stop_after_first_win": False,
                "term_structure_max_slope": -0.04,
                "min_avg_volume30": 4_000_000,
                "min_iv30_rv30_ratio": 1.18,
                "move_penalty_mult": 0.9,
                "breach_penalty_mult": 2.3,
                "entry_time": "15:45",
                "exit_time": "09:45",
            },
        ),
        StrategyPreset("straddle", "Straddle", "High variance straddle mode with tight sizing controls", {
            "vol_structure": "short_straddle",
            "risk_percent": 2.0,
            "max_daily_loss_usd": -200.0,
            "max_total_risk_usd": 250.0,
            "max_daily_trades": 1,
            "stop_after_first_win": False,
            "term_structure_max_slope": -0.05,
            "min_avg_volume30": 7_000_000,
            "min_iv30_rv30_ratio": 1.30,
            "entry_time": "15:45",
            "exit_time": "09:45",
        }),
    ],
    optimal_parameters={
        # Trade structure
        "vol_structure": "long_calendar",          # preferred
        "front_dte_days": 7,
        "back_dte_days": 37,                       # ~30-day gap
        "target_expiration_gap_days": 30,

        # Execution timing (critical)
        "entry_time": "15:45",
        "exit_time": "09:45",

        # Alpha filters
        "term_structure_max_slope": -0.05,         # backwardation requirement
        "min_avg_volume30": 5_000_000,
        "min_iv30_rv30_ratio": 1.25,

        # Required dataset columns
        "earnings_event_col": "earnings_event",
        "iv_front_col": "iv_front",
        "iv_back_col": "iv_back",
        "iv_far_col": "iv_45d",
        "volume30_col": "volume30",
        "iv30_col": "iv30",
        "rv30_col": "rv30",

        # Proxy PnL model tuning
        "expected_move_scale": 1.0,
        "straddle_premium_factor": 0.95,
        "calendar_edge_factor": 1.20,
        "move_penalty_mult": 1.0,
        "breach_penalty_mult": 2.5,
        "iv_point_value": 100.0,
        "calendar_back_vega_weight": 0.35,

        # Engine interaction defaults
        "max_spread_usd": 0.20,
        "min_sl_usd": 0.50,
        "max_sl_usd": 25.0,
        "slippage_atr_factor": 0.0,
        "simulate_spread": True,
        "simulate_slippage": True,
        "simulate_swap": True,
        "use_trailing": False,
        "close_before_weekend": True,
        "stop_after_first_win": False,
        "allow_event_lookahead": False,

        # Metadata for UI
        "timeframes": ["M5", "M15"],
        "symbols": ["AAPL", "MSFT", "NVDA", "AMZN", "META", "TSLA"],
    },
    instrument_overrides={
        # Keep equity-like sizing semantics (1x underlying) and avoid
        # accidental fallback to Gold contract assumptions.
        "AAPL": {"contract_size": 1.0, "max_spread_usd": 0.20, "commission_per_lot": 1.0},
        "MSFT": {"contract_size": 1.0, "max_spread_usd": 0.25, "commission_per_lot": 1.0},
        "NVDA": {"contract_size": 1.0, "max_spread_usd": 0.40, "commission_per_lot": 1.0},
        "AMZN": {"contract_size": 1.0, "max_spread_usd": 0.25, "commission_per_lot": 1.0},
        "META": {"contract_size": 1.0, "max_spread_usd": 0.30, "commission_per_lot": 1.0},
        "TSLA": {"contract_size": 1.0, "max_spread_usd": 0.40, "commission_per_lot": 1.0},
    },
)


# =============================================================================
# STRATEGY REGISTRY
# =============================================================================

class StrategyRegistry:
    """Central registry of all available trading strategies"""

    _strategies: Dict[str, StrategyDefinition] = {
        ORB_STRATEGY.id: ORB_STRATEGY,
        ADVANCED_ORB_STRATEGY.id: ADVANCED_ORB_STRATEGY,
        ORB_ML_STRATEGY.id: ORB_ML_STRATEGY,
        ADVANCED_ORB_ML_STRATEGY.id: ADVANCED_ORB_ML_STRATEGY,
        LIQUIDITY_SWEEP_STRATEGY.id: LIQUIDITY_SWEEP_STRATEGY,
        HTF_FVG_LIQUIDITY_RECLAIM_STRATEGY.id: HTF_FVG_LIQUIDITY_RECLAIM_STRATEGY,
        KELTNER_BREAKOUT_STRATEGY.id: KELTNER_BREAKOUT_STRATEGY,
        B_PROFILE_REVERSION_STRATEGY.id: B_PROFILE_REVERSION_STRATEGY,
        EARNINGS_VOLATILITY_STRATEGY.id: EARNINGS_VOLATILITY_STRATEGY,
    }

    @classmethod
    def get_strategy(cls, strategy_id: str) -> Optional[StrategyDefinition]:
        """Get a strategy by ID"""
        return cls._strategies.get(strategy_id)

    @classmethod
    def get_all_strategies(cls) -> List[StrategyDefinition]:
        """Get all registered strategies"""
        return list(cls._strategies.values())

    @classmethod
    def get_strategy_list(cls) -> List[Dict[str, str]]:
        """Get simplified list of strategies for dropdown"""
        return [
            {"id": s.id, "name": s.name, "description": s.description}
            for s in cls._strategies.values()
        ]

    @classmethod
    def register_strategy(cls, strategy: StrategyDefinition) -> None:
        """Register a new strategy"""
        cls._strategies[strategy.id] = strategy

    @classmethod
    def get_defaults_for_strategy(cls, strategy_id: str) -> Dict[str, Any]:
        """Get default parameter values for a strategy"""
        strategy = cls.get_strategy(strategy_id)
        if strategy:
            return strategy.get_defaults()
        return {}

    @classmethod
    def get_preset_config(cls, strategy_id: str, preset_id: str, symbol: str = None) -> Dict[str, Any]:
        """Get full configuration for a strategy preset, optionally instrument-adjusted"""
        strategy = cls.get_strategy(strategy_id)
        if strategy:
            return strategy.get_preset_config(preset_id, symbol)
        return {}
