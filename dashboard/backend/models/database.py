"""
Database configuration and models for the trading dashboard
SQLite for local development, PostgreSQL-ready for production
"""

from sqlalchemy import (
    create_engine, Column, Integer, String, Float, Date, DateTime,
    Boolean, JSON, ForeignKey, Text, Enum as SQLEnum, event
)
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, relationship
from datetime import datetime
import enum
import os
import json
from pathlib import Path

# Get the project root path (dashboard folder)
# Use resolve() to get absolute path - prevents different DBs when started from different directories
BACKEND_DIR = Path(__file__).resolve().parent.parent  # models -> backend
DASHBOARD_DIR = BACKEND_DIR.parent  # backend -> dashboard
DATA_DIR = DASHBOARD_DIR / "data"

# Ensure data directory exists
DATA_DIR.mkdir(exist_ok=True, parents=True)

# Database URL - SQLite for development
DATABASE_PATH = DATA_DIR / "trading.db"
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    f"sqlite:///{DATABASE_PATH}"
)

_IS_SQLITE = "sqlite" in str(DATABASE_URL).lower()

# Create engine
engine = create_engine(
    DATABASE_URL,
    connect_args=(
        {"check_same_thread": False, "timeout": 30.0}
        if _IS_SQLITE
        else {}
    ),
    echo=False
)

if _IS_SQLITE:
    @event.listens_for(engine, "connect")
    def _sqlite_configure_connection(dbapi_connection, connection_record):
        """Reduce writer contention for high-frequency background workers."""
        cur = dbapi_connection.cursor()
        try:
            cur.execute("PRAGMA journal_mode=WAL")
            cur.execute("PRAGMA synchronous=NORMAL")
            cur.execute("PRAGMA busy_timeout=30000")
            cur.execute("PRAGMA foreign_keys=ON")
            cur.execute("PRAGMA temp_store=MEMORY")
        finally:
            cur.close()

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


class TradeDirection(enum.Enum):
    BUY = "BUY"
    SELL = "SELL"


class TradeStatus(enum.Enum):
    OPEN = "OPEN"
    CLOSED = "CLOSED"
    CANCELLED = "CANCELLED"


class BacktestStatus(enum.Enum):
    PENDING = "PENDING"
    RUNNING = "RUNNING"
    COMPLETED = "COMPLETED"
    FAILED = "FAILED"


class BacktestConfigModel(Base):
    """Stores backtest configuration parameters"""
    __tablename__ = "backtest_configs"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(255), nullable=False)
    description = Column(Text, nullable=True)
    strategy_id = Column(String(50), default="orb_strategy")
    preset_name = Column(String(20), nullable=True)  # default, conservative, aggressive
    created_at = Column(DateTime, default=datetime.utcnow)

    # Symbol & Timeframe
    symbol = Column(String(20), default="XAUUSD")
    timeframe = Column(String(10), default="M1")

    # Date Range
    start_date = Column(DateTime, nullable=False)
    end_date = Column(DateTime, nullable=False)

    # Risk Management
    initial_balance = Column(Float, default=10000.0)
    risk_percent = Column(Float, default=1.0)
    max_spread_usd = Column(Float, nullable=True)  # Derived from instrument_specs
    max_daily_loss_usd = Column(Float, default=-150.0)
    max_total_risk_usd = Column(Float, default=200.0)

    # Contract Size (derived from instrument: Gold=100oz, FX=100k)
    contract_size = Column(Float, nullable=True)  # Derived from instrument_specs

    # Simulation Realism - Spread
    simulate_spread = Column(Boolean, default=True)
    use_variable_spread = Column(Boolean, default=True)  # Time-of-day spread model

    # Simulation Realism - Slippage (ATR-based)
    simulate_slippage = Column(Boolean, default=True)
    slippage_atr_factor = Column(Float, default=0.02)  # slippage = ATR * this factor
    min_slippage_usd = Column(Float, default=0.01)
    max_slippage_usd = Column(Float, default=0.50)
    avg_slippage_usd = Column(Float, default=0.05)  # Legacy field for backwards compat

    # Commission
    commission_per_lot = Column(Float, default=3.50)  # Round-trip commission per lot

    # Overnight Swap Simulation
    simulate_swap = Column(Boolean, default=True)
    swap_long_per_lot = Column(Float, default=-8.50)   # Typical gold swap for long
    swap_short_per_lot = Column(Float, default=-3.20)  # Typical gold swap for short
    triple_swap_day = Column(Integer, default=2)       # Wednesday (0=Mon, 2=Wed)

    # Bias Strength (match live bot)
    bias_min_strength = Column(Integer, default=30)  # Minimum bias score to trade (0-100)

    # Friday Close Settings
    close_before_weekend = Column(Boolean, default=True)
    friday_close_hour = Column(Integer, default=15)
    friday_close_minute = Column(Integer, default=30)

    # Stop Loss Parameters (derived from instrument_specs)
    min_sl_usd = Column(Float, nullable=True)
    max_sl_usd = Column(Float, nullable=True)
    gold_rr_threshold = Column(Float, nullable=True)

    # ICT Parameters - FVG (derived from instrument_specs)
    min_fvg_gap = Column(Float, nullable=True)
    fvg_lookback = Column(Integer, default=50)

    # ICT Parameters - Displacement
    displacement_percentile = Column(Integer, default=75)
    displacement_lookback = Column(Integer, default=20)
    max_opposing_wick_ratio = Column(Float, default=0.4)

    # ICT Parameters - Order Blocks
    ob_lookback = Column(Integer, default=100)
    ob_min_body_percent = Column(Integer, default=60)
    ob_validation_bars = Column(Integer, default=3)

    # ICT Parameters - Liquidity
    liquidity_wick_ratio = Column(Float, default=0.6)
    sweep_tolerance_usd = Column(Float, default=0.20)

    # Session Times (stored as HH:MM strings)
    orb_start_time = Column(String(5), default="09:30")
    orb_end_time = Column(String(5), default="09:45")
    trade_start_time = Column(String(5), default="09:45")
    trade_end_time = Column(String(5), default="16:00")

    # Asian Session
    asian_start = Column(String(5), default="20:00")
    asian_end = Column(String(5), default="02:00")

    # London Session
    london_start = Column(String(5), default="03:00")
    london_end = Column(String(5), default="12:00")

    # Trailing Stop
    use_trailing = Column(Boolean, default=True)
    trailing_atr_period = Column(Integer, default=14)
    trailing_atr_multiplier = Column(Float, default=1.5)

    # Trend Filter
    min_adr_for_trend = Column(Float, default=12.0)
    adr_period = Column(Integer, default=5)

    # Trade Limits
    max_daily_trades = Column(Integer, default=2)
    stop_after_first_win = Column(Boolean, default=True)

    # Cross-Asset Regime Filter
    enable_cross_asset_filter = Column(Boolean, default=False)
    regime_timeframe = Column(String(10), default="M15")
    regime_lookback_bars = Column(Integer, default=96)
    regime_return_bars = Column(Integer, default=8)
    regime_signal_threshold = Column(Float, default=0.18)
    regime_strong_threshold = Column(Float, default=0.40)
    regime_block_countertrend = Column(Boolean, default=True)
    regime_reduce_size_in_headwind = Column(Boolean, default=True)
    regime_tailwind_risk_multiplier = Column(Float, default=1.15)
    regime_headwind_risk_multiplier = Column(Float, default=0.50)
    regime_neutral_risk_multiplier = Column(Float, default=1.00)
    regime_symbol_dxy = Column(String(255), default="DXY,USDX,USDX.i")
    regime_symbol_yield = Column(String(255), default="US10Y,TNX,US10Y.cash")
    regime_symbol_riskoff = Column(String(255), default="VIX,VIX.cash,VOLX")
    regime_symbol_riskon = Column(String(255), default="SPX500,US500,US30")
    regime_weight_dxy = Column(Float, default=0.40)
    regime_weight_yield = Column(Float, default=0.35)
    regime_weight_riskoff = Column(Float, default=0.15)
    regime_weight_riskon = Column(Float, default=0.10)

    # Data Source: "auto" (MT5+CSV), "csv_only" (imported files only)
    data_source = Column(String(20), default="auto")

    # Specific CSV files to use (JSON array of filenames, null = use all matching)
    csv_files = Column(JSON, nullable=True)

    # ML Settings
    use_ml_filter = Column(Boolean, default=False)
    ml_min_win_probability = Column(Float, default=0.55)
    use_ml_dynamic_rr = Column(Boolean, default=False)
    ml_base_strategy_id = Column(String(50), nullable=True)
    ml_model_id = Column(Integer, nullable=True)  # Specific ML model to use (None = auto/latest)

    # Results relationship
    results = relationship("BacktestResultModel", back_populates="config")


class BacktestResultModel(Base):
    """Stores backtest execution results"""
    __tablename__ = "backtest_results"

    id = Column(Integer, primary_key=True, index=True)
    config_id = Column(Integer, ForeignKey("backtest_configs.id"), nullable=False)

    status = Column(SQLEnum(BacktestStatus), default=BacktestStatus.PENDING)
    started_at = Column(DateTime, nullable=True)
    completed_at = Column(DateTime, nullable=True)
    error_message = Column(Text, nullable=True)

    # Performance Metrics
    total_trades = Column(Integer, default=0)
    winning_trades = Column(Integer, default=0)
    losing_trades = Column(Integer, default=0)
    win_rate = Column(Float, default=0.0)

    # Financial Metrics
    initial_balance = Column(Float, default=0.0)
    final_balance = Column(Float, default=0.0)
    total_profit = Column(Float, default=0.0)
    total_loss = Column(Float, default=0.0)
    net_profit = Column(Float, default=0.0)
    profit_factor = Column(Float, default=0.0)

    # Risk Metrics
    max_drawdown = Column(Float, default=0.0)
    max_drawdown_percent = Column(Float, default=0.0)
    sharpe_ratio = Column(Float, default=0.0)
    sortino_ratio = Column(Float, default=0.0)
    calmar_ratio = Column(Float, default=0.0)

    # Trade Statistics
    avg_win = Column(Float, default=0.0)
    avg_loss = Column(Float, default=0.0)
    largest_win = Column(Float, default=0.0)
    largest_loss = Column(Float, default=0.0)
    avg_trade_duration = Column(Float, default=0.0)  # in minutes

    # Risk/Reward
    avg_rr_ratio = Column(Float, default=0.0)
    expectancy = Column(Float, default=0.0)

    # Equity curve data (JSON array of {timestamp, equity} objects)
    equity_curve = Column(JSON, nullable=True)

    # Drawdown curve data
    drawdown_curve = Column(JSON, nullable=True)

    # Daily P&L data
    daily_pnl = Column(JSON, nullable=True)

    # Monthly breakdown
    monthly_returns = Column(JSON, nullable=True)

    # ML Stats (JSON with proposed/taken/filtered counts, avg probabilities)
    ml_stats = Column(JSON, nullable=True)
    regime_analysis = Column(JSON, nullable=True)
    microstructure_analysis = Column(JSON, nullable=True)
    walk_forward_report = Column(JSON, nullable=True)  # Full walk-forward diagnostics
    run_manifest = Column(JSON, nullable=True)  # Effective config + code/data fingerprints

    # Data versioning - SHA-256 hash of input DataFrame for reproducibility
    data_hash = Column(String(64), nullable=True)

    # Relationships
    config = relationship("BacktestConfigModel", back_populates="results")
    trades = relationship("BacktestTradeModel", back_populates="result")


class BacktestTradeModel(Base):
    """Stores individual trades from backtests"""
    __tablename__ = "backtest_trades"

    id = Column(Integer, primary_key=True, index=True)
    result_id = Column(Integer, ForeignKey("backtest_results.id"), nullable=False)

    # Trade Details
    trade_number = Column(Integer, nullable=False)
    direction = Column(SQLEnum(TradeDirection), nullable=False)
    status = Column(SQLEnum(TradeStatus), default=TradeStatus.CLOSED)

    # Timestamps
    entry_time = Column(DateTime, nullable=False)
    exit_time = Column(DateTime, nullable=True)

    # Prices
    entry_price = Column(Float, nullable=False)
    exit_price = Column(Float, nullable=True)
    stop_loss = Column(Float, nullable=False)
    take_profit = Column(Float, nullable=True)

    # Position
    lot_size = Column(Float, nullable=False)

    # Results
    profit_loss = Column(Float, default=0.0)
    profit_loss_pips = Column(Float, default=0.0)
    profit_loss_percent = Column(Float, default=0.0)

    # R-Multiple
    r_multiple = Column(Float, default=0.0)

    # Trade Context
    setup_type = Column(String(100), nullable=True)  # e.g., "Bullish FVG + ORB Breakout"
    bias = Column(String(20), nullable=True)  # bullish/bearish/neutral

    # Session Levels at time of trade
    orb_high = Column(Float, nullable=True)
    orb_low = Column(Float, nullable=True)
    asian_high = Column(Float, nullable=True)
    asian_low = Column(Float, nullable=True)
    pd_high = Column(Float, nullable=True)
    pd_low = Column(Float, nullable=True)

    # ICT Pattern Details
    fvg_size = Column(Float, nullable=True)
    fvg_top = Column(Float, nullable=True)
    fvg_bottom = Column(Float, nullable=True)
    ob_high = Column(Float, nullable=True)
    ob_low = Column(Float, nullable=True)

    # Exit Reason
    exit_reason = Column(String(50), nullable=True)  # TP, SL, Trailing, Manual, etc.

    # Strategy Diagnostics
    entry_reason = Column(JSON, nullable=True)  # Strategy metadata at entry
    gross_pnl = Column(Float, nullable=True)
    spread_cost = Column(Float, nullable=True)
    slippage_cost = Column(Float, nullable=True)
    commission_cost = Column(Float, nullable=True)
    swap_cost = Column(Float, nullable=True)

    # Balance at time of trade
    balance_before = Column(Float, nullable=True)
    balance_after = Column(Float, nullable=True)

    # ML Data
    ml_features = Column(JSON, nullable=True)  # Feature vector at entry
    ml_win_probability = Column(Float, nullable=True)  # ML predicted win prob
    max_favorable_excursion = Column(Float, nullable=True)  # MFE in R-multiples
    max_adverse_excursion = Column(Float, nullable=True)  # MAE in R-multiples

    # Relationships
    result = relationship("BacktestResultModel", back_populates="trades")


class LiveTradeModel(Base):
    """Stores live/demo trades from the bot"""
    __tablename__ = "live_trades"

    id = Column(Integer, primary_key=True, index=True)
    ticket = Column(Integer, unique=True, nullable=False)

    # Trade Details
    direction = Column(SQLEnum(TradeDirection), nullable=False)
    status = Column(SQLEnum(TradeStatus), default=TradeStatus.OPEN)

    # Timestamps
    entry_time = Column(DateTime, nullable=False)
    exit_time = Column(DateTime, nullable=True)

    # Prices
    entry_price = Column(Float, nullable=False)
    exit_price = Column(Float, nullable=True)
    stop_loss = Column(Float, nullable=False)
    take_profit = Column(Float, nullable=True)
    current_price = Column(Float, nullable=True)

    # Position
    symbol = Column(String(20), default="XAUUSD")
    lot_size = Column(Float, nullable=False)

    # Results
    profit_loss = Column(Float, default=0.0)
    commission = Column(Float, default=0.0)
    swap = Column(Float, default=0.0)

    # Trade Context
    setup_type = Column(String(100), nullable=True)
    comment = Column(String(255), nullable=True)

    # Account Info
    balance_before = Column(Float, nullable=True)
    equity_at_entry = Column(Float, nullable=True)

    # Execution quality fields
    intended_entry_price = Column(Float, nullable=True)
    actual_entry_price = Column(Float, nullable=True)
    intended_exit_price = Column(Float, nullable=True)
    actual_exit_price = Column(Float, nullable=True)
    spread_at_entry = Column(Float, nullable=True)
    spread_at_exit = Column(Float, nullable=True)
    slippage_entry = Column(Float, nullable=True)
    slippage_exit = Column(Float, nullable=True)

    # ML features for online learning / retrain from live data
    ml_features = Column(JSON, nullable=True)
    ml_win_probability = Column(Float, nullable=True)
    max_favorable_excursion = Column(Float, nullable=True)
    max_adverse_excursion = Column(Float, nullable=True)


class DailyPerformanceModel(Base):
    """Stores daily performance summaries"""
    __tablename__ = "daily_performance"

    id = Column(Integer, primary_key=True, index=True)
    date = Column(DateTime, unique=True, nullable=False)

    # Trade counts
    total_trades = Column(Integer, default=0)
    winning_trades = Column(Integer, default=0)
    losing_trades = Column(Integer, default=0)

    # Financial
    starting_balance = Column(Float, default=0.0)
    ending_balance = Column(Float, default=0.0)
    gross_profit = Column(Float, default=0.0)
    gross_loss = Column(Float, default=0.0)
    net_pnl = Column(Float, default=0.0)

    # Session Data
    orb_high = Column(Float, nullable=True)
    orb_low = Column(Float, nullable=True)
    bias = Column(String(20), nullable=True)
    is_trending = Column(Boolean, default=True)


class MLModelRecord(Base):
    """Tracks trained ML models"""
    __tablename__ = "ml_models"

    id = Column(Integer, primary_key=True, index=True)
    strategy_id = Column(String(50), nullable=False)  # e.g., "orb_strategy"
    symbol = Column(String(20), nullable=False, default="XAUUSD")  # Scoped to symbol
    timeframe = Column(String(10), nullable=False, default="M1")  # Scoped to timeframe
    model_type = Column(String(20), nullable=False, default="xgboost")  # xgboost, lightgbm, lstm, cnn, ensemble
    base_result_id = Column(Integer, nullable=True)  # Backtest result used for training
    trained_at = Column(DateTime, default=datetime.utcnow)

    # Training data stats
    total_trades = Column(Integer, default=0)
    winning_trades = Column(Integer, default=0)
    losing_trades = Column(Integer, default=0)

    # Walk-forward validation metrics (averaged across folds)
    avg_accuracy = Column(Float, default=0.0)
    avg_precision = Column(Float, default=0.0)
    avg_recall = Column(Float, default=0.0)
    avg_f1 = Column(Float, default=0.0)
    avg_auc_roc = Column(Float, default=0.0)
    avg_rr_mae = Column(Float, default=0.0)
    avg_rr_r2 = Column(Float, default=0.0)

    # Feature importance (JSON: {feature_name: importance_score})
    feature_importance = Column(JSON, nullable=True)

    # Model file paths
    filter_model_path = Column(String(500), nullable=True)
    rr_model_path = Column(String(500), nullable=True)
    metadata_path = Column(String(500), nullable=True)

    # Walk-forward fold details (JSON array)
    folds = Column(JSON, nullable=True)


class RetrainingLogModel(Base):
    """Tracks automated ML model retraining attempts"""
    __tablename__ = "retraining_logs"

    id = Column(Integer, primary_key=True, index=True)
    model_id = Column(Integer, nullable=False)
    strategy_id = Column(String(50), nullable=False)
    symbol = Column(String(20), nullable=True)
    timeframe = Column(String(10), nullable=True)
    model_type = Column(String(20), nullable=True)

    triggered_at = Column(DateTime, default=datetime.utcnow)
    completed_at = Column(DateTime, nullable=True)
    trigger_type = Column(String(20), default="scheduled")  # "scheduled" or "manual"

    old_auc_roc = Column(Float, nullable=True)
    new_auc_roc = Column(Float, nullable=True)
    old_accuracy = Column(Float, nullable=True)
    new_accuracy = Column(Float, nullable=True)

    accepted = Column(Boolean, default=False)
    new_model_id = Column(Integer, nullable=True)

    error_message = Column(Text, nullable=True)
    status = Column(String(20), default="pending")  # pending, running, completed, failed


class RLOnlineLogModel(Base):
    """Tracks RL online learning updates from live trading"""
    __tablename__ = "rl_online_logs"

    id = Column(Integer, primary_key=True, index=True)
    updated_at = Column(DateTime, default=datetime.utcnow)
    experiences_count = Column(Integer, default=0)
    avg_reward = Column(Float, default=0.0)
    model_path = Column(String(500), nullable=True)
    backup_path = Column(String(500), nullable=True)
    status = Column(String(20), default="success")  # success, rollback, error


class OptionsEdgeScanRunModel(Base):
    """Stores one options-edge universe scan run."""
    __tablename__ = "options_scan_runs"

    scan_id = Column(String(64), primary_key=True, index=True)
    scan_ts = Column(DateTime, default=datetime.utcnow, index=True)
    status = Column(String(20), default="COMPLETED")
    error = Column(Text, nullable=True)

    universe_size = Column(Integer, default=0)
    passed_gate_count = Column(Integer, default=0)
    selected_count = Column(Integer, default=0)
    top_n = Column(Integer, default=8)
    max_sector_fraction = Column(Float, default=0.35)

    gate_config = Column(JSON, nullable=True)
    score_config = Column(JSON, nullable=True)
    summary_json = Column(JSON, nullable=True)

    llm_model = Column(String(100), nullable=True)
    llm_cost_usd = Column(Float, default=0.0)
    latency_sec = Column(Float, default=0.0)

    snapshots = relationship("OptionsEdgeStockSnapshotModel", back_populates="scan_run")
    scores = relationship("OptionsEdgeCandidateScoreModel", back_populates="scan_run")
    trade_candidates = relationship("OptionsEdgeTradeCandidateModel", back_populates="scan_run")


class OptionsEdgeStockSnapshotModel(Base):
    """Per-symbol snapshot captured during options-edge scan."""
    __tablename__ = "options_stock_snapshots"

    id = Column(Integer, primary_key=True, index=True)
    scan_id = Column(String(64), ForeignKey("options_scan_runs.scan_id"), nullable=False, index=True)

    symbol = Column(String(20), nullable=False, index=True)
    sector = Column(String(80), nullable=True)
    price = Column(Float, nullable=True)

    iv30 = Column(Float, nullable=True)
    hv30 = Column(Float, nullable=True)
    iv_rank_252 = Column(Float, nullable=True)
    iv_hv_spread = Column(Float, nullable=True)

    avg_opt_volume_30d = Column(Float, nullable=True)
    avg_oi_30d = Column(Float, nullable=True)
    avg_bid_ask_pct = Column(Float, nullable=True)

    earnings_date = Column(String(20), nullable=True)
    days_to_earnings = Column(Float, nullable=True)
    borrow_rate = Column(Float, nullable=True)

    gate_pass = Column(Boolean, default=False)
    gate_reasons = Column(JSON, nullable=True)

    scan_run = relationship("OptionsEdgeScanRunModel", back_populates="snapshots")


class OptionsEdgeCandidateScoreModel(Base):
    """Per-symbol deterministic score for options-edge scan."""
    __tablename__ = "options_candidate_scores"

    id = Column(Integer, primary_key=True, index=True)
    scan_id = Column(String(64), ForeignKey("options_scan_runs.scan_id"), nullable=False, index=True)

    symbol = Column(String(20), nullable=False, index=True)
    sector = Column(String(80), nullable=True)
    rank_global = Column(Integer, nullable=True)
    rank_in_sector = Column(Integer, nullable=True)
    selected = Column(Boolean, default=False)

    score_total = Column(Float, default=0.0)
    score_vol_edge = Column(Float, default=0.0)
    score_liquidity = Column(Float, default=0.0)
    score_event_timing = Column(Float, default=0.0)
    score_risk = Column(Float, default=0.0)
    penalty_sector_concentration = Column(Float, default=0.0)
    builder_status = Column(String(20), nullable=True)  # built / rejected / skipped
    builder_policy = Column(String(80), nullable=True)
    builder_reasons = Column(JSON, nullable=True)

    scan_run = relationship("OptionsEdgeScanRunModel", back_populates="scores")


class OptionsEdgeTradeCandidateModel(Base):
    """Constructed options strategies for selected symbols (Phase 2+)."""
    __tablename__ = "options_trade_candidates"

    id = Column(Integer, primary_key=True, index=True)
    scan_id = Column(String(64), ForeignKey("options_scan_runs.scan_id"), nullable=False, index=True)

    symbol = Column(String(20), nullable=False, index=True)
    structure_type = Column(String(40), nullable=False)
    expiry_date = Column(String(20), nullable=True)
    dte = Column(Integer, nullable=True)

    legs_json = Column(JSON, nullable=True)
    net_credit = Column(Float, nullable=True)
    max_profit = Column(Float, nullable=True)
    max_loss = Column(Float, nullable=True)
    pop_est = Column(Float, nullable=True)
    delta_net = Column(Float, nullable=True)
    theta_net = Column(Float, nullable=True)
    vega_net = Column(Float, nullable=True)
    breakeven_low = Column(Float, nullable=True)
    breakeven_high = Column(Float, nullable=True)
    quality_flags = Column(JSON, nullable=True)

    scan_run = relationship("OptionsEdgeScanRunModel", back_populates="trade_candidates")


class OptionsEdgeBacktestRunModel(Base):
    """Stores options-edge Phase 3 backtest/walk-forward runs."""
    __tablename__ = "options_backtest_runs"

    run_id = Column(String(64), primary_key=True, index=True)
    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    status = Column(String(20), default="COMPLETED")
    error = Column(Text, nullable=True)

    scans_used = Column(Integer, default=0)
    trades_simulated = Column(Integer, default=0)

    initial_balance = Column(Float, default=0.0)
    final_balance = Column(Float, default=0.0)
    net_profit = Column(Float, default=0.0)
    win_rate = Column(Float, default=0.0)
    profit_factor = Column(Float, default=0.0)
    max_drawdown_pct = Column(Float, default=0.0)
    sharpe_ratio = Column(Float, default=0.0)

    request_json = Column(JSON, nullable=True)
    metrics_json = Column(JSON, nullable=True)
    walk_forward_json = Column(JSON, nullable=True)
    stress_json = Column(JSON, nullable=True)
    equity_curve_json = Column(JSON, nullable=True)
    trade_log_json = Column(JSON, nullable=True)
    notes_json = Column(JSON, nullable=True)


class OptionsEdgeTradeJournalModel(Base):
    """Manual journal for options-edge trade lifecycle tracking."""
    __tablename__ = "options_trade_journal"

    id = Column(Integer, primary_key=True, index=True)
    journal_id = Column(String(64), unique=True, nullable=False, index=True)
    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    closed_at = Column(DateTime, nullable=True, index=True)
    status = Column(String(20), default="OPEN", index=True)  # OPEN, CLOSED, EXPIRED, CANCELLED

    scan_id = Column(String(64), nullable=True, index=True)
    trade_candidate_id = Column(Integer, nullable=True, index=True)

    symbol = Column(String(20), nullable=False, index=True)
    structure_type = Column(String(40), nullable=False)
    legs_json = Column(JSON, nullable=True)
    entry_credit = Column(Float, nullable=True)
    max_profit = Column(Float, nullable=True)
    max_loss = Column(Float, nullable=True)
    pop_est = Column(Float, nullable=True)
    expiry_date = Column(String(20), nullable=True)
    dte_at_entry = Column(Integer, nullable=True)

    contracts = Column(Integer, default=1)
    account_balance_at_entry = Column(Float, nullable=True)
    risk_pct_at_entry = Column(Float, nullable=True)
    portfolio_scope_key = Column(String(255), nullable=True, index=True)
    portfolio_scope_profile = Column(String(64), nullable=True)
    portfolio_scope_broker = Column(String(128), nullable=True)
    portfolio_scope_account_login = Column(String(64), nullable=True)
    portfolio_scope_account_server = Column(String(128), nullable=True)

    exit_credit = Column(Float, nullable=True)
    actual_pnl = Column(Float, nullable=True)       # per contract
    actual_pnl_total = Column(Float, nullable=True)  # total across contracts
    exit_reason = Column(String(40), nullable=True)
    hold_days = Column(Integer, nullable=True)
    notes = Column(Text, nullable=True)


class CSPScreenRunModel(Base):
    """Tracks each CSP universe/fundamental screening run."""
    __tablename__ = "csp_screen_runs"

    id = Column(Integer, primary_key=True, index=True)
    run_date = Column(DateTime, default=datetime.utcnow, index=True)
    total_symbols_screened = Column(Integer, default=0)
    candidates_passed = Column(Integer, default=0)
    config_json = Column(JSON, nullable=True)
    summary_json = Column(JSON, nullable=True)

    candidates = relationship("CSPCandidateModel", back_populates="screen_run")


class CSPCandidateModel(Base):
    """Symbols that pass CSP screening constraints."""
    __tablename__ = "csp_candidates"

    id = Column(Integer, primary_key=True, index=True)
    screen_run_id = Column(Integer, ForeignKey("csp_screen_runs.id"), nullable=False, index=True)
    symbol = Column(String(20), nullable=False, index=True)
    sector = Column(String(80), nullable=True)
    industry = Column(String(120), nullable=True)
    fundamentals_json = Column(JSON, nullable=True)
    iv_rank = Column(Float, nullable=True)
    option_volume = Column(Float, nullable=True)
    regime = Column(String(20), nullable=True)
    pe_current = Column(Float, nullable=True)
    pe_5y_avg = Column(Float, nullable=True)
    pe_10y_avg = Column(Float, nullable=True)
    price_vs_sma200 = Column(Float, nullable=True)
    gate_reasons = Column(JSON, nullable=True)

    screen_run = relationship("CSPScreenRunModel", back_populates="candidates")


class CSPTradeModel(Base):
    """CSP trade lifecycle records (open, roll, assignment, close)."""
    __tablename__ = "csp_trades"

    id = Column(Integer, primary_key=True, index=True)
    backtest_run_id = Column(Integer, ForeignKey("csp_backtest_runs.id"), nullable=True, index=True)
    symbol = Column(String(20), nullable=False, index=True)
    state = Column(String(32), nullable=False, default="OPEN_CSP", index=True)
    open_date = Column(Date, nullable=True, index=True)
    expiry_date = Column(Date, nullable=True, index=True)
    strike = Column(Float, nullable=True)
    premium_received = Column(Float, nullable=True)
    cash_secured = Column(Float, nullable=True)
    yield_pct = Column(Float, nullable=True)
    delta_at_open = Column(Float, nullable=True)
    iv_at_open = Column(Float, nullable=True)
    regime = Column(String(20), nullable=True)
    current_value = Column(Float, nullable=True)
    close_date = Column(Date, nullable=True)
    close_reason = Column(String(40), nullable=True)
    total_premium_collected = Column(Float, nullable=True)
    rolls_json = Column(JSON, nullable=True)
    assignment_cost = Column(Float, nullable=True)
    shares_assigned = Column(Integer, default=0)
    realized_pnl = Column(Float, nullable=True)
    metadata_json = Column(JSON, nullable=True)


class CSPBacktestRunModel(Base):
    """CSP lifecycle backtest run and aggregated outputs."""
    __tablename__ = "csp_backtest_runs"

    id = Column(Integer, primary_key=True, index=True)
    run_date = Column(DateTime, default=datetime.utcnow, index=True)
    start_date = Column(Date, nullable=True)
    end_date = Column(Date, nullable=True)
    initial_capital = Column(Float, nullable=True)
    final_capital = Column(Float, nullable=True)
    status = Column(String(20), default="COMPLETED", index=True)
    error = Column(Text, nullable=True)
    config_json = Column(JSON, nullable=True)
    results_json = Column(JSON, nullable=True)
    equity_curve_json = Column(JSON, nullable=True)
    trades_json = Column(JSON, nullable=True)


class AIBotRunModel(Base):
    """Generic persisted AI bot run for strategy contexts (phase-1 control plane)."""
    __tablename__ = "ai_bot_runs"

    run_id = Column(String(64), primary_key=True, index=True)
    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    status = Column(String(20), default="COMPLETED", index=True)  # COMPLETED | FAILED

    strategy_id = Column(String(80), nullable=False, index=True)  # e.g. options_edge
    context_id = Column(String(80), nullable=False, index=True)   # e.g. scan_id

    provider = Column(String(80), nullable=False, default="deterministic")
    model_label = Column(String(120), nullable=True)

    request_json = Column(JSON, nullable=True)
    report_json = Column(JSON, nullable=True)
    execution_plan_json = Column(JSON, nullable=True)
    notes_json = Column(JSON, nullable=True)
    error = Column(Text, nullable=True)


class SimulationSession(Base):
    """Tracks interactive trading simulation sessions."""
    __tablename__ = "simulation_sessions"
    id = Column(Integer, primary_key=True, index=True)
    strategy_id = Column(String(50), nullable=False, index=True)
    symbol = Column(String(20), nullable=False)
    timeframe = Column(String(10), nullable=False)
    mode = Column(String(10), default="replay")  # replay | live
    data_file = Column(String(255), nullable=True)
    current_bar = Column(Integer, default=0)
    total_bars = Column(Integer, default=0)
    initial_balance = Column(Float, default=10000.0)
    current_balance = Column(Float, default=10000.0)
    total_pnl = Column(Float, default=0.0)
    trades_count = Column(Integer, default=0)
    wins = Column(Integer, default=0)
    losses = Column(Integer, default=0)
    status = Column(String(20), default="active")  # active | completed
    config_json = Column(Text, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    sim_trades = relationship("SimulationTrade", back_populates="session")


class SimulationTrade(Base):
    """Individual trades within a simulation session."""
    __tablename__ = "simulation_trades"
    id = Column(Integer, primary_key=True, index=True)
    session_id = Column(Integer, ForeignKey("simulation_sessions.id"), nullable=False, index=True)
    direction = Column(String(4), nullable=False)  # BUY | SELL
    entry_price = Column(Float, nullable=False)
    entry_bar = Column(Integer, nullable=False)
    entry_time = Column(String(30), nullable=True)
    stop_loss = Column(Float, nullable=False)
    take_profit = Column(Float, nullable=True)
    lot_size = Column(Float, default=0.01)
    entry_mid_price = Column(Float, nullable=True)
    entry_fill_price = Column(Float, nullable=True)
    spread_value = Column(Float, nullable=True)
    tc_rate = Column(Float, nullable=True)
    exit_price = Column(Float, nullable=True)
    exit_mid_price = Column(Float, nullable=True)
    exit_fill_price = Column(Float, nullable=True)
    exit_bar = Column(Integer, nullable=True)
    exit_time = Column(String(30), nullable=True)
    exit_reason = Column(String(50), nullable=True)
    raw_pnl = Column(Float, nullable=True)
    spread_cost = Column(Float, nullable=True)
    turnover_cost = Column(Float, nullable=True)
    total_cost = Column(Float, nullable=True)
    cost_breakdown_json = Column(JSON, nullable=True)
    pnl = Column(Float, nullable=True)
    r_multiple = Column(Float, nullable=True)
    status = Column(String(10), default="open")  # open | closed
    created_at = Column(DateTime, default=datetime.utcnow)

    session = relationship("SimulationSession", back_populates="sim_trades")


class StrategyAutomationLogModel(Base):
    """Durable per-automation telemetry/event log rows for analysis/debug."""
    __tablename__ = "strategy_automation_logs"

    id = Column(Integer, primary_key=True, index=True)
    parent_session_id = Column(Integer, ForeignKey("simulation_sessions.id"), nullable=True, index=True)
    child_session_id = Column(Integer, ForeignKey("simulation_sessions.id"), nullable=False, index=True)
    job_id = Column(String(80), nullable=False, index=True)
    strategy = Column(String(50), nullable=False, index=True)
    mode = Column(String(32), nullable=False, index=True)
    symbol = Column(String(20), nullable=False, index=True)
    timeframe = Column(String(10), nullable=False, index=True)
    event_type = Column(String(24), nullable=False, index=True)  # major | routine | future
    event_name = Column(String(80), nullable=False, index=True)
    trade_id = Column(Integer, nullable=True, index=True)
    direction = Column(String(8), nullable=True, index=True)
    event_time = Column(DateTime, nullable=True, index=True)
    payload_json = Column(JSON, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, index=True)


class TradingSimulationSessionModel(Base):
    """Guided trading simulation control-plane session."""
    __tablename__ = "trading_simulation_sessions"
    id = Column(Integer, primary_key=True, index=True)
    session_uid = Column(String(64), unique=True, nullable=False, index=True)
    strategy_id = Column(String(80), nullable=False, index=True)
    symbol = Column(String(20), nullable=False)
    timeframe = Column(String(10), nullable=False)
    mode = Column(String(12), default="demo")  # demo | live
    status = Column(String(20), default="ACTIVE")  # ACTIVE | ENDED
    current_step_id = Column(String(80), nullable=True)
    current_step_status = Column(String(20), default="WAIT")
    telemetry_json = Column(JSON, nullable=True)
    step_states_json = Column(JSON, nullable=True)
    summary_json = Column(JSON, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    ended_at = Column(DateTime, nullable=True)

    events = relationship("TradingSimulationEventModel", back_populates="session")
    actions = relationship("TradingSimulationActionModel", back_populates="session")


class TradingSimulationEventModel(Base):
    """Session-level events for observability/audit."""
    __tablename__ = "trading_simulation_events"
    id = Column(Integer, primary_key=True, index=True)
    session_id = Column(Integer, ForeignKey("trading_simulation_sessions.id"), nullable=False, index=True)
    event_type = Column(String(80), nullable=False, index=True)
    payload_json = Column(JSON, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    session = relationship("TradingSimulationSessionModel", back_populates="events")


class TradingSimulationActionModel(Base):
    """User actions during guided simulation (journal/checklist)."""
    __tablename__ = "trading_simulation_actions"
    id = Column(Integer, primary_key=True, index=True)
    session_id = Column(Integer, ForeignKey("trading_simulation_sessions.id"), nullable=False, index=True)
    action_type = Column(String(50), nullable=False, index=True)
    step_id = Column(String(80), nullable=True)
    note = Column(Text, nullable=True)
    payload_json = Column(JSON, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    session = relationship("TradingSimulationSessionModel", back_populates="actions")


class WorkbenchCopilotSessionModel(Base):
    """Always-on copilot loop session for Workbench simulation."""
    __tablename__ = "workbench_copilot_sessions"
    id = Column(Integer, primary_key=True, index=True)
    simulation_session_id = Column(Integer, ForeignKey("simulation_sessions.id"), nullable=False, index=True)
    mode = Column(String(20), default="ADVISE", index=True)  # OBSERVE | ADVISE | ASSIST | AUTO_PAPER
    status = Column(String(20), default="ACTIVE", index=True)  # ACTIVE | STOPPED
    provider = Column(String(80), default="deterministic")
    model_label = Column(String(120), nullable=True)
    config_json = Column(JSON, nullable=True)
    last_snapshot_json = Column(JSON, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    stopped_at = Column(DateTime, nullable=True)

    events = relationship("WorkbenchCopilotEventModel", back_populates="copilot_session")
    advices = relationship("WorkbenchCopilotAdviceModel", back_populates="copilot_session")
    actions = relationship("WorkbenchCopilotActionModel", back_populates="copilot_session")


class WorkbenchCopilotEventModel(Base):
    """Event stream generated by copilot loop."""
    __tablename__ = "workbench_copilot_events"
    id = Column(Integer, primary_key=True, index=True)
    copilot_session_id = Column(Integer, ForeignKey("workbench_copilot_sessions.id"), nullable=False, index=True)
    event_type = Column(String(80), nullable=False, index=True)
    severity = Column(String(20), default="info", index=True)
    payload_json = Column(JSON, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, index=True)

    copilot_session = relationship("WorkbenchCopilotSessionModel", back_populates="events")


class WorkbenchCopilotAdviceModel(Base):
    """Advice outputs generated by copilot from events."""
    __tablename__ = "workbench_copilot_advices"
    id = Column(Integer, primary_key=True, index=True)
    copilot_session_id = Column(Integer, ForeignKey("workbench_copilot_sessions.id"), nullable=False, index=True)
    event_id = Column(Integer, ForeignKey("workbench_copilot_events.id"), nullable=True, index=True)
    advice_type = Column(String(80), nullable=False, index=True)
    summary = Column(Text, nullable=False)
    confidence = Column(Float, nullable=True)
    source_event_priority = Column(Integer, default=0, index=True)
    delivery = Column(String(20), default="ACTIONABLE", index=True)  # ACTIONABLE | WATCH | SUPPRESS
    evidence_json = Column(JSON, nullable=True)
    action_json = Column(JSON, nullable=True)
    status = Column(String(20), default="NEW", index=True)  # NEW | ACKNOWLEDGED | REJECTED | EXECUTED
    created_at = Column(DateTime, default=datetime.utcnow, index=True)

    copilot_session = relationship("WorkbenchCopilotSessionModel", back_populates="advices")


class WorkbenchCopilotActionModel(Base):
    """Actions/audits for user or copilot responses."""
    __tablename__ = "workbench_copilot_actions"
    id = Column(Integer, primary_key=True, index=True)
    copilot_session_id = Column(Integer, ForeignKey("workbench_copilot_sessions.id"), nullable=False, index=True)
    advice_id = Column(Integer, ForeignKey("workbench_copilot_advices.id"), nullable=True, index=True)
    action_type = Column(String(80), nullable=False, index=True)
    payload_json = Column(JSON, nullable=True)
    note = Column(Text, nullable=True)
    requested_by = Column(String(20), default="USER", index=True)  # USER | COPILOT
    status = Column(String(20), default="PROPOSED", index=True)  # PROPOSED | APPROVED | REJECTED | EXECUTED
    created_at = Column(DateTime, default=datetime.utcnow, index=True)

    copilot_session = relationship("WorkbenchCopilotSessionModel", back_populates="actions")


class WorkbenchCopilotSnapshotModel(Base):
    """Compact per-iteration snapshots for replayable copilot context."""
    __tablename__ = "workbench_copilot_snapshots"
    id = Column(Integer, primary_key=True, index=True)
    copilot_session_id = Column(Integer, ForeignKey("workbench_copilot_sessions.id"), nullable=False, index=True)
    bar_index = Column(Integer, nullable=False, index=True)
    source = Column(String(40), default="advance", index=True)  # advance | seek | reset | tool_scan | manual
    snapshot_json = Column(JSON, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, index=True)


class WorkbenchCopilotJobModel(Base):
    """Async LLM job queue for workbench copilot advice generation."""
    __tablename__ = "workbench_copilot_jobs"
    id = Column(Integer, primary_key=True, index=True)
    copilot_session_id = Column(Integer, ForeignKey("workbench_copilot_sessions.id"), nullable=False, index=True)
    simulation_session_id = Column(Integer, nullable=False, index=True)
    job_type = Column(String(40), default="ADVICE_GENERATION", index=True)
    status = Column(String(20), default="PENDING", index=True)  # PENDING | RUNNING | COMPLETED | APPLIED | FAILED | CANCELLED
    priority = Column(Integer, default=50, index=True)
    payload_json = Column(JSON, nullable=True)
    result_json = Column(JSON, nullable=True)
    error = Column(Text, nullable=True)
    attempts = Column(Integer, default=0)
    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    started_at = Column(DateTime, nullable=True)
    finished_at = Column(DateTime, nullable=True)


class WorkbenchAgentSessionModel(Base):
    """Unified agent control-plane session for Workbench."""
    __tablename__ = "workbench_agent_sessions"
    id = Column(Integer, primary_key=True, index=True)
    simulation_session_id = Column(Integer, ForeignKey("simulation_sessions.id"), nullable=False, index=True)
    copilot_session_id = Column(Integer, ForeignKey("workbench_copilot_sessions.id"), nullable=True, index=True)
    mode = Column(String(20), default="LOOP", index=True)  # CHAT | RUN_ONCE | LOOP
    status = Column(String(20), default="ACTIVE", index=True)  # ACTIVE | STOPPED
    provider = Column(String(80), default="deterministic", index=True)
    model_label = Column(String(120), nullable=True)
    permissions_json = Column(JSON, nullable=True)
    config_json = Column(JSON, nullable=True)
    runtime_json = Column(JSON, nullable=True)
    last_snapshot_json = Column(JSON, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, index=True)
    stopped_at = Column(DateTime, nullable=True)

    events = relationship("WorkbenchAgentEventModel", back_populates="agent_session")
    actions = relationship("WorkbenchAgentActionModel", back_populates="agent_session")
    snapshots = relationship("WorkbenchAgentSnapshotModel", back_populates="agent_session")


class WorkbenchAgentEventModel(Base):
    """Agent event stream for auditing and debugging."""
    __tablename__ = "workbench_agent_events"
    id = Column(Integer, primary_key=True, index=True)
    agent_session_id = Column(Integer, ForeignKey("workbench_agent_sessions.id"), nullable=False, index=True)
    event_type = Column(String(80), nullable=False, index=True)
    severity = Column(String(20), default="info", index=True)
    payload_json = Column(JSON, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, index=True)

    agent_session = relationship("WorkbenchAgentSessionModel", back_populates="events")


class WorkbenchAgentActionModel(Base):
    """Agent action/audit records with optional link to copilot action rows."""
    __tablename__ = "workbench_agent_actions"
    id = Column(Integer, primary_key=True, index=True)
    agent_session_id = Column(Integer, ForeignKey("workbench_agent_sessions.id"), nullable=False, index=True)
    copilot_action_id = Column(Integer, ForeignKey("workbench_copilot_actions.id"), nullable=True, index=True)
    action_type = Column(String(80), nullable=False, index=True)
    status = Column(String(24), default="PROPOSED", index=True)  # PROPOSED | APPROVED | REJECTED | EXECUTED | BLOCKED_POLICY | FAILED
    requested_by = Column(String(20), default="USER", index=True)  # USER | AGENT
    reason = Column(Text, nullable=True)
    payload_json = Column(JSON, nullable=True)
    result_json = Column(JSON, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, index=True)

    agent_session = relationship("WorkbenchAgentSessionModel", back_populates="actions")


class WorkbenchAgentSnapshotModel(Base):
    """Compact snapshots from agent-facing flows."""
    __tablename__ = "workbench_agent_snapshots"
    id = Column(Integer, primary_key=True, index=True)
    agent_session_id = Column(Integer, ForeignKey("workbench_agent_sessions.id"), nullable=False, index=True)
    bar_index = Column(Integer, nullable=False, index=True)
    source = Column(String(40), default="external", index=True)  # start | stop | chat | run_once | tool_state | action | state
    snapshot_json = Column(JSON, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, index=True)

    agent_session = relationship("WorkbenchAgentSessionModel", back_populates="snapshots")


class WorkbenchAgentMemoryModel(Base):
    """Durable long-term memory notes for unified Workbench Agent."""
    __tablename__ = "workbench_agent_memories"
    id = Column(Integer, primary_key=True, index=True)
    simulation_session_id = Column(Integer, ForeignKey("simulation_sessions.id"), nullable=True, index=True)
    scope = Column(String(20), default="SESSION", index=True)  # GLOBAL | SESSION | SYMBOL
    symbol = Column(String(32), nullable=True, index=True)
    timeframe = Column(String(16), nullable=True, index=True)
    memory_type = Column(String(40), default="note", index=True)
    content = Column(Text, nullable=False)
    metadata_json = Column(JSON, nullable=True)
    pinned = Column(Boolean, default=False)
    importance = Column(Float, default=0.5)
    source = Column(String(32), default="user")
    fingerprint = Column(String(64), nullable=False)
    access_count = Column(Integer, default=0)
    last_accessed_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, index=True)


class TelegramAutomationExecutionLogModel(Base):
    """Persistent execution audit rows for telegram + indicator automations."""
    __tablename__ = "telegram_automation_execution_logs"

    id = Column(Integer, primary_key=True, index=True)
    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    event_ts = Column(DateTime, nullable=True, index=True)

    source_type = Column(String(40), nullable=False, default="unknown", index=True)
    source_name = Column(String(160), nullable=False, default="unknown", index=True)
    trigger = Column(String(64), nullable=False, default="unknown", index=True)
    status = Column(String(24), nullable=False, default="unknown", index=True)

    symbol = Column(String(32), nullable=True, index=True)
    timeframe = Column(String(16), nullable=True, index=True)
    direction = Column(String(16), nullable=True, index=True)
    lot = Column(Float, nullable=True)
    stop_loss = Column(Float, nullable=True)
    final_tp = Column(Float, nullable=True)
    stages_total = Column(Integer, nullable=True)
    stages_opened = Column(Integer, nullable=True)
    ticket = Column(Integer, nullable=True, index=True)

    profile = Column(String(40), nullable=True, index=True)
    indicator = Column(String(120), nullable=True, index=True)
    source_tag = Column(String(80), nullable=True, index=True)
    message = Column(Text, nullable=True)
    extra_json = Column(JSON, nullable=True)


def get_db():
    """Dependency for getting database sessions"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db():
    """Initialize database tables"""
    # Data directory is already created at module import time
    Base.metadata.create_all(bind=engine)

    # Run migrations for new columns (SQLite ALTER TABLE)
    _run_migrations()

    print(f"Database initialized at: {DATABASE_PATH}")


def _run_migrations():
    """Add new columns to existing tables (safe to run multiple times)"""
    import sqlite3
    conn = sqlite3.connect(str(DATABASE_PATH))
    cursor = conn.cursor()

    migrations = [
        ("backtest_configs", "data_source", "TEXT DEFAULT 'auto'"),
        ("backtest_configs", "csv_files", "TEXT"),
        ("ml_models", "model_type", "TEXT DEFAULT 'xgboost'"),
        ("ml_models", "symbol", "TEXT DEFAULT 'XAUUSD'"),
        ("ml_models", "timeframe", "TEXT DEFAULT 'M1'"),
        ("backtest_configs", "ml_model_id", "INTEGER"),
        # Execution quality fields for live trades
        ("live_trades", "intended_entry_price", "REAL"),
        ("live_trades", "actual_entry_price", "REAL"),
        ("live_trades", "intended_exit_price", "REAL"),
        ("live_trades", "actual_exit_price", "REAL"),
        ("live_trades", "spread_at_entry", "REAL"),
        ("live_trades", "spread_at_exit", "REAL"),
        ("live_trades", "slippage_entry", "REAL"),
        ("live_trades", "slippage_exit", "REAL"),
        # ML features for online learning / retrain from live data
        ("live_trades", "ml_features", "TEXT"),
        ("live_trades", "ml_win_probability", "REAL"),
        ("live_trades", "max_favorable_excursion", "REAL"),
        ("live_trades", "max_adverse_excursion", "REAL"),
        # Preset name for configuration presets per strategy
        ("backtest_configs", "preset_name", "TEXT"),
        # Trade diagnostics for backtest trades
        ("backtest_trades", "entry_reason", "TEXT"),
        ("backtest_trades", "gross_pnl", "REAL"),
        ("backtest_trades", "spread_cost", "REAL"),
        ("backtest_trades", "slippage_cost", "REAL"),
        ("backtest_trades", "commission_cost", "REAL"),
        ("backtest_trades", "swap_cost", "REAL"),
        # Cross-asset regime filter config
        ("backtest_configs", "enable_cross_asset_filter", "BOOLEAN DEFAULT 0"),
        ("backtest_configs", "regime_timeframe", "TEXT DEFAULT 'M15'"),
        ("backtest_configs", "regime_lookback_bars", "INTEGER DEFAULT 96"),
        ("backtest_configs", "regime_return_bars", "INTEGER DEFAULT 8"),
        ("backtest_configs", "regime_signal_threshold", "REAL DEFAULT 0.18"),
        ("backtest_configs", "regime_strong_threshold", "REAL DEFAULT 0.40"),
        ("backtest_configs", "regime_block_countertrend", "BOOLEAN DEFAULT 1"),
        ("backtest_configs", "regime_reduce_size_in_headwind", "BOOLEAN DEFAULT 1"),
        ("backtest_configs", "regime_tailwind_risk_multiplier", "REAL DEFAULT 1.15"),
        ("backtest_configs", "regime_headwind_risk_multiplier", "REAL DEFAULT 0.50"),
        ("backtest_configs", "regime_neutral_risk_multiplier", "REAL DEFAULT 1.00"),
        ("backtest_configs", "regime_symbol_dxy", "TEXT DEFAULT 'DXY,USDX,USDX.i'"),
        ("backtest_configs", "regime_symbol_yield", "TEXT DEFAULT 'US10Y,TNX,US10Y.cash'"),
        ("backtest_configs", "regime_symbol_riskoff", "TEXT DEFAULT 'VIX,VIX.cash,VOLX'"),
        ("backtest_configs", "regime_symbol_riskon", "TEXT DEFAULT 'SPX500,US500,US30'"),
        ("backtest_configs", "regime_weight_dxy", "REAL DEFAULT 0.40"),
        ("backtest_configs", "regime_weight_yield", "REAL DEFAULT 0.35"),
        ("backtest_configs", "regime_weight_riskoff", "REAL DEFAULT 0.15"),
        ("backtest_configs", "regime_weight_riskon", "REAL DEFAULT 0.10"),
        # Backtest analytics
        ("backtest_results", "regime_analysis", "TEXT"),
        ("backtest_results", "microstructure_analysis", "TEXT"),
        ("backtest_results", "walk_forward_report", "TEXT"),
        # Trade limits: stop after first win
        ("backtest_configs", "stop_after_first_win", "BOOLEAN DEFAULT 1"),
        # Data versioning: SHA-256 hash of input DataFrame
        ("backtest_results", "data_hash", "TEXT"),
        # Reproducibility manifest
        ("backtest_results", "run_manifest", "TEXT"),
        # Options edge builder diagnostics
        ("options_candidate_scores", "builder_status", "TEXT"),
        ("options_candidate_scores", "builder_policy", "TEXT"),
        ("options_candidate_scores", "builder_reasons", "TEXT"),
        # Options edge backtest details
        ("options_backtest_runs", "equity_curve_json", "TEXT"),
        ("options_backtest_runs", "trade_log_json", "TEXT"),
        # CSP lifecycle linkage
        ("csp_trades", "backtest_run_id", "INTEGER"),
        # Workbench copilot advice fields
        ("workbench_copilot_advices", "source_event_priority", "INTEGER DEFAULT 0"),
        ("workbench_copilot_advices", "delivery", "TEXT DEFAULT 'ACTIONABLE'"),
        # Simulation trade cost model fields
        ("simulation_trades", "entry_mid_price", "REAL"),
        ("simulation_trades", "entry_fill_price", "REAL"),
        ("simulation_trades", "spread_value", "REAL"),
        ("simulation_trades", "tc_rate", "REAL"),
        ("simulation_trades", "exit_mid_price", "REAL"),
        ("simulation_trades", "exit_fill_price", "REAL"),
        ("simulation_trades", "raw_pnl", "REAL"),
        ("simulation_trades", "spread_cost", "REAL"),
        ("simulation_trades", "turnover_cost", "REAL"),
        ("simulation_trades", "total_cost", "REAL"),
        ("simulation_trades", "cost_breakdown_json", "TEXT"),
        ("workbench_agent_memories", "pinned", "BOOLEAN DEFAULT 0"),
        ("options_trade_journal", "portfolio_scope_key", "TEXT"),
        ("options_trade_journal", "portfolio_scope_profile", "TEXT"),
        ("options_trade_journal", "portfolio_scope_broker", "TEXT"),
        ("options_trade_journal", "portfolio_scope_account_login", "TEXT"),
        ("options_trade_journal", "portfolio_scope_account_server", "TEXT"),
    ]

    # Build a cache of existing columns per table
    existing_cols_cache = {}
    for table, col, col_def in migrations:
        if table not in existing_cols_cache:
            try:
                cursor.execute(f"PRAGMA table_info({table})")
                existing_cols_cache[table] = {row[1] for row in cursor.fetchall()}
            except Exception:
                existing_cols_cache[table] = set()

        if col not in existing_cols_cache[table]:
            try:
                cursor.execute(f"ALTER TABLE {table} ADD COLUMN {col} {col_def}")
                existing_cols_cache[table].add(col)
                print(f"  Migration: Added {table}.{col}")
            except Exception as e:
                print(f"  Migration skip {table}.{col}: {e}")

    conn.commit()

    # Backfill dedicated pinned column from legacy metadata_json flag if present.
    try:
        cursor.execute("PRAGMA table_info(workbench_agent_memories)")
        cols = {str(r[1]) for r in cursor.fetchall()}
        if "pinned" in cols and "metadata_json" in cols:
            cursor.execute(
                """
                SELECT id, metadata_json, pinned
                FROM workbench_agent_memories
                WHERE metadata_json IS NOT NULL
                """
            )
            updates = []
            for rid, meta_raw, pinned_raw in cursor.fetchall():
                try:
                    already = int(pinned_raw or 0)
                except Exception:
                    already = 0
                if already == 1:
                    continue
                meta_obj = None
                if isinstance(meta_raw, str):
                    try:
                        meta_obj = json.loads(meta_raw)
                    except Exception:
                        meta_obj = None
                elif isinstance(meta_raw, dict):
                    meta_obj = meta_raw
                if isinstance(meta_obj, dict) and bool(meta_obj.get("pinned", False)):
                    updates.append((int(rid),))
            if updates:
                cursor.executemany(
                    "UPDATE workbench_agent_memories SET pinned = 1 WHERE id = ?",
                    updates,
                )
                print(f"  Migration: Backfilled pinned flag on {len(updates)} workbench_agent_memories rows")
                conn.commit()
    except Exception as e:
        print(f"  Migration skip workbench_agent_memories pinned backfill: {e}")

    # Table-level migration for options-edge journal.
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS options_trade_journal (
            id INTEGER PRIMARY KEY,
            journal_id TEXT UNIQUE NOT NULL,
            created_at TIMESTAMP,
            closed_at TIMESTAMP,
            status TEXT,
            scan_id TEXT,
            trade_candidate_id INTEGER,
            symbol TEXT NOT NULL,
            structure_type TEXT NOT NULL,
            legs_json TEXT,
            entry_credit REAL,
            max_profit REAL,
            max_loss REAL,
            pop_est REAL,
            expiry_date TEXT,
            dte_at_entry INTEGER,
            contracts INTEGER,
            account_balance_at_entry REAL,
            risk_pct_at_entry REAL,
            portfolio_scope_key TEXT,
            portfolio_scope_profile TEXT,
            portfolio_scope_broker TEXT,
            portfolio_scope_account_login TEXT,
            portfolio_scope_account_server TEXT,
            exit_credit REAL,
            actual_pnl REAL,
            actual_pnl_total REAL,
            exit_reason TEXT,
            hold_days INTEGER,
            notes TEXT
        )
        """
    )
    conn.commit()

    # Idempotent indexes for frequently queried journal fields.
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_options_trade_journal_journal_id ON options_trade_journal(journal_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_options_trade_journal_status ON options_trade_journal(status)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_options_trade_journal_scan_id ON options_trade_journal(scan_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_options_trade_journal_symbol ON options_trade_journal(symbol)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_options_trade_journal_scope ON options_trade_journal(portfolio_scope_key)")
    # Table-level migration for generic AI bot runs.
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS ai_bot_runs (
            run_id TEXT PRIMARY KEY,
            created_at TIMESTAMP,
            status TEXT,
            strategy_id TEXT NOT NULL,
            context_id TEXT NOT NULL,
            provider TEXT NOT NULL,
            model_label TEXT,
            request_json TEXT,
            report_json TEXT,
            execution_plan_json TEXT,
            notes_json TEXT,
            error TEXT
        )
        """
    )
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_ai_bot_runs_created_at ON ai_bot_runs(created_at)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_ai_bot_runs_strategy_id ON ai_bot_runs(strategy_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_ai_bot_runs_context_id ON ai_bot_runs(context_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_ai_bot_runs_status ON ai_bot_runs(status)")

    # Table-level migrations for CSP lifecycle engine.
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS csp_screen_runs (
            id INTEGER PRIMARY KEY,
            run_date TIMESTAMP,
            total_symbols_screened INTEGER,
            candidates_passed INTEGER,
            config_json TEXT,
            summary_json TEXT
        )
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS csp_candidates (
            id INTEGER PRIMARY KEY,
            screen_run_id INTEGER NOT NULL,
            symbol TEXT NOT NULL,
            sector TEXT,
            industry TEXT,
            fundamentals_json TEXT,
            iv_rank REAL,
            option_volume REAL,
            regime TEXT,
            pe_current REAL,
            pe_5y_avg REAL,
            pe_10y_avg REAL,
            price_vs_sma200 REAL,
            gate_reasons TEXT
        )
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS csp_trades (
            id INTEGER PRIMARY KEY,
            backtest_run_id INTEGER,
            symbol TEXT NOT NULL,
            state TEXT NOT NULL,
            open_date DATE,
            expiry_date DATE,
            strike REAL,
            premium_received REAL,
            cash_secured REAL,
            yield_pct REAL,
            delta_at_open REAL,
            iv_at_open REAL,
            regime TEXT,
            current_value REAL,
            close_date DATE,
            close_reason TEXT,
            total_premium_collected REAL,
            rolls_json TEXT,
            assignment_cost REAL,
            shares_assigned INTEGER,
            realized_pnl REAL,
            metadata_json TEXT
        )
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS csp_backtest_runs (
            id INTEGER PRIMARY KEY,
            run_date TIMESTAMP,
            start_date DATE,
            end_date DATE,
            initial_capital REAL,
            final_capital REAL,
            status TEXT,
            error TEXT,
            config_json TEXT,
            results_json TEXT,
            equity_curve_json TEXT,
            trades_json TEXT
        )
        """
    )
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_csp_screen_runs_run_date ON csp_screen_runs(run_date)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_csp_candidates_screen_run_id ON csp_candidates(screen_run_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_csp_candidates_symbol ON csp_candidates(symbol)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_csp_trades_symbol ON csp_trades(symbol)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_csp_trades_state ON csp_trades(state)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_csp_trades_backtest_run_id ON csp_trades(backtest_run_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_csp_backtest_runs_run_date ON csp_backtest_runs(run_date)")

    # Simulation dashboard tables
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS simulation_sessions (
            id INTEGER PRIMARY KEY,
            strategy_id TEXT NOT NULL,
            symbol TEXT NOT NULL,
            timeframe TEXT NOT NULL,
            mode TEXT DEFAULT 'replay',
            data_file TEXT,
            current_bar INTEGER DEFAULT 0,
            total_bars INTEGER DEFAULT 0,
            initial_balance REAL DEFAULT 10000.0,
            current_balance REAL DEFAULT 10000.0,
            total_pnl REAL DEFAULT 0.0,
            trades_count INTEGER DEFAULT 0,
            wins INTEGER DEFAULT 0,
            losses INTEGER DEFAULT 0,
            status TEXT DEFAULT 'active',
            config_json TEXT,
            created_at TIMESTAMP,
            updated_at TIMESTAMP
        )
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS simulation_trades (
            id INTEGER PRIMARY KEY,
            session_id INTEGER NOT NULL,
            direction TEXT NOT NULL,
            entry_price REAL NOT NULL,
            entry_bar INTEGER NOT NULL,
            entry_time TEXT,
            stop_loss REAL NOT NULL,
            take_profit REAL,
            lot_size REAL DEFAULT 0.01,
            entry_mid_price REAL,
            entry_fill_price REAL,
            spread_value REAL,
            tc_rate REAL,
            exit_price REAL,
            exit_mid_price REAL,
            exit_fill_price REAL,
            exit_bar INTEGER,
            exit_time TEXT,
            exit_reason TEXT,
            raw_pnl REAL,
            spread_cost REAL,
            turnover_cost REAL,
            total_cost REAL,
            cost_breakdown_json TEXT,
            pnl REAL,
            r_multiple REAL,
            status TEXT DEFAULT 'open',
            created_at TIMESTAMP,
            FOREIGN KEY (session_id) REFERENCES simulation_sessions(id)
        )
        """
    )
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_sim_sessions_strategy ON simulation_sessions(strategy_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_sim_sessions_status ON simulation_sessions(status)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_sim_trades_session ON simulation_trades(session_id)")
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS strategy_automation_logs (
            id INTEGER PRIMARY KEY,
            parent_session_id INTEGER,
            child_session_id INTEGER NOT NULL,
            job_id TEXT NOT NULL,
            strategy TEXT NOT NULL,
            mode TEXT NOT NULL,
            symbol TEXT NOT NULL,
            timeframe TEXT NOT NULL,
            event_type TEXT NOT NULL,
            event_name TEXT NOT NULL,
            trade_id INTEGER,
            direction TEXT,
            event_time TIMESTAMP,
            payload_json TEXT,
            created_at TIMESTAMP,
            FOREIGN KEY (parent_session_id) REFERENCES simulation_sessions(id),
            FOREIGN KEY (child_session_id) REFERENCES simulation_sessions(id)
        )
        """
    )
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_sa_logs_parent_session ON strategy_automation_logs(parent_session_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_sa_logs_child_session ON strategy_automation_logs(child_session_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_sa_logs_job_id ON strategy_automation_logs(job_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_sa_logs_strategy ON strategy_automation_logs(strategy)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_sa_logs_mode ON strategy_automation_logs(mode)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_sa_logs_event_type ON strategy_automation_logs(event_type)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_sa_logs_event_name ON strategy_automation_logs(event_name)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_sa_logs_trade_id ON strategy_automation_logs(trade_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_sa_logs_event_time ON strategy_automation_logs(event_time)")

    # Guided trading simulation control-plane tables
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS trading_simulation_sessions (
            id INTEGER PRIMARY KEY,
            session_uid TEXT NOT NULL UNIQUE,
            strategy_id TEXT NOT NULL,
            symbol TEXT NOT NULL,
            timeframe TEXT NOT NULL,
            mode TEXT DEFAULT 'demo',
            status TEXT DEFAULT 'ACTIVE',
            current_step_id TEXT,
            current_step_status TEXT DEFAULT 'WAIT',
            telemetry_json TEXT,
            step_states_json TEXT,
            summary_json TEXT,
            created_at TIMESTAMP,
            updated_at TIMESTAMP,
            ended_at TIMESTAMP
        )
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS trading_simulation_events (
            id INTEGER PRIMARY KEY,
            session_id INTEGER NOT NULL,
            event_type TEXT NOT NULL,
            payload_json TEXT,
            created_at TIMESTAMP,
            FOREIGN KEY (session_id) REFERENCES trading_simulation_sessions(id)
        )
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS trading_simulation_actions (
            id INTEGER PRIMARY KEY,
            session_id INTEGER NOT NULL,
            action_type TEXT NOT NULL,
            step_id TEXT,
            note TEXT,
            payload_json TEXT,
            created_at TIMESTAMP,
            FOREIGN KEY (session_id) REFERENCES trading_simulation_sessions(id)
        )
        """
    )
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_tsim_sessions_strategy ON trading_simulation_sessions(strategy_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_tsim_sessions_status ON trading_simulation_sessions(status)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_tsim_events_session ON trading_simulation_events(session_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_tsim_events_type ON trading_simulation_events(event_type)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_tsim_actions_session ON trading_simulation_actions(session_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_tsim_actions_type ON trading_simulation_actions(action_type)")

    # Workbench copilot control-plane tables
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS workbench_copilot_sessions (
            id INTEGER PRIMARY KEY,
            simulation_session_id INTEGER NOT NULL,
            mode TEXT DEFAULT 'ADVISE',
            status TEXT DEFAULT 'ACTIVE',
            provider TEXT DEFAULT 'deterministic',
            model_label TEXT,
            config_json TEXT,
            last_snapshot_json TEXT,
            created_at TIMESTAMP,
            updated_at TIMESTAMP,
            stopped_at TIMESTAMP,
            FOREIGN KEY (simulation_session_id) REFERENCES simulation_sessions(id)
        )
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS workbench_copilot_events (
            id INTEGER PRIMARY KEY,
            copilot_session_id INTEGER NOT NULL,
            event_type TEXT NOT NULL,
            severity TEXT DEFAULT 'info',
            payload_json TEXT,
            created_at TIMESTAMP,
            FOREIGN KEY (copilot_session_id) REFERENCES workbench_copilot_sessions(id)
        )
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS workbench_copilot_advices (
            id INTEGER PRIMARY KEY,
            copilot_session_id INTEGER NOT NULL,
            event_id INTEGER,
            advice_type TEXT NOT NULL,
            summary TEXT NOT NULL,
            confidence REAL,
            source_event_priority INTEGER DEFAULT 0,
            delivery TEXT DEFAULT 'ACTIONABLE',
            evidence_json TEXT,
            action_json TEXT,
            status TEXT DEFAULT 'NEW',
            created_at TIMESTAMP,
            FOREIGN KEY (copilot_session_id) REFERENCES workbench_copilot_sessions(id),
            FOREIGN KEY (event_id) REFERENCES workbench_copilot_events(id)
        )
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS workbench_copilot_actions (
            id INTEGER PRIMARY KEY,
            copilot_session_id INTEGER NOT NULL,
            advice_id INTEGER,
            action_type TEXT NOT NULL,
            payload_json TEXT,
            note TEXT,
            requested_by TEXT DEFAULT 'USER',
            status TEXT DEFAULT 'PROPOSED',
            created_at TIMESTAMP,
            FOREIGN KEY (copilot_session_id) REFERENCES workbench_copilot_sessions(id),
            FOREIGN KEY (advice_id) REFERENCES workbench_copilot_advices(id)
        )
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS workbench_copilot_snapshots (
            id INTEGER PRIMARY KEY,
            copilot_session_id INTEGER NOT NULL,
            bar_index INTEGER NOT NULL,
            source TEXT DEFAULT 'advance',
            snapshot_json TEXT,
            created_at TIMESTAMP,
            FOREIGN KEY (copilot_session_id) REFERENCES workbench_copilot_sessions(id)
        )
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS workbench_copilot_jobs (
            id INTEGER PRIMARY KEY,
            copilot_session_id INTEGER NOT NULL,
            simulation_session_id INTEGER NOT NULL,
            job_type TEXT DEFAULT 'ADVICE_GENERATION',
            status TEXT DEFAULT 'PENDING',
            priority INTEGER DEFAULT 50,
            payload_json TEXT,
            result_json TEXT,
            error TEXT,
            attempts INTEGER DEFAULT 0,
            created_at TIMESTAMP,
            started_at TIMESTAMP,
            finished_at TIMESTAMP,
            FOREIGN KEY (copilot_session_id) REFERENCES workbench_copilot_sessions(id)
        )
        """
    )
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wbc_sessions_sim_session ON workbench_copilot_sessions(simulation_session_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wbc_sessions_status ON workbench_copilot_sessions(status)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wbc_events_session ON workbench_copilot_events(copilot_session_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wbc_events_type ON workbench_copilot_events(event_type)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wbc_advices_session ON workbench_copilot_advices(copilot_session_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wbc_advices_status ON workbench_copilot_advices(status)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wbc_advices_delivery ON workbench_copilot_advices(delivery)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wbc_advices_priority ON workbench_copilot_advices(source_event_priority)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wbc_actions_session ON workbench_copilot_actions(copilot_session_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wbc_actions_type ON workbench_copilot_actions(action_type)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wbc_snapshots_session ON workbench_copilot_snapshots(copilot_session_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wbc_snapshots_bar ON workbench_copilot_snapshots(bar_index)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wbc_snapshots_source ON workbench_copilot_snapshots(source)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wbc_jobs_session ON workbench_copilot_jobs(copilot_session_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wbc_jobs_sim_session ON workbench_copilot_jobs(simulation_session_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wbc_jobs_status ON workbench_copilot_jobs(status)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wbc_jobs_type ON workbench_copilot_jobs(job_type)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wbc_jobs_created ON workbench_copilot_jobs(created_at)")

    # Unified agent control-plane tables (Phase 4)
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS workbench_agent_sessions (
            id INTEGER PRIMARY KEY,
            simulation_session_id INTEGER NOT NULL,
            copilot_session_id INTEGER,
            mode TEXT DEFAULT 'LOOP',
            status TEXT DEFAULT 'ACTIVE',
            provider TEXT DEFAULT 'deterministic',
            model_label TEXT,
            permissions_json TEXT,
            config_json TEXT,
            runtime_json TEXT,
            last_snapshot_json TEXT,
            created_at TIMESTAMP,
            updated_at TIMESTAMP,
            stopped_at TIMESTAMP,
            FOREIGN KEY (simulation_session_id) REFERENCES simulation_sessions(id),
            FOREIGN KEY (copilot_session_id) REFERENCES workbench_copilot_sessions(id)
        )
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS workbench_agent_events (
            id INTEGER PRIMARY KEY,
            agent_session_id INTEGER NOT NULL,
            event_type TEXT NOT NULL,
            severity TEXT DEFAULT 'info',
            payload_json TEXT,
            created_at TIMESTAMP,
            FOREIGN KEY (agent_session_id) REFERENCES workbench_agent_sessions(id)
        )
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS workbench_agent_actions (
            id INTEGER PRIMARY KEY,
            agent_session_id INTEGER NOT NULL,
            copilot_action_id INTEGER,
            action_type TEXT NOT NULL,
            status TEXT DEFAULT 'PROPOSED',
            requested_by TEXT DEFAULT 'USER',
            reason TEXT,
            payload_json TEXT,
            result_json TEXT,
            created_at TIMESTAMP,
            FOREIGN KEY (agent_session_id) REFERENCES workbench_agent_sessions(id),
            FOREIGN KEY (copilot_action_id) REFERENCES workbench_copilot_actions(id)
        )
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS workbench_agent_snapshots (
            id INTEGER PRIMARY KEY,
            agent_session_id INTEGER NOT NULL,
            bar_index INTEGER NOT NULL,
            source TEXT DEFAULT 'external',
            snapshot_json TEXT,
            created_at TIMESTAMP,
            FOREIGN KEY (agent_session_id) REFERENCES workbench_agent_sessions(id)
        )
        """
    )
    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS workbench_agent_memories (
            id INTEGER PRIMARY KEY,
            simulation_session_id INTEGER,
            scope TEXT DEFAULT 'SESSION',
            symbol TEXT,
            timeframe TEXT,
            memory_type TEXT DEFAULT 'note',
            content TEXT NOT NULL,
            metadata_json TEXT,
            pinned INTEGER DEFAULT 0,
            importance REAL DEFAULT 0.5,
            source TEXT DEFAULT 'user',
            fingerprint TEXT NOT NULL,
            access_count INTEGER DEFAULT 0,
            last_accessed_at TIMESTAMP,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (simulation_session_id) REFERENCES simulation_sessions(id)
        )
        """
    )
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wba_sessions_sim_session ON workbench_agent_sessions(simulation_session_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wba_sessions_copilot ON workbench_agent_sessions(copilot_session_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wba_sessions_status ON workbench_agent_sessions(status)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wba_sessions_provider ON workbench_agent_sessions(provider)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wba_sessions_mode ON workbench_agent_sessions(mode)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wba_sessions_created ON workbench_agent_sessions(created_at)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wba_sessions_updated ON workbench_agent_sessions(updated_at)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wba_events_session ON workbench_agent_events(agent_session_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wba_events_type ON workbench_agent_events(event_type)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wba_events_severity ON workbench_agent_events(severity)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wba_events_created ON workbench_agent_events(created_at)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wba_actions_session ON workbench_agent_actions(agent_session_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wba_actions_type ON workbench_agent_actions(action_type)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wba_actions_status ON workbench_agent_actions(status)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wba_actions_requested_by ON workbench_agent_actions(requested_by)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wba_actions_copilot_action_id ON workbench_agent_actions(copilot_action_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wba_actions_created ON workbench_agent_actions(created_at)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wba_snapshots_session ON workbench_agent_snapshots(agent_session_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wba_snapshots_bar ON workbench_agent_snapshots(bar_index)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wba_snapshots_source ON workbench_agent_snapshots(source)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wba_snapshots_created ON workbench_agent_snapshots(created_at)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wbam_session ON workbench_agent_memories(simulation_session_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wbam_scope ON workbench_agent_memories(scope)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wbam_symbol ON workbench_agent_memories(symbol)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wbam_timeframe ON workbench_agent_memories(timeframe)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wbam_type ON workbench_agent_memories(memory_type)")
    cursor.execute(
        """
        DELETE FROM workbench_agent_memories
        WHERE id NOT IN (
            SELECT MIN(id)
            FROM workbench_agent_memories
            GROUP BY fingerprint, IFNULL(simulation_session_id, -1)
        )
        """
    )
    cursor.execute(
        "CREATE UNIQUE INDEX IF NOT EXISTS uq_wbam_fingerprint_session "
        "ON workbench_agent_memories(fingerprint, IFNULL(simulation_session_id, -1))"
    )
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wbam_created ON workbench_agent_memories(created_at)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_wbam_updated ON workbench_agent_memories(updated_at)")
    cursor.execute("DROP INDEX IF EXISTS idx_wbam_source")
    cursor.execute("DROP INDEX IF EXISTS idx_wbam_fingerprint")
    cursor.execute("DROP INDEX IF EXISTS idx_wbam_accessed")
    cursor.execute("DROP INDEX IF EXISTS idx_wbam_importance")
    cursor.execute("DROP INDEX IF EXISTS ix_workbench_agent_memories_source")
    cursor.execute("DROP INDEX IF EXISTS ix_workbench_agent_memories_fingerprint")
    cursor.execute("DROP INDEX IF EXISTS ix_workbench_agent_memories_last_accessed_at")
    cursor.execute("DROP INDEX IF EXISTS ix_workbench_agent_memories_importance")
    cursor.execute("DROP INDEX IF EXISTS ix_workbench_agent_memories_access_count")

    conn.commit()
    conn.close()
