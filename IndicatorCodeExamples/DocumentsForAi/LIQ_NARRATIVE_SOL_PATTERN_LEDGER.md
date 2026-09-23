# Liquidity Narrative Sol Pattern Research Ledger

## Purpose

This file is the durable registry for strong JP225 SolVersion patterns. A pattern may be recorded here before it is production-proven, but its evidence level must be explicit.

The production source is immutable during research:

- `IndicatorCodeExamples/LiqNarrativeSolVersion.mq5`
- Research changes belong only in `IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5` (canonical path since the EA family migration).

## Evidence Levels

- `DISCOVERED`: descriptive result only; vulnerable to selection bias.
- `TEMPORAL_OOS`: survived development/validation/forward separation.
- `EA_PATH_TESTED`: survived the real path-dependent EA audit, including reverse-signal exits.
- `PAPER_FORWARD`: survived unseen forward data after discovery.
- `PRODUCTION_CANDIDATE`: passed all earlier levels with acceptable frequency and drawdown.

## Data Coverage

- V14 journal period: `2020-12-18` through `2026-07-16` UTC.
- V14 sample: `975` trades, `465W / 510L`, `47.6923% WR`, `+144.996R`.
- The worker has JP225 broker history from 2019 onward. This is not a true ten-year sample.
- Every future result must report exact start/end dates. A UI label such as `10Y` is not evidence of ten years of broker data.

## Candidate Registry

### PAT-001: Autumn Reversal

- Status: `EA_PATH_TESTED`
- Definition: signal month is September, October, or November UTC and the Sol session router preserves the base liquidity-sweep reversal direction (`sol_session_reversal`).
- Total: `140` trades, `85W / 55L`, `60.7143% WR`, `+50.148R`.
- Development through 2022: `55` trades, `58.18% WR`, `+18.96R`.
- Validation 2023: `31` trades, `61.29% WR`, `+5.16R`.
- Forward 2024 onward: `54` trades, `62.96% WR`, `+26.02R`.
- Monthly: Sep `62.75%`, Oct `58.54%`, Nov `60.42%`.
- Strength: directionally stable across all temporal partitions.
- EA-path verification: the autumn-entry audit retained all raw opposite signals as exits and reproduced this subset exactly.
- Risk: only about 25-30 trades per complete year and discovered after broad pattern search. It fails the standalone annual-frequency requirement.
- Next test: paper-forward observation or use as one component of a broader regime portfolio, not as a standalone production strategy.

### PAT-002: Autumn Entries, All Routes

- Status: `EA_PATH_TESTED`
- Definition: accept entries in September, October, and November UTC; preserve the existing Sol router direction. Raw opposite signals from every month remain valid exits.
- Total: `238` trades, `132W / 106L`, `55.4622% WR`, `+65.1649R`.
- Yearly: 2021 `50.94%`, 2022 `51.06%`, 2023 `61.54%`, 2024 `51.02%`, 2025 `64.86%`.
- Development through 2022: `100` trades, `51.00% WR`, `+23.232R`.
- Validation 2023: `52` trades, `61.54% WR`, `+10.580R`.
- Forward 2024 onward: `86` trades, `56.98% WR`, `+31.353R`.
- Strength: every complete calendar year is above 50% WR and the true path-dependent audit equals the descriptive result.
- Risk: only 37-53 trades per complete year, far below the standalone target of roughly 170-200 trades/year. The season was discovered after broad calendar search.
- Decision: retain as a strong regime component; do not promote as the sole production strategy.
### GEO-001: Price-Normalized Pip SL

- Status: `REJECTED`
- Motivation: a fixed JP225 `4000 pip` SL equals `400` price units at every historical price. As the index price rises, that stop becomes progressively smaller as a percentage of price.
- Reference observation: `400 / 66,788.3 = 0.598907%` of entry price.
- Proposed causal formula:

  `dynamic_sl_pips = configured_pips * signal_entry / reference_price`

  With `configured_pips=4000` and `reference_price=66,788.3`, the current geometry is unchanged.
- Example: at the 2021 median entry `28,860.8`, the equivalent stop is approximately `1,728.9 pips`, not `4000 pips`.
- Strength: scale-invariant and known entirely at signal time.
- Real EA-path baseline: `975` trades, `465W / 510L`, `47.6923% WR`, `+144.996R`.
- Real EA-path normalized result: `975` trades, `383W / 592L`, `39.2821% WR`, `+67.492R`.
- Delta: frequency unchanged, WR `-8.4102` percentage points, net result `-77.504R`.
- Yearly effect: normalized WR was worse in every reported year from 2020 through 2026. The largest degradation occurred in 2023-2025.
- Route effect: continuation fell from `46.51%` to `36.63%`; reversal fell from `48.57%` to `41.25%`.
- Conclusion: full proportional normalization over-tightens historical stops and is not a production candidate.
- Research note: fractional/hybrid scaling may still be tested, but it must be selected on older development years and judged on untouched later years before a full EA-path finalist run.

### GEO-002: Fractional Price-Normalized Pip SL

- Status: `REJECTED`
- Formula: `effective_pips = 4000 * (entry / 66788.3)^alpha`.
- `alpha=0.25`: `975` trades, `45.8462% WR`, `+133.435R`.
- `alpha=0.50`: `975` trades, `43.0769% WR`, `+91.407R`.
- `alpha=0.75`: `975` trades, `40.9231% WR`, `+74.941R`.
- Baseline `alpha=0`: `47.6923% WR`, `+144.996R`.
- Development/forward check: even `alpha=0.25` reduced development WR to `45.16%` and forward WR to `46.62%`; its forward net R was effectively flat versus baseline while total robustness fell.
- Conclusion: no tested fractional normalization exponent beat the fixed 4000-pip geometry. Do not deploy.

### GEO-003: Causal Volatility-Scaled Pip SL

- Status: `REJECTED_AS_WR_SOLUTION`; implementation retained in Advanced with default `OFF` for reproducible research only.
- Scope: `LiqNarrativeSol_Advanced.mq5` only. Production `LiqNarrativeSolVersion.mq5` was not modified.
- Causality: every scale uses only the signal bar and older closed H1 bars. No future ATR observation is read.
- Frequency invariant: all complete comparisons retained the same `975` signals; 2R target geometry and signal/router logic were unchanged.
- Default-off regression: `975` trades, `465W / 510L`, `47.6923% WR`, `+144.996R`, exactly matching the fixed-4000 baseline.

Absolute ATR experiment:

- Formula: `SL pips = clamp(ATR(short) * multiplier, 0.5 * 4000, 2.0 * 4000)`.
- Low multipliers `0.75-2.5` collapsed to the 2000-pip floor and materially reduced WR.
- High multipliers converged on the 8000-pip cap. Best development WR was `52.1680%`, but the same result was reproduced by fixed 8000 pips.
- Conclusion: the apparent improvement came from wider geometry, not volatility adaptation.

Relative ATR experiment:

- Formula: `SL pips = 4000 * (ATR(short) / ATR(reference))^exponent`, bounded to `2000-8000` pips.
- Grid: short ATR `14/28/56`, reference ATR `168/336`, exponent `0.5/1.0/1.5`.
- Best development candidate: ATR `14/336`, exponent `1.5`, `49.0541% WR`, `+36.235R` on 2019-2023.
- Untouched validation 2024: `44.69% WR`.
- Untouched forward 2025: `40.88% WR`; 2026 YTD: `51.52% WR`.
- Full result: `975` trades, `462W / 513L`, `47.3846% WR`, `+101.303R`, worse than the fixed-4000 baseline.

Geometry controls and feasibility bound:

- Fixed 8000 full result: `975` trades, `510W / 465L`, `52.3077% WR`, `+90.255R`.
- Yearly fixed-8000 WR: 2021 `50.94%`, 2022 `56.35%`, 2023 `52.66%`, 2024 `55.87%`, 2025 `48.07%`, 2026 YTD `47.47%`.
- A monotonic three-volatility-regime search over fixed `4000/5000/6000/7000/8000` selected `[8000, 8000, 8000]`; volatility supplied no routing information.
- Even a look-ahead oracle allowed to choose the winning geometry per signal stayed below 60% in 2021-2025: `52.20%`, `58.01%`, `52.66%`, `56.42%`, `53.59%`. Only 2026 YTD reached `61.62%`.
- Therefore the every-year `>60% WR` target is mathematically unattainable inside the tested SL-scaling family. Reaching it requires predictive signal/direction information, not another stop-width curve.
- Decision: do not enable volatility SL in production and do not replace the SolVersion 4000-pip geometry. Keep the Advanced inputs default-off for future falsifiable research.
- Reproducibility: `configs/sol_advanced_jp225_volsl_*`, `logs/sol_advanced_volsl_*.json`, `logs/sol_advanced_volatility_*analysis.json`, and `scripts/analyze_sol_volatility_*.py`.
### REJECTED-002: Autumn Force-Reversal Router

- Status: `REJECTED`
- Rule: retain all signals, but cancel continuation flips during autumn.
- Real EA-path result: `975` trades, `460W / 515L`, `47.1795% WR`, `+117.489R`.
- Baseline: `47.6923% WR`, `+144.996R`.
- Lesson: a profitable reversal subgroup does not imply that continuation setups become profitable when mechanically inverted.

### REJECTED-003: Four-Season Route Policy

- Status: `REJECTED`
- Development-derived rule: autumn/winter reversal; spring/summer continuation.
- Real EA-path result: `976` trades, `441W / 535L`, `45.1844% WR`, `+94.995R`.
- Forward instability: 2024 `42.46%`, 2025 `47.51%`, 2026 `34.34%`.
- Conclusion: descriptive route preference does not survive direction reconstruction as a routing policy.
### REJECTED-001: Offline Five-Feature Confluence Gate

- Status: `REJECTED`
- Offline row filtering appeared to exceed 52% WR.
- Real EA path test produced `366` trades, `179W / 187L`, `48.91% WR`.
- Root cause: filtering a signal changes subsequent reverse-exit timing and invalidates post-hoc row labels.
- Rule: all future signal filters must be validated by rerunning the EA path.

### REJECTED-004: Defended FVG / Inverse-FVG State Machine

- Status: REJECTED
- Causal rule: after the first HTF FVG touch, trade the original direction only after a defended close; after a completed close-through, allow the inverse direction only after a later retest/rejection.
- Baseline: 975 trades, 47.6923% WR, +144.996R.
- Loose structural result: 953 trades, 46.2749% WR, +41.439R.
- Loose branch attribution: defended 853 trades at 45.60% WR; inverse-FVG 100 trades at 52.00% WR.
- Hybrid preserving the existing Sol router for defended setups: 953 trades, 46.5897% WR, +136.358R.
- Mid and strict confirmations reduced both frequency and WR further.
- Conclusion: inverse-FVG is mildly interesting as a portfolio component, but replacing the base FVG lifecycle with defended/retest confirmation degrades the full strategy. Keep the mode default-off.

### REJECTED-005: First Active Retest IRL Selection

- Status: REJECTED
- Motivation: choose the first causally touched active HTF FVG rather than locking to the first FVG formed after reclaim.
- Nearest active result: 946 trades, 45.0317% WR, +111.818R.
- Strongest active result: 944 trades, 45.0212% WR, +112.283R.
- Annual frequency remained broadly usable, but both variants lost roughly 2.66 percentage points of WR versus baseline.
- Conclusion: for this JP225 model the first formed displacement FVG contains more information than later active alternatives. Keep first-formed as default.

### FEAS-002: Causal Direction-Routing Bound

- Paired reversal/continuation data contains 976 common setups. A look-ahead oracle can exceed 72% in every year, so direction selection is theoretically the main opportunity.
- That oracle is not tradable because it selects direction from the eventual result.
- A scan of 60 causal market/FVG/sequence features and 1,978 development-selected univariate routing rules found no stable candidate: the best development plus 2023 validation rule was approximately 50%, then fell to approximately 42% forward.
- A deliberately leaked test using realized R appeared above 80%; it was identified and rejected as future-outcome leakage.
- Existing expanding-window logistic, random-forest, and extra-trees routing experiments also failed to reach stable forward performance.
- Conclusion: every complete year above 60% WR at roughly 170-200 trades/year is unsupported by the current endogenous OHLC/FVG feature set. The next valid research family must add genuinely new causal information, preferably synchronized USDJPY and US-index context or lower-timeframe order-flow features. Do not manufacture the target with calendar memorization or realized-outcome leakage.

### REJECTED-006: H2/H4/D1 Direction and Room Overrides

- Status: `REJECTED_BEFORE_EA_PATH_TEST`.
- Scope: preserve all v14 setups and fixed 4000-pip / 2R geometry; override only the existing reversal/continuation route from causal closed-bar H2/H4/D1 trend, range-position, and target-room disagreements.
- A broad direct trend scan covered approximately 13,800 simple rules. Its best minimum yearly WR remained about `43.43%`.
- The stricter v14 override scan used 2021-2022 for discovery and 2023 as validation. No tested single structural override was non-negative versus v14 in every year from 2021 through 2026.
- Example: deep negative H4 one-bar structure improved development by about 2.2 points and 2023 by 3.0 points, but degraded each forward year and did not exceed `49.5%` in 2026.
- Regime diagnosis: even when both H4 and D1 pointed opposite the sweep-reversal direction, reversal remained superior in 2021-2024; the relation weakened in 2025 and inverted in 2026 YTD. The feature/outcome relation is regime-dependent, not a stable direction law.
- Decision: do not add an H4/D1 trend or room override to Advanced.

### REJECTED-007: Structural Conflict Wait With Market Fallback

- Status: `REJECTED_BEFORE_EA_PATH_TEST`.
- Scope: keep the v14 direction, fixed 400-price-unit stop and 2R target. On H4/D1 conflict only, wait for pullback, breakout, adverse-reclaim, or fixed delay; enter at market after a mandatory 15-240 minute fallback so frequency is retained.
- Causal M1 OHLC screen baseline: `975` trades at `49.03%` WR.
- Best full-period screen: D1 dual-mismatch plus 0.33R pullback / 240-minute fallback, `99.0%` retention and `50.05%` WR.
- Yearly best-candidate WR: 2021 `50.0%`, 2022 `49.2%`, 2023 `49.7%`, 2024 `50.0%`, 2025 `48.1%`, 2026 YTD `55.6%`.
- Decision: the loss mechanism is not merely an unfavorable initial fill. Improvement is too small and does not approach the annual target; do not port.
- Reproducibility: `scripts/research_sol_structural_entry_router.py` and `logs/sol_structural_entry_router.json`.

### REJECTED-008: Two-Sided Sweep/Reclaim Confirmation

- Status: `REJECTED_BEFORE_EA_PATH_TEST`.
- Scope: after setup availability, require a causal M1 probe and close reclaim before choosing direction; otherwise fall back to v14 after 60/240/720 minutes. Geometry remains fixed at 400 price units and 2R.
- The best development candidate was only about `49.1%`; a representative high-retention rule produced 2025 holdout WR of `41.9%`.
- Decision: additional generic sweep/reclaim confirmation does not identify the losing setup family.
- Reproducibility: `scripts/research_sol_sweep_reclaim_router.py` and `logs/sol_sweep_reclaim_router.json`.

### REJECTED-009: Synchronized USDJPY / US100 / US500 Direction Context

- Status: `REJECTED_BEFORE_EA_PATH_TEST`.
- Data: causal prior-closed H1/H4/D1 bars for `USDJPYm`, `USTECm`, and `US500m`, exported from 2020-12-01 through 2026-07-21.
- Tested interpretations: follow/fade each market, median cross-market vote, and unanimous cross-market override across 1-120 bar horizons.
- Best simple high-level candidate was the D1 five-bar unanimous override at approximately `47.7%` overall. Yearly WR: 2021 `43.4%`, 2022 `53.0%`, 2023 `44.4%`, 2024 `47.5%`, 2025 `49.7%`, 2026 YTD `48.5%`.
- Decision: these price-trend proxies add no stable direction edge. Do not add cross-market routing to Advanced from this family.
- Data artifacts: `logs/sol_cross_market_rates/`.
## Research Backlog

Candidate causal feature families:

- Calendar: weekday, month, season, holiday proximity, month-end/quarter-end.
- Session: Tokyo open, London overlap, New York overlap, minutes from session open.
- Price scale: percent-normalized SL, ATR/price, range/price, FVG width/price.
- Volatility regime: ATR percentile using only trailing observations, realized range percentile, compression/expansion transitions.
- Structure: sweep depth normalized by ATR, reclaim strength, displacement body/range, FVG width and age, distance to ERL/IRL.
- Sequence: previous signal direction and age, recent flip count, narrative age. Previous trade outcome is forbidden unless its exit time precedes the current signal.
- Cross-market causal context: prior-closed USDJPY/Nikkei proxy returns only when timestamp alignment proves availability.

## Tournament Rules

1. Never modify the production SolVersion during research.
2. Never use final outcomes from trades that were still open at the candidate signal time.
3. Develop on older years, select on a separate validation year, and report untouched forward years.
4. Report frequency, WR, net R, maximum drawdown, yearly stability, and confidence intervals.
5. Reject rules that depend on a single weekday/year or collapse trade frequency without explicit approval. A standalone champion should target roughly 170-200 trades per full year; lower-frequency patterns remain portfolio components only.
6. Re-run every finalist through the actual path-dependent EA audit.
7. Preserve rejected candidates and rejection reasons so the same false edge is not rediscovered.

## Champion Board

| Rank | Candidate | Evidence | Trades | WR | Net R | Decision |
|---:|---|---|---:|---:|---:|---|
| 1 | PAT-002 Autumn Entries | EA_PATH_TESTED | 238 | 55.46% | +65.16R | Strong regime component; frequency too low standalone |
| 2 | PAT-001 Autumn Reversal | EA_PATH_TESTED | 140 | 60.71% | +50.15R | Strong subset; frequency too low standalone |
| - | GEO-001 Price-Normalized Pip SL | REJECTED | 975 | 39.28% | +67.49R | Do not deploy; fixed baseline was 47.69% / +145.00R |
| - | GEO-002 Fractional Price Normalization | REJECTED | 975 | 45.85% best | +133.43R best | No alpha beat fixed baseline |
| - | GEO-003 Causal Volatility SL | REJECTED | 975 | 47.38% relative / 52.31% fixed-wide | +101.30R / +90.25R | Volatility did not beat fixed geometry; every-year 60% impossible in tested family |
| - | REJECTED-002 Autumn Force Reversal | REJECTED | 975 | 47.18% | +117.49R | Do not deploy |
| - | REJECTED-003 Seasonal Route Policy | REJECTED | 976 | 45.18% | +94.99R | Do not deploy |
| - | REJECTED-001 Offline Confluence | REJECTED | 366 | 48.91% | +97.70R | Do not deploy |

### REGIME-001: Synchronized H1/H2/H4/D1 Market Regime Map

- Status: `RESEARCH_ONLY_NOT_A_PRODUCTION_FILTER`.
- Data: 968 V14 trades from 2021-01 through 2026-07; this is approximately 5.6 years, not ten years.
- Descriptive result: penalized 3-6 month segmentation and fixed four-month blocks confirm persistent good, bad, and break-even strategy episodes.
- Causal construction: H1/H2/H4/D1 returns share identical prior 5/20/100 completed-D1-session anchors. Macro direction uses the four-TF 100-session median with +/-5% hysteresis; H1/H2 five-session return identifies pullback/rebound phase. H4/D1 slow consensus is retained separately.
- Important correction: equal raw bar counts across TFs are invalid because they represent unequal calendar horizons and can manufacture apparent separation.
- Temporal result: `DOWN_REBOUND` averaged +0.183R/trade in 2021-22 but -0.128 in 2023 and -0.117 from 2024 onward. `UP_ALIGNED` averaged -0.162 in 2023 but +0.422 from 2024 onward.
- Decision: the detector describes market state, but state-to-edge mapping is not stationary enough for an automatic production filter. Log/paper-forward first.
- Reproducibility: `scripts/research_sol_market_regimes.py`, `logs/sol_market_regimes.*`, and `IndicatorCodeExamples/DocumentsForAi/LIQ_NARRATIVE_SOL_MARKET_REGIMES.md`.

### REGIME-002: Hierarchical Structural/Tactical Regime Engine

- Status: `RESEARCH_ONLY_NOT_EA_PATH_VALIDATED`.
- V1 was frozen before development. Production SolVersion was not modified.
- Structural states: trend/range x high/low volatility using synchronized H1/H2/H4/D1 returns, H4/D1 agreement, 100-session efficiency, RV60/RV100, volatility percentile, hysteresis, and 15-session confirmation.
- Tactical layer: 20/5-session trend/volatility and H1/H2 pullback/rebound phase with five-session confirmation.
- Session layer: trailing H1 range activity by Asia/Europe/US/Late UTC buckets.
- Finding: the same coarse label changed because macro depth, route expectancy, and intraday price-discovery session changed. 2021 `DOWN_REBOUND` was +0.269R/trade; 2023 was -0.128 and 2025 -0.227.
- Flip hypothesis: a prior-years-only expanding policy reduced 2023-2026 offline-screen expectancy from +106.20R to +33.09R. Automatic regime flip is rejected.
- Decision: observer/research only. Require paper-forward logging and a dedicated path-dependent EA rerun before any execution effect.
- Reproducibility: `scripts/research_sol_market_regimes_v2.py`, `logs/sol_market_regimes_v2.*`, and `IndicatorCodeExamples/DocumentsForAi/LIQ_NARRATIVE_SOL_MARKET_REGIMES_V2.md`.

### REGIME-003: Low-Latency Hierarchical Regime and Edge-Hint Engine

- Status: `RESEARCH_ONLY_OBSERVER_NOT_AN_EXECUTION_FILTER`.
- Production SolVersion, V1, and V2 were not modified.
- Core: trend/range x high/low volatility from bounded H1/H2/H4/D1 trend-depth and volatility-depth scores with hysteresis.
- Exact transition contract: candidate visible after one completed session; decisive evidence confirms in exactly three sessions, ordinary evidence in exactly five; candidate changes reset the counter.
- Context: effective/confirmed regime age, H1/H2 shallow/deep pullback or rebound, reversal pressure, compressed/normal/elevated/extreme volatility, and expanding/steady/contracting volatility impulse.
- Outcome-free structural hints remain descriptive. A separate 730-day, 180-day-half-life walk-forward estimator uses prior trades only and emits `FAVORABLE`, `CAUTION`, `REGIME_CONFLICT`, or support-limited labels.
- Strict `FAVORABLE` was positive in every covered year: 237 trades total, +82.65R, +0.349R/trade. Sparse 2023-2024 support prevents execution promotion.
- Flip remains rejected. V3 does not flip, block, or open production trades.
- Verification includes exact 3/5-session latency invariants and truncated-history prefix-causality checks.
- Reproducibility: `scripts/research_sol_market_regimes_v3.py`, `scripts/verify_sol_market_regimes_v3.py`, `logs/sol_market_regimes_v3.*`, and `IndicatorCodeExamples/DocumentsForAi/LIQ_NARRATIVE_SOL_MARKET_REGIMES_V3.md`.
