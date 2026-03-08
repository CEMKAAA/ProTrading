# Cash-Secured Put (CSP) Strategy Design

**Date**: 2026-02-21
**Status**: Approved (Sections 1-3), Draft (Sections 4-6)
**Architecture**: Approach 1 - CSP Lifecycle Engine (dedicated state machine, separate from bar-based BacktestEngine)

---

## Context & Decisions

- **Hybrid Architecture**: ProTradingSystem = strategy brain (screening, regime detection, roll policy, portfolio logic). NautilusTrader + Interactive Brokers = execution engine (deferred to later phase). MT5 stays for existing 9 spot/CFD strategies only.
- **Data Source**: Polygon API for fundamentals + options snapshots. Black-Scholes proxy for backtesting (no historical option chains needed).
- **Module Location**: Extend existing `dashboard/backend/core/options_edge/` module.
- **Universe**: S&P 500 symbol list (already in connectors.py).
- **IB Integration**: Deferred. Build full CSP engine first, add NautilusTrader+IB bridge in a later phase.

---

## Design Section 1: Module Structure & State Machine

### File Layout

```
dashboard/backend/core/options_edge/
├── csp_screener.py          # Phase 1: Fundamental + liquidity screening
├── csp_engine.py            # Phase 2-4: CSP lifecycle engine (backtest + state machine)
├── csp_pricing.py           # Black-Scholes proxy pricing for puts
├── csp_models.py            # Pydantic schemas for CSP-specific data
└── (existing files unchanged)
```

### CSP Position State Machine

```
                    ┌──────────────┐
                    │   SCREENED   │  Passed fundamental + IV + volume filters
                    └──────┬───────┘
                           │ select_candidate()
                    ┌──────▼───────┐
                    │  CANDIDATE   │  POP/yield validated, cash reserved
                    └──────┬───────┘
                           │ open_csp()
                    ┌──────▼───────┐
              ┌─────│   OPEN_CSP   │─────┐
              │     └──────┬───────┘     │
              │            │             │
     roll trigger    expires OTM    expires ITM
              │            │             │
       ┌──────▼──────┐  ┌─▼──────┐  ┌───▼──────┐
       │   ROLLING   │  │EXPIRED │  │ ASSIGNED │  Accept 100 shares
       └──────┬──────┘  │  _OTM  │  └───┬──────┘
              │         └─┬──────┘      │
              │           │         buy shares +
         credit-only?     │      reinvest premium
              │           │             │
        ┌─────▼─────┐    │        ┌────▼─────┐
        │ OPEN_CSP  │    │        │  CLOSED  │
        │ (new exp) │    │        └──────────┘
        └───────────┘    │
                    ┌────▼─────┐
                    │  CLOSED  │  Premium kept
                    └──────────┘
```

**Roll Triggers:**
- **Value Decay**: Option lost 75% of initial premium (worth only 25%)
- **Time Decay**: 7 DTE remaining AND 90% premium decayed
- **Roll Rule**: Only roll if net transaction is a credit (never debit)

---

## Design Section 2: Fundamental Screener (`csp_screener.py`)

### Data Flow

```
S&P 500 list (existing connectors.py)
    │
    ▼
Polygon Financials API ──► FundamentalSnapshot per symbol
    │
    ▼
Gate Filters (hard pass/fail)
    │
    ▼
Polygon Options Snapshot ──► IV + Volume check
    │
    ▼
Qualified CSP Universe (10-30 symbols typically)
```

### Fundamental Gates (all must pass)

| Gate | Metric | Source | Threshold |
|------|--------|--------|-----------|
| Revenue Growth | TTM sales growth | Polygon `income_statement` | > 10% |
| Historical EPS Growth | 5-year EPS CAGR | Polygon `income_statement` (5 annual) | > 10% |
| Projected EPS Growth | Forward EPS estimate | Polygon `income_statement` + analyst | > 5% |
| Profit Margin | Net income / revenue | Polygon `income_statement` | > 15% |
| Balance Sheet | Total assets > total liabilities | Polygon `balance_sheet` | assets > liabilities |
| Free Cash Flow | Operating CF - CapEx | Polygon `cash_flow_statement` | > 0 |
| Industry Exclusion | SIC/NAICS code | Polygon ticker details | Not in blocklist |

### Liquidity & Volatility Gates

| Gate | Metric | Source | Threshold |
|------|--------|--------|-----------|
| Implied Volatility | IV rank or IV% | Polygon options snapshot (existing) | > 30% |
| Option Volume | 30-day avg option volume | Polygon options snapshot | > 5,000,000 |

### Output: `CSPCandidate` dataclass

```python
@dataclass
class CSPCandidate:
    symbol: str
    # Fundamentals
    revenue_growth_pct: float
    eps_growth_5y_pct: float
    eps_growth_fwd_pct: float
    profit_margin_pct: float
    assets_to_liabilities: float
    free_cash_flow: float
    sector: str
    industry: str
    # Options
    iv_rank: float
    option_volume_30d: float
    # Valuation
    pe_current: float
    pe_5y_avg: float
    pe_10y_avg: float
    price_vs_sma200: float  # % above/below SMA200
    # Regime
    regime: str  # "normal" or "aggressive"
```

---

## Design Section 3: CSP Pricing & Option Selection (`csp_pricing.py`)

### Black-Scholes Proxy Pricing

For backtesting, we simulate put option prices using Black-Scholes since we're not fetching historical option chains:

```python
def bs_put_price(S, K, T, r, sigma) -> float:
    """S=spot, K=strike, T=years to expiry, r=risk-free rate, sigma=IV"""

def bs_put_delta(S, K, T, r, sigma) -> float:
    """Delta of put option (negative, -1 to 0)"""

def estimate_pop(delta) -> float:
    """POP ≈ 1 - |delta| for OTM puts"""
```

### Option Selection Logic

**Parameter Set A (Normal Mode):**

| Parameter | Value |
|-----------|-------|
| DTE target | 30-45 days |
| Strike selection | POP between 70-80% (delta ≈ -0.20 to -0.30) |
| Min monthly yield | 1.5% on cash secured amount |
| Hard abort | < 1% yield → skip, deploy to SPY instead |
| Max monthly yield | 3% (if higher, something's wrong - check for events) |

**Parameter Set B (Aggressive Mode):**

Triggered when: stock touches/approaches 200-SMA OR VIX > configurable threshold (default 30)

| Parameter | Value |
|-----------|-------|
| Strike selection | ATM (delta ≈ -0.50) |
| Target yield | 4-6% on cash secured amount |
| DTE | Same 30-45 days |

### Strike Selection Algorithm

```
1. For each candidate symbol on each screening date:
2. Get current price S, IV (from snapshot or proxy)
3. Determine regime: normal vs aggressive
4. Compute target delta range based on regime
5. Find strike K where BS delta matches target range
6. Compute premium = bs_put_price(S, K, T, r, IV)
7. Compute yield = premium / (K * 100) * 100%  (cash-secured)
8. Validate yield against min/max thresholds
9. Return CSPTrade if all checks pass
```

### `CSPTrade` dataclass

```python
@dataclass
class CSPTrade:
    symbol: str
    open_date: date
    expiry_date: date
    strike: float
    premium_received: float     # Per share (multiply by 100 for contract)
    cash_secured: float         # K * 100
    yield_pct: float            # premium / cash_secured
    delta_at_open: float
    iv_at_open: float
    regime: str                 # "normal" or "aggressive"
    pop_at_open: float
    # State machine
    state: str                  # OPEN_CSP, ROLLING, EXPIRED_OTM, ASSIGNED, CLOSED
    rolls: List[RollEvent]      # History of rolls
    current_value: float        # Current option value (updated daily)
    # Assignment
    shares_assigned: int        # 0 or 100
    assignment_cost: float      # K * 100 if assigned
```

---

## Design Section 4: CSP Lifecycle Engine (`csp_engine.py`)

### Backtest Simulation (Daily-Tick)

Unlike the bar-based BacktestEngine, the CSP engine advances one **calendar day** at a time:

```
for each day in date_range:
    1. Update spot prices for all tracked symbols (from OHLCV data)
    2. Recompute VIX proxy → determine regime (normal/aggressive)
    3. For each OPEN_CSP position:
       a. Reprice option via Black-Scholes with updated S, T, IV
       b. Check roll triggers:
          - Value decay: current_value <= 0.25 * premium_received
          - Time decay: DTE <= 7 AND current_value <= 0.10 * premium_received
       c. If roll triggered → attempt credit-only roll:
          - Close current put (buy back at current_value)
          - Open new put (sell at new strike/expiry)
          - Net credit = new_premium - current_value
          - If net_credit <= 0 → REJECT roll, hold to expiry
       d. If expiry reached:
          - S >= K → EXPIRED_OTM (keep premium)
          - S < K  → ASSIGNED (buy 100 shares at K)
    4. If portfolio has capacity → screen for new CSP candidates
    5. Open new CSP positions from qualified candidates
    6. Record daily portfolio state (cash, positions, P&L)
```

### IV Simulation for Backtesting

Since historical IV data is not available per-symbol:

```python
def estimate_historical_iv(symbol_df, window=30) -> float:
    """
    Proxy IV from realized volatility:
    rv = std(log_returns) * sqrt(252)
    iv_proxy = rv * iv_premium_factor (default 1.2)
    """
```

The `iv_premium_factor` (default 1.2) approximates the typical IV-over-realized-vol premium. This is configurable per backtest.

### VIX Regime Detection

```python
def detect_regime(vix_value: float, sma200_distance_pct: float) -> str:
    """
    Returns "aggressive" if:
      - vix_value > VIX_AGGRESSIVE_THRESHOLD (default 30), OR
      - sma200_distance_pct <= SMA200_TOUCH_PCT (default 2.0, i.e. within 2% of SMA200)
    Otherwise returns "normal"
    """
```

### Portfolio-Level Constraints

| Constraint | Default | Description |
|-----------|---------|-------------|
| `max_concurrent_csps` | 5 | Max open CSP positions at once |
| `max_portfolio_allocation_pct` | 20% | Max % of account in CSP cash reservations |
| `max_sector_concentration` | 2 | Max CSPs in same sector |
| `max_single_stock_pct` | 5% | Max % of portfolio in one symbol |

### RollEvent dataclass

```python
@dataclass
class RollEvent:
    roll_date: date
    roll_type: str              # "out", "up", "down"
    old_strike: float
    old_expiry: date
    new_strike: float
    new_expiry: date
    buyback_cost: float         # Cost to close old position
    new_premium: float          # Premium from new position
    net_credit: float           # new_premium - buyback_cost (must be > 0)
```

---

## Design Section 5: Database Models & Persistence

### New Tables

**`csp_screen_runs`** - Tracks each screening execution

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment |
| run_date | DATETIME | When screening ran |
| total_symbols_screened | INTEGER | S&P 500 count |
| candidates_passed | INTEGER | Symbols that passed all gates |
| config_json | TEXT | Screening parameters used |

**`csp_candidates`** - Symbols that passed screening

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment |
| screen_run_id | INTEGER FK | Links to screen run |
| symbol | VARCHAR | Ticker |
| fundamentals_json | TEXT | All fundamental metrics |
| iv_rank | FLOAT | Implied volatility rank |
| option_volume | FLOAT | 30d avg option volume |
| regime | VARCHAR | "normal" or "aggressive" |
| pe_current | FLOAT | Current P/E ratio |
| pe_5y_avg | FLOAT | 5-year avg P/E |
| price_vs_sma200 | FLOAT | % distance from SMA200 |

**`csp_trades`** - CSP position lifecycle tracking

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment |
| symbol | VARCHAR | Ticker |
| state | VARCHAR | OPEN_CSP, ROLLING, EXPIRED_OTM, ASSIGNED, CLOSED |
| open_date | DATE | Position open date |
| expiry_date | DATE | Current expiry (updates on roll) |
| strike | FLOAT | Current strike price |
| premium_received | FLOAT | Initial premium per share |
| cash_secured | FLOAT | K * 100 |
| yield_pct | FLOAT | Premium / cash secured |
| delta_at_open | FLOAT | Delta when opened |
| iv_at_open | FLOAT | IV when opened |
| regime | VARCHAR | normal / aggressive |
| current_value | FLOAT | Latest option value |
| close_date | DATE | When position closed |
| close_reason | VARCHAR | expired_otm, assigned, rolled |
| total_premium_collected | FLOAT | Sum of all credits (including rolls) |
| rolls_json | TEXT | JSON array of RollEvent records |
| assignment_cost | FLOAT | K * 100 if assigned, NULL otherwise |
| realized_pnl | FLOAT | Total P&L including assignment |

**`csp_backtest_runs`** - Backtest execution records

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment |
| run_date | DATETIME | When backtest ran |
| start_date | DATE | Backtest period start |
| end_date | DATE | Backtest period end |
| initial_capital | FLOAT | Starting account balance |
| config_json | TEXT | All backtest parameters |
| results_json | TEXT | Summary metrics (total return, Sharpe, max DD, etc.) |
| equity_curve_json | TEXT | Daily equity snapshots |
| trades_json | TEXT | All CSP trades with full lifecycle |

### Migration Strategy

Use `ALTER TABLE` for SQLite (consistent with existing project pattern). New tables are additive - no changes to existing Options Edge tables.

---

## Design Section 6: API Endpoints & Frontend

### API Routes (added to `dashboard/backend/api/routes.py`)

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/v1/options-edge/csp/screen` | Run fundamental screener (live Polygon data) |
| GET | `/api/v1/options-edge/csp/screen/{id}` | Get screening results |
| GET | `/api/v1/options-edge/csp/screens` | List past screen runs |
| POST | `/api/v1/options-edge/csp/backtest` | Run CSP lifecycle backtest |
| GET | `/api/v1/options-edge/csp/backtest/{id}` | Get backtest results |
| GET | `/api/v1/options-edge/csp/backtests` | List past backtest runs |

### Frontend Pages (Flask + Jinja2 + Bootstrap 5)

**`/options-edge/csp`** - Main CSP Dashboard

- Screening section: Run screener button, results table with fundamental metrics
- Backtest section: Configure parameters (date range, capital, regime thresholds), run backtest
- Results section: Equity curve (Chart.js), trade log table, summary stats cards

**`/options-edge/csp/screen/{id}`** - Screening Detail

- Table of all S&P 500 symbols with pass/fail per gate
- Qualified candidates highlighted with regime tag
- Click candidate → shows fundamental breakdown + option chain snapshot

**`/options-edge/csp/backtest/{id}`** - Backtest Detail

- Summary cards: Total return, Sharpe, max drawdown, win rate, avg yield
- Equity curve chart (daily)
- Trade lifecycle table: symbol, state, open date, expiry, strike, premium, rolls, outcome
- Roll history breakdown per trade
- Assignment analysis: cost basis, shares held, unrealized P&L

---

## Phase 5: Capital Allocation & Premium Reinvestment

Automated within the CSP engine:

- **50/50 Split**: Each month, divide total premium collected:
  - 50% stays as cash → increases buying power for future CSPs
  - 50% used to market-buy shares of assigned stocks or SPY/VOO
- **Portfolio Allocation**: CSP positions should not exceed ~20% of total account value
- **Assignment Handling**: When assigned, shares are held at cost basis = strike price. Can sell covered calls on assigned shares (future enhancement).

---

## Implementation Phases (Execution Order)

| Phase | Scope | Dependencies |
|-------|-------|-------------|
| 1 | `csp_pricing.py` - BS functions + unit tests | None |
| 2 | `csp_models.py` - Pydantic schemas + DB models | None |
| 3 | `csp_screener.py` - Fundamental screening + tests | Phase 1, Phase 2 |
| 4 | `csp_engine.py` - Lifecycle engine + backtest | Phase 1, 2, 3 |
| 5 | API routes + frontend pages | Phase 4 |
| 6 | Integration testing + validation | Phase 5 |

---

## Deferred (Future Phases)

- **NautilusTrader + IB bridge**: Production execution via Interactive Brokers TWS/Gateway
- **Covered call on assigned shares**: Wheel strategy extension
- **Live option chain data**: Replace BS proxy with real Greeks from IB
- **Real-time position monitoring**: WebSocket updates for open CSP positions
- **Earnings event gate**: Avoid selling puts into earnings if not desired

---

## Non-Negotiable Rules

1. **Never buy back at a loss** - no stop-loss orders on CSPs
2. **Never roll for a debit** - credit-only rolls or hold to expiry
3. **Cash-secured only** - no margin, full cash to cover 100 shares at strike
4. **Accept assignment** - if ITM at expiry, take the shares
5. **Never execute CSP via MT5** - MT5 is for existing spot/CFD strategies only
