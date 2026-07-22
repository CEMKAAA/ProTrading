# Liq Narrative Sol Market Regimes V2

## Status

`RESEARCH_ONLY_NOT_EA_PATH_VALIDATED`

Production `LiqNarrativeSolVersion.mq5` was not modified. V1 was frozen before V2 work:

- `scripts/research_sol_market_regimes_v1_frozen.py`
- `IndicatorCodeExamples/DocumentsForAi/LIQ_NARRATIVE_SOL_MARKET_REGIMES_V1_FROZEN.md`

## Exact Data Coverage

- Exact Exness JP225m signal sample: 2020-12-18 through 2026-07-16.
- Regime-covered sample after causal warm-up: 941 trades.
- Exness tester confirms H1 history begins at 2019-07-16 07:00 and H2 at 2019-07-16 06:00.
- Six years of exact-feed research is accepted. A job named `10Y` is not treated as ten years when the broker cache starts in 2019.

## Production-Oriented Formula

The detector is hierarchical. Outcome labels never enter state generation.

### Structural Core

Four canonical states:

- `TREND_HIGH_VOL`
- `TREND_LOW_VOL`
- `RANGE_HIGH_VOL`
- `RANGE_LOW_VOL`

Inputs:

- H1/H2/H4/D1 returns synchronized to the same completed 5/20/100 D1 sessions.
- Macro trend signal-to-noise: median four-TF 100-session return divided by 100-session realized-volatility noise.
- H4/D1 direction agreement.
- D1 100-session efficiency ratio.
- D1 60/100-session volatility ratio.
- Trailing realized-volatility percentile.

Hysteresis:

- Trend enters at `|trend_z| >= 0.85`, `efficiency_100 >= 0.18`, and H4/D1 agreement.
- Trend exits below `|trend_z| < 0.55` or `efficiency_100 < 0.10`.
- High volatility enters at `RV60/RV100 >= 1.10` or trailing percentile >= 70%.
- High volatility exits at `RV60/RV100 <= 0.95` and percentile <= 55%.
- A structural state change requires 15 completed-session confirmations.

### Tactical Layer

- Tactical `TREND/RANGE x HIGH/LOW_VOL` uses D1 20-session efficiency and RV20/RV100.
- Tactical state changes require five completed-session confirmations.
- Macro direction uses +/-3% hysteresis on the synchronized four-TF 100-session return.
- H1/H2 five-session return labels the transition as aligned, pullback, or rebound.

### Session Structure

Trailing 20-session H1 ranges are grouped into UTC activity buckets:

- Asia: 00:00-05:59
- Europe: 06:00-11:59
- US: 12:00-19:59
- Late: 20:00-23:59

The detector records dominant session and activity concentration. This is market data, not a hard-coded trade-hour filter.

## Why 2021 Changed Later

The old `DOWN_REBOUND` label was too coarse. Its expectancy changed as follows:

- 2021: +0.269R/trade.
- 2022: +0.148R/trade.
- 2023: -0.128R/trade.
- 2024: +0.152R/trade on only 14 trades.
- 2025: -0.227R/trade.

The internal composition was not constant:

- 2021 reversal setups in this phase averaged +0.439R; continuation averaged +0.046R.
- 2023 reversal averaged -0.122R and continuation -0.135R. Both mechanisms failed.
- 2025 reversal averaged -0.106R and continuation -0.481R.
- The 2021 edge was concentrated in 00:00-11:00 UTC. In 2023 and 2025, later-session expectancy deteriorated materially.
- Macro depth also differed: the phase averaged only -0.189% macro return in 2021 versus -6.199% in 2025.

Therefore this was not the same economic regime repeating with random noise. A sign-only label merged shallow rotation, deep drawdown, different session leadership, and different route behavior.

## Four-Regime Temporal Results

Average baseline R per trade:

| Structural state | 2021-22 dev | 2023 validation | 2024+ forward |
|---|---:|---:|---:|
| RANGE_HIGH_VOL | +0.111 | -0.075 | +0.146 |
| RANGE_LOW_VOL | +0.129 | -0.003 | +0.284 |
| TREND_HIGH_VOL | insufficient dev support | -0.297 | +0.348 |
| TREND_LOW_VOL | +0.100 | +0.434 | +0.479 |

The detector identifies economically meaningful states, but the strategy/state payoff mapping still changes. `TREND_HIGH_VOL` is the clearest example: poor in 2023, strongly positive forward.

Dominant session alone is also insufficient:

- Asia-dominant 2023: -0.065R/trade.
- Asia-dominant 2024+: +0.317R/trade.

This confirms that production decisions must use hierarchical context, persistence, and forward evidence rather than one categorical switch.

## Flip Hypothesis

A paired normal/opposite-direction screen was tested. It is an offline screen, not a final EA-path result, because mixing rows from globally routed runs can change later reverse exits.

Interesting but unstable observation:

- Old `UP_ALIGNED` in 2023: normal -0.162R, opposite direction +0.249R.
- The same opposite-direction choice from 2024 onward: -0.306R.

Expanding walk-forward policy:

- Each test year used prior years only.
- Minimum state support: 30 trades.
- Flip required >0.10R improvement and positive expected R in prior data.
- 2023-2026 baseline: 628 trades, +106.20R, +0.169R/trade.
- Adaptive flip screen: 628 trades, +33.09R, +0.053R/trade.

Decision: reject automatic regime flip. Keep it as a falsified hypothesis unless genuinely new causal information is added.

## Current State

At the latest available completed session, 2026-07-20 UTC:

- Structural: `TREND_HIGH_VOL`, confirmed age 17 sessions.
- Tactical: `RANGE_HIGH_VOL`.
- Macro direction: UP.
- Transition: PULLBACK.
- Dominant session: ASIA.

This is an observer state, not an instruction to alter production positions.

## Decision

- Preserve production SolVersion unchanged.
- Preserve V1 frozen and continue V2 as the research line.
- Do not add a flip or block rule to Advanced from these results.
- Next valid promotion gate is paper-forward logging of the frozen V2 state formula followed by a dedicated path-dependent EA run.

## Reproduction

```powershell
python scripts\research_sol_market_regimes_v2.py
```

Outputs:

- `logs/sol_market_regimes_v2.daily_states.csv`
- `logs/sol_market_regimes_v2.trades.csv`
- `logs/sol_market_regimes_v2.walk_forward_flip.csv`
- `logs/sol_market_regimes_v2.json`
