# ProTradingSystem - System Architecture Guide

> Enterprise-level algorithmic trading platform for Gold (XAUUSD) and Forex.
> Backtesting engine with full cost simulation, 11 trading strategies, ML pipeline (6 model types), RL agent, and live trading via MetaTrader 5.

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Project Structure](#project-structure)
3. [Architecture Overview](#architecture-overview)
4. [Backend (FastAPI)](#backend-fastapi)
5. [Frontend (Flask + Jinja2)](#frontend-flask--jinja2)
6. [Strategy System](#strategy-system)
7. [Backtest Engine](#backtest-engine)
8. [ML Pipeline](#ml-pipeline)
9. [RL Agent](#rl-agent)
10. [Live Trading Bot](#live-trading-bot)
11. [Database Schema](#database-schema)
12. [API Reference](#api-reference)
13. [Data Management](#data-management)
14. [Online Learning Systems](#online-learning-systems)
15. [Key Patterns & Gotchas](#key-patterns--gotchas)

---

## Quick Start

```bash
# Backend (FastAPI) - run from project root
python -m uvicorn dashboard.backend.main:app --reload --port 8000

# Frontend (Flask) - separate terminal
cd dashboard/frontend
python app.py   # runs on port 5000

# Seed preset configs (optional - creates 33 configs: 11 strategies x 3 presets)
python seed_preset_configs.py

# Download historical data (CLI)
python download_dukascopy.py --start 2022-01-01 --end 2025-12-31 --symbol XAUUSD
```

**Requirements**: Python 3.10+, MetaTrader 5 (for live trading), PyTorch (optional, for LSTM/CNN/Transformer/RL)

---

## Project Structure

```
ProTradingSystem/
├── dashboard/                          # Web application
│   ├── backend/                        # FastAPI backend (port 8000)
│   │   ├── main.py                     # FastAPI app entry, CORS, router registration
│   │   ├── api/
│   │   │   ├── routes.py               # All REST API endpoints (~60)
│   │   │   └── websocket.py            # WebSocket for real-time updates
│   │   ├── core/                       # Business logic
│   │   │   ├── backtest_engine.py      # Enterprise backtesting engine
│   │   │   ├── ml_backtest_engine.py   # ML-filtered backtesting (extends above)
│   │   │   ├── metrics_calculator.py   # Performance metrics (Sharpe, Sortino, etc.)
│   │   │   ├── data_provider.py        # MT5 + CSV data fetcher with auto-resample
│   │   │   ├── strategy_registry.py    # Strategy definitions, parameters, presets
│   │   │   ├── ml_features.py          # 27-feature extraction for ML
│   │   │   ├── ml_model_factory.py     # XGBoost/LightGBM/LSTM/CNN/Transformer/Ensemble
│   │   │   ├── ml_hpo.py              # Optuna hyperparameter optimization
│   │   │   ├── ml_trainer.py          # Walk-forward training pipeline
│   │   │   ├── ml_models.py           # Model loading, caching, inference
│   │   │   ├── rl_environment.py      # Gymnasium trading environment (28-dim state)
│   │   │   ├── rl_trainer.py          # PPO trainer with Actor-Critic network
│   │   │   └── strategies/            # Strategy implementations
│   │   │       ├── base.py            # BacktestStrategy ABC
│   │   │       ├── factory.py         # create_strategy(id, config) factory
│   │   │       ├── orb_strategy.py    # ORB + ICT concepts (FVG, OB, Displacement)
│   │   │       ├── macd_ema_strategy.py    # MACD + EMA trend-following + ADX
│   │   │       ├── ichimoku_strategy.py    # Ichimoku cloud retracement
│   │   │       ├── basso_strategy.py       # Bollinger + RSI mean reversion
│   │   │       ├── confluence_zone_strategy.py  # Multi-TF level clustering
│   │   │       ├── liquidity_sweep_strategy.py  # Session liquidity sweeps
│   │   │       └── rl_strategy.py     # RL (PPO) strategy wrapper
│   │   ├── models/
│   │   │   ├── database.py            # SQLAlchemy models (8 tables) + migrations
│   │   │   └── schemas.py             # Pydantic schemas (20+ schemas)
│   │   └── services/
│   │       ├── backtest_service.py     # Backtest orchestration + DB storage
│   │       ├── ml_service.py           # ML model CRUD + training
│   │       ├── live_service.py         # Live trading status + MT5 interface
│   │       ├── live_data_retrain.py    # Retrain ML from backtest + live data
│   │       ├── ibkr_service.py         # Interactive Brokers data download
│   │       └── dukascopy_service.py    # Dukascopy free data download
│   ├── frontend/                       # Flask frontend (port 5000)
│   │   ├── app.py                      # Flask routes + API proxy
│   │   ├── templates/                  # Jinja2 templates (Bootstrap 5)
│   │   │   ├── base.html              # Layout: sidebar, nav, Bootstrap/Chart.js
│   │   │   ├── dashboard.html         # Home: stats cards, equity chart
│   │   │   ├── trading_systems.html   # Live strategy control (start/stop)
│   │   │   ├── configurations.html    # Saved backtest configs list
│   │   │   ├── new_configuration.html # Create/edit backtest config form
│   │   │   ├── view_configuration.html # View config details
│   │   │   ├── run_backtest.html      # Launch backtest with progress
│   │   │   ├── backtests.html         # Backtest results list
│   │   │   ├── backtest_detail.html   # Result detail: metrics, equity, trades
│   │   │   ├── ml_models.html         # ML model training + management
│   │   │   ├── live_trading.html      # Live trading monitor
│   │   │   ├── live_performance.html  # Execution quality + adaptive filter
│   │   │   └── data_management.html   # Upload/download historical data
│   │   └── static/                    # CSS/JS assets (if any)
│   └── data/
│       ├── historical/                # CSV data files (XAUUSD_M1_*.csv)
│       └── trading.db                 # SQLite database
├── Strategies/                        # Live trading strategies (legacy + modular)
│   ├── base.py                        # BaseStrategy ABC (live trading)
│   ├── shared/
│   │   ├── adaptive_filter.py         # Adaptive filter (hysteresis WR gating)
│   │   └── trade_journal.py           # TradeJournal (execution quality logging)
│   ├── ORB/
│   │   └── orb_strategy.py            # Live ORB strategy implementation
│   ├── HTFReversal/
│   │   └── htf_reversal_strategy.py   # Live HTF Reversal implementation
│   └── AdvancedORB/
│       └── advanced_orb_strategy.py   # Live Advanced ORB implementation
├── main.py                            # Live bot entry point
├── config.py                          # Global config (API keys, paths, feature flags)
├── risk_manager.py                    # Live risk management
├── trade_executor.py                  # MT5 trade execution + MFE/MAE tracking
├── ml_wrapper.py                      # ML integration for live trading
├── download_dukascopy.py              # CLI: Download Dukascopy historical data
├── seed_preset_configs.py             # CLI: Seed 33 preset configs to DB
├── test_bot.py                        # CLI: Test MT5 connection + ICT patterns
├── data/                              # Bot state files, logs
│   ├── bot_state.json                 # ORB bot state (live)
│   ├── htf_reversal_state.json        # HTF bot state (live)
│   ├── advanced_orb_state.json        # Advanced ORB bot state (live)
│   ├── ml_models/                     # Trained ML model files (.joblib, .pt)
│   └── rl_models/                     # Trained RL model files (.pt)
└── logs/                              # Application logs
```

**IMPORTANT**: The frontend is **Flask + Jinja2 + Bootstrap 5**, NOT React. There are legacy React files in `src/` and `node_modules/` — ignore them.

---

## Architecture Overview

```
┌─────────────────────┐     ┌──────────────────────┐
│   Flask Frontend     │────▶│   FastAPI Backend     │
│   (port 5000)        │     │   (port 8000)         │
│   Jinja2 + BS5       │     │   /api/v1/*           │
└─────────────────────┘     └──────┬───────────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    │               │               │
              ┌─────▼─────┐  ┌─────▼─────┐  ┌─────▼─────┐
              │  Backtest  │  │    ML     │  │   Live    │
              │  Engine    │  │  Pipeline │  │  Service  │
              └─────┬──────┘  └─────┬─────┘  └─────┬─────┘
                    │               │               │
              ┌─────▼──────┐  ┌─────▼─────┐  ┌─────▼─────┐
              │  Strategy   │  │  Model    │  │    MT5    │
              │  Factory    │  │  Factory  │  │  Terminal  │
              └─────┬──────┘  └───────────┘  └───────────┘
                    │
        ┌───────────┼───────────┐
        │           │           │
   ┌────▼───┐ ┌────▼───┐ ┌────▼───┐
   │  ORB   │ │  MACD  │ │  RL    │  ... (11 strategies)
   │Strategy│ │  +EMA  │ │Strategy│
   └────────┘ └────────┘ └────────┘
```

**Data Flow**: Strategy Registry → Backtest Config → Engine → Data Provider → Trade Processing → Metrics Calculator → DB Storage → API → Frontend

---

## Backend (FastAPI)

### Entry Point: `dashboard/backend/main.py`

- Creates FastAPI app with CORS middleware
- Registers all routes via `app.include_router(api_router, prefix="/api/v1")`
- Root endpoints: `GET /` (app info), `GET /health` (health check)

### Services Layer (`services/`)

| Service | File | Purpose |
|---------|------|---------|
| `BacktestService` | `backtest_service.py` | Orchestrates backtest execution, builds strategy configs, stores results |
| `MLService` | `ml_service.py` | ML model training, CRUD, inference management |
| `LiveTradingService` | `live_service.py` | Live bot status, MT5 interface, strategy management |
| `LiveDataRetrainService` | `live_data_retrain.py` | Retrain ML models from backtest + live trade data |
| `IBKRDataService` | `ibkr_service.py` | Interactive Brokers data download (background tasks) |
| `DukascopyDataService` | `dukascopy_service.py` | Dukascopy free data download (tick → M1) |

### Key Service: `BacktestService`

```python
# How a backtest runs (background task):
def run_backtest_task(result_id, config_id):
    1. Load BacktestConfigModel from DB
    2. Build strategy config via _build_strategy_config()
       - Merges: registry optimal_params + preset overrides + user overrides
    3. Create strategy instance via factory.create_strategy(strategy_id, config)
    4. Create engine: BacktestEngine(config, strategy) or MLBacktestEngine(config, strategy)
    5. engine.run() → returns results dict
    6. Store results + trades to DB
    7. Notify via WebSocket
```

**Critical**: `_build_strategy_config()` MUST merge registry's `get_preset_config()`, not just ICT params. Otherwise preset-specific parameters (risk_percent, max_daily_trades, etc.) are lost.

---

## Frontend (Flask + Jinja2)

### Flask App: `dashboard/frontend/app.py`

The Flask app serves Jinja2 templates and proxies API calls to the FastAPI backend.

### Pages

| Route | Template | Description |
|-------|----------|-------------|
| `/` | `dashboard.html` | Home: stats cards, equity chart, recent backtests |
| `/trading-systems` | `trading_systems.html` | Start/stop live strategies with preset cards |
| `/configurations` | `configurations.html` | List saved backtest configurations |
| `/configurations/new` | `new_configuration.html` | Create/edit config with dynamic strategy params |
| `/configurations/<id>` | `view_configuration.html` | View config details |
| `/run-backtest/<id>` | `run_backtest.html` | Launch backtest with real-time progress |
| `/backtests` | `backtests.html` | Backtest results list with sorting |
| `/backtests/<id>` | `backtest_detail.html` | Detail: metrics, equity curve, expandable trades |
| `/ml-models` | `ml_models.html` | Train/manage ML models |
| `/live-trading` | `live_trading.html` | Live trading monitor |
| `/live-performance` | `live_performance.html` | Execution quality, cost comparison, adaptive filter |
| `/data-management` | `data_management.html` | Upload CSV, download from MT5/IBKR/Dukascopy |

### API Proxy Pattern

Flask proxies all `/api/*` requests to FastAPI:
```python
@app.route('/api/<path:path>', methods=['GET', 'POST', 'PUT', 'DELETE'])
def proxy_api(path):
    resp = requests.request(method, f'http://localhost:8000/api/v1/{path}', ...)
    return jsonify(resp.json()), resp.status_code
```

### Template Architecture

- `base.html`: Master layout with sidebar navigation, Bootstrap 5 CDN, Chart.js CDN
- All pages extend `base.html` via `{% extends "base.html" %}`
- JavaScript is inline in `{% block extra_js %}` blocks
- No build step needed — pure server-side rendering

---

## Strategy System

### Two Strategy ABCs (Backtest vs Live)

| ABC | Location | Purpose |
|-----|----------|---------|
| `BacktestStrategy` | `dashboard/backend/core/strategies/base.py` | Backtesting: `initialize_day()`, `find_setup()`, `should_close_early()` |
| `BaseStrategy` | `Strategies/base.py` | Live trading: `initialize()`, `run()`, `shutdown()`, `get_state()` |

### Backtest Strategy ABC

```python
class BacktestStrategy(ABC):
    def initialize_day(date, daily_df, intraday_df) → DayContext
        # Called once per day. Calculate bias, ATR, session levels.
        # daily_df: data up to (not including) this day (no look-ahead)

    def find_setup(bar, df, day_context, current_bar_index) → Optional[TradeSetup]
        # Called per bar. df = all bars up to current (full history).
        # Return TradeSetup or None.

    def should_close_early(bar, df, position, day_context) → Optional[str]
        # Optional. Custom exit logic beyond SL/TP/trailing.
        # Return exit reason string or None.
```

### Data Classes

```python
@dataclass
class DayContext:
    date: datetime.date
    bias: str                    # 'bullish' / 'bearish' / 'neutral'
    bias_strength: int           # 0-100
    atr: float                   # ATR for position sizing
    levels: Dict[str, float]     # Session levels

@dataclass
class TradeSetup:
    direction: str               # 'BUY' / 'SELL'
    entry_price: float
    stop_loss: float
    take_profit: Optional[float] # None = engine calculates from R:R
    setup_type: str              # e.g. "Bullish FVG + ORB Breakout"
    confidence: float            # 0-100, used as bias_strength
    metadata: Dict[str, Any]     # Strategy-specific diagnostics
```

### 11 Registered Strategies

| ID | Name | Timeframe | Key Concept | Has `should_close_early` |
|----|------|-----------|-------------|--------------------------|
| `orb_strategy` | ORB Strategy | M1 | ICT FVG + Order Blocks + ORB breakout | No (ORB path) |
| `advanced_orb_strategy` | Advanced ORB | M1 | Stricter ICT filters | No (ORB path) |
| `htf_reversal_strategy` | HTF Reversal | H4 | Monthly/Weekly/Daily level reversals | No (legacy) |
| `macd_ema_strategy` | MACD + EMA | M5-H1 | EMA9/21/50/200, MACD crossover, ADX filter | Yes |
| `ichimoku_strategy` | Ichimoku | M5-H4 | Kijun-sen pullbacks, cloud breaks | Yes |
| `basso_strategy` | Basso Mean Rev | M5-H1 | Bollinger + RSI + EMA200 trend filter | Yes |
| `confluence_zone_strategy` | Confluence Zone | M15 | H4+H1+M15 level alignment, zone scoring | Yes |
| `liquidity_sweep_strategy` | Liquidity Sweep | M1-M5 | Session high/low sweeps + FVG confirmation | Yes |
| `orb_ml_strategy` | ORB + ML | M1 | ORB base + XGBoost trade filter | No (ML wrapper) |
| `advanced_orb_ml_strategy` | Adv ORB + ML | M1 | Advanced ORB + XGBoost filter | No (ML wrapper) |
| `rl_strategy` | RL Trading | M1-M15 | PPO agent (requires trained model) | No |

### Strategy Registry (`strategy_registry.py`)

Each strategy is registered with:
- **Parameters**: `List[ParameterDefinition]` — UI-editable fields with types, ranges, defaults
- **Optimal Parameters**: Hard-coded pro settings (always applied)
- **Presets**: Conservative / Default / Aggressive bundles with descriptions

```python
StrategyRegistry.get_strategy_list()        # → [{id, name, description}]
StrategyRegistry.get_strategy(strategy_id)  # → StrategyDefinition
StrategyRegistry.get_preset_config(id, preset)  # → Dict (full merged config)
```

### Strategy Factory (`strategies/factory.py`)

```python
create_strategy(strategy_id, config) → Optional[BacktestStrategy]
# Maps strategy_id to class, instantiates with config dict
# ML variants use the same base class (ML filtering via MLBacktestEngine wrapper)
```

---

## Backtest Engine

### File: `dashboard/backend/core/backtest_engine.py`

The engine has **two code paths**:

```python
if hasattr(strategy, 'calculate_bias'):
    # ORB path: calculate ORB levels, call strategy.calculate_bias(), check ORB range
else:
    # Generic path: call strategy.initialize_day(), skip ORB blocks
```

### Engine Flow

```
1. Load historical data via HistoricalDataProvider
2. For each trading day:
   a. Calculate session levels (Asian H/L, London H/L, PD H/L)
   b. Calculate ATR
   c. For ORB strategies: compute ORB range, call calculate_bias()
      For generic strategies: call strategy.initialize_day()
   d. For each bar in trading window:
      - If position open: _manage_position() → SL/TP/trailing/early exit
      - If no position: find trade setup → _execute_trade()
   e. End of day: close positions if needed
3. Calculate metrics via MetricsCalculator
4. Return results dict
```

### Position Management (`_manage_position`)

1. Check SL hit → close
2. Check TP hit → close
3. Update MFE/MAE (in R-multiples)
4. Apply trailing stop (if enabled):
   - Breakeven at 1R profit
   - ATR-based trail after breakeven (multiplier from config)
5. Call `strategy.should_close_early()` (if implemented) → close with reason
6. Check Friday close rule

### Cost Simulation

| Cost | Implementation |
|------|---------------|
| **Spread** | Static baseline + time-of-day variable model (wider at session open/close) |
| **Slippage** | `ATR × slippage_atr_factor` (default 0.02), clamped min/max |
| **Commission** | Round-trip per lot (default $3.50 for Gold) |
| **Swap** | Long/short differentiated, Wednesday 3x (triple swap day) |

### Key Config Fields

```python
@dataclass
class BacktestConfig:
    symbol: str = "XAUUSD"
    timeframe: str = "M1"
    initial_balance: float = 10000.0
    risk_percent: float = 1.0           # Risk per trade
    gold_rr_threshold: float = 3.0      # Min R:R for Gold
    use_trailing: bool = True
    trailing_atr_multiplier: float = 1.5
    max_daily_trades: int = 2
    max_daily_loss_usd: float = -150.0
    # ... 60+ fields total
```

---

## ML Pipeline

### Architecture

```
Backtest Trades → Feature Extraction (27 features) → Walk-Forward Training
                                                           │
                                          ┌────────────────┼────────────────┐
                                          │                │                │
                                     Filter Model    R:R Predictor    Metadata
                                     (classifier)     (regressor)      (JSON)
                                          │
                            ML Backtest Engine (trade filtering)
```

### 27 ML Features (`ml_features.py`)

All features are **ATR-normalized** for scale invariance:

| Category | Features |
|----------|----------|
| Bias | bias_direction (-1/0/1), bias_strength (0-100) |
| ORB | orb_range_atr, breakout_distance_atr |
| Sessions | asian_range_atr, pd_range_atr, london_range_atr |
| ICT Quality | fvg_size_atr, has_order_block, ob_body_percent |
| Risk | sl_distance_atr, rr_ratio, spread_atr |
| Time | hour_of_day, day_of_week, minutes_since_orb |
| Daily | daily_pnl_pct, trades_today |
| Displacement | displacement_magnitude_atr |
| V2 (8 new) | volatility_regime, htf_nearest_level_distance_atr, confluence_count, adx_14, hours_to_session_close, consecutive_results, proximity_to_round_number, fvg_fill_ratio |

### Model Types (`ml_model_factory.py`)

| Type | Class | Requirements | Min Trades |
|------|-------|-------------|-----------|
| `xgboost` | XGBoostModel | scikit-learn, xgboost | ~50 |
| `lightgbm` | LightGBMModel | lightgbm | ~50 |
| `lstm` | LSTMModel | PyTorch | 500+ |
| `cnn` | CNNModel | PyTorch | 500+ |
| `transformer` | TransformerModel | PyTorch | 500+ |
| `ensemble` | EnsembleModel | xgboost + lightgbm | ~50 |

### Training Pipeline (`ml_trainer.py`)

1. Extract features + labels from backtest trades
2. Walk-forward split: expanding window (train on months 1..N, test N+1)
3. Optional HPO via Optuna (`ml_hpo.py`)
4. Train final model on ALL data
5. Save: `filter_*.joblib` (classifier) + `rr_predictor_*.joblib` (regressor) + `metadata_*.json`

### ML Model Scoping

Models are scoped to `(strategy_id, symbol, timeframe)`. A model trained on `basso_strategy + XAUUSD + M5` only applies to that combination.

### ML Backtest Engine (`ml_backtest_engine.py`)

Extends `BacktestEngine`. Before each trade:
1. Extract 27 features from current state
2. Predict win probability via filter model
3. If probability < threshold (default 0.55) → skip trade
4. Optionally predict optimal R:R via regressor

---

## RL Agent

### Environment (`rl_environment.py`)

- **State**: 28 dimensions (price features[20] + account[5] + position[3])
- **Actions**: 4 discrete (Hold, Buy, Sell, Close)
- **Reward**: R-multiple of closed trades (-0.001 for entry, -0.0005 for holding)

### Trainer (`rl_trainer.py`)

PPO (Proximal Policy Optimization) with Actor-Critic:
- PolicyNetwork: shared layers → actor head (logits) + critic head (value)
- Training: N episodes, collect trajectories, compute GAE advantages, clip policy gradients

### RL Strategy (`strategies/rl_strategy.py`)

- Requires pre-trained model file (`rl_model_path` in config)
- Builds 28-dim state vector per bar → agent.predict(state) → action
- Without trained model, `find_setup()` always returns None (0 trades by design)

---

## Live Trading Bot

### Entry Point: `main.py` (root)

The live bot connects to MetaTrader 5 and runs strategies in real-time.

### Key Root Files

| File | Class | Purpose |
|------|-------|---------|
| `main.py` | — | Bot entry point, strategy orchestration |
| `config.py` | — | Global config (API keys, paths, feature flags) |
| `risk_manager.py` | `RiskManager` | Position sizing, daily loss limits, exposure limits |
| `trade_executor.py` | `TradeExecutor` | MT5 trade execution, MFE/MAE tracking, close callbacks |
| `ml_wrapper.py` | — | ML integration layer, adaptive filter before execution |
| `Strategies/base.py` | `BaseStrategy` | Live strategy ABC: `initialize()`, `run()`, `shutdown()` |
| `Strategies/shared/adaptive_filter.py` | `AdaptiveFilter` | Rolling WR tracking, hysteresis gating (35%/45%) |
| `Strategies/shared/trade_journal.py` | `TradeJournal` | Execution quality logging, ML feature recording |

### Bot State Files

Strategies write state to JSON files for dashboard monitoring:
- `data/bot_state.json` (orb_strategy)
- `data/htf_reversal_state.json` (htf_reversal_strategy)
- `data/advanced_orb_state.json` (advanced_orb_strategy)

### Adaptive Filter

Per-setup-type rolling win rate tracking:
- Window: 30 trades
- Disable threshold: 35% WR (blocks trades)
- Re-enable threshold: 45% WR (hysteresis prevents oscillation)

---

## Database Schema

### SQLite: `dashboard/data/trading.db`

8 tables, managed via SQLAlchemy with ALTER TABLE migrations.

### Tables

#### `backtest_configs` (BacktestConfigModel)
60+ columns covering all backtest parameters: symbol, timeframe, dates, risk management, ICT params, session times, trailing stop, cost simulation, ML settings.

#### `backtest_results` (BacktestResultModel)
| Key Columns | Type | Description |
|-------------|------|-------------|
| config_id | FK → configs | Configuration used |
| status | Enum | PENDING/RUNNING/COMPLETED/FAILED |
| total_trades, win_rate, net_profit | Float | Summary metrics |
| sharpe_ratio, sortino_ratio, calmar_ratio | Float | Risk-adjusted metrics |
| max_drawdown, max_drawdown_percent | Float | Drawdown stats |
| equity_curve, drawdown_curve, daily_pnl | JSON | Chart data |
| monthly_returns | JSON | Monthly breakdown |

#### `backtest_trades` (BacktestTradeModel)
| Key Columns | Type | Description |
|-------------|------|-------------|
| result_id | FK → results | Parent result |
| direction, entry_time, entry_price | — | Trade basics |
| stop_loss, take_profit, lot_size | Float | Position params |
| profit_loss, r_multiple | Float | Result |
| setup_type, bias, exit_reason | String | Trade metadata |
| entry_reason | JSON | Strategy diagnostics at entry |
| gross_pnl, spread_cost, slippage_cost, commission_cost, swap_cost | Float | Cost breakdown |
| max_favorable_excursion, max_adverse_excursion | Float | MFE/MAE in R-multiples |
| ml_features, ml_win_probability | JSON/Float | ML data |

#### `live_trades` (LiveTradeModel)
Live trade records with MT5 ticket, execution quality fields (intended vs actual prices, slippage, spread at entry/exit).

#### `daily_performance` (DailyPerformanceModel)
Daily aggregated stats: trades, P&L, ORB levels, bias.

#### `ml_models` (MLModelRecord)
| Key Columns | Type | Description |
|-------------|------|-------------|
| strategy_id, symbol, timeframe | String | Model scope |
| model_type | String | xgboost/lightgbm/lstm/cnn/transformer/ensemble |
| avg_accuracy, avg_auc_roc, avg_f1 | Float | Walk-forward metrics |
| filter_model_path, rr_model_path | String | File paths |
| feature_importance | JSON | Feature importance scores |

#### `retraining_logs` (RetrainingLogModel)
Auto-retrain history: old vs new AUC, accepted flag, quality gate.

#### `rl_online_logs` (RLOnlineLogModel)
RL online learning updates: experiences count, avg reward, model/backup paths.

### Migrations

All schema changes use `ALTER TABLE` (SQLite-compatible). Never delete the database. Migrations run automatically in `database.py._run_migrations()`.

---

## API Reference

All endpoints are prefixed with `/api/v1`.

### Dashboard
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/dashboard/stats` | Overview statistics |
| GET | `/dashboard/live-status` | Live trading status |

### Configurations
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/configs` | List configs (skip, limit) |
| POST | `/configs` | Create/upsert config |
| GET | `/configs/{id}` | Get config |
| PUT | `/configs/{id}` | Update config |
| DELETE | `/configs/{id}` | Delete config + results |
| POST | `/configs/{id}/duplicate` | Duplicate config |

### Backtests
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/backtests/run/{config_id}` | Start backtest (background) |
| GET | `/backtests/status/{result_id}` | Poll status |
| GET | `/backtests/results` | List results |
| GET | `/backtests/results/{id}` | Get result detail |
| GET | `/backtests/results/{id}/trades` | Get trades |
| DELETE | `/backtests/results/{id}` | Delete result |
| POST | `/backtests/compare` | Compare multiple results |
| POST | `/backtests/export/{id}` | Export CSV/JSON |

### Strategy Definitions
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/strategy-definitions` | All definitions with parameters |
| GET | `/strategy-definitions/list` | Simplified dropdown list |
| GET | `/strategy-definitions/{id}` | Full definition |
| GET | `/strategy-definitions/{id}/defaults` | Default parameter values |
| GET | `/strategy-definitions/{id}/preset/{preset}` | Full preset config |
| GET | `/strategy-definitions/{id}/ml-base` | Base strategy for ML |

### Strategy Management (Live)
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/strategies` | List all strategies with status |
| GET | `/strategies/{id}/state` | Running strategy state |
| POST | `/strategies/{id}/start` | Start strategy with config |
| POST | `/strategies/{id}/stop` | Stop strategy |
| GET | `/strategies/capital/allocation` | Capital allocation |

### ML Models
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/ml/train/{result_id}` | Train from backtest (model_type, use_hpo) |
| GET | `/ml/models` | List trained models |
| GET | `/ml/models/matching` | Find models for strategy/symbol/TF |
| DELETE | `/ml/models/{id}` | Delete model |
| POST | `/ml/retrain-live/{id}` | Retrain with live data |

### RL Online Learning
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/rl/online-status` | Buffer status |
| POST | `/rl/online-config` | Enable/disable |
| GET | `/rl/online-logs` | Update history |

### Adaptive Filter
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/adaptive-filter/state` | Setup types + win rates |
| POST | `/adaptive-filter/config` | Update thresholds |
| POST | `/adaptive-filter/reset` | Reset state |

### Data Management
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/data/files` | List CSV files |
| POST | `/data/download-mt5` | Download from MT5 |
| POST | `/data/download-ibkr` | Start IBKR download |
| GET | `/data/ibkr-status/{task_id}` | Poll IBKR progress |
| POST | `/data/download-dukascopy` | Start Dukascopy download |
| GET | `/data/dukascopy-status/{task_id}` | Poll Dukascopy progress |
| DELETE | `/data/files/{filename}` | Delete CSV file |

---

## Data Management

### Data Provider (`data_provider.py`)

```python
HistoricalDataProvider.get_historical_data(symbol, timeframe, start, end, data_source)
```

**Resolution strategy**:
1. Look for CSV files matching symbol/timeframe in `dashboard/data/historical/`
2. If CSV covers full range → use it
3. If partial → merge CSV + MT5 live data
4. If no CSV → try M1 CSV + auto-resample to requested timeframe
5. Fallback → pure MT5 fetch

**Auto-resample**: If requesting M5/M15/M30/H1/H4/D1 and only M1 CSV exists, the provider resamples M1 data automatically.

### CSV File Naming

```
XAUUSD_M1_20220101_20251231_dukascopy.csv
{symbol}_{timeframe}_{start}_{end}_{source}.csv
```

Format: Tab-separated with headers: Date, Time, Open, High, Low, Close, Tickvolume, Volume, Spread

### Data Sources

| Source | Coverage | Notes |
|--------|----------|-------|
| MT5 (MetaQuotes-Demo) | ~90 days M1 | Limited by broker |
| IBKR | ~1 year M1 | Requires TWS connection |
| Dukascopy | 10+ years M1 | Free, tick → M1 aggregation, VPN may be needed |
| Manual CSV | Any | Upload via Data Management page |

---

## Online Learning Systems

### System A: ML Retrain from Live Data

- `LiveTradeModel` stores `ml_features` and `ml_win_probability` per trade
- `TradeExecutor` tracks MFE/MAE during position lifetime
- `LiveDataRetrainService` combines backtest + weighted live trades (2x weight)
- Quality gate: new AUC >= old AUC - 0.02

### System B: RL Online Learning

- `RLExperienceBuffer` persists (state, action, reward) to JSON
- `RLTrainer.online_ppo_update()` — mini PPO with lower LR, fewer epochs
- Rate-limited updates with model backup/rollback
- Config flag: `RL_ONLINE_LEARNING = False` (off by default)

### System C: Adaptive Filtering

- Per-setup-type rolling win rate (window=30 trades)
- Hysteresis: block at 35% WR, re-enable at 45%
- Integrated into `ml_wrapper.py` before trade execution

---

## Key Patterns & Gotchas

### Architecture Patterns

1. **Strategy Registry + Factory**: Define in `strategy_registry.py`, instantiate via `factory.py`. No frontend changes needed for new strategies.
2. **Dual Engine Paths**: ORB strategies use `calculate_bias()`, generic strategies use `initialize_day()` + `find_setup()`.
3. **Config Merging**: `optimal_parameters` + `preset_overrides` + `user_overrides` → final config dict.
4. **ML Model Scoping**: Models scoped to `(strategy_id, symbol, timeframe)`.
5. **Cost Simulation**: Full spread/slippage/commission/swap simulation in backtest.
6. **MFE/MAE Tracking**: Best/worst price movement per trade, stored as R-multiples.

### Critical Gotchas

| Gotcha | Details |
|--------|---------|
| **Frontend is Flask, NOT React** | Templates in `templates/*.html`. No npm/React/Vite. |
| **Gold P&L formula** | `price_diff × lot_size × 100` (contract_size=100 oz) |
| **Never 1:1 R:R on Gold** | Minimum 2:1 always. `gold_rr_threshold` enforces this. |
| **TP sentinel is None, not 0.0** | `0.0 is not None` is True. Engine validates TP > 0 AND directional sense. |
| **Use ALTER TABLE for migrations** | SQLite. Never delete the DB. |
| **Start backend from project root** | `python -m uvicorn dashboard.backend.main:app` |
| **Non-ORB strategies need full history** | Engine passes `df.iloc[:global_pos]` (all bars), not just today's bars. EMA200 needs 200+ bars. |
| **RL strategy needs trained model** | Without `rl_model_path`, `find_setup()` returns None (0 trades). By design. |
| **Data gap threshold is 4 days** | Holiday weekends (July 4th, Christmas) produce 3+ day gaps. |
| **Preset has hidden params** | `risk_percent`, `max_daily_loss_usd`, `bias_min_strength`, `gold_rr_threshold`, `max_daily_trades` come from preset overrides only, not ParameterDefinitions. |
| **`should_close_early()` signature** | `(bar, df, position, day_context)` → Optional[str]. Called in `_manage_position()`. |
| **`initialize_day()` uses data up to day start** | NOT day end — prevents look-ahead bias. |
| **Concurrent agent caution** | Don't have two agents modify the same file simultaneously. |

### Adding a New Strategy

1. Create `dashboard/backend/core/strategies/my_strategy.py` implementing `BacktestStrategy`
2. Register in `dashboard/backend/core/strategy_registry.py` with parameters + presets
3. Add to factory map in `dashboard/backend/core/strategies/factory.py`
4. **No frontend changes needed** — strategy auto-appears in all dropdowns

### Running a Backtest Programmatically

```python
from dashboard.backend.core.backtest_engine import BacktestEngine, BacktestConfig
from dashboard.backend.core.strategies.factory import create_strategy

config = BacktestConfig(symbol="XAUUSD", timeframe="M5", ...)
strategy = create_strategy("basso_strategy", config.__dict__)
engine = BacktestEngine(config, strategy)
results = engine.run()
```

---

*Last updated: 2026-02-09*
