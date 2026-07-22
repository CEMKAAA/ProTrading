# Liq Narrative Sol Market Regimes V3

## Status

`RESEARCH_ONLY_OBSERVER_NOT_AN_EXECUTION_FILTER`

Production `LiqNarrativeSolVersion.mq5` was not modified. V1 and V2 remain preserved. V3 replaces neither the production signal path nor the V2 research record.

## Objective

V3 makes the regime lifecycle explicit and live-usable without pretending that a regime label can determine every trade outcome. It combines:

- synchronized H1/H2/H4/D1 structure;
- regime age;
- an explicit transition candidate and confirmation contract;
- H1/H2 pullback/rebound depth;
- volatility depth and acceleration;
- an outcome-free structural hint;
- a separate prior-trades-only walk-forward edge hint.

## Causality Contract

- Every market feature uses completed bars only.
- A D1 observation becomes available when the next D1 session opens.
- H1/H2/H4/D1 horizons share the same completed D1-session anchors.
- Trade outcomes are joined only after the state machine has generated all market states.
- Walk-forward edge hints can see only trades strictly earlier than the current trade.
- Prefix-invariance is checked by rerunning the state machine on truncated histories.

## Core Scores

### Trend depth

The bounded `trend_depth_score` is:

- 40% absolute synchronized 100-session macro return divided by realized-volatility noise;
- 30% D1 100-session efficiency ratio;
- 15% H4/D1 directional agreement;
- 15% H1/H2/H4/D1 20-session directional persistence relative to the macro direction.

Hysteresis:

- range to trend candidate: score >= 0.62;
- trend remains active while score >= 0.42;
- score >= 0.76 is decisive trend evidence;
- score <= 0.28 is decisive range evidence.

### Volatility depth

The bounded `volatility_depth_score` is:

- 40% RV60/RV100 depth;
- 35% trailing RV20 percentile;
- 25% RV20/RV100 acceleration.

Hysteresis:

- low to high volatility candidate: score >= 0.62;
- high volatility remains active while score >= 0.42;
- score >= 0.76 is decisive expansion;
- score <= 0.28 is decisive contraction.

The descriptive depth label is `COMPRESSED`, `NORMAL`, `ELEVATED`, or `EXTREME`. The separate impulse label is `EXPANDING`, `STEADY`, or `CONTRACTING`.

## Exact Transition Contract

The official core remains one of:

- `TREND_HIGH_VOL`
- `TREND_LOW_VOL`
- `RANGE_HIGH_VOL`
- `RANGE_LOW_VOL`

Rules:

1. A different candidate is exposed as `WATCH` on its first completed session.
2. The same candidate becomes `DEVELOPING` while confirmation is pending.
3. Decisive evidence confirms after exactly three completed sessions.
4. Ordinary evidence confirms after exactly five completed sessions.
5. A candidate reset or change restarts the counter.
6. The confirmation requirement is frozen when the candidate starts; it cannot move mid-transition.
7. After confirmation the state is `FRESH_CONFIRMED`; otherwise a non-pending state is `STABLE`.

Observed exact-feed result:

- 36 confirmed core transitions;
- first warning latency: one completed session;
- confirmation latency values: only 3 or 5 sessions;
- median confirmation latency: 5 sessions;
- maximum confirmation latency: 5 sessions.

Core transitions include volatility-only changes. The slower trend/range dimension generally persists for multi-month periods, while the volatility layer can change more frequently.

## Regime Age

Effective age includes the sessions spent confirming the successful candidate:

- `FRESH`: 1-10 sessions;
- `ESTABLISHED`: 11-40;
- `MATURE`: 41-80;
- `LATE`: 81+.

Confirmed age is also stored separately and begins at one on the confirmation session.

## H1/H2 Transition Phase

H1/H2 five-session and 20-session returns are normalized by trailing daily realized volatility. Direction and agreement produce:

- `ALIGNED_IMPULSE`
- `ALIGNED`
- `NEUTRAL_ROTATION`
- `SHALLOW_PULLBACK`
- `DEEP_PULLBACK`
- `SHALLOW_REBOUND`
- `DEEP_REBOUND`
- `REVERSAL_PRESSURE`

Pullback is counter to an UP macro direction. Rebound is counter to a DOWN macro direction. `REVERSAL_PRESSURE` requires persistent medium-horizon opposition or a developing opposite macro-direction candidate; it is not triggered by one bar.

## Hint Layers

### Structural hint

This is outcome-free and descriptive. Examples are:

- `TREND_CONTINUATION_SUPPORT`
- `TREND_RETRACE_SETUP`
- `RANGE_COMPRESSION`
- `RANGE_EXPANSION_RISK`
- `REVERSAL_RISK`
- `TRANSITION_UNCERTAIN`
- `PRICE_DISCOVERY_RISK`

These labels describe market mechanics. They are not permission to open, block, or flip a trade.

### Walk-forward edge hint

This estimator uses only prior trades from a trailing 730-day window with a 180-day half-life. Context similarity includes core regime, age bucket, H1/H2 phase family, volatility depth, and transition lifecycle. A 20-trade global prior shrinks sparse contexts.

Recent context (0-180 days) and older context (181-730 days) must agree before a directional label is issued:

- `FAVORABLE`: stable positive context with positive lower uncertainty bound;
- `CAUTION`: stable negative context with negative/flat upper uncertainty bound;
- `REGIME_CONFLICT`: recent and older context disagree;
- `MIXED_UNCONFIRMED`: not enough temporal agreement for a directional claim;
- `INSUFFICIENT_CONTEXT` / `INSUFFICIENT_HISTORY`: support gate failed.

`REGIME_CONFLICT` does not mean a losing trade. It means the detector refuses to force a directional claim while the context mapping is changing.

## Temporal Results

Strict walk-forward `FAVORABLE` results:

| Year | Trades | Avg R/trade |
|---:|---:|---:|
| 2021 | 14 | +0.042 |
| 2022 | 67 | +0.163 |
| 2023 | 9 | +0.133 |
| 2024 | 4 | +0.929 |
| 2025 | 66 | +0.396 |
| 2026 YTD | 77 | +0.520 |

Full covered `FAVORABLE`: 237 trades, +82.65R, +0.349R/trade.

This is a meaningful observer hint, not a standalone strategy: support is sparse in 2023-2024, and the production path has not been rerun with this label affecting execution.

Full covered `CAUTION`: 26 trades, -4.03R, -0.155R/trade. Its support is too small for an execution block and 2024 was approximately flat rather than negative.

## Current State

At the latest completed exact-feed session, 2026-07-20 UTC:

- core: `TREND_LOW_VOL`;
- effective age: 74 sessions, `MATURE`;
- transition status: `STABLE`;
- macro direction: `UP`;
- H1/H2 phase: `REVERSAL_PRESSURE`;
- volatility depth: `NORMAL`;
- volatility impulse: `STEADY`;
- structural hint: `REVERSAL_RISK`.

This means an established low-volatility uptrend is experiencing persistent H1/H2 counter-pressure. It is not an automatic short or flip instruction.

## Promotion Gate

V3 remains observer-only until all conditions hold:

1. Formula is frozen before paper-forward collection.
2. Regime and hint columns are logged without changing production trades.
3. Paper-forward transitions match offline prefix-causal output.
4. A dedicated path-dependent EA test confirms any proposed use.
5. Any execution rule has minimum support and remains stable across forward periods.

## Live Observer Integration

V3 is integrated into `LiqNarrativeSol_Advanced.mq5` as an observer-only module:

- implementation: `LiqNarrativeSol_RegimeV3.mqh`;
- build: `2026-07-22.sol-advanced-regime-v3-observer`;
- dashboard: colored `MARKET REGIME V3` panel above the existing controls;
- lifecycle: one forced reconstruction on initialization and incremental refreshes from the timer;
- execution contract: regime state is not read by signal generation, order opening, position management, stop/target geometry, or bridge publication;
- production reference: `LiqNarrativeSolVersion.mq5` remains unchanged.

The integration verifier recursively compares all signal/geometry dependencies reachable from the production signal roots. The current baseline is 57 functions and 23 signal-affecting input declarations/defaults, all byte-for-byte equal to `LiqNarrativeSolVersion.mq5`. The verifier also rejects observer calls inside execution functions and requires a clean MetaEditor compile log.

```powershell
python scripts\verify_liq_advanced_regime_v3.py
```

Verified compile result: `0 errors, 0 warnings`.

## Reproduction

```powershell
python scripts\research_sol_market_regimes_v3.py
python scripts\verify_sol_market_regimes_v3.py
```

Outputs:

- `logs/sol_market_regimes_v3.daily_states.csv`
- `logs/sol_market_regimes_v3.transition_events.csv`
- `logs/sol_market_regimes_v3.trades.csv`
- `logs/sol_market_regimes_v3.json`
## Frozen 56.80 Candidate

Status: `PRESERVED_IN_LiqNarrativeSol_Advanced_ONLY_DEFAULT_OFF`

This candidate is an opt-in post-signal regime filter. It does not modify raw `BuildSignals` mathematics and it does not modify `LiqNarrativeSolVersion.mq5`. A rejected opposite setup remains a valid reverse-exit event for an existing position but cannot open a new position.

Research source: `logs/sol_market_regimes_v3.trades.csv`, covering 2021-03-23 through 2026-07-16.

Frozen result:

- source trades: 941;
- retained trades: 581 (61.7428%);
- rejected entries: 360;
- retained wins/losses: 330W / 251L;
- retained WR: 56.7986%;
- worst covered year: 2022 at 55.4545%.

Frozen rejection rules:

1. `RANGE_LOW_VOL + MATURE + STABLE + continuation`
2. `TREND_LOW_VOL + NEUTRAL_ROTATION + macro UP`
3. `ALIGNED_IMPULSE + macro DOWN + continuation`
4. `RANGE_HIGH_VOL + DEVELOPING`
5. `RANGE_LOW_VOL + DEEP_REBOUND + NORMAL volatility`
6. `RANGE_LOW_VOL + SHALLOW_REBOUND`
7. `ALIGNED + FRESH + STABLE`
8. `SHALLOW_PULLBACK + MATURE + STABLE`
9. `RANGE_HIGH_VOL + ALIGNED_IMPULSE`
10. `RANGE_LOW_VOL + COMPRESSED + macro DOWN + reversal`
11. `ALIGNED_IMPULSE + NORMAL volatility + reversal`
12. `SHALLOW_PULLBACK + NORMAL volatility`

Production contract:

- Dashboard toggle: `FILTER ON/OFF`.
- Default: OFF.
- Unknown/unavailable regime history: fail open and expose the unclassified counter.
- Historical audit, optimizer/backtest, and live execution use the same rules.
- Historical state lookup uses the latest completed causal snapshot available at signal time.
- Filtered reverse signals use the raw causal stream for exit timing.
- cTrader propagation uses the existing scoped atomic latest/outbox path with a `RegimeFilterCloseOnly` event.
- Do not hardcode the research start date to force exact headline metrics; longer broker history must remain valid.
