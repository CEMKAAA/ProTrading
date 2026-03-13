"""
Pydantic schemas for API request/response validation
"""

from pydantic import BaseModel, Field, field_validator, model_validator
from typing import Optional, List, Dict, Any, Literal
from datetime import datetime, date, time
from enum import Enum


class TimeframeEnum(str, Enum):
    M1 = "M1"
    M5 = "M5"
    M15 = "M15"
    M30 = "M30"
    H1 = "H1"
    H4 = "H4"
    D1 = "D1"


class TradeDirectionEnum(str, Enum):
    BUY = "BUY"
    SELL = "SELL"


class BacktestStatusEnum(str, Enum):
    PENDING = "PENDING"
    RUNNING = "RUNNING"
    COMPLETED = "COMPLETED"
    FAILED = "FAILED"


# ========================== Configuration Schemas ==========================

class BacktestConfigBase(BaseModel):
    """Base schema for backtest configuration"""
    name: str = Field(..., min_length=1, max_length=255)
    description: Optional[str] = None
    strategy_id: str = Field(default="orb_strategy", max_length=50)
    preset_name: Optional[str] = Field(default=None, max_length=20)

    # Symbol & Timeframe
    symbol: str = Field(default="XAUUSD", max_length=20)
    timeframe: TimeframeEnum = Field(default=TimeframeEnum.M1)

    # Date Range
    start_date: datetime
    end_date: datetime

    # Risk Management
    initial_balance: float = Field(default=10000.0, ge=100.0)
    risk_percent: float = Field(default=1.0, ge=0.1, le=10.0)
    max_spread_usd: Optional[float] = Field(default=None, ge=0.000001, le=5.0)
    max_daily_loss_usd: float = Field(default=-150.0, le=0.0)
    max_total_risk_usd: float = Field(default=200.0, ge=10.0)

    # Stop Loss Parameters
    min_sl_usd: Optional[float] = Field(default=None, ge=0.001, le=50.0)
    max_sl_usd: Optional[float] = Field(default=None, ge=0.005, le=100.0)
    gold_rr_threshold: Optional[float] = Field(default=None, ge=0.50, le=20.0)

    # ICT Parameters - FVG
    min_fvg_gap: Optional[float] = Field(default=None, ge=0.00001, le=5.0)
    fvg_lookback: int = Field(default=50, ge=10, le=500)

    # ICT Parameters - Displacement
    displacement_percentile: int = Field(default=75, ge=50, le=99)
    displacement_lookback: int = Field(default=20, ge=5, le=100)
    max_opposing_wick_ratio: float = Field(default=0.4, ge=0.1, le=1.0)

    # ICT Parameters - Order Blocks
    ob_lookback: int = Field(default=100, ge=20, le=500)
    ob_min_body_percent: int = Field(default=60, ge=30, le=90)
    ob_validation_bars: int = Field(default=3, ge=1, le=10)

    # ICT Parameters - Liquidity
    liquidity_wick_ratio: float = Field(default=0.6, ge=0.2, le=1.0)
    sweep_tolerance_usd: float = Field(default=0.20, ge=0.05, le=2.0)

    # Session Times
    orb_start_time: str = Field(default="09:30", pattern=r"^\d{2}:\d{2}$")
    orb_end_time: str = Field(default="09:45", pattern=r"^\d{2}:\d{2}$")
    trade_start_time: str = Field(default="09:45", pattern=r"^\d{2}:\d{2}$")
    trade_end_time: str = Field(default="16:00", pattern=r"^\d{2}:\d{2}$")

    # Asian Session
    asian_start: str = Field(default="20:00", pattern=r"^\d{2}:\d{2}$")
    asian_end: str = Field(default="02:00", pattern=r"^\d{2}:\d{2}$")

    # London Session
    london_start: str = Field(default="03:00", pattern=r"^\d{2}:\d{2}$")
    london_end: str = Field(default="12:00", pattern=r"^\d{2}:\d{2}$")

    # Trailing Stop
    use_trailing: bool = Field(default=True)
    trailing_atr_period: int = Field(default=14, ge=5, le=50)
    trailing_atr_multiplier: float = Field(default=1.5, ge=0.5, le=5.0)

    # Trend Filter
    min_adr_for_trend: float = Field(default=12.0, ge=1.0, le=100.0)
    adr_period: int = Field(default=5, ge=1, le=20)

    # Contract Size (derived from instrument: Gold=100oz, FX=100k)
    contract_size: Optional[float] = Field(default=None, ge=1.0)

    # Simulation Realism - Spread
    simulate_spread: bool = Field(default=True)
    use_variable_spread: bool = Field(default=True)

    # Simulation Realism - Slippage
    simulate_slippage: bool = Field(default=True)
    slippage_atr_factor: float = Field(default=0.02, ge=0.0, le=1.0)

    # Commission
    commission_per_lot: float = Field(default=3.50, ge=0.0, le=20.0)

    # Overnight Swap
    simulate_swap: bool = Field(default=True)
    swap_long_per_lot: float = Field(default=-8.50)
    swap_short_per_lot: float = Field(default=-3.20)

    # Bias Strength
    bias_min_strength: int = Field(default=30, ge=0, le=100)

    # Friday Close
    close_before_weekend: bool = Field(default=True)
    friday_close_hour: int = Field(default=15, ge=0, le=23)
    friday_close_minute: int = Field(default=30, ge=0, le=59)

    # Trade Limits
    max_daily_trades: int = Field(default=2, ge=1, le=10)
    stop_after_first_win: bool = Field(default=True)

    # Cross-Asset Regime Filter
    enable_cross_asset_filter: bool = Field(default=False)
    regime_timeframe: TimeframeEnum = Field(default=TimeframeEnum.M15)
    regime_lookback_bars: int = Field(default=96, ge=24, le=2000)
    regime_return_bars: int = Field(default=8, ge=1, le=200)
    regime_signal_threshold: float = Field(default=0.18, ge=0.05, le=1.0)
    regime_strong_threshold: float = Field(default=0.40, ge=0.10, le=1.0)
    regime_block_countertrend: bool = Field(default=True)
    regime_reduce_size_in_headwind: bool = Field(default=True)
    regime_tailwind_risk_multiplier: float = Field(default=1.15, ge=0.1, le=3.0)
    regime_headwind_risk_multiplier: float = Field(default=0.50, ge=0.05, le=2.0)
    regime_neutral_risk_multiplier: float = Field(default=1.00, ge=0.1, le=3.0)
    regime_symbol_dxy: str = Field(default="DXY,USDX,USDX.i", max_length=255)
    regime_symbol_yield: str = Field(default="US10Y,TNX,US10Y.cash", max_length=255)
    regime_symbol_riskoff: str = Field(default="VIX,VIX.cash,VOLX", max_length=255)
    regime_symbol_riskon: str = Field(default="SPX500,US500,US30", max_length=255)
    regime_weight_dxy: float = Field(default=0.40, ge=0.0, le=1.0)
    regime_weight_yield: float = Field(default=0.35, ge=0.0, le=1.0)
    regime_weight_riskoff: float = Field(default=0.15, ge=0.0, le=1.0)
    regime_weight_riskon: float = Field(default=0.10, ge=0.0, le=1.0)

    # Data Source: "auto" (MT5+CSV merge), "csv_only" (imported files only)
    data_source: str = Field(default="auto", pattern=r"^(auto|csv_only)$")

    # Specific CSV files to use (null = auto-discover all matching files)
    csv_files: Optional[List[str]] = Field(default=None)

    # ML Settings
    use_ml_filter: bool = Field(default=False)
    ml_min_win_probability: float = Field(default=0.55, ge=0.30, le=0.95)
    use_ml_dynamic_rr: bool = Field(default=False)
    ml_base_strategy_id: Optional[str] = Field(default=None, max_length=50)
    ml_model_id: Optional[int] = Field(default=None)  # Specific ML model to use

    @model_validator(mode='after')
    def apply_instrument_defaults_and_validate(self):
        """Fill None instrument-specific fields from instrument_specs, then validate."""
        try:
            from ..core.instrument_specs import get_instrument
            inst = get_instrument(self.symbol)
        except Exception:
            # Fallback to Gold defaults if import fails (e.g. during testing)
            inst = None

        if inst is not None:
            if self.max_spread_usd is None:
                self.max_spread_usd = inst.max_spread
            if self.min_sl_usd is None:
                self.min_sl_usd = inst.min_sl
            if self.max_sl_usd is None:
                self.max_sl_usd = inst.max_sl
            if self.gold_rr_threshold is None:
                self.gold_rr_threshold = inst.rr_threshold
            if self.contract_size is None:
                self.contract_size = inst.contract_size
            if self.min_fvg_gap is None:
                self.min_fvg_gap = inst.min_fvg_gap
        else:
            # Hard fallback if instrument_specs unavailable
            if self.max_spread_usd is None:
                self.max_spread_usd = 0.40
            if self.min_sl_usd is None:
                self.min_sl_usd = 1.00
            if self.max_sl_usd is None:
                self.max_sl_usd = 10.00
            if self.gold_rr_threshold is None:
                self.gold_rr_threshold = 3.00
            if self.contract_size is None:
                self.contract_size = 100.0
            if self.min_fvg_gap is None:
                self.min_fvg_gap = 0.30

        if self.end_date <= self.start_date:
            raise ValueError('end_date must be after start_date')
        if self.max_sl_usd <= self.min_sl_usd:
            raise ValueError('max_sl_usd must be greater than min_sl_usd')
        return self


class BacktestConfigCreate(BacktestConfigBase):
    """Schema for creating a new backtest configuration"""
    pass


class BacktestConfigUpdate(BaseModel):
    """Schema for updating backtest configuration"""
    name: Optional[str] = None
    description: Optional[str] = None
    strategy_id: Optional[str] = None
    preset_name: Optional[str] = None

    # Symbol & Timeframe
    symbol: Optional[str] = None
    timeframe: Optional[TimeframeEnum] = None

    # Date Range
    start_date: Optional[datetime] = None
    end_date: Optional[datetime] = None

    # Risk Management
    initial_balance: Optional[float] = None
    risk_percent: Optional[float] = None
    max_spread_usd: Optional[float] = None
    max_daily_loss_usd: Optional[float] = None
    max_total_risk_usd: Optional[float] = None

    # Stop Loss Parameters
    min_sl_usd: Optional[float] = None
    max_sl_usd: Optional[float] = None
    gold_rr_threshold: Optional[float] = None

    # ICT Parameters - FVG
    min_fvg_gap: Optional[float] = None
    fvg_lookback: Optional[int] = None

    # ICT Parameters - Displacement
    displacement_percentile: Optional[int] = None
    displacement_lookback: Optional[int] = None
    max_opposing_wick_ratio: Optional[float] = None

    # ICT Parameters - Order Blocks
    ob_lookback: Optional[int] = None
    ob_min_body_percent: Optional[int] = None
    ob_validation_bars: Optional[int] = None

    # ICT Parameters - Liquidity
    liquidity_wick_ratio: Optional[float] = None
    sweep_tolerance_usd: Optional[float] = None

    # Session Times
    orb_start_time: Optional[str] = None
    orb_end_time: Optional[str] = None
    trade_start_time: Optional[str] = None
    trade_end_time: Optional[str] = None
    asian_start: Optional[str] = None
    asian_end: Optional[str] = None
    london_start: Optional[str] = None
    london_end: Optional[str] = None

    # Trailing Stop
    use_trailing: Optional[bool] = None
    trailing_atr_period: Optional[int] = None
    trailing_atr_multiplier: Optional[float] = None

    # Trend Filter
    min_adr_for_trend: Optional[float] = None
    adr_period: Optional[int] = None

    # Contract Size
    contract_size: Optional[float] = None

    # Simulation Realism - Spread
    simulate_spread: Optional[bool] = None
    use_variable_spread: Optional[bool] = None

    # Simulation Realism - Slippage
    simulate_slippage: Optional[bool] = None
    slippage_atr_factor: Optional[float] = None

    # Commission
    commission_per_lot: Optional[float] = None

    # Overnight Swap
    simulate_swap: Optional[bool] = None
    swap_long_per_lot: Optional[float] = None
    swap_short_per_lot: Optional[float] = None

    # Bias Strength
    bias_min_strength: Optional[int] = None

    # Friday Close
    close_before_weekend: Optional[bool] = None
    friday_close_hour: Optional[int] = None
    friday_close_minute: Optional[int] = None

    # Trade Limits
    max_daily_trades: Optional[int] = None
    stop_after_first_win: Optional[bool] = None

    # Cross-Asset Regime Filter
    enable_cross_asset_filter: Optional[bool] = None
    regime_timeframe: Optional[TimeframeEnum] = None
    regime_lookback_bars: Optional[int] = None
    regime_return_bars: Optional[int] = None
    regime_signal_threshold: Optional[float] = None
    regime_strong_threshold: Optional[float] = None
    regime_block_countertrend: Optional[bool] = None
    regime_reduce_size_in_headwind: Optional[bool] = None
    regime_tailwind_risk_multiplier: Optional[float] = None
    regime_headwind_risk_multiplier: Optional[float] = None
    regime_neutral_risk_multiplier: Optional[float] = None
    regime_symbol_dxy: Optional[str] = None
    regime_symbol_yield: Optional[str] = None
    regime_symbol_riskoff: Optional[str] = None
    regime_symbol_riskon: Optional[str] = None
    regime_weight_dxy: Optional[float] = None
    regime_weight_yield: Optional[float] = None
    regime_weight_riskoff: Optional[float] = None
    regime_weight_riskon: Optional[float] = None

    # Data Source
    data_source: Optional[str] = None
    csv_files: Optional[List[str]] = None

    # ML Settings
    use_ml_filter: Optional[bool] = None
    ml_min_win_probability: Optional[float] = None
    use_ml_dynamic_rr: Optional[bool] = None
    ml_base_strategy_id: Optional[str] = None
    ml_model_id: Optional[int] = None


class BacktestConfig(BacktestConfigBase):
    """Schema for backtest configuration response"""
    id: int
    created_at: datetime

    class Config:
        from_attributes = True


# ========================== Trade Schemas ==========================

class TradeBase(BaseModel):
    """Base schema for trade data"""
    direction: TradeDirectionEnum
    entry_time: datetime
    entry_price: float
    stop_loss: float
    take_profit: Optional[float] = None
    lot_size: float
    setup_type: Optional[str] = None
    bias: Optional[str] = None


class TradeCreate(TradeBase):
    """Schema for creating a trade record"""
    result_id: int


class TradeResponse(BaseModel):
    """Schema for trade response"""
    id: int
    trade_number: int
    direction: str
    status: str

    entry_time: datetime
    exit_time: Optional[datetime] = None

    entry_price: float
    exit_price: Optional[float] = None
    stop_loss: float
    take_profit: Optional[float] = None
    lot_size: float

    profit_loss: float
    profit_loss_pips: float
    profit_loss_percent: float
    r_multiple: float

    setup_type: Optional[str] = None
    bias: Optional[str] = None
    exit_reason: Optional[str] = None

    # Strategy diagnostics
    entry_reason: Optional[dict] = None
    gross_pnl: Optional[float] = None
    spread_cost: Optional[float] = None
    slippage_cost: Optional[float] = None
    commission_cost: Optional[float] = None
    swap_cost: Optional[float] = None

    # Session levels
    orb_high: Optional[float] = None
    orb_low: Optional[float] = None
    asian_high: Optional[float] = None
    asian_low: Optional[float] = None

    # ICT patterns
    fvg_size: Optional[float] = None
    ob_high: Optional[float] = None
    ob_low: Optional[float] = None

    # MFE/MAE
    max_favorable_excursion: Optional[float] = None
    max_adverse_excursion: Optional[float] = None

    balance_before: Optional[float] = None
    balance_after: Optional[float] = None

    class Config:
        from_attributes = True


# ========================== Performance Metrics Schemas ==========================

class PerformanceMetrics(BaseModel):
    """Schema for performance metrics"""
    total_trades: int = 0
    winning_trades: int = 0
    losing_trades: int = 0
    win_rate: float = 0.0

    initial_balance: float = 0.0
    final_balance: float = 0.0
    total_profit: float = 0.0
    total_loss: float = 0.0
    net_profit: float = 0.0
    profit_factor: float = 0.0

    max_drawdown: float = 0.0
    max_drawdown_percent: float = 0.0
    sharpe_ratio: float = 0.0
    sortino_ratio: float = 0.0
    calmar_ratio: float = 0.0

    avg_win: float = 0.0
    avg_loss: float = 0.0
    largest_win: float = 0.0
    largest_loss: float = 0.0
    avg_trade_duration: float = 0.0

    avg_rr_ratio: float = 0.0
    expectancy: float = 0.0


# ========================== Backtest Result Schemas ==========================

class BacktestResultBase(BaseModel):
    """Base schema for backtest results"""
    status: BacktestStatusEnum = BacktestStatusEnum.PENDING
    error_message: Optional[str] = None


class BacktestResultCreate(BacktestResultBase):
    """Schema for creating backtest result"""
    config_id: int


class BacktestResultResponse(BaseModel):
    """Schema for backtest result response"""
    id: int
    config_id: int
    status: str
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    error_message: Optional[str] = None

    # Performance Metrics
    metrics: PerformanceMetrics

    # Equity Curve (list of {timestamp, equity} points)
    equity_curve: Optional[List[Dict[str, Any]]] = None
    drawdown_curve: Optional[List[Dict[str, Any]]] = None
    daily_pnl: Optional[List[Dict[str, Any]]] = None
    monthly_returns: Optional[Dict[str, float]] = None
    regime_analysis: Optional[Dict[str, Any]] = None
    microstructure_analysis: Optional[Dict[str, Any]] = None
    walk_forward_report: Optional[Dict[str, Any]] = None

    # Data versioning
    data_hash: Optional[str] = None

    # Config reference
    config: Optional[BacktestConfig] = None

    class Config:
        from_attributes = True


class BacktestResultSummary(BaseModel):
    """Compact summary for list views"""
    id: int
    config_id: int
    config_name: str
    strategy_id: str = "orb_strategy"
    symbol: str = "XAUUSD"
    timeframe: str = "M1"
    status: str
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    total_trades: int = 0
    win_rate: float = 0.0
    net_profit: float = 0.0
    max_drawdown_percent: float = 0.0

    class Config:
        from_attributes = True


# ========================== Dashboard Schemas ==========================

class DashboardStats(BaseModel):
    """Schema for dashboard statistics"""
    total_backtests: int = 0
    successful_backtests: int = 0
    total_live_trades: int = 0

    # Current live performance
    current_balance: float = 0.0
    daily_pnl: float = 0.0
    weekly_pnl: float = 0.0
    monthly_pnl: float = 0.0

    # Best backtest metrics
    best_win_rate: float = 0.0
    best_profit_factor: float = 0.0
    lowest_drawdown: float = 0.0

    # Active positions
    open_positions: int = 0
    total_exposure: float = 0.0


class LiveStatus(BaseModel):
    """Schema for live bot status"""
    is_connected: bool = False
    is_trading: bool = False
    is_running: bool = False
    mt5_available: bool = False
    symbol_requested: Optional[str] = None
    symbol_resolved: Optional[str] = None
    active_strategy: Optional[str] = None
    current_time_ny: Optional[datetime] = None
    current_price: Optional[float] = None
    spread: Optional[float] = None

    # Session info
    session_bias: Optional[str] = None
    is_trending: bool = False
    orb_high: Optional[float] = None
    orb_low: Optional[float] = None
    asian_high: Optional[float] = None
    asian_low: Optional[float] = None

    # Today's performance
    daily_trades: int = 0
    daily_pnl: float = 0.0
    can_trade: bool = False

    # Account info
    balance: float = 0.0
    equity: float = 0.0
    margin_level: Optional[float] = None
    strategy_diagnostics: Dict[str, Any] = Field(default_factory=dict)
    running_strategies: List[Dict[str, Any]] = Field(default_factory=list)


# ========================== Chart Data Schemas ==========================

class CandleData(BaseModel):
    """Schema for candlestick data"""
    time: datetime
    open: float
    high: float
    low: float
    close: float
    volume: int = 0


class ChartAnnotation(BaseModel):
    """Schema for chart annotations (FVGs, OBs, etc.)"""
    type: str  # fvg, order_block, liquidity_level, entry, exit
    time: datetime
    price: Optional[float] = None
    price_high: Optional[float] = None
    price_low: Optional[float] = None
    color: Optional[str] = None
    label: Optional[str] = None


class ChartDataResponse(BaseModel):
    """Schema for chart data with annotations"""
    candles: List[CandleData]
    annotations: List[ChartAnnotation] = []
    trades: List[Dict[str, Any]] = []


# ========================== Comparison Schemas ==========================

class BacktestComparison(BaseModel):
    """Schema for comparing multiple backtests"""
    backtest_ids: List[int]
    metrics: List[PerformanceMetrics]
    configs: List[BacktestConfig]
    equity_curves: Dict[int, List[Dict[str, Any]]]


# ========================== Export Schemas ==========================

class ExportRequest(BaseModel):
    """Schema for export requests"""
    backtest_id: int
    format: str = "csv"  # csv, xlsx, json
    include_trades: bool = True
    include_equity_curve: bool = True
    include_daily_pnl: bool = True


# ========================== Options Edge Schemas ==========================

class OptionsEdgeUniverseRow(BaseModel):
    symbol: str
    sector: Optional[str] = "UNKNOWN"
    price: float
    iv30: float
    hv30: float
    iv_rank_252: float
    avg_opt_volume_30d: float
    avg_oi_30d: float
    avg_bid_ask_pct: float
    days_to_earnings: float
    borrow_rate: Optional[float] = 0.0
    earnings_date: Optional[str] = None
    trend_20d_return: Optional[float] = None
    put_call_skew: Optional[float] = None


class OptionsEdgeScanRequest(BaseModel):
    universe: Optional[List[OptionsEdgeUniverseRow]] = None
    csv_file: Optional[str] = None
    option_chain: Optional[List[Dict[str, Any]]] = None
    chain_csv_file: Optional[str] = None
    build_strategies: bool = True
    top_n: int = Field(default=8, ge=1, le=100)
    max_sector_fraction: float = Field(default=0.35, ge=0.1, le=1.0)
    gate_config: Optional[Dict[str, float]] = None
    score_weights: Optional[Dict[str, float]] = None
    builder_config: Optional[Dict[str, Any]] = None
    llm_model: Optional[str] = None
    llm_cost_usd: float = Field(default=0.0, ge=0.0)


class OptionsEdgeLiveScanRequest(BaseModel):
    provider: str = Field(default="polygon", max_length=40)
    symbols: List[str] = Field(default_factory=list, max_length=500)
    use_sp500: bool = False
    sp500_limit: int = Field(default=475, ge=1, le=600)
    min_dte: int = Field(default=21, ge=1, le=365)
    max_dte: int = Field(default=55, ge=1, le=365)
    lookback_days: int = Field(default=45, ge=30, le=365)
    default_days_to_earnings: float = Field(default=999.0, ge=0.0)
    include_news: bool = False
    include_analyst: bool = False
    news_limit: int = Field(default=3, ge=0, le=10)
    build_strategies: bool = True
    top_n: int = Field(default=8, ge=1, le=100)
    max_sector_fraction: float = Field(default=0.35, ge=0.1, le=1.0)
    gate_config: Optional[Dict[str, float]] = None
    score_weights: Optional[Dict[str, float]] = None
    builder_config: Optional[Dict[str, Any]] = None
    llm_model: Optional[str] = None
    llm_cost_usd: float = Field(default=0.0, ge=0.0)


class OptionsEdgeProviderStatusResponse(BaseModel):
    provider: str
    configured: bool
    api_key_masked: Optional[str] = None
    base_url: Optional[str] = None
    warnings: Optional[List[str]] = None


class OptionsEdgeProviderProbeItem(BaseModel):
    name: str
    path: str
    ok: bool
    status_code: Optional[int] = None
    access: str
    message: Optional[str] = None


class OptionsEdgeProviderProbeResponse(BaseModel):
    provider: str
    symbol: str
    configured: bool
    api_key_masked: Optional[str] = None
    results: List[OptionsEdgeProviderProbeItem]


class OptionsEdgeScanResponse(BaseModel):
    scan_id: str
    scan_ts: datetime
    status: str
    summary: Dict[str, Any]
    selected_symbols: List[str]


class OptionsEdgeScanDetailResponse(BaseModel):
    scan_id: str
    scan_ts: datetime
    status: str
    universe_size: int
    passed_gate_count: int
    selected_count: int
    top_n: int
    max_sector_fraction: float
    gate_config: Optional[Dict[str, Any]] = None
    score_config: Optional[Dict[str, Any]] = None
    summary: Optional[Dict[str, Any]] = None
    llm_model: Optional[str] = None
    llm_cost_usd: float = 0.0
    latency_sec: float = 0.0
    error: Optional[str] = None


class OptionsEdgeCandidateResponse(BaseModel):
    symbol: str
    sector: Optional[str] = None
    selected: bool
    rank_global: Optional[int] = None
    rank_in_sector: Optional[int] = None
    score_total: float
    score_vol_edge: float
    score_liquidity: float
    score_event_timing: float
    score_risk: float
    penalty_sector_concentration: float
    builder_status: Optional[str] = None
    builder_policy: Optional[str] = None
    builder_reasons: Optional[List[str]] = None


class OptionsEdgeTradeCandidateResponse(BaseModel):
    id: Optional[int] = None
    symbol: str
    structure_type: str
    expiry_date: Optional[str] = None
    dte: Optional[int] = None
    net_credit: Optional[float] = None
    max_profit: Optional[float] = None
    max_loss: Optional[float] = None
    pop_est: Optional[float] = None
    delta_net: Optional[float] = None
    theta_net: Optional[float] = None
    vega_net: Optional[float] = None
    breakeven_low: Optional[float] = None
    breakeven_high: Optional[float] = None
    quality_flags: Optional[List[str]] = None
    legs_json: Optional[List[Dict[str, Any]]] = None
    payoff_curve: Optional[List[Dict[str, float]]] = None


class OptionsEdgeScanReportResponse(BaseModel):
    scan_id: str
    report_version: str
    llm_used: bool
    llm_model: str
    market_summary: str
    risk_summary: str
    candidate_notes: List[Dict[str, Any]]
    trade_decisions: List[Dict[str, Any]] = Field(default_factory=list)
    warnings: List[str]


class OptionsEdgeBacktestRequest(BaseModel):
    scan_ids: Optional[List[str]] = None
    start_ts: Optional[datetime] = None
    end_ts: Optional[datetime] = None

    initial_balance: float = Field(default=10000.0, gt=0.0)
    allocation_per_trade_usd: float = Field(default=1000.0, gt=0.0)
    max_contracts_per_trade: int = Field(default=3, ge=1, le=100)
    max_trades_per_scan: int = Field(default=8, ge=1, le=100)
    min_selected_symbols: int = Field(default=1, ge=0, le=500)
    min_pop: float = Field(default=0.0, ge=0.0, le=1.0)

    take_profit_frac: float = Field(default=0.50, gt=0.0, le=1.0)
    stop_loss_credit_mult: float = Field(default=1.75, ge=0.5, le=5.0)

    commission_per_leg: float = Field(default=0.65, ge=0.0, le=50.0)
    slippage_pct: float = Field(default=0.01, ge=0.0, le=1.0)
    spread_pct: float = Field(default=0.005, ge=0.0, le=1.0)
    min_fill_ratio: float = Field(default=0.70, ge=0.1, le=1.0)
    max_fill_ratio: float = Field(default=1.00, ge=0.1, le=1.0)

    walk_forward_folds: int = Field(default=4, ge=2, le=12)
    stress_slippage_mult: float = Field(default=1.25, ge=1.0, le=5.0)
    stress_spread_mult: float = Field(default=1.50, ge=1.0, le=5.0)
    stress_pop_penalty: float = Field(default=0.05, ge=0.0, le=0.5)
    stress_fill_probability: float = Field(default=0.90, ge=0.1, le=1.0)
    random_seed: int = Field(default=42, ge=0, le=2_147_483_647)


class OptionsEdgeBacktestResponse(BaseModel):
    run_id: str
    created_at: datetime
    status: str
    scans_used: int
    trades_simulated: int
    mode: str
    metrics: Dict[str, Any]
    walk_forward: Dict[str, Any]
    stress: Dict[str, Any]
    equity_curve: List[Dict[str, Any]] = Field(default_factory=list)
    trade_log: List[Dict[str, Any]] = Field(default_factory=list)
    notes: List[str]
    request: Dict[str, Any]


class OptionsEdgePositionTradeInput(BaseModel):
    symbol: str
    structure_type: str
    max_loss: float = Field(gt=0.0)
    legs_count: int = Field(default=2, ge=1, le=16)


class OptionsEdgePositionSizingRequest(BaseModel):
    account_balance: float = Field(gt=0.0)
    risk_pct: float = Field(default=2.0, gt=0.0, le=100.0)
    commission_per_leg: float = Field(default=0.65, ge=0.0, le=50.0)
    max_contracts_cap: int = Field(default=50, ge=1, le=1000)
    trades: List[OptionsEdgePositionTradeInput] = Field(default_factory=list)


class OptionsEdgePositionSizingItem(BaseModel):
    symbol: str
    structure_type: str
    max_contracts: int
    risk_budget_usd: float
    risk_per_contract_usd: float
    total_risk_usd: float
    remaining_budget_usd: float
    account_risk_pct: float
    skip_reason: Optional[str] = None


class OptionsEdgePositionSizingResponse(BaseModel):
    ok: bool = True
    portfolio_total_risk_usd: float
    portfolio_risk_pct: float
    sizing: List[OptionsEdgePositionSizingItem] = Field(default_factory=list)


class OptionsEdgeJournalTrackRequest(BaseModel):
    scan_id: str
    trade_candidate_id: int
    contracts: int = Field(default=1, ge=1, le=1000)
    account_balance_at_entry: Optional[float] = Field(default=None, gt=0.0)
    risk_pct_at_entry: Optional[float] = Field(default=None, gt=0.0, le=100.0)
    notes: Optional[str] = None


class OptionsEdgeJournalCloseRequest(BaseModel):
    exit_credit: Optional[float] = None
    actual_pnl: float
    exit_reason: str = Field(default="manual", max_length=40)
    notes: Optional[str] = None


class OptionsEdgeJournalEntryResponse(BaseModel):
    journal_id: str
    status: str
    created_at: datetime
    closed_at: Optional[datetime] = None
    scan_id: Optional[str] = None
    trade_candidate_id: Optional[int] = None
    symbol: str
    structure_type: str
    expiry_date: Optional[str] = None
    dte_at_entry: Optional[int] = None
    entry_credit: Optional[float] = None
    max_profit: Optional[float] = None
    max_loss: Optional[float] = None
    pop_est: Optional[float] = None
    contracts: int
    account_balance_at_entry: Optional[float] = None
    risk_pct_at_entry: Optional[float] = None
    portfolio_scope_key: Optional[str] = None
    portfolio_scope_profile: Optional[str] = None
    portfolio_scope_broker: Optional[str] = None
    portfolio_scope_account_login: Optional[str] = None
    portfolio_scope_account_server: Optional[str] = None
    exit_credit: Optional[float] = None
    actual_pnl: Optional[float] = None
    actual_pnl_total: Optional[float] = None
    exit_reason: Optional[str] = None
    hold_days: Optional[int] = None
    notes: Optional[str] = None
    legs_json: Optional[List[Dict[str, Any]]] = None


class OptionsEdgeJournalStatsResponse(BaseModel):
    total: int
    open: int
    closed: int
    wins: int
    losses: int
    win_rate: float
    total_pnl: float
    avg_pnl: float
    avg_hold_days: float


class CSPScreenRequest(BaseModel):
    provider: str = Field(default="polygon", max_length=40)
    symbols: List[str] = Field(default_factory=list, max_length=600)
    use_sp500: bool = True
    sp500_limit: int = Field(default=475, ge=1, le=600)
    min_revenue_growth_pct: float = Field(default=5.0)
    min_eps_growth_5y_pct: float = Field(default=5.0)
    min_eps_growth_fwd_pct: float = Field(default=0.0)
    min_profit_margin_pct: float = Field(default=10.0)
    min_iv_rank: float = Field(default=0.30, ge=0.0, le=1.0)
    min_option_volume_30d: float = Field(default=5_000_000.0, ge=0.0)
    excluded_industries: List[str] = Field(default_factory=list)
    vix_value: Optional[float] = Field(default=None, ge=0.0, le=120.0)
    vix_aggressive_threshold: float = Field(default=30.0, ge=5.0, le=120.0)
    sma200_touch_pct: float = Field(default=2.0, ge=0.0, le=20.0)
    fetch_fundamentals: bool = True
    include_price_vs_sma200: bool = False
    fundamentals_overrides: Dict[str, Dict[str, Any]] = Field(default_factory=dict)


class CSPCandidateResponse(BaseModel):
    symbol: str
    sector: Optional[str] = None
    industry: Optional[str] = None
    regime: str
    iv_rank: Optional[float] = None
    option_volume: Optional[float] = None
    pe_current: Optional[float] = None
    pe_5y_avg: Optional[float] = None
    pe_10y_avg: Optional[float] = None
    price_vs_sma200: Optional[float] = None
    fundamentals: Dict[str, Any] = Field(default_factory=dict)
    gate_reasons: List[str] = Field(default_factory=list)


class CSPScreenRunResponse(BaseModel):
    id: int
    run_date: datetime
    total_symbols_screened: int
    candidates_passed: int
    config: Dict[str, Any] = Field(default_factory=dict)
    summary: Dict[str, Any] = Field(default_factory=dict)
    candidates: List[CSPCandidateResponse] = Field(default_factory=list)


class CSPBacktestRequest(BaseModel):
    symbol: Optional[str] = None
    symbols: List[str] = Field(default_factory=list)
    screen_run_id: Optional[int] = None
    portfolio_mode: bool = True
    max_symbols: int = Field(default=10, ge=1, le=200)
    start_date: date
    end_date: date
    initial_capital: float = Field(default=100000.0, gt=0.0)
    max_concurrent_csps: int = Field(default=5, ge=1, le=100)
    max_portfolio_allocation_pct: float = Field(default=20.0, ge=1.0, le=100.0)
    max_sector_concentration: int = Field(default=2, ge=1, le=100)
    max_single_stock_pct: float = Field(default=5.0, ge=0.1, le=100.0)
    target_dte_min: int = Field(default=30, ge=1, le=365)
    target_dte_max: int = Field(default=45, ge=1, le=365)
    normal_pop_min: float = Field(default=0.70, ge=0.0, le=1.0)
    normal_pop_max: float = Field(default=0.80, ge=0.0, le=1.0)
    normal_yield_min_pct: float = Field(default=1.5, ge=0.0)
    normal_yield_max_pct: float = Field(default=3.0, ge=0.0)
    hard_min_yield_pct: float = Field(default=1.0, ge=0.0)
    aggressive_yield_min_pct: float = Field(default=4.0, ge=0.0)
    aggressive_yield_max_pct: float = Field(default=6.0, ge=0.0)
    vix_aggressive_threshold: float = Field(default=30.0, ge=5.0, le=120.0)
    sma200_touch_pct: float = Field(default=2.0, ge=0.0, le=20.0)
    iv_premium_factor: float = Field(default=1.2, ge=0.1, le=5.0)
    iv_floor: float = Field(default=0.40, ge=0.05, le=2.5)
    risk_free_rate: float = Field(default=0.03, ge=0.0, le=0.2)

    @model_validator(mode="after")
    def validate_ranges(self):
        if self.end_date < self.start_date:
            raise ValueError("end_date must be >= start_date")
        if self.target_dte_max < self.target_dte_min:
            raise ValueError("target_dte_max must be >= target_dte_min")
        if self.normal_pop_max < self.normal_pop_min:
            raise ValueError("normal_pop_max must be >= normal_pop_min")
        if self.normal_yield_max_pct < self.normal_yield_min_pct:
            raise ValueError("normal_yield_max_pct must be >= normal_yield_min_pct")
        if self.aggressive_yield_max_pct < self.aggressive_yield_min_pct:
            raise ValueError("aggressive_yield_max_pct must be >= aggressive_yield_min_pct")
        return self


class CSPBacktestRunResponse(BaseModel):
    id: int
    run_date: datetime
    start_date: Optional[date] = None
    end_date: Optional[date] = None
    initial_capital: Optional[float] = None
    final_capital: Optional[float] = None
    status: str
    error: Optional[str] = None
    config: Dict[str, Any] = Field(default_factory=dict)
    results: Dict[str, Any] = Field(default_factory=dict)
    equity_curve: List[Dict[str, Any]] = Field(default_factory=list)
    trades: List[Dict[str, Any]] = Field(default_factory=list)


class AIBotOptionsEdgePlanRequest(BaseModel):
    provider: str = Field(default="deterministic", max_length=80)
    llm_model_label: Optional[str] = Field(default=None, max_length=120)
    llm_url: Optional[str] = Field(default=None, max_length=300)
    api_key: Optional[str] = Field(default=None, max_length=300)
    account_balance: float = Field(default=10000.0, gt=0.0)
    risk_pct: float = Field(default=1.0, gt=0.0, le=100.0)
    max_contracts_cap: int = Field(default=5, ge=1, le=1000)
    dry_run: bool = True


class AIBotExecutionDecision(BaseModel):
    symbol: str
    action: str
    structure_type: Optional[str] = None
    trade_candidate_id: Optional[int] = None
    contracts: int = 0
    confidence: float = 0.0
    reason: str = ""
    evidence: Dict[str, Any] = Field(default_factory=dict)


class AIBotRunResponse(BaseModel):
    run_id: str
    created_at: datetime
    status: str
    strategy_id: str
    context_id: str
    provider: str
    llm_model_label: Optional[str] = None
    report: Dict[str, Any] = Field(default_factory=dict)
    execution_plan: List[AIBotExecutionDecision] = Field(default_factory=list)
    notes: List[str] = Field(default_factory=list)
    error: Optional[str] = None


class TradingSimulationSessionCreateRequest(BaseModel):
    strategy_id: str = Field(..., max_length=80)
    symbol: str = Field(default="XAUUSD", max_length=20)
    timeframe: str = Field(default="M1", max_length=10)
    mode: Literal["demo", "live"] = "demo"
    confirm_live_mode: bool = False


class TradingSimulationTelemetryResponse(BaseModel):
    strategy_id: str
    timestamp: str
    mode: Literal["demo", "live"]
    market: Dict[str, Any] = Field(default_factory=dict)
    risk: Dict[str, Any] = Field(default_factory=dict)
    step_inputs: Dict[str, Any] = Field(default_factory=dict)
    signals: Dict[str, Any] = Field(default_factory=dict)
    explanations: List[str] = Field(default_factory=list)
    telemetry_available: bool = False


class TradingSimulationStepStatusResponse(BaseModel):
    id: str
    title: str
    status: Literal["WAIT", "READY", "ACTIONABLE", "BLOCKED", "DONE"]
    why: str = ""
    wait_for: str = ""
    invalidates: str = ""
    action_now: str = ""
    evidence_keys: List[str] = Field(default_factory=list)
    reason: str = ""


class TradingSimulationGuideResponse(BaseModel):
    strategy_id: str
    what_this_strategy_is: str
    when_not_to_trade: List[str] = Field(default_factory=list)
    step_by_step: List[str] = Field(default_factory=list)
    common_mistakes: List[str] = Field(default_factory=list)
    risk_rules: List[str] = Field(default_factory=list)
    example_scenario: str = ""


class TradingSimulationSessionResponse(BaseModel):
    id: int
    session_uid: str
    strategy_id: str
    symbol: str
    timeframe: str
    mode: Literal["demo", "live"]
    status: str
    current_step_id: Optional[str] = None
    current_step_status: str = "WAIT"
    created_at: Optional[str] = None
    updated_at: Optional[str] = None
    ended_at: Optional[str] = None
    telemetry: Dict[str, Any] = Field(default_factory=dict)
    step_states: List[TradingSimulationStepStatusResponse] = Field(default_factory=list)
    summary: Dict[str, Any] = Field(default_factory=dict)
    current_step: Optional[Dict[str, Any]] = None
    playbook: Dict[str, Any] = Field(default_factory=dict)
    guide: Dict[str, Any] = Field(default_factory=dict)
    actions: List[Dict[str, Any]] = Field(default_factory=list)


class TradingSimulationActionRequest(BaseModel):
    action_type: Literal["step_done", "confirm_condition", "paper_enter", "paper_close", "skip_setup", "note"]
    step_id: Optional[str] = Field(default=None, max_length=80)
    note: Optional[str] = Field(default=None, max_length=500)
    payload: Dict[str, Any] = Field(default_factory=dict)


class TradingSimulationActionResponse(BaseModel):
    ok: bool
    state: TradingSimulationSessionResponse


class TradingSimulationCapabilityResponse(BaseModel):
    strategy_id: str
    listed: bool
    runnable: bool
    has_live_state: bool
    has_playbook: bool
    status_label: Literal["Live Runnable", "Replay Only", "Coming Soon"]
