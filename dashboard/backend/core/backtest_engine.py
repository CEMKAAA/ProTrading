"""
Enterprise Backtesting Engine
Simulates trading strategy on historical data with full ICT concept implementation
"""

import pandas as pd
import numpy as np
from datetime import datetime, time, timedelta
from typing import Optional, Dict, Any, List, Tuple
from dataclasses import dataclass, field, asdict
import pytz
import logging
from .instrument_specs import get_instrument, InstrumentSpec
from .timezone_config import NY_TZ, FRIDAY_CLOSE_TIME, FRIDAY_WEEKDAY
import sys
import os
import hashlib
import inspect
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__)))))

from .data_provider import HistoricalDataProvider
from .metrics_calculator import MetricsCalculator, TradeRecord
from .ml_features import FeatureExtractor
from .cross_asset_regime import CrossAssetRegimeFilter
from .future_data_guard import FutureDataGuard
from .microstructure import (
    MicrostructureExecutionSimulator,
    summarize_microstructure_from_trades,
)

logger = logging.getLogger(__name__)


@dataclass
class BacktestConfig:
    """Configuration for backtest run"""
    # Symbol & Timeframe
    symbol: str = "XAUUSD"
    timeframe: str = "M1"

    # Date Range
    start_date: datetime = None
    end_date: datetime = None

    # Risk Management
    initial_balance: float = 10000.0
    risk_percent: float = 1.0
    max_spread_usd: float = 0.40
    max_daily_loss_usd: float = -150.0
    max_total_risk_usd: float = 200.0

    # Contract Size (Gold: 1 lot = 100 oz)
    contract_size: float = 100.0

    # Simulation Realism - Spread
    simulate_spread: bool = True
    use_variable_spread: bool = True  # Time-of-day spread model

    # Simulation Realism - Slippage (ATR-based)
    simulate_slippage: bool = True
    slippage_atr_factor: float = 0.02  # slippage = ATR * this factor
    min_slippage_usd: float = 0.01
    max_slippage_usd: float = 0.50

    # Commission
    commission_per_lot: float = 3.50  # Round-trip commission per lot

    # Overnight Swap Simulation
    simulate_swap: bool = True
    swap_long_per_lot: float = -8.50   # Typical gold swap for long (per night per lot)
    swap_short_per_lot: float = -3.20  # Typical gold swap for short
    triple_swap_day: int = 2           # Wednesday = triple swap (0=Mon, 2=Wed)

    # Friday Close Settings
    close_before_weekend: bool = True
    friday_close_hour: int = 15  # 3 PM NY time
    friday_close_minute: int = 30

    # Bias Strength (match live bot)
    bias_min_strength: int = 30  # Minimum bias score to trade (0-100)

    # Stop Loss Parameters
    min_sl_usd: float = 1.00
    max_sl_usd: float = 10.00
    gold_rr_threshold: float = 3.00

    # ICT Parameters - FVG
    min_fvg_gap: float = 0.30
    fvg_lookback: int = 50

    # ICT Parameters - Displacement
    displacement_percentile: int = 75
    displacement_lookback: int = 20
    max_opposing_wick_ratio: float = 0.4

    # ICT Parameters - Order Blocks
    ob_lookback: int = 100
    ob_min_body_percent: int = 60
    ob_validation_bars: int = 3

    # ICT Parameters - Liquidity
    liquidity_wick_ratio: float = 0.6
    sweep_tolerance_usd: float = 0.20

    # Session Times (NY timezone)
    orb_start_time: str = "09:30"
    orb_end_time: str = "09:45"
    trade_start_time: str = "09:45"
    trade_end_time: str = "16:00"

    # Session definitions
    asian_start: str = "20:00"
    asian_end: str = "02:00"
    london_start: str = "03:00"
    london_end: str = "12:00"

    # Trailing Stop
    use_trailing: bool = True
    trailing_atr_period: int = 14
    trailing_atr_multiplier: float = 1.5

    # Trend Filter
    min_adr_for_trend: float = 12.0
    adr_period: int = 5

    # Trade Limits
    max_daily_trades: int = 2
    stop_after_first_win: bool = True

    # Cross-Asset Regime Filter (macro gate + dynamic risk sizing)
    enable_cross_asset_filter: bool = False
    regime_timeframe: str = "M15"
    regime_lookback_bars: int = 96
    regime_return_bars: int = 8
    regime_signal_threshold: float = 0.18
    regime_strong_threshold: float = 0.40
    regime_block_countertrend: bool = True
    regime_reduce_size_in_headwind: bool = True
    regime_tailwind_risk_multiplier: float = 1.15
    regime_headwind_risk_multiplier: float = 0.50
    regime_neutral_risk_multiplier: float = 1.00
    regime_symbol_dxy: str = "DXY,USDX,USDX.i"
    regime_symbol_yield: str = "US10Y,TNX,US10Y.cash"
    regime_symbol_riskoff: str = "VIX,VIX.cash,VOLX"
    regime_symbol_riskon: str = "SPX500,US500,US30"
    regime_weight_dxy: float = 0.40
    regime_weight_yield: float = 0.35
    regime_weight_riskoff: float = 0.15
    regime_weight_riskon: float = 0.10

    # Data Source
    data_source: str = "auto"  # "auto" or "csv_only"
    csv_files: Optional[List[str]] = None  # Specific CSV filenames to use
    # Reproducibility (None = non-deterministic randomness)
    random_seed: Optional[int] = 42

    # Execution model
    execution_mode: str = "bar"  # bar | microstructure

    # Microstructure execution (used when execution_mode == "microstructure")
    micro_latency_bars: int = 0
    micro_base_fill_probability: float = 0.95
    micro_min_fill_probability: float = 0.15
    micro_partial_fill_min: float = 0.65
    micro_partial_fill_max: float = 1.00
    micro_min_volume: float = 0.0
    micro_spread_scale: float = 1.0
    micro_slippage_scale: float = 1.0
    micro_adverse_selection_scale: float = 0.2
    micro_max_extra_slippage_usd: float = 1.0
    micro_flow_imbalance_col: str = "of_flow_imbalance"
    micro_dom_imbalance_col: str = "dom_imbalance"
    micro_absorption_col: str = "dom_absorption_score"
    micro_lva_velocity_col: str = "lva_velocity"


@dataclass
class Position:
    """Represents an open position"""
    direction: str  # "BUY" or "SELL"
    entry_time: datetime
    entry_price: float
    stop_loss: float
    initial_stop_loss: float  # Preserved at entry for canonical R-multiple
    take_profit: float
    lot_size: float
    setup_type: str
    bias: str
    orb_high: float
    orb_low: float
    asian_high: float
    asian_low: float
    pd_high: float
    pd_low: float
    fvg_size: Optional[float] = None
    fvg_top: Optional[float] = None
    fvg_bottom: Optional[float] = None
    ob_high: Optional[float] = None
    ob_low: Optional[float] = None
    at_breakeven: bool = False
    trailing_sl: Optional[float] = None
    # Cost tracking
    spread_cost: float = 0.0      # Entry spread cost
    slippage_cost: float = 0.0    # Entry slippage cost
    commission_cost: float = 0.0  # Entry commission (half)
    swap_cost: float = 0.0        # Accumulated overnight swap
    last_swap_date: Optional[datetime] = None  # Track last swap charge date
    # Strategy diagnostics: why this trade was taken
    strategy_metadata: Optional[Dict[str, Any]] = None
    # ML features (captured at entry for training data)
    ml_features: Optional[Dict[str, float]] = None
    # MFE/MAE tracking (Maximum Favorable/Adverse Excursion)
    max_favorable_excursion: float = 0.0  # Best price movement in R-multiples
    max_adverse_excursion: float = 0.0    # Worst price movement in R-multiples


@dataclass
class DayState:
    """State for a trading day"""
    date: datetime
    pd_high: Optional[float] = None
    pd_low: Optional[float] = None
    asian_high: Optional[float] = None
    asian_low: Optional[float] = None
    london_high: Optional[float] = None
    london_low: Optional[float] = None
    orb_high: Optional[float] = None
    orb_low: Optional[float] = None
    bias: str = "neutral"
    bias_strength: int = 0  # 0-100 score matching live bot
    atr: float = 1.0  # Current ATR for slippage calculation
    daily_atr: float = 0.0  # Daily ATR for ORB range normalization
    is_trending: bool = False
    daily_pnl: float = 0.0
    daily_trades: int = 0
    first_trade_won: bool = False
    can_trade: bool = True


class BacktestEngine:
    """
    Enterprise-grade backtesting engine with full ICT strategy implementation.
    Simulates the GoldORBBot trading logic on historical data.

    Optionally delegates signal detection to a BacktestStrategy instance.
    When ``strategy`` is ``None`` the engine uses its built-in (legacy)
    ``_find_trade_setup`` / ``_calculate_bias`` code path.
    """

    def __init__(self, config: BacktestConfig, strategy=None):
        """
        Args:
            config: Backtest configuration dataclass.
            strategy: Optional BacktestStrategy instance for signal detection.
                      When provided, the engine delegates bias calculation and
                      trade setup detection to the strategy.
        """
        self.config = config
        self.strategy = strategy      # Optional BacktestStrategy
        self.day_context = None       # DayContext populated when strategy is used
        self.data_provider = HistoricalDataProvider()
        self.metrics_calc = MetricsCalculator(config.initial_balance)
        self.ny_tz = NY_TZ
        self.instrument = get_instrument(config.symbol)
        self.rng = np.random.default_rng(config.random_seed) if config.random_seed is not None else np.random.default_rng()

        # State tracking
        self.balance = config.initial_balance
        self.equity_curve: List[Tuple[datetime, float]] = []
        self.trades: List[TradeRecord] = []
        self.open_position: Optional[Position] = None
        self.day_state: Optional[DayState] = None
        self.trade_counter = 0

        # ML feature support
        self._recent_trade_results: list = []  # Rolling win/loss for consecutive_results

        # Progress tracking
        self.progress = 0.0
        self.status = "PENDING"
        self.error_message: Optional[str] = None

        # Optional macro regime filter
        self.cross_asset_filter: Optional[CrossAssetRegimeFilter] = None
        self.micro_simulator: Optional[MicrostructureExecutionSimulator] = None
        if str(getattr(self.config, "execution_mode", "bar")).lower() == "microstructure":
            self.micro_simulator = MicrostructureExecutionSimulator(
                config=self.config,
                rng=self.rng,
                spread_fn=self._get_simulated_spread,
            )

    def _log_config_parameters(self):
        """Log all configuration parameters for debugging and verification"""
        c = self.config
        logger.info("=" * 80)
        logger.info("BACKTEST CONFIGURATION PARAMETERS")
        logger.info("=" * 80)

        logger.info(">>> BASIC SETTINGS <<<")
        logger.info(f"  Symbol: {c.symbol}")
        logger.info(f"  Timeframe: {c.timeframe}")
        logger.info(f"  Start Date: {c.start_date}")
        logger.info(f"  End Date: {c.end_date}")
        logger.info(f"  Initial Balance: ${c.initial_balance:,.2f}")

        logger.info(">>> RISK MANAGEMENT <<<")
        logger.info(f"  Risk Percent: {c.risk_percent}%")
        logger.info(f"  Max Spread: ${c.max_spread_usd}")
        logger.info(f"  Max Daily Loss: ${c.max_daily_loss_usd}")
        logger.info(f"  Max Total Risk: ${c.max_total_risk_usd}")
        # Contract size description varies by instrument
        contract_desc = {
            "XAUUSD": "100oz/lot", "XAGUSD": "5000oz/lot",
            "EURUSD": "100k units", "GBPUSD": "100k units", "USDJPY": "100k units",
            "US500": "$1/point", "NAS100": "$1/point"
        }.get(c.symbol, "per lot")
        logger.info(f"  Contract Size: {c.contract_size} ({contract_desc})")

        logger.info(">>> SIMULATION SETTINGS <<<")
        logger.info(f"  Execution Mode: {c.execution_mode}")
        logger.info(f"  Simulate Spread: {c.simulate_spread}")
        logger.info(f"  Use Variable Spread: {c.use_variable_spread}")
        logger.info(f"  Simulate Slippage: {c.simulate_slippage}")
        logger.info(f"  Slippage ATR Factor: {c.slippage_atr_factor}")
        logger.info(f"  Min/Max Slippage: ${c.min_slippage_usd} - ${c.max_slippage_usd}")
        logger.info(f"  Commission per Lot: ${c.commission_per_lot}")
        logger.info(f"  Simulate Swap: {c.simulate_swap}")
        logger.info(f"  Random Seed: {c.random_seed}")
        logger.info(f"  Swap Long/Short: ${c.swap_long_per_lot} / ${c.swap_short_per_lot}")
        logger.info(f"  Triple Swap Day: {c.triple_swap_day} (0=Mon, 2=Wed)")
        if str(c.execution_mode).lower() == "microstructure":
            logger.info(">>> MICROSTRUCTURE EXECUTION <<<")
            logger.info(f"  Latency Bars: {c.micro_latency_bars}")
            logger.info(f"  Base/Min Fill Probability: {c.micro_base_fill_probability} / {c.micro_min_fill_probability}")
            logger.info(f"  Partial Fill Ratio Range: {c.micro_partial_fill_min} - {c.micro_partial_fill_max}")
            logger.info(f"  Spread/Slippage Scale: {c.micro_spread_scale} / {c.micro_slippage_scale}")
            logger.info(f"  Adverse Selection Scale: {c.micro_adverse_selection_scale}")
            logger.info(
                "  Feature Cols: flow=%s dom=%s absorption=%s lva=%s",
                c.micro_flow_imbalance_col,
                c.micro_dom_imbalance_col,
                c.micro_absorption_col,
                c.micro_lva_velocity_col,
            )

        logger.info(">>> STOP LOSS / TAKE PROFIT <<<")
        logger.info(f"  Min SL: ${c.min_sl_usd}")
        logger.info(f"  Max SL: ${c.max_sl_usd}")
        logger.info(f"  Gold R:R Threshold: {c.gold_rr_threshold}")

        logger.info(">>> ICT PARAMETERS - FVG <<<")
        logger.info(f"  Min FVG Gap: ${c.min_fvg_gap}")
        logger.info(f"  FVG Lookback: {c.fvg_lookback} bars")

        logger.info(">>> ICT PARAMETERS - DISPLACEMENT <<<")
        logger.info(f"  Displacement Percentile: {c.displacement_percentile}%")
        logger.info(f"  Displacement Lookback: {c.displacement_lookback} bars")
        logger.info(f"  Max Opposing Wick Ratio: {c.max_opposing_wick_ratio}")

        logger.info(">>> ICT PARAMETERS - ORDER BLOCKS <<<")
        logger.info(f"  OB Lookback: {c.ob_lookback} bars")
        logger.info(f"  OB Min Body Percent: {c.ob_min_body_percent}%")
        logger.info(f"  OB Validation Bars: {c.ob_validation_bars}")

        logger.info(">>> ICT PARAMETERS - LIQUIDITY <<<")
        logger.info(f"  Liquidity Wick Ratio: {c.liquidity_wick_ratio}")
        logger.info(f"  Sweep Tolerance: ${c.sweep_tolerance_usd}")

        logger.info(">>> SESSION TIMES (NY Timezone) <<<")
        logger.info(f"  ORB Start: {c.orb_start_time}")
        logger.info(f"  ORB End: {c.orb_end_time}")
        logger.info(f"  Trade Start: {c.trade_start_time}")
        logger.info(f"  Trade End: {c.trade_end_time}")
        logger.info(f"  Asian Session: {c.asian_start} - {c.asian_end}")
        logger.info(f"  London Session: {c.london_start} - {c.london_end}")

        logger.info(">>> TRAILING STOP <<<")
        logger.info(f"  Use Trailing: {c.use_trailing}")
        logger.info(f"  Trailing ATR Period: {c.trailing_atr_period}")
        logger.info(f"  Trailing ATR Multiplier: {c.trailing_atr_multiplier}")

        logger.info(">>> TREND FILTER <<<")
        logger.info(f"  Min ADR for Trend: {c.min_adr_for_trend}")
        logger.info(f"  ADR Period: {c.adr_period}")

        logger.info(">>> TRADE LIMITS <<<")
        logger.info(f"  Max Daily Trades: {c.max_daily_trades}")
        logger.info(">>> CROSS-ASSET REGIME FILTER <<<")
        logger.info(f"  Enable Filter: {c.enable_cross_asset_filter}")
        logger.info(f"  Regime TF: {c.regime_timeframe} | Lookback: {c.regime_lookback_bars} | Return Bars: {c.regime_return_bars}")
        logger.info(f"  Thresholds: signal={c.regime_signal_threshold} strong={c.regime_strong_threshold}")
        logger.info(f"  Countertrend Block: {c.regime_block_countertrend} | Headwind Scale: {c.regime_reduce_size_in_headwind}")
        logger.info(f"  Risk Multipliers (tail/neutral/head): {c.regime_tailwind_risk_multiplier}/{c.regime_neutral_risk_multiplier}/{c.regime_headwind_risk_multiplier}")
        logger.info(f"  Symbols: DXY={c.regime_symbol_dxy} | YIELD={c.regime_symbol_yield} | RISKOFF={c.regime_symbol_riskoff} | RISKON={c.regime_symbol_riskon}")

        logger.info(">>> FRIDAY CLOSE <<<")
        logger.info(f"  Close Before Weekend: {c.close_before_weekend}")
        logger.info(f"  Friday Close Time: {c.friday_close_hour:02d}:{c.friday_close_minute:02d}")

        logger.info(">>> BIAS <<<")
        logger.info(f"  Min Bias Strength: {c.bias_min_strength} (0-100)")

        logger.info("=" * 80)

    def run(self, progress_callback=None) -> Dict[str, Any]:
        """
        Execute backtest with the given configuration.

        Args:
            progress_callback: Optional callback function(progress, message)

        Returns:
            Dictionary containing all results and metrics
        """
        self.status = "RUNNING"
        self.progress = 0.0

        # Log all configuration parameters for debugging
        self._log_config_parameters()

        try:
            # Fetch historical data with progress callback for chunked fetching
            self._update_progress(5, "Fetching historical data...", progress_callback)

            # Create a wrapper for data fetching progress (5% to 10%)
            def data_progress_callback(data_pct, message):
                # Map data fetching progress (0-100) to our range (5-10)
                overall_pct = 5 + (data_pct / 100.0) * 5
                self._update_progress(overall_pct, f"Data: {message}", progress_callback)

            df = self.data_provider.get_historical_data(
                self.config.symbol,
                self.config.timeframe,
                self.config.start_date,
                self.config.end_date,
                progress_callback=data_progress_callback,
                data_source=self.config.data_source,
                csv_files=self.config.csv_files,
            )

            if df is None or df.empty:
                raise ValueError("Failed to fetch historical data")

            # Validate data
            is_valid, msg = self.data_provider.validate_data_quality(df)
            if not is_valid:
                raise ValueError(f"Data validation failed: {msg}")

            # Get daily data for trend analysis
            daily_df = self.data_provider.get_daily_data(
                self.config.symbol,
                self.config.start_date - timedelta(days=30),
                self.config.end_date,
                data_source=self.config.data_source,
            )

            # Store reference for ML feature extraction (V2/V3 features need df)
            self._df = df

            # Data versioning: compute SHA-256 hash for reproducibility tracking
            # Uses pd.util.hash_pandas_object for deterministic hashing across
            # OS line endings, pandas versions, and float formatting differences
            import hashlib
            row_hashes = pd.util.hash_pandas_object(df, index=True)
            self._data_hash = hashlib.sha256(
                row_hashes.values.tobytes()
            ).hexdigest()
            logger.info(f"Data hash (SHA-256): {self._data_hash[:12]}...")

            self._update_progress(10, "Data loaded, starting simulation...", progress_callback)

            # Initialize cross-asset regime filter (optional)
            if self.config.enable_cross_asset_filter:
                self._update_progress(12, "Initializing cross-asset regime filter...", progress_callback)
                self._initialize_cross_asset_filter(df)

            # Initialize equity curve with starting balance
            self.equity_curve = [(self.config.start_date, self.config.initial_balance)]

            # Get trading days
            trading_days = self.data_provider.get_trading_days(df)
            total_days = len(trading_days)

            # Determine if strategy uses ORB-based flow
            self._strategy_uses_orb = (
                self.strategy is None or
                hasattr(self.strategy, 'calculate_bias')
            )

            # Process each trading day
            for day_idx, day in enumerate(trading_days):
                progress = 10 + (day_idx / total_days * 80)
                self._update_progress(
                    progress,
                    f"Processing day {day_idx + 1}/{total_days}: {day.date()}",
                    progress_callback
                )

                # Skip weekends
                if day.weekday() >= 5:
                    continue

                # Initialize day state (session levels, ADR trend check)
                self._initialize_day(day, df, daily_df)

                # For non-ORB strategies, call strategy.initialize_day()
                # to let the strategy compute its own bias/ATR/levels
                if not self._strategy_uses_orb:
                    day_start = self.ny_tz.localize(
                        datetime.combine(day.date(), time(0, 0))
                    )
                    intraday_up_to = df[df.index <= day_start]
                    guarded_intraday = FutureDataGuard(df, len(intraday_up_to))
                    self.day_context = self.strategy.initialize_day(
                        day, daily_df, guarded_intraday
                    )
                    self.day_state.bias = self.day_context.bias
                    self.day_state.bias_strength = self.day_context.bias_strength
                    if self.day_context.atr > 0:
                        self.day_state.atr = self.day_context.atr
                    # Non-ORB strategies always pass trending check
                    # (they handle their own trend filtering internally)
                    self.day_state.is_trending = True

                # Skip if not trending
                if not self.day_state.is_trending:
                    continue

                # Process intraday bars
                self._process_trading_day(day, df)

            # Calculate final metrics
            self._update_progress(95, "Calculating performance metrics...", progress_callback)

            # Close any open position at end
            if self.open_position:
                last_bar = df.iloc[-1]
                self._close_position(last_bar, "End of backtest")

            results = self._compile_results()

            self.status = "COMPLETED"
            self._update_progress(100, "Backtest completed", progress_callback)

            return results

        except Exception as e:
            self.status = "FAILED"
            self.error_message = str(e)
            logger.error(f"Backtest failed: {e}", exc_info=True)
            raise

        finally:
            self.data_provider.shutdown_mt5()

    def _update_progress(self, progress: float, message: str, callback=None):
        """Update progress and optionally call callback"""
        self.progress = progress
        logger.info(f"Backtest progress: {progress:.1f}% - {message}")
        if callback:
            callback(progress, message)

    def _initialize_cross_asset_filter(self, base_df: pd.DataFrame):
        """Build optional cross-asset regime filter."""
        try:
            self.cross_asset_filter = CrossAssetRegimeFilter(
                provider=self.data_provider,
                cfg=self.config,
                base_df=base_df,
                start_date=self.config.start_date,
                end_date=self.config.end_date,
                data_source=self.config.data_source,
            )
            if self.cross_asset_filter.enabled:
                logger.info(
                    "Cross-asset filter ready | coverage=%.1f%% | symbols=%s",
                    self.cross_asset_filter.summary().get("coverage_ratio", 0.0) * 100.0,
                    self.cross_asset_filter.summary().get("selected_symbols", {}),
                )
            else:
                reason = ""
                if self.config.data_source == "csv_only":
                    reason = " (csv_only mode — driver CSVs for DXY/US10Y/VIX not available)"
                logger.warning(
                    f"Cross-asset filter configured but inactive{reason}. "
                    f"ON/OFF comparison will be identical without driver data."
                )
        except Exception as e:
            logger.warning(f"Cross-asset filter initialization failed, continuing without it: {e}")
            self.cross_asset_filter = None

    def _initialize_day(self, day: datetime, df: pd.DataFrame, daily_df: pd.DataFrame):
        """Initialize state for a new trading day"""
        self.day_state = DayState(date=day)

        # Get previous day levels
        pd_high, pd_low = self.data_provider.get_previous_day_session(
            df, day,
            self.config.orb_start_time,
            self.config.trade_end_time
        )
        self.day_state.pd_high = pd_high
        self.day_state.pd_low = pd_low

        # Get Asian session levels
        asian_high, asian_low = self.data_provider.get_asian_session(
            df, day,
            self.config.asian_start,
            self.config.asian_end
        )
        self.day_state.asian_high = asian_high
        self.day_state.asian_low = asian_low

        # Get London session levels
        london_high, london_low = self.data_provider.get_london_session(
            df, day,
            self.config.london_start,
            self.config.london_end
        )
        self.day_state.london_high = london_high
        self.day_state.london_low = london_low

        # Check if market is trending (only use daily data up to current day)
        # Also compute daily ATR for ORB range normalization
        if daily_df is not None and not daily_df.empty:
            day_date = day.date() if hasattr(day, 'date') else day
            daily_up_to_today = daily_df[daily_df.index.date <= day_date]
            if not daily_up_to_today.empty:
                adr = self.data_provider.calculate_adr(daily_up_to_today, self.config.adr_period)
                if len(adr) > 0:
                    latest_adr = adr.iloc[-1]
                    if not pd.isna(latest_adr):
                        self.day_state.daily_atr = float(latest_adr)
                    self.day_state.is_trending = latest_adr >= self.config.min_adr_for_trend
                else:
                    self.day_state.is_trending = True
            else:
                self.day_state.is_trending = True
        else:
            self.day_state.is_trending = True

        # Reset daily counters
        self.day_state.daily_pnl = 0.0
        self.day_state.daily_trades = 0
        self.day_state.first_trade_won = False
        self.day_state.can_trade = self.day_state.is_trending

    def _process_trading_day(self, day: datetime, df: pd.DataFrame):
        """Process all bars for a trading day"""

        # For non-ORB strategies, use strategy's own trade times if available
        if not self._strategy_uses_orb and self.strategy is not None:
            strat_start = self.strategy.config.get(
                'trade_start_time', self.config.trade_start_time
            )
            strat_end = self.strategy.config.get(
                'trade_end_time', self.config.trade_end_time
            )
            trade_start = self._parse_time(strat_start)
            trade_end = self._parse_time(strat_end)
        else:
            trade_start = self._parse_time(self.config.trade_start_time)
            trade_end = self._parse_time(self.config.trade_end_time)

        orb_end = self._parse_time(self.config.orb_end_time)

        # Friday close time (for closing before weekend)
        is_friday = day.weekday() == 4
        friday_close_time = time(self.config.friday_close_hour, self.config.friday_close_minute)

        # Get day's data
        day_start = self.ny_tz.localize(datetime.combine(day.date(), time(0, 0)))
        day_end = self.ny_tz.localize(datetime.combine(day.date(), time(23, 59)))
        day_df = df[(df.index >= day_start) & (df.index <= day_end)]

        # Find where today starts in the full df for global position tracking.
        # Non-ORB strategies need this for history slicing; ORB strategies
        # need it for correct ML feature extraction (global df index).
        if len(day_df) > 0:
            day_first_ts = day_df.index[0]
            day_offset_in_df = df.index.get_loc(day_first_ts)
            if isinstance(day_offset_in_df, slice):
                day_offset_in_df = day_offset_in_df.start
        else:
            day_offset_in_df = 0

        orb_calculated = False
        friday_closed = False

        for i in range(len(day_df)):
            bar = day_df.iloc[i]
            bar_time = bar.name

            # Get bar's time component
            bar_time_only = bar_time.time()

            # Friday close logic - close all positions before weekend
            if (is_friday and self.config.close_before_weekend and
                bar_time_only >= friday_close_time and not friday_closed):
                if self.open_position:
                    self._close_position(bar, "Friday Close (Weekend)")
                    logger.info(f"Position closed before weekend at {bar_time}")
                friday_closed = True
                # Don't open new trades after Friday close time
                continue

            # ORB calculation block - only for ORB-based strategies
            if self._strategy_uses_orb:
                if not orb_calculated and bar_time_only >= orb_end:
                    orb_high, orb_low = self.data_provider.get_orb_levels(
                        df, day.date(),
                        self.config.orb_start_time,
                        self.config.orb_end_time
                    )
                    self.day_state.orb_high = orb_high
                    self.day_state.orb_low = orb_low
                    orb_calculated = True

                    # Calculate bias with ATR for strength scoring
                    self._calculate_bias(bar, day_df.iloc[:i+1])
                    # If a strategy is attached, let it (re)calculate bias
                    if self.strategy is not None:
                        self.day_context = self._build_day_context()
                        self.day_context = self.strategy.calculate_bias(
                            self.day_context, bar['close']
                        )
                        self.day_state.bias = self.day_context.bias
                        self.day_state.bias_strength = self.day_context.bias_strength

            # Skip if outside trading hours
            if bar_time_only < trade_start or bar_time_only > trade_end:
                continue

            # On Friday, don't trade after close time
            if is_friday and self.config.close_before_weekend and bar_time_only >= friday_close_time:
                continue

            # Build the dataframe slices for strategies.
            # bars_up_to_now: includes current bar (for position management,
            #   SL/TP checks, and trailing stop updates).
            # signal_bars: excludes current bar (for signal detection —
            #   prevents lookahead by ensuring the strategy only sees
            #   completed bars; entry executes at the *next* bar's open).
            if self._strategy_uses_orb:
                bars_up_to_now = day_df.iloc[:i+1]
                signal_bars = day_df.iloc[:i]
                self._current_global_pos = day_offset_in_df + i + 1  # Global index for ML feature extraction
            else:
                # Use integer slicing on full df for performance
                global_pos = day_offset_in_df + i + 1
                bars_up_to_now = df.iloc[:global_pos]
                signal_bars = df.iloc[:global_pos - 1]
                self._current_global_pos = global_pos  # For ML feature extraction

            # Manage open position (needs current bar for SL/TP/trailing)
            if self.open_position:
                self._manage_position(bar, bars_up_to_now)
                continue

            # Check if we can trade
            if not self._can_open_trade():
                continue

            # ORB readiness check - only for ORB-based strategies
            if self._strategy_uses_orb:
                if self.day_state.orb_high is None or self.day_state.orb_low is None:
                    continue
                orb_range = self.day_state.orb_high - self.day_state.orb_low
                if orb_range < 0.50:
                    continue

            # Look for trade setup using COMPLETED bars only (no lookahead).
            # Signal evaluates bar i-1's close; if triggered, entry is at
            # bar i's open (the current bar) via _execute_trade().
            if self.strategy is not None:
                if len(signal_bars) < 2:
                    continue  # Need at least some history for signal
                # Delegate to strategy: rebuild day_context with latest
                # levels in case they have been updated during the day.
                self.day_context = self._build_day_context()
                # Dynamic bias: recalculate on every bar using the last
                # completed bar's close.  The initial bias at 09:45 is often
                # "neutral" because price hasn't broken ORB yet; updating it
                # here captures breakouts that happen later in the session.
                if self._strategy_uses_orb and orb_calculated:
                    signal_price = signal_bars.iloc[-1]['close'] if len(signal_bars) > 0 else bar['close']
                    self.day_context = self.strategy.calculate_bias(
                        self.day_context, signal_price
                    )
                    self.day_state.bias = self.day_context.bias
                    self.day_state.bias_strength = self.day_context.bias_strength
                try:
                    self.day_context.levels['execution_open'] = float(bar['open'])
                except Exception:
                    pass
                signal_bar = signal_bars.iloc[-1]  # Last completed bar
                # Wrap with FutureDataGuard to prevent lookahead unless strategy
                # explicitly opts in to known-ahead event calendars.
                allow_event_lookahead = bool(
                    getattr(self.strategy, "config", {}).get("allow_event_lookahead", False)
                )
                if self._strategy_uses_orb:
                    guarded_df = FutureDataGuard(day_df, i)
                elif allow_event_lookahead:
                    guarded_df = df
                else:
                    guarded_df = FutureDataGuard(df, self._current_global_pos - 1)
                trade_setup = self.strategy.find_setup(
                    signal_bar, guarded_df, self.day_context, i
                )
                if trade_setup:
                    # Convert TradeSetup dataclass to the dict that
                    # _execute_trade() expects.
                    setup = {
                        'direction': trade_setup.direction,
                        'sl': trade_setup.stop_loss,
                        'tp': trade_setup.take_profit,
                        'setup_type': trade_setup.setup_type,
                        'fvg': trade_setup.metadata.get('fvg'),
                        'ob': trade_setup.metadata.get('ob'),
                        'bias_strength': int(trade_setup.confidence),
                        'metadata': trade_setup.metadata,
                    }
                    if self.cross_asset_filter is not None and self.cross_asset_filter.enabled:
                        allowed, risk_mul, decision, reason = self.cross_asset_filter.allow_trade(
                            setup['direction'], bar.name
                        )
                        if not allowed:
                            continue
                        setup['risk_multiplier'] = risk_mul
                        setup_meta = setup.setdefault('metadata', {})
                        setup_meta['cross_asset_reason'] = reason
                        setup_meta['cross_asset_risk_multiplier'] = float(risk_mul)
                        setup_meta['cross_asset_decision'] = self.cross_asset_filter.decision_to_metadata(decision)
                    self._execute_trade(setup, bar)
            else:
                # Legacy code path (no strategy attached) — also uses signal_bars
                setup = self._find_trade_setup(signal_bars if len(signal_bars) >= 2 else day_df.iloc[:i+1])
                if setup:
                    if self.cross_asset_filter is not None and self.cross_asset_filter.enabled:
                        allowed, risk_mul, decision, reason = self.cross_asset_filter.allow_trade(
                            setup['direction'], bar.name
                        )
                        if not allowed:
                            continue
                        setup['risk_multiplier'] = risk_mul
                        setup_meta = setup.setdefault('metadata', {})
                        setup_meta['cross_asset_reason'] = reason
                        setup_meta['cross_asset_risk_multiplier'] = float(risk_mul)
                        setup_meta['cross_asset_decision'] = self.cross_asset_filter.decision_to_metadata(decision)
                    self._execute_trade(setup, bar)

    def _parse_time(self, time_str: str) -> time:
        """Parse time string HH:MM to time object"""
        hours, minutes = map(int, time_str.split(':'))
        return time(hours, minutes)

    def _get_simulated_spread(self, bar_time: datetime) -> float:
        """
        Get time-of-day based spread simulation.
        Returns the full spread (entry + exit combined).
        """
        base_spread = (self.config.max_spread_usd or self.instrument.max_spread) / 2
        bar_time_only = bar_time.time() if hasattr(bar_time, 'time') else bar_time
        is_friday = bar_time.weekday() == 4 if hasattr(bar_time, 'weekday') else False

        # Session open (9:30-9:35 NY): wide spreads during ORB breakout
        if time(9, 30) <= bar_time_only < time(9, 35):
            multiplier = 2.5
        # First 15 min (9:35-9:45 NY)
        elif time(9, 35) <= bar_time_only < time(9, 45):
            multiplier = 1.8
        # NY morning (9:45-12:00): normal liquidity
        elif time(9, 45) <= bar_time_only < time(12, 0):
            multiplier = 1.0
        # NY afternoon (12:00-15:00)
        elif time(12, 0) <= bar_time_only < time(15, 0):
            multiplier = 1.2
        # End of day (15:00-16:00)
        elif time(15, 0) <= bar_time_only < time(16, 0):
            multiplier = 1.5
        # Pre-market / off-hours
        else:
            multiplier = 2.0

        # Friday afternoon: weekend liquidity drain
        if is_friday and bar_time_only >= time(14, 0):
            multiplier = max(multiplier, 1.8)

        # Add random component (±15%)
        spread = base_spread * multiplier * self.rng.uniform(0.85, 1.15)
        return spread

    def _calculate_bias_strength(self, current_price: float, atr: float) -> Tuple[str, int]:
        """
        Calculate bias direction and strength score (0-100).
        Matches the live bot's calculate_bias_strength logic.

        Returns:
            Tuple of (bias_direction, strength_score)
        """
        pd_high = self.day_state.pd_high
        pd_low = self.day_state.pd_low
        asian_high = self.day_state.asian_high
        asian_low = self.day_state.asian_low
        orb_high = self.day_state.orb_high
        orb_low = self.day_state.orb_low

        if atr <= 0:
            atr = 1.0  # Prevent division by zero

        bullish_score = 0
        bearish_score = 0

        # ORB Bias (30 points max)
        if orb_high is not None and orb_low is not None:
            if current_price > orb_high:
                extension = (current_price - orb_high) / atr
                bullish_score += min(30, int(15 + extension * 15))
            elif current_price < orb_low:
                extension = (orb_low - current_price) / atr
                bearish_score += min(30, int(15 + extension * 15))

        # Asian Session Bias (25 points max)
        if asian_high is not None and asian_low is not None:
            if current_price > asian_high:
                extension = (current_price - asian_high) / atr
                bullish_score += min(25, int(12 + extension * 13))
            elif current_price < asian_low:
                extension = (asian_low - current_price) / atr
                bearish_score += min(25, int(12 + extension * 13))

        # Previous Day Bias (25 points max)
        if pd_high is not None and pd_low is not None:
            if current_price > pd_high:
                extension = (current_price - pd_high) / atr
                bullish_score += min(25, int(12 + extension * 13))
            elif current_price < pd_low:
                extension = (pd_low - current_price) / atr
                bearish_score += min(25, int(12 + extension * 13))

        # London session confluence (20 points max)
        london_high = self.day_state.london_high
        london_low = self.day_state.london_low
        if london_high is not None and london_low is not None:
            london_mid = (london_high + london_low) / 2
            if current_price > london_high:
                bullish_score += 15
            elif current_price > london_mid:
                bullish_score += 8
            elif current_price < london_low:
                bearish_score += 15
            elif current_price < london_mid:
                bearish_score += 8

        # Determine direction and final score
        if bullish_score > bearish_score:
            return "bullish", min(100, bullish_score)
        elif bearish_score > bullish_score:
            return "bearish", min(100, bearish_score)
        else:
            return "neutral", 0

    def _calculate_bias(self, bar, df: pd.DataFrame = None):
        """Calculate market bias and strength score based on session levels"""
        current_price = bar['close']

        # Calculate ATR for bias strength scoring and slippage
        atr = 1.0
        if df is not None and len(df) >= 14:
            atr_series = self.data_provider.calculate_atr(df, 14)
            if len(atr_series) > 0 and not pd.isna(atr_series.iloc[-1]):
                atr = atr_series.iloc[-1]
        self.day_state.atr = atr

        # Use new bias strength calculation
        bias, strength = self._calculate_bias_strength(current_price, atr)
        self.day_state.bias = bias
        self.day_state.bias_strength = strength

    def _can_open_trade(self) -> bool:
        """Check if we can open a new trade"""
        # Daily loss limit
        if self.day_state.daily_pnl <= self.config.max_daily_loss_usd:
            return False

        # ORB discipline: if first trade is green, stop for the day.
        if self._strategy_uses_orb and getattr(self.config, "stop_after_first_win", True):
            if self.day_state.first_trade_won:
                return False

        # Max trades per day (configurable, no revenge trading logic)
        if self.day_state.daily_trades >= self.config.max_daily_trades:
            return False

        return True

    def _build_day_context(self):
        """
        Build a DayContext from the engine's current DayState.

        Used to pass session-level data to the attached BacktestStrategy so
        it can compute bias and detect setups.
        """
        from .strategies.base import DayContext
        ctx = DayContext(
            date=self.day_state.date,
            bias=self.day_state.bias,
            bias_strength=self.day_state.bias_strength,
            atr=self.day_state.atr,
        )
        ctx.levels = {
            'orb_high': self.day_state.orb_high,
            'orb_low': self.day_state.orb_low,
            'asian_high': self.day_state.asian_high,
            'asian_low': self.day_state.asian_low,
            'pd_high': self.day_state.pd_high,
            'pd_low': self.day_state.pd_low,
            'london_high': self.day_state.london_high,
            'london_low': self.day_state.london_low,
            'daily_atr': self.day_state.daily_atr,
        }
        return ctx

    def _find_trade_setup(self, df: pd.DataFrame) -> Optional[Dict[str, Any]]:
        """
        Look for trade setup based on ICT concepts.

        Signal detection uses previous bar (df.iloc[-2]) to confirm pattern.
        Entry will happen at CURRENT bar's open (passed to _execute_trade)
        to eliminate look-ahead bias.
        """
        if len(df) < 10:
            return None

        bias = self.day_state.bias
        bias_strength = self.day_state.bias_strength

        # Check bias requirements
        if bias == "neutral":
            return None

        # Require minimum bias strength (matches live bot)
        if bias_strength < self.config.bias_min_strength:
            return None

        # Use previous bar's close for signal detection (pattern confirmed)
        signal_bar = df.iloc[-2]
        signal_close = signal_bar['close']

        # Bullish setup
        if bias == "bullish" and signal_close > self.day_state.orb_high:
            fvg = self._find_fvg(df, "bullish")
            if fvg:
                ob = self._find_order_block(df, "bullish")
                sl = ob['low'] if ob else fvg['bottom']

                # Don't set entry here - will use current bar's open in _execute_trade
                return {
                    'direction': 'BUY',
                    'sl': sl,
                    'setup_type': 'Bullish FVG + ORB Breakout',
                    'fvg': fvg,
                    'ob': ob,
                    'bias_strength': bias_strength
                }

        # Bearish setup
        elif bias == "bearish" and signal_close < self.day_state.orb_low:
            fvg = self._find_fvg(df, "bearish")
            if fvg:
                ob = self._find_order_block(df, "bearish")
                sl = ob['high'] if ob else fvg['top']

                return {
                    'direction': 'SELL',
                    'sl': sl,
                    'setup_type': 'Bearish FVG + ORB Breakout',
                    'fvg': fvg,
                    'ob': ob,
                    'bias_strength': bias_strength
                }

        return None

    def _find_fvg(self, df: pd.DataFrame, direction: str) -> Optional[Dict[str, Any]]:
        """
        Find Fair Value Gap pattern by scanning through the lookback window.

        Scans from most recent to oldest, returns the first (most recent) valid FVG
        that hasn't been fully filled by subsequent price action.
        """
        lookback = min(self.config.fvg_lookback, len(df) - 3)
        if lookback < 3:
            return None

        current_price = df.iloc[-1]['close']

        # Scan from most recent to oldest (offset 2 = most recent possible FVG)
        for offset in range(2, lookback):
            c1 = df.iloc[-offset - 2]  # First candle
            c2 = df.iloc[-offset - 1]  # Middle candle (displacement)
            c3 = df.iloc[-offset]      # Third candle

            if direction == "bullish":
                gap = c3['low'] - c1['high']
                if gap > self.config.min_fvg_gap:
                    fvg_top = c3['low']
                    fvg_bottom = c1['high']

                    # Check displacement on the middle candle
                    sub_df = df.iloc[:len(df) - offset]
                    if len(sub_df) < self.config.displacement_lookback + 3:
                        continue
                    if not self._has_displacement(sub_df, c2, "bullish"):
                        continue

                    # Check FVG not fully filled (price hasn't gone below fvg_bottom since)
                    bars_after = df.iloc[-offset:]
                    if bars_after['low'].min() < fvg_bottom:
                        continue  # FVG was filled, skip

                    return {
                        'type': 'bullish_fvg',
                        'top': fvg_top,
                        'bottom': fvg_bottom,
                        'size': gap,
                        'time': c2.name
                    }
            else:
                gap = c1['low'] - c3['high']
                if gap > self.config.min_fvg_gap:
                    fvg_top = c1['low']
                    fvg_bottom = c3['high']

                    # Check displacement on the middle candle
                    sub_df = df.iloc[:len(df) - offset]
                    if len(sub_df) < self.config.displacement_lookback + 3:
                        continue
                    if not self._has_displacement(sub_df, c2, "bearish"):
                        continue

                    # Check FVG not fully filled (price hasn't gone above fvg_top since)
                    bars_after = df.iloc[-offset:]
                    if bars_after['high'].max() > fvg_top:
                        continue  # FVG was filled, skip

                    return {
                        'type': 'bearish_fvg',
                        'top': fvg_top,
                        'bottom': fvg_bottom,
                        'size': gap,
                        'time': c2.name
                    }

        return None

    def _has_displacement(self, df: pd.DataFrame, candle, direction: str) -> bool:
        """Check if candle shows strong displacement"""
        lookback = self.config.displacement_lookback
        if len(df) < lookback + 3:
            return False

        recent = df.iloc[-lookback-3:-3]
        recent_bodies = (recent['close'] - recent['open']).abs()
        threshold = recent_bodies.quantile(self.config.displacement_percentile / 100.0)

        if direction == "bullish":
            body = candle['close'] - candle['open']
            if body <= 0:
                return False
            opposing_wick = candle['high'] - candle['close']
        else:
            body = candle['open'] - candle['close']
            if body <= 0:
                return False
            opposing_wick = candle['close'] - candle['low']

        strong_body = body >= threshold
        small_wick = opposing_wick < (body * self.config.max_opposing_wick_ratio)

        return strong_body and small_wick

    def _find_order_block(self, df: pd.DataFrame, direction: str) -> Optional[Dict[str, Any]]:
        """
        Find Order Block pattern matching live bot logic exactly.

        Bullish OB = last BEARISH (down) candle before bullish impulse
        Bearish OB = last BULLISH (up) candle before bearish impulse

        Validation (matching live bot):
        - Bullish: last validation bar close > candle.high AND all validation lows > candle.low
        - Bearish: last validation bar close < candle.low AND all validation highs < candle.high
        """
        lookback = min(self.config.ob_lookback, len(df) - 2)
        if lookback < 5:
            return None

        scan_range = df.iloc[-lookback:-2]
        validation_bars = self.config.ob_validation_bars

        for i in range(len(scan_range) - validation_bars - 1, -1, -1):
            candle = scan_range.iloc[i]
            candle_range = candle['high'] - candle['low']

            if candle_range < 0.10:
                continue

            validation_candles = scan_range.iloc[i+1:i+1+validation_bars]
            if len(validation_candles) < validation_bars:
                continue

            if direction == "bullish":
                # Bullish OB: Look for BEARISH candle (open > close)
                is_bearish_candle = candle['open'] > candle['close']
                if not is_bearish_candle:
                    continue

                body = candle['open'] - candle['close']
                body_percent = (body / candle_range) * 100
                if body_percent < self.config.ob_min_body_percent:
                    continue

                # Validation: LAST bar close > candle.high AND all lows > candle.low
                impulse_up = (
                    validation_candles['close'].iloc[-1] > candle['high'] and
                    validation_candles['low'].min() > candle['low']
                )

                # Check not violated by recent price action
                not_violated = df.iloc[-10:]['low'].min() > candle['low']

                if impulse_up and not_violated:
                    return {
                        'type': 'bullish_ob',
                        'high': candle['high'],
                        'low': candle['low'],
                        'body_pct': body_percent,
                        'time': candle.name
                    }

            else:  # bearish
                # Bearish OB: Look for BULLISH candle (close > open)
                is_bullish_candle = candle['close'] > candle['open']
                if not is_bullish_candle:
                    continue

                body = candle['close'] - candle['open']
                body_percent = (body / candle_range) * 100
                if body_percent < self.config.ob_min_body_percent:
                    continue

                # Validation: LAST bar close < candle.low AND all highs < candle.high
                impulse_down = (
                    validation_candles['close'].iloc[-1] < candle['low'] and
                    validation_candles['high'].max() < candle['high']
                )

                # Check not violated by recent price action
                not_violated = df.iloc[-10:]['high'].max() < candle['high']

                if impulse_down and not_violated:
                    return {
                        'type': 'bearish_ob',
                        'high': candle['high'],
                        'low': candle['low'],
                        'body_pct': body_percent,
                        'time': candle.name
                    }

        return None

    def _execute_trade(self, setup: Dict[str, Any], bar):
        """
        Execute a trade based on setup with realistic simulation.

        Entry is at CURRENT bar's open (eliminating look-ahead bias).
        Applies variable spread, ATR-based slippage, and tracks all costs.
        """
        direction = setup['direction']
        sl = setup['sl']

        # Entry at current bar's open (signal detected on previous bar)
        base_entry = bar['open']
        execution_mode = str(getattr(self.config, "execution_mode", "bar")).lower()
        current_atr = self.day_state.atr if self.day_state.atr > 0 else 1.0
        spread_cost = 0.0
        slippage_cost = 0.0
        execution_impact_cost = 0.0
        fill_ratio = 1.0
        fill_probability = 1.0
        micro_diagnostics: Dict[str, float] = {}

        if execution_mode == "microstructure" and self.micro_simulator is not None:
            micro_decision = self.micro_simulator.simulate_entry(
                bar=bar,
                direction=direction,
                base_price=float(base_entry),
                atr=float(current_atr),
            )
            if not micro_decision.filled:
                logger.debug(
                    "Trade skipped: microstructure fill rejected (%s, p=%.3f)",
                    micro_decision.reason,
                    micro_decision.fill_probability,
                )
                return

            entry = micro_decision.adjusted_price
            spread_cost = micro_decision.spread_cost
            slippage_cost = micro_decision.slippage_cost
            execution_impact_cost = micro_decision.adverse_selection_cost
            fill_ratio = micro_decision.fill_ratio
            fill_probability = micro_decision.fill_probability
            micro_diagnostics = micro_decision.diagnostics
        else:
            # === Spread Simulation ===
            if self.config.simulate_spread:
                if self.config.use_variable_spread:
                    half_spread = self._get_simulated_spread(bar.name)
                else:
                    half_spread = self.config.max_spread_usd / 2

                # Check spread filter before entering
                full_spread = half_spread * 2
                if full_spread > self.config.max_spread_usd:
                    logger.debug(f"Trade skipped: spread ${full_spread:.2f} > max ${self.config.max_spread_usd:.2f}")
                    return  # Skip this trade due to spread

                if direction == 'BUY':
                    base_entry += half_spread  # Buy at ask (higher)
                else:
                    base_entry -= half_spread  # Sell at bid (lower)
                spread_cost = half_spread  # Entry cost only, exit cost added at close

            entry = base_entry

            # === ATR-based Slippage Simulation ===
            if self.config.simulate_slippage:
                # ATR-based slippage with randomness
                base_slippage = current_atr * self.config.slippage_atr_factor
                slippage = np.clip(
                    base_slippage * self.rng.uniform(0.5, 2.0),
                    self.config.min_slippage_usd,
                    self.config.max_slippage_usd
                )

                if direction == 'BUY':
                    entry += slippage  # Worse fill for buys
                else:
                    entry -= slippage  # Worse fill for sells
                slippage_cost = slippage

        # Validate and adjust stop loss
        sl_distance = abs(entry - sl)
        setup_meta = setup.get('metadata') or {}
        skip_out_of_bounds_sl = bool(setup_meta.get('skip_out_of_bounds_sl', False))
        if skip_out_of_bounds_sl:
            if sl_distance < self.config.min_sl_usd or sl_distance > self.config.max_sl_usd:
                logger.debug(
                    f"Trade skipped: structural SL ${sl_distance:.2f} outside "
                    f"[${self.config.min_sl_usd:.2f}, ${self.config.max_sl_usd:.2f}]"
                )
                return
        else:
            sl_distance = max(self.config.min_sl_usd, min(self.config.max_sl_usd, sl_distance))

        if direction == 'BUY':
            sl = entry - sl_distance
        else:
            sl = entry + sl_distance

        # Calculate take profit
        # If strategy provided a TP, use it (with minimum 2:1 R:R safety)
        # None or 0.0 means "let the engine calculate from R:R"
        strategy_tp = setup.get('tp')
        tp_is_valid = (
            strategy_tp is not None
            and strategy_tp > 0
            and sl_distance > 0
            # TP must make directional sense
            and (direction == 'BUY' and strategy_tp > entry
                 or direction == 'SELL' and strategy_tp < entry)
        )
        if tp_is_valid:
            tp_distance_from_strategy = abs(strategy_tp - entry)
            rr_from_strategy = tp_distance_from_strategy / sl_distance
            allow_sub2_rr = bool(setup_meta.get('allow_sub2_rr', False))
            # Enforce minimum 2:1 R:R on Gold
            if rr_from_strategy >= 2.0 or allow_sub2_rr:
                tp = strategy_tp
            else:
                tp_distance = sl_distance * 2.0
                tp = entry + tp_distance if direction == 'BUY' else entry - tp_distance
        else:
            # Default engine logic: tight SL gets 3:1, normal gets 2:1
            if sl_distance < self.config.gold_rr_threshold:
                rr_ratio = 3.0
            else:
                rr_ratio = 2.0
            tp_distance = sl_distance * rr_ratio
            if direction == 'BUY':
                tp = entry + tp_distance
            else:
                tp = entry - tp_distance

        # Compute actual R:R from final entry/tp/sl (used by ML feature extraction)
        rr_ratio = abs(tp - entry) / sl_distance if sl_distance > 0 else 2.0

        # Calculate position size with contract size
        # P&L = price_diff * lot_size * contract_size
        # Risk = sl_distance * lot_size * contract_size
        # So: lot_size = risk_amount / (sl_distance * contract_size)
        risk_multiplier = float(setup.get('risk_multiplier', 1.0))
        risk_multiplier = max(0.05, min(risk_multiplier, 2.0))
        requested_risk_amount = self.balance * (self.config.risk_percent / 100.0) * risk_multiplier
        raw_lot_size = requested_risk_amount / (sl_distance * self.config.contract_size)
        raw_lot_size *= max(0.05, min(fill_ratio, 1.0))
        lot_size = round(raw_lot_size, 2)
        effective_risk_amount = lot_size * sl_distance * self.config.contract_size

        # Enforce lot size limits from instrument spec
        if lot_size < self.instrument.min_lot:
            logger.debug(f"Trade skipped: lot size {lot_size:.4f} below minimum {self.instrument.min_lot}")
            return
        lot_size = min(lot_size, self.instrument.max_lot)

        # === Commission (half on entry, half on exit) ===
        # Entry commission: deducted from balance immediately here
        # Exit commission: will be deducted at close via net_pnl calculation in _close_position()
        # Total per trade: commission_per_lot * lot_size (split 50/50 between entry and exit)
        entry_commission = (self.config.commission_per_lot * lot_size) / 2
        self.balance -= entry_commission

        # Create position with cost tracking
        fvg = setup.get('fvg')
        ob = setup.get('ob')

        self.open_position = Position(
            direction=direction,
            entry_time=bar.name,
            entry_price=entry,
            stop_loss=sl,
            initial_stop_loss=sl,  # Freeze initial SL for R-multiple calc
            take_profit=tp,
            lot_size=lot_size,
            setup_type=setup['setup_type'],
            bias=self.day_state.bias,
            orb_high=self.day_state.orb_high,
            orb_low=self.day_state.orb_low,
            asian_high=self.day_state.asian_high,
            asian_low=self.day_state.asian_low,
            pd_high=self.day_state.pd_high,
            pd_low=self.day_state.pd_low,
            fvg_size=fvg['size'] if fvg else None,
            fvg_top=fvg['top'] if fvg else None,
            fvg_bottom=fvg['bottom'] if fvg else None,
            ob_high=ob['high'] if ob else None,
            ob_low=ob['low'] if ob else None,
            # Cost tracking
            spread_cost=spread_cost,
            slippage_cost=slippage_cost + execution_impact_cost,
            commission_cost=entry_commission,
            swap_cost=0.0,
            last_swap_date=bar.name.date() if hasattr(bar.name, 'date') else None
        )

        # === Strategy Metadata (for trade diagnostics) ===
        strategy_meta = {
            'setup_type': setup['setup_type'],
            'bias': self.day_state.bias,
            'bias_strength': self.day_state.bias_strength,
            'atr': round(self.day_state.atr, 4),
            'base_entry': round(bar['open'], 2),
            'adjusted_entry': round(entry, 2),
            'sl_distance': round(sl_distance, 2),
            'rr_ratio': round(rr_ratio, 2),
            'risk_amount': round(effective_risk_amount, 2),
            'risk_amount_requested': round(requested_risk_amount, 2),
            'risk_multiplier': round(risk_multiplier, 4),
            'spread_cost': round(spread_cost, 4),
            'slippage_cost': round(slippage_cost, 4),
            'execution_mode': execution_mode,
        }
        if execution_mode == "microstructure":
            entry_impact_usd = execution_impact_cost * lot_size * self.config.contract_size
            strategy_meta.update({
                'micro_fill_probability': round(fill_probability, 4),
                'micro_fill_ratio': round(fill_ratio, 4),
                'micro_latency_bars': int(getattr(self.config, "micro_latency_bars", 0) or 0),
                'micro_entry_impact': round(execution_impact_cost, 6),
                'micro_entry_impact_usd': round(entry_impact_usd, 2),
            })
            for key, value in micro_diagnostics.items():
                strategy_meta[f"micro_{key}"] = round(value, 6)
        # Include strategy-specific metadata from TradeSetup
        raw_meta = setup.get('metadata') or {}
        for k, v in raw_meta.items():
            if isinstance(v, (int, float, str, bool)):
                strategy_meta[k] = round(v, 4) if isinstance(v, float) else v
        self.open_position.strategy_metadata = strategy_meta

        # === ML Feature Extraction (always, for training data) ===
        try:
            # Pass df slice for V2 features (volatility_regime, ADX) and
            # recent_results for V2 consecutive_results feature
            df_slice = None
            if hasattr(self, '_df') and hasattr(self, '_current_global_pos'):
                df_slice = self._df.iloc[:self._current_global_pos]

            ml_feat_vec = FeatureExtractor.extract(
                day_state=self.day_state,
                setup=setup,
                bar=bar,
                config=self.config,
                balance=self.balance,
                spread=spread_cost * 2,  # full spread
                entry_price=entry,
                sl_distance=sl_distance,
                rr_ratio=rr_ratio,
                df=df_slice,
                recent_results=self._recent_trade_results,
            )
            self.open_position.ml_features = FeatureExtractor.to_dict(ml_feat_vec)
        except Exception as e:
            logger.warning(f"ML feature extraction failed: {e}")
            self.open_position.ml_features = None

        logger.info(
            f"TRADE #{self.trade_counter + 1} ENTRY: {direction} {self.config.symbol} @ {entry:.2f} | "
            f"SL: {sl:.2f} TP: {tp:.2f} ({rr_ratio:.1f}:1 R:R) | "
            f"Lots: {lot_size} Risk: ${effective_risk_amount:.0f} | "
            f"Setup: {setup['setup_type']} | "
            f"Costs: spread=${spread_cost:.3f} slip=${slippage_cost:.3f} impact=${execution_impact_cost:.3f} comm=${entry_commission:.2f}"
        )
        # Log strategy-specific signals
        if raw_meta:
            meta_str = ", ".join(f"{k}={v:.4f}" if isinstance(v, float) else f"{k}={v}"
                                 for k, v in raw_meta.items()
                                 if isinstance(v, (int, float, str, bool)))
            if meta_str:
                logger.info(f"  Strategy signals: {meta_str}")

    def _manage_position(self, bar, df: pd.DataFrame):
        """
        Manage open position - check SL/TP, trailing, and charge overnight swap.

        When both SL and TP could be hit in the same bar, we use a conservative
        approach: if the bar's open is closer to one level, assume that hit first.
        Otherwise, assume stop loss hit first (worst case for backtesting accuracy).
        """
        pos = self.open_position
        is_long = pos.direction == "BUY"
        strategy_meta = pos.strategy_metadata or {}
        disable_sl_tp = bool(strategy_meta.get("disable_sl_tp", False))
        disable_trailing = bool(strategy_meta.get("disable_trailing", False))

        high = bar['high']
        low = bar['low']
        close = bar['close']
        open_price = bar['open']

        # === Charge overnight swap ===
        if self.config.simulate_swap:
            self._charge_overnight_swap(bar)

        # === MFE/MAE tracking (in R-multiples based on INITIAL risk) ===
        initial_risk = abs(pos.entry_price - pos.initial_stop_loss)
        if initial_risk > 0:
            if is_long:
                favorable = (high - pos.entry_price) / initial_risk
                adverse = (pos.entry_price - low) / initial_risk
            else:
                favorable = (pos.entry_price - low) / initial_risk
                adverse = (high - pos.entry_price) / initial_risk
            pos.max_favorable_excursion = max(pos.max_favorable_excursion, favorable)
            pos.max_adverse_excursion = max(pos.max_adverse_excursion, adverse)

        if not disable_sl_tp:
            # Determine which levels were hit
            if is_long:
                sl_hit = low <= pos.stop_loss
                tp_hit = high >= pos.take_profit
            else:
                sl_hit = high >= pos.stop_loss
                tp_hit = low <= pos.take_profit

            # Handle case when both SL and TP are hit in same bar
            # Uses OHLC path reconstruction (industry standard: Backtrader/Zipline)
            if sl_hit and tp_hit:
                exit_price, exit_reason = self._resolve_same_bar_sl_tp(
                    bar, pos, is_long
                )
                self._close_position(bar, exit_reason, exit_price)
                return

            # Check stop loss hit
            if sl_hit:
                self._close_position(bar, "Stop Loss", pos.stop_loss)
                return

            # Check take profit hit
            if tp_hit:
                self._close_position(bar, "Take Profit", pos.take_profit)
                return

        # Trailing stop logic
        if self.config.use_trailing and not disable_trailing:
            self._update_trailing_stop(bar, df)

        # Strategy early exit logic (e.g., indicator reversal)
        if self.strategy is not None and not self._strategy_uses_orb:
            exit_reason = self.strategy.should_close_early(
                bar, df, pos, self.day_context
            )
            if exit_reason:
                self._close_position(bar, exit_reason, close)

    def _resolve_same_bar_sl_tp(
        self, bar, pos, is_long: bool
    ) -> Tuple[float, str]:
        """
        Resolve which level (SL or TP) was hit first when both are breached
        in the same bar, using OHLC path reconstruction.

        Standard technique (Backtrader/Zipline):
        - Bullish bar (close >= open): path is Open -> Low -> High -> Close
        - Bearish bar (close < open):  path is Open -> High -> Low -> Close

        Walk the inferred path and check which level is reached first.

        Returns:
            Tuple of (exit_price, exit_reason)
        """
        o = bar['open']
        h = bar['high']
        l = bar['low']
        c = bar['close']
        is_bullish = c >= o  # Doji treated as bullish (O->L->H->C)

        if is_bullish:
            # Bullish bar path: Open -> Low -> High -> Close
            # Check Low first, then High
            if is_long:
                # LONG: SL hit if Low <= SL, TP hit if High >= TP
                if l <= pos.stop_loss:
                    return pos.stop_loss, "Stop Loss"
                if h >= pos.take_profit:
                    return pos.take_profit, "Take Profit"
            else:
                # SHORT: TP hit if Low <= TP, SL hit if High >= SL
                if l <= pos.take_profit:
                    return pos.take_profit, "Take Profit"
                if h >= pos.stop_loss:
                    return pos.stop_loss, "Stop Loss"
        else:
            # Bearish bar path: Open -> High -> Low -> Close
            # Check High first, then Low
            if is_long:
                # LONG: TP hit if High >= TP, SL hit if Low <= SL
                if h >= pos.take_profit:
                    return pos.take_profit, "Take Profit"
                if l <= pos.stop_loss:
                    return pos.stop_loss, "Stop Loss"
            else:
                # SHORT: SL hit if High >= SL, TP hit if Low <= TP
                if h >= pos.stop_loss:
                    return pos.stop_loss, "Stop Loss"
                if l <= pos.take_profit:
                    return pos.take_profit, "Take Profit"

        # Fallback (should never reach here if both sl_hit and tp_hit)
        logger.warning(
            f"Same-bar SL/TP resolution fallback: O={o} H={h} L={l} C={c}, "
            f"SL={pos.stop_loss} TP={pos.take_profit} dir={'LONG' if is_long else 'SHORT'}"
        )
        return pos.stop_loss, "Stop Loss"

    def _charge_overnight_swap(self, bar):
        """
        Charge overnight swap if position is held past daily rollover.
        Rollover typically happens at 5pm NY time (17:00).
        Wednesday is triple swap day (accounts for weekend).
        """
        pos = self.open_position
        bar_time = bar.name

        # Get current date
        current_date = bar_time.date() if hasattr(bar_time, 'date') else bar_time

        # Check if we already charged swap for this date
        if pos.last_swap_date is not None and pos.last_swap_date >= current_date:
            return

        # Check if it's past rollover time (5pm NY = 17:00)
        bar_time_only = bar_time.time() if hasattr(bar_time, 'time') else bar_time
        if bar_time_only < time(17, 0):
            return

        # Charge swap for holding overnight
        is_long = pos.direction == "BUY"
        swap_rate = self.config.swap_long_per_lot if is_long else self.config.swap_short_per_lot
        swap_amount = swap_rate * pos.lot_size

        # Triple swap on Wednesday (to account for Saturday/Sunday)
        day_of_week = bar_time.weekday() if hasattr(bar_time, 'weekday') else 0
        if day_of_week == self.config.triple_swap_day:
            swap_amount *= 3

        # Accrue swap on the position and apply once at close.
        # Keep signed value: negative = cost, positive = credit.
        pos.swap_cost += swap_amount
        pos.last_swap_date = current_date

        logger.debug(
            f"Swap accrued: ${swap_amount:.2f} (triple: {day_of_week == self.config.triple_swap_day}), "
            f"Cumulative swap: ${pos.swap_cost:.2f}"
        )

    def _update_trailing_stop(self, bar, df: pd.DataFrame):
        """Update trailing stop based on ATR"""
        pos = self.open_position
        is_long = pos.direction == "BUY"
        entry = pos.entry_price
        # Use initial risk for 1R breakeven target (not trailed SL)
        risk = abs(entry - pos.initial_stop_loss)
        close = bar['close']

        # Step 1: Move to breakeven at 1R profit
        if not pos.at_breakeven:
            if is_long and close >= (entry + risk):
                pos.stop_loss = entry
                pos.at_breakeven = True
                logger.debug(f"Breakeven set @ {entry:.2f}")
            elif not is_long and close <= (entry - risk):
                pos.stop_loss = entry
                pos.at_breakeven = True
                logger.debug(f"Breakeven set @ {entry:.2f}")
            return

        # Step 2: ATR trailing (only after breakeven)
        atr = self.data_provider.calculate_atr(df, self.config.trailing_atr_period)
        if len(atr) == 0:
            return

        current_atr = atr.iloc[-1]
        if pd.isna(current_atr) or current_atr <= 0:
            return

        trail_offset = current_atr * self.config.trailing_atr_multiplier

        if is_long:
            new_sl = close - trail_offset
            if new_sl > pos.stop_loss:
                pos.stop_loss = new_sl
                logger.debug(f"Trailing SL updated: {new_sl:.2f}")
        else:
            new_sl = close + trail_offset
            if new_sl < pos.stop_loss:
                pos.stop_loss = new_sl
                logger.debug(f"Trailing SL updated: {new_sl:.2f}")

    def _close_position(self, bar, exit_reason: str, exit_price: float = None):
        """
        Close the open position and record trade with full cost tracking.

        Calculates gross P&L (from price movement only) and net P&L (after all costs).
        Tracks: spread (entry+exit), slippage (entry), commission (entry+exit), swap.
        """
        pos = self.open_position

        if exit_price is None:
            exit_price = bar['close']

        # === Exit spread/slippage cost ===
        exit_spread_cost = 0.0
        exit_slippage_cost = 0.0
        exit_execution_impact_cost = 0.0
        execution_mode = str(getattr(self.config, "execution_mode", "bar")).lower()
        current_atr = self.day_state.atr if self.day_state is not None and self.day_state.atr > 0 else 1.0

        if execution_mode == "microstructure" and self.micro_simulator is not None:
            close_side = "SELL" if pos.direction == "BUY" else "BUY"
            micro_decision = self.micro_simulator.simulate_exit(
                bar=bar,
                close_side=close_side,
                base_price=float(exit_price),
                atr=float(current_atr),
            )
            exit_price = micro_decision.adjusted_price
            exit_spread_cost = micro_decision.spread_cost
            exit_slippage_cost = micro_decision.slippage_cost
            exit_execution_impact_cost = micro_decision.adverse_selection_cost
            if isinstance(pos.strategy_metadata, dict):
                pos.strategy_metadata["micro_exit_impact"] = round(exit_execution_impact_cost, 6)
                pos.strategy_metadata["micro_exit_impact_usd"] = round(
                    exit_execution_impact_cost * pos.lot_size * self.config.contract_size, 2
                )
                pos.strategy_metadata["micro_exit_fill_probability"] = round(micro_decision.fill_probability, 4)
        elif self.config.simulate_spread:
            if self.config.use_variable_spread:
                exit_spread_cost = self._get_simulated_spread(bar.name)
            else:
                exit_spread_cost = self.config.max_spread_usd / 2

            if pos.direction == "BUY":
                exit_price -= exit_spread_cost  # Sell at bid (lower)
            else:
                exit_price += exit_spread_cost  # Buy back at ask (higher)

        exit_time = bar.name

        # === P&L Accounting ===
        #
        # IMPORTANT: gross_pnl is calculated from entry_price and exit_price, which were
        # ALREADY adjusted for spread and slippage at execution time:
        #   - Entry: price was worsened by spread + slippage in _execute_trade()
        #   - Exit: price was worsened by spread (above in this method)
        # Therefore, gross_pnl already has spread and slippage costs embedded in it.
        # It is NOT a true "zero-cost" gross -- it's the price-adjusted P&L.
        #
        # The only costs NOT embedded in the prices are:
        #   - Commission: charged separately (half at entry, half at exit)
        #   - Swap: accumulated overnight charges
        #
        # Full balance accounting for one trade:
        #   balance -= entry_commission               (at trade open, in _execute_trade)
        #   balance += net_pnl                        (at trade close, below)
        #   where net_pnl = gross_pnl - exit_commission + swap_pnl
        #
        # So total balance change = gross_pnl - entry_commission - exit_commission + swap_pnl
        #   where gross_pnl already reflects spread + slippage via adjusted prices.

        proxy_result = self._compute_proxy_pnl(pos, bar, exit_price)
        if proxy_result is None:
            # Gross P&L from adjusted prices (spread + slippage already embedded)
            if pos.direction == "BUY":
                gross_pnl = (exit_price - pos.entry_price) * pos.lot_size * self.config.contract_size
            else:
                gross_pnl = (pos.entry_price - exit_price) * pos.lot_size * self.config.contract_size
        else:
            gross_pnl, proxy_meta = proxy_result
            if isinstance(pos.strategy_metadata, dict):
                pos.strategy_metadata["proxy_pnl"] = proxy_meta

        # Exit commission deducted here (entry commission was already deducted at trade open)
        exit_commission = (self.config.commission_per_lot * pos.lot_size) / 2

        # === Tally all costs for REPORTING purposes ===
        # These totals are stored on TradeRecord so reports can show a cost breakdown.
        total_spread_cost = pos.spread_cost + exit_spread_cost  # Entry + exit spread (price units)
        total_slippage_cost = pos.slippage_cost + exit_slippage_cost + exit_execution_impact_cost  # Entry+exit
        total_commission = pos.commission_cost + exit_commission  # Entry + exit commission (USD)
        total_swap_cost = pos.swap_cost  # Accumulated overnight swaps (USD)

        # Convert spread/slippage from price units to USD for reporting
        # These are for display only -- they are NOT subtracted from net_pnl because
        # they are already reflected in gross_pnl through the adjusted prices.
        spread_cost_usd = total_spread_cost * pos.lot_size * self.config.contract_size
        slippage_cost_usd = total_slippage_cost * pos.lot_size * self.config.contract_size

        # Net P&L = gross_pnl - exit_commission + swap_pnl
        # Spread and slippage are NOT subtracted here because they are already
        # embedded in gross_pnl via the adjusted entry_price and exit_price.
        net_pnl = gross_pnl - exit_commission + pos.swap_cost

        # Calculate R-multiple (based on INITIAL risk at entry, not trailing SL)
        initial_risk = abs(pos.entry_price - pos.initial_stop_loss) * pos.lot_size * self.config.contract_size
        r_multiple = net_pnl / initial_risk if initial_risk > 0 else 0

        balance_before = self.balance
        self.balance += net_pnl  # Entry commission was already deducted at open
        balance_after = self.balance

        # Update day state
        self.day_state.daily_pnl += net_pnl
        self.day_state.daily_trades += 1
        if self.day_state.daily_trades == 1:
            self.day_state.first_trade_won = net_pnl > 0

        # Record trade with cost breakdown
        self.trade_counter += 1
        trade = TradeRecord(
            trade_number=self.trade_counter,
            direction=pos.direction,
            entry_time=pos.entry_time,
            exit_time=exit_time,
            entry_price=pos.entry_price,
            exit_price=exit_price,
            stop_loss=pos.stop_loss,
            take_profit=pos.take_profit,
            lot_size=pos.lot_size,
            profit_loss=round(net_pnl, 2),
            balance_before=balance_before,
            balance_after=balance_after,
            setup_type=pos.setup_type,
            exit_reason=exit_reason,
            r_multiple=round(r_multiple, 2),
            # Strategy diagnostics
            entry_reason=pos.strategy_metadata,
            # Cost breakdown
            gross_pnl=round(gross_pnl, 2),
            spread_cost=round(spread_cost_usd, 2),
            slippage_cost=round(slippage_cost_usd, 2),
            commission_cost=round(total_commission, 2),
            swap_cost=round(total_swap_cost, 2),
            # ML data
            ml_features=pos.ml_features,
            max_favorable_excursion=round(pos.max_favorable_excursion, 4),
            max_adverse_excursion=round(pos.max_adverse_excursion, 4),
        )
        self.trades.append(trade)

        # Track recent results for ML consecutive_results feature
        self._recent_trade_results.append(1 if net_pnl > 0 else 0)
        if len(self._recent_trade_results) > 50:
            self._recent_trade_results = self._recent_trade_results[-50:]

        # Update equity curve
        self.equity_curve.append((exit_time, balance_after))

        # Duration
        duration = exit_time - pos.entry_time if exit_time and pos.entry_time else timedelta(0)
        hours = duration.total_seconds() / 3600

        outcome = "WIN" if net_pnl > 0 else "LOSS"
        logger.info(
            f"TRADE #{self.trade_counter} EXIT: {exit_reason} | {outcome} "
            f"${net_pnl:+.2f} ({r_multiple:+.2f}R) | "
            f"Duration: {hours:.1f}h | MFE: {pos.max_favorable_excursion:.2f}R MAE: {pos.max_adverse_excursion:.2f}R | "
            f"Costs: spread=${spread_cost_usd:.2f} slip=${slippage_cost_usd:.2f} "
            f"comm=${total_commission:.2f} swap=${total_swap_cost:.2f} | "
            f"Balance: ${balance_after:.2f}"
        )

        self.open_position = None

    @staticmethod
    def _safe_float(value, default: float = 0.0) -> float:
        """Best-effort float conversion with fallback."""
        try:
            if value is None or pd.isna(value):
                return float(default)
            return float(value)
        except Exception:
            return float(default)

    def _compute_proxy_pnl(self, pos: Position, bar, exit_price: float) -> Optional[Tuple[float, Dict[str, Any]]]:
        """
        Optional custom P&L path for non-directional strategy proxies.

        Returns:
            None when standard directional P&L should be used, otherwise
            (gross_pnl_usd, diagnostics_dict).
        """
        meta = pos.strategy_metadata or {}
        if meta.get("pnl_model") != "earnings_short_vol_proxy":
            return None

        structure = str(meta.get("structure", "long_calendar")).lower()
        premium_usd = max(self._safe_float(meta.get("premium_usd"), 0.0), 0.0)
        expected_move_usd = max(self._safe_float(meta.get("expected_move_usd"), 0.01), 0.01)
        move_penalty_mult = max(self._safe_float(meta.get("move_penalty_mult"), 1.0), 0.0)
        breach_penalty_mult = max(self._safe_float(meta.get("breach_penalty_mult"), 2.5), 0.0)
        iv_point_value = max(self._safe_float(meta.get("iv_point_value"), 100.0), 0.0)
        back_vega_weight = max(self._safe_float(meta.get("calendar_back_vega_weight"), 0.35), 0.0)

        bar_close = self._safe_float(bar.get("close"), exit_price)
        move_usd = abs(bar_close - pos.entry_price)
        move_ratio = move_usd / expected_move_usd

        iv_front_col = str(meta.get("iv_front_col", "iv_front"))
        iv_back_col = str(meta.get("iv_back_col", "iv_back"))
        iv_front_entry = self._safe_float(meta.get("iv_front_entry"), 0.0)
        iv_back_entry = self._safe_float(meta.get("iv_back_entry"), 0.0)
        iv_front_exit = self._safe_float(bar.get(iv_front_col), iv_front_entry)
        iv_back_exit = self._safe_float(bar.get(iv_back_col), iv_back_entry)

        front_crush = max(iv_front_entry - iv_front_exit, 0.0)
        back_crush = max(iv_back_entry - iv_back_exit, 0.0)

        if structure == "short_straddle":
            iv_component = front_crush * iv_point_value
            move_penalty = premium_usd * move_penalty_mult * move_ratio
            breach_penalty = 0.0
            if move_ratio > 1.0:
                breach_penalty = premium_usd * breach_penalty_mult * (move_ratio - 1.0)
            gross_per_unit = premium_usd + iv_component - move_penalty - breach_penalty
        else:
            # Calendar profile: front crush helps, back crush partially offsets.
            iv_component = (front_crush - back_vega_weight * back_crush) * iv_point_value
            move_penalty = premium_usd * 0.5 * move_penalty_mult * move_ratio
            breach_penalty = 0.0
            if move_ratio > 1.0:
                breach_penalty = premium_usd * 0.75 * breach_penalty_mult * (move_ratio - 1.0)
            gross_per_unit = premium_usd + iv_component - move_penalty - breach_penalty
            # Calendar worst-case should be near premium paid.
            gross_per_unit = max(gross_per_unit, -1.05 * premium_usd)

        gross_pnl = gross_per_unit * pos.lot_size * self.config.contract_size
        diagnostics = {
            "model": "earnings_short_vol_proxy",
            "structure": structure,
            "premium_usd": round(premium_usd, 6),
            "expected_move_usd": round(expected_move_usd, 6),
            "move_usd": round(move_usd, 6),
            "move_ratio": round(move_ratio, 6),
            "iv_front_entry": round(iv_front_entry, 6),
            "iv_front_exit": round(iv_front_exit, 6),
            "iv_back_entry": round(iv_back_entry, 6),
            "iv_back_exit": round(iv_back_exit, 6),
            "front_crush": round(front_crush, 6),
            "back_crush": round(back_crush, 6),
            "gross_per_unit_usd": round(gross_per_unit, 6),
            "gross_pnl_usd": round(gross_pnl, 6),
        }
        return gross_pnl, diagnostics

    def _compile_results(self) -> Dict[str, Any]:
        """Compile all backtest results and metrics"""

        # Generate equity curve if not enough points
        if len(self.equity_curve) == 0:
            self.equity_curve = [(self.config.start_date, self.config.initial_balance)]

        # Calculate all metrics
        metrics = self.metrics_calc.calculate_all_metrics(
            self.trades,
            self.equity_curve
        )

        # Generate additional analytics
        daily_pnl = self.metrics_calc.calculate_daily_pnl(self.trades)
        monthly_returns = self.metrics_calc.calculate_monthly_returns(self.trades)
        equity_curve_data = self.metrics_calc.generate_equity_curve(self.trades)
        setup_analysis = self.metrics_calc.calculate_setup_analysis(self.trades)

        # Convert trades to serializable format
        trades_data = []
        for t in self.trades:
            trades_data.append({
                'trade_number': t.trade_number,
                'direction': t.direction,
                'entry_time': t.entry_time.isoformat() if t.entry_time else None,
                'exit_time': t.exit_time.isoformat() if t.exit_time else None,
                'entry_price': t.entry_price,
                'exit_price': t.exit_price,
                'stop_loss': t.stop_loss,
                'take_profit': t.take_profit,
                'lot_size': t.lot_size,
                'profit_loss': t.profit_loss,
                'r_multiple': t.r_multiple,
                'balance_before': t.balance_before,
                'balance_after': t.balance_after,
                'setup_type': t.setup_type,
                'exit_reason': t.exit_reason,
                # Strategy diagnostics
                'entry_reason': t.entry_reason,
                # Cost breakdown
                'gross_pnl': t.gross_pnl,
                'spread_cost': t.spread_cost,
                'slippage_cost': t.slippage_cost,
                'commission_cost': t.commission_cost,
                'swap_cost': t.swap_cost,
                # ML data
                'ml_features': t.ml_features,
                'max_favorable_excursion': t.max_favorable_excursion,
                'max_adverse_excursion': t.max_adverse_excursion,
            })

        return {
            'status': self.status,
            'data_hash': getattr(self, '_data_hash', None),
            'run_manifest': self._build_run_manifest(),
            'metrics': metrics,
            'trades': trades_data,
            'equity_curve': equity_curve_data,
            'daily_pnl': daily_pnl,
            'monthly_returns': monthly_returns,
            'setup_analysis': setup_analysis,
            'regime_analysis': self.cross_asset_filter.summary() if self.cross_asset_filter else None,
            'microstructure_analysis': summarize_microstructure_from_trades(self.trades),
            'config': {
                'symbol': self.config.symbol,
                'timeframe': self.config.timeframe,
                'start_date': self.config.start_date.isoformat() if self.config.start_date else None,
                'end_date': self.config.end_date.isoformat() if self.config.end_date else None,
                'initial_balance': self.config.initial_balance,
            }
        }

    @staticmethod
    def _json_safe(value):
        """Convert values to JSON-safe primitives for run manifests."""
        if isinstance(value, datetime):
            return value.isoformat()
        if isinstance(value, list):
            return [BacktestEngine._json_safe(v) for v in value]
        if isinstance(value, dict):
            return {k: BacktestEngine._json_safe(v) for k, v in value.items()}
        return value

    def _effective_config_snapshot(self) -> Dict[str, Any]:
        """Return the full effective BacktestConfig in JSON-safe form."""
        return self._json_safe(asdict(self.config))

    def _compute_code_hash(self) -> str:
        """
        Hash core runtime code files for reproducibility diagnostics.

        Includes the active engine module, shared core modules, and the active
        strategy class source file when available.
        """
        files = [
            Path(__file__),
            Path(__file__).parent / "data_provider.py",
            Path(__file__).parent / "metrics_calculator.py",
            Path(__file__).parent / "config_builder.py",
            Path(__file__).parent / "strategy_registry.py",
        ]

        if self.strategy is not None:
            strategy_src = inspect.getsourcefile(self.strategy.__class__)
            if strategy_src:
                files.append(Path(strategy_src))

        digest = hashlib.sha256()
        seen = set()
        for f in files:
            try:
                fp = f.resolve()
            except Exception:
                fp = f
            if fp in seen or not Path(fp).exists():
                continue
            seen.add(fp)
            p = Path(fp)
            digest.update(str(p).encode("utf-8"))
            digest.update(p.read_bytes())

        return digest.hexdigest()

    def _build_run_manifest(self) -> Dict[str, Any]:
        """Build reproducibility metadata to persist with each backtest result."""
        return {
            "generated_at": datetime.utcnow().isoformat(),
            "engine_class": self.__class__.__name__,
            "strategy_class": self.strategy.__class__.__name__ if self.strategy else None,
            "code_hash": self._compute_code_hash(),
            "data_hash": getattr(self, "_data_hash", None),
            "effective_config": self._effective_config_snapshot(),
        }
