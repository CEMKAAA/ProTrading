# Options Volatility Edge Module Spec (S&P 500 Scanner)

## 1) Objective
Build a production module that scans the S&P 500 options universe, filters high-quality short-vol candidates, ranks them, constructs trade structures (credit spreads/condors), and outputs deterministic trade cards with optional LLM explanations.

This module is designed as a portfolio-level edge system:
- Edge source: IV risk premium + strict liquidity/event gating
- Edge amplifier: portfolio construction (sector/risk concentration control)
- Edge durability: repeatable pipeline + walk-forward validation + risk kill-switches

## 2) Scope And Non-Goals
In scope:
- Universe scan, hard gates, scoring, top-N portfolio selection
- Strategy constructor for defined structures
- Backtest and walk-forward protocol integrated with existing engine/services
- LLM explanation layer (read-only analysis, no autonomous trade decisions)

Out of scope (Phase 1):
- Autonomous live order routing
- Unbounded strategy generation by LLM
- Pure news/sentiment-only trading

## 3) Integration Map (Current Repo)
Primary integration points:
- `dashboard/backend/core/strategy_registry.py`
- `dashboard/backend/core/config_builder.py`
- `dashboard/backend/core/backtest_engine.py`
- `dashboard/backend/core/walk_forward.py`
- `dashboard/backend/services/backtest_service.py`
- `dashboard/backend/api/routes.py`
- `dashboard/backend/models/database.py`

Recommended new modules:
- `dashboard/backend/core/options_edge/scan_engine.py`
- `dashboard/backend/core/options_edge/score_engine.py`
- `dashboard/backend/core/options_edge/strategy_builder.py`
- `dashboard/backend/core/options_edge/portfolio_allocator.py`
- `dashboard/backend/core/options_edge/llm_reporter.py`
- `dashboard/backend/core/options_edge/contracts.py`

## 4) Data Model
Use SQLite tables (or JSON columns in existing DB if preferred for v1). Keep all snapshots immutable by `scan_id`.

### 4.1 `options_scan_run`
- `scan_id` TEXT PRIMARY KEY
- `scan_ts` DATETIME (NY normalized)
- `universe_size` INT
- `passed_gate_count` INT
- `selected_count` INT
- `llm_model` TEXT
- `llm_cost_usd` REAL
- `latency_sec` REAL
- `status` TEXT
- `error` TEXT

### 4.2 `options_stock_snapshot`
- `scan_id` TEXT
- `symbol` TEXT
- `sector` TEXT
- `price` REAL
- `iv30` REAL
- `hv30` REAL
- `iv_rank_252` REAL
- `iv_hv_spread` REAL
- `avg_opt_volume_30d` REAL
- `avg_oi_30d` REAL
- `avg_bid_ask_pct` REAL
- `earnings_date` DATE
- `days_to_earnings` REAL
- `borrow_rate` REAL
- `gate_pass` INT
- `gate_reasons` TEXT (JSON array)

### 4.3 `options_candidate_score`
- `scan_id` TEXT
- `symbol` TEXT
- `score_total` REAL (0-100)
- `score_vol_edge` REAL
- `score_liquidity` REAL
- `score_event_timing` REAL
- `score_risk` REAL
- `penalty_sector_concentration` REAL
- `rank_global` INT
- `rank_in_sector` INT

### 4.4 `options_trade_candidate`
- `scan_id` TEXT
- `symbol` TEXT
- `structure_type` TEXT (`put_credit_spread`, `call_credit_spread`, `iron_condor`, `strangle`, `straddle`)
- `expiry_date` DATE
- `dte` INT
- `legs_json` TEXT
- `net_credit` REAL
- `max_profit` REAL
- `max_loss` REAL
- `pop_est` REAL
- `delta_net` REAL
- `theta_net` REAL
- `vega_net` REAL
- `breakeven_low` REAL
- `breakeven_high` REAL
- `quality_flags` TEXT (JSON array)

## 5) Hard Gates (Deterministic)
Reject candidate if any gate fails.

Required baseline gates:
1. Liquidity:
- `avg_opt_volume_30d >= VOLUME_MIN`
- `avg_oi_30d >= OI_MIN`
- `avg_bid_ask_pct <= SPREAD_PCT_MAX`

2. Volatility regime:
- `iv_rank_252 >= IVR_MIN`
- `iv30 - hv30 >= IV_HV_SPREAD_MIN`

3. Event risk:
- `days_to_earnings >= EARNINGS_BUFFER_MIN_DAYS`
- (or explicit earnings policy for event plays, if enabled)

4. Financing/risk:
- `borrow_rate <= BORROW_MAX` (for structures exposed to borrow constraints)

5. Strategy constructability:
- Valid chain depth at target DTE bucket and strike deltas
- Credit/risk ratio above minimum

All gate values must be stored in preset config (not hardcoded).

## 6) Scoring Formula (0-100)
Normalize each component to `[0, 1]`, then weighted sum.

Definitions:
- `vol_edge = clip((iv30 - hv30) / max(hv30, 1e-6), -1, 3)`
- `liq = liquidity composite from spread/volume/OI`
- `evt = event timing quality`
- `risk = borrow/dispersion/correlation quality`

Base score:
`score_raw = w1*vol_edge_n + w2*liq_n + w3*evt_n + w4*risk_n`

Sector concentration penalty:
`penalty_sector = lambda * max(0, sector_weight_after_add - sector_cap)`

Final:
`score_total = clip(100 * (score_raw - penalty_sector), 0, 100)`

Suggested start weights:
- `w1=0.40` (vol edge)
- `w2=0.30` (liquidity)
- `w3=0.15` (event timing)
- `w4=0.15` (risk quality)

## 7) Portfolio Construction
Select top `N` (default `N=8`) after constraints.

Constraints:
- Max per sector weight (e.g. `<= 30%`)
- Max single-name portfolio allocation
- Max aggregate short vega
- Max aggregate event-day exposure
- Max correlated cluster exposure (same sector + high return correlation)

Allocator objective:
- maximize `sum(score_total_i * alloc_i)` subject to constraints

## 8) Strategy Builder Rules
Target expiry:
- Preferred `30-45 DTE`
- Fallback bucket if no valid liquidity: `21-55 DTE`

Default structure mapping:
- High IVR + range-friendly: `iron_condor`
- Moderate skew + directional lean: `credit_spread`

Initial leg heuristics (v1):
- Short strike near target delta magnitude (`0.15-0.30`)
- Long hedge wing at risk budget width
- Reject if spread too wide or credit too thin

Minimum quality:
- `credit / width >= MIN_CREDIT_WIDTH_RATIO`
- `pop_est >= POP_MIN`

## 9) LLM Usage Policy
LLM is explanation-only:
- No autonomous ranking override
- No autonomous order placement
- Must cite numeric fields from stored snapshots

Prompt contract:
- Input: compact JSON with metrics and selected candidates
- Output: strict JSON:
  - `market_summary`
  - `risk_summary`
  - `candidate_notes[]` with numeric references
  - `warnings[]`

If parse fails, system falls back to deterministic non-LLM report.

## 10) Backtest Protocol
### 10.1 Simulation cadence
- Run scanner once per trading day (configurable time, default near close)
- Build portfolio from that day snapshot
- Enter next session open/close per strategy policy
- Manage exits via deterministic rules

### 10.2 Exit model
For short premium structures (example defaults):
- Profit-take at `50% max profit`
- Stop at `1.5x to 2.0x initial credit loss`
- Time stop at `X DTE remaining` (e.g. 14 DTE)
- Hard exit before earnings if policy requires

### 10.3 Validation protocol
Mandatory:
- Walk-forward (rolling/expanding)
- Purged splits around earnings/events
- Cost stress scenarios:
  - +25% slippage
  - +50% spread
  - delayed fills
- Bootstrap/Monte Carlo on trade sequence

Deployment pass criteria (proposed):
- Sharpe > 1.2
- Profit Factor > 1.35
- Max Drawdown < 15%
- Positive expectancy after stressed costs
- Stable performance across folds (no single-fold dominance)

## 11) API Endpoints (Proposed)
- `POST /api/v1/options-edge/scan/run`
- `GET /api/v1/options-edge/scan/{scan_id}`
- `GET /api/v1/options-edge/scan/{scan_id}/candidates`
- `GET /api/v1/options-edge/scan/{scan_id}/report`
- `POST /api/v1/options-edge/backtest/run`

## 12) Preset Families
1. `conservative_income`
- stricter liquidity gates, lower leverage, tighter sector caps

2. `balanced_edge`
- baseline production preset

3. `aggressive_harvest`
- looser score threshold, higher turnover, stricter portfolio drawdown stop

## 13) Deployment Checklist
Data:
- Universe snapshot completeness verified
- Chain quality checks pass
- Earnings calendar integrity checks pass

Model:
- Gate and score version IDs stamped in each scan
- LLM output schema validation in place
- Deterministic fallback active

Risk:
- Position sizing caps active
- Sector and vega caps active
- Kill-switch thresholds configured

Ops:
- End-to-end scan latency under target
- Cost monitor for API and LLM spend
- Alerting for missing data / stale chain / failed scan

## 14) Build Plan (Phased)
Phase 1 (Deterministic core):
- Implement scanner + gates + scoring + top-N allocator without LLM dependency
- Add scan persistence tables and API

Phase 2 (Strategy constructor):
- Add spread/condor builder with quality flags and PnL profile payload

Phase 3 (Backtest + WF):
- Add event-driven portfolio backtest path + walk-forward/stress reports

Phase 4 (LLM explanation):
- Add strict-schema LLM reporter and A/B compare against non-LLM baseline

## 15) Acceptance Criteria For “Edge Candidate”
The module is considered a true candidate edge only if:
1. Deterministic baseline already profitable (LLM off)
2. LLM improves usability/report quality without degrading outcomes
3. Portfolio-level risk limits hold in stress regimes
4. Out-of-sample and walk-forward remain positive after realistic costs

