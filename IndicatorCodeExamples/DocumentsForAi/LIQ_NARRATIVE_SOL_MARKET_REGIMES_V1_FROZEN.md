# Liq Narrative Sol Market Regime Research

## Scope

- Production source: `IndicatorCodeExamples/LiqNarrativeSolVersion.mq5`.
- Production source was not modified.
- Trade sample: 968 completed V14 trades from 2021-01-01 through 2026-07-16 UTC.
- Market rates: JP225m H1, H2, H4, and D1.
- This is about 5.6 years of data, not a true ten-year sample.

## Causality Contract

The descriptive episode map and the live-knowable market detector are deliberately separate.

- Descriptive episodes use realized trade outcomes. They explain history and must never be read by an EA.
- Causal month M features use only bars completed before 00:00 UTC on the first day of month M.
- H1, H2, H4, and D1 are anchored to the same prior 5, 20, and 100 completed D1 sessions.
- No H1/H2 bar-count shortcut is used. Such a shortcut gives each timeframe a different calendar horizon and produced a false-looking separation in early experiments.

## Observed Four-Month Performance Blocks

Classification uses expectancy, not WR: GOOD >= +0.12R/trade, BAD <= -0.12R/trade, otherwise BREAK_EVEN. Reverse exits produce variable R, so WR alone is insufficient.

| Period | Trades | Avg R/trade | State |
|---|---:|---:|---|
| 2021-01 to 2021-04 | 47 | +0.176 | GOOD |
| 2021-05 to 2021-08 | 52 | +0.152 | GOOD |
| 2021-09 to 2021-12 | 60 | +0.227 | GOOD |
| 2022-01 to 2022-04 | 64 | +0.156 | GOOD |
| 2022-05 to 2022-08 | 57 | -0.043 | BREAK_EVEN |
| 2022-09 to 2022-12 | 60 | +0.055 | BREAK_EVEN |
| 2023-01 to 2023-04 | 58 | -0.008 | BREAK_EVEN |
| 2023-05 to 2023-08 | 48 | -0.292 | BAD |
| 2023-09 to 2023-12 | 63 | +0.051 | BREAK_EVEN |
| 2024-01 to 2024-04 | 51 | -0.006 | BREAK_EVEN |
| 2024-05 to 2024-08 | 62 | +0.291 | GOOD |
| 2024-09 to 2024-12 | 66 | +0.203 | GOOD |
| 2025-01 to 2025-04 | 63 | +0.025 | BREAK_EVEN |
| 2025-05 to 2025-08 | 66 | -0.009 | BREAK_EVEN |
| 2025-09 to 2025-12 | 52 | +0.693 | GOOD |
| 2026-01 to 2026-04 | 61 | +0.213 | GOOD |
| 2026-05 to 2026-07 | 38 | +0.955 | GOOD, partial block |

The non-optimized four-month table supports the user's observation: strategy compatibility persists for roughly four to five months and can spend long intervals near break-even.

## Retrospective Change-Point Episodes

A penalized 3-6 month segmentation finds the major bad episodes at:

- 2022-03 to 2022-07: 71 trades, -0.185R/trade.
- 2023-02 to 2023-07: 80 trades, -0.303R/trade.
- 2023-11 to 2024-03: 65 trades, -0.163R/trade.
- 2025-03 to 2025-07: 84 trades, -0.158R/trade.

These boundaries are explanatory only. They are selected using realized outcomes and therefore are not tradable signals.

## Causal Multi-TF Detector

The current research detector is intentionally simple and interpretable:

1. Macro score: median return of H1, H2, H4, and D1 over the same 100 completed D1 sessions.
2. Macro direction: switch UP only above +5%, switch DOWN only below -5%; remain in the prior state inside the band.
3. Transition score: median H1/H2 return over the same five completed D1 sessions.
4. Phase labels:
   - UP_ALIGNED: macro UP, H1/H2 transition non-negative.
   - UP_PULLBACK: macro UP, H1/H2 transition negative.
   - DOWN_ALIGNED: macro DOWN, H1/H2 transition non-positive.
   - DOWN_REBOUND: macro DOWN, H1/H2 transition positive.
5. H4/D1 100-session consensus is exported separately as the slow structural anchor.

This explicitly includes H2 and H1. H4/D1 describe broad structure; H1/H2 identify the internal transition phase.

## Temporal Stability Test

Average R per trade by causal phase:

| Phase | 2021-22 development | 2023 validation | 2024+ forward |
|---|---:|---:|---:|
| DOWN_ALIGNED | +0.091 | +0.113 | +0.005 |
| DOWN_REBOUND | +0.183 | -0.128 | -0.117 |
| UP_ALIGNED | +0.043 | -0.162 | +0.422 |
| UP_PULLBACK | +0.029 | -0.018 | +0.166 |

This proves two things:

- The market-state detector captures real structural transitions.
- The mapping from market state to Sol profitability is not stationary enough to become a production block/allow rule yet.

A rule such as `block DOWN_REBOUND` would have been selected by recent data but contradicted 2021-22. A rule such as `trade only UP_ALIGNED` would have failed badly in 2023. Neither is production-safe.

## Current Reading

At the 2026-07 month open:

- Macro regime: UP.
- Regime age: 13 observed months.
- Phase: UP_ALIGNED.
- Four-TF 100-session median return: +28.52%.
- H1/H2 five-session median return: +2.19%.

This is a month-open reading, not an intramonth recomputation and not a performance guarantee.

## Decision

- Keep `LiqNarrativeSolVersion.mq5` unchanged.
- Retain this detector as `RESEARCH_ONLY_NOT_A_PRODUCTION_FILTER`.
- Use the generated state as an audit/feature column first, then require genuine paper-forward evidence before allowing it to alter risk or entries.
- Any future finalist must be rerun through the path-dependent EA audit because filtering an entry changes later reverse-exit paths.

## Reproduction

```powershell
python scripts\research_sol_market_regimes.py
```

Outputs:

- `logs/sol_market_regimes.monthly.csv`
- `logs/sol_market_regimes.blocks4.csv`
- `logs/sol_market_regimes.episodes.csv`
- `logs/sol_market_regimes.json`
