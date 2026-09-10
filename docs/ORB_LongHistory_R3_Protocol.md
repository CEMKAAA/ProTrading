# Long-History R3 Protocol

Frozen before new training. No production model replacement or activation.

## Scope And Dates

Use 22 USDJPY strategies with verified prior-period and recent CSV exports.
Training-history floor 2018-01-01. The prior export ends 2021-09-09 and recent
export starts 2021-09-15: explicitly report this six-day export gap, do not
invent missing trades or claim a perfectly continuous eight-year replay.
Both export settings/cost snapshots must match. Preserve both source hashes.
JP225/USTEC are excluded from this run: equally long strategy CSVs were not
verified here. No claim that raw broker history is unavailable for them.

Final fit: 2018-01-01 through 2024-09-08 (about 6.7 years).
Final threshold calibration: 2024-09-09 through 2025-09-08 (one year).
Last-year test: 2025-09-09 through 2026-09-08.
24h label purge at each boundary; crossing/unresolved labels excluded.
MLP uses oldest 80% of fit for gradient training, newest 20% for chronological
early stopping; that stopping segment is not the threshold calibration year.

All test dates have been examined in earlier research; this experiment holds
them out from THIS fit, not from all historical human/strategy decisions.

## Fixed Candidates

1. Original 50-feature expected-return Ridge, alpha=100.
2. Original shallow HGB: 7 leaves, 80 iterations, min leaf=30, L2=10, seed42.
3. Original 40-feature classifier MLP: 16 ReLU units, alpha=10, chronological
   early stopping, max200 epochs. No change to production classifier.
4. R2 strategy-local regime deviation model, penalty400.

Features include the existing regimes in all four families. The first three
preserve established feature representations. No new indicator search.
Each fit uses ONLY that strategy's rows. Models reject wrong strategy identity.
No current production hyperparameters are reselected using test outcomes.

## Inner Temporal Model Selection

Three scoring years begin 2021-09-09, 2022-09-09, 2023-09-09. Each model fits
only before the preceding six-month calibration period, calibrates its threshold
there, then scores the subsequent year. These scoring years end before final
calibration/test. Shared dates across all strategies.

Return thresholds: no veto, -.10, -.05, 0, .025, .05, .10, .15, .20.
Classifier thresholds: no veto, .05, .35, .45, .50, .55, .60, .65, .70, .75, .80.
Threshold selection uses net R, then greater retention; >=40% retention and
>=20 trades on calibration only. NO_VETO always remains a fallback.

Define for each scored segment:
g = (filtered net R - unfiltered net R) / candidate count
s = (filtered net R - month-count-matched random expected R) / candidate count
e = min(g,s)
d = (unfiltered closed-trade DD - filtered closed-trade DD) / candidate count
o = max(0, training e at the same calibrated threshold - validation e)

Pre-test robustness score = 100 * [mean(e) + .25*mean(d) - std(e) - mean(o)].
Require three completed inner folds, two positive-e folds and positive score.
If none passes: NO_VETO. Final calibration must still improve g and s with
>=40% retention. Freeze chosen family, threshold and file hashes BEFORE test.

This score is a preregistered engineering utility with a stability/optimism
penalty, NOT an estimated probability of overfitting or an academic theorem.
Weights are fixed now, not optimized to improve final-test rankings.

## Incumbent Comparison And Preservation

Read the exact registered .experimental file and verify adapter hash against
the published registry. Keep its weights and threshold unchanged. Check its
original train/calibration label horizon. If later than last-year test start,
restrict head-to-head to timestamps after BOTH models' information cutoffs
plus purge; disclose shortened paired period. No in-sample incumbent scores
may be called independent historical forward results.

Report full-year new model vs base separately from matched incumbent comparison.
For each on the matched test rows calculate descriptive TestRobustness:
100 * [min(g,s) + .25*d - std(quarterly min(g,s)) - uncertainty_penalty].
uncertainty_penalty = max(0, actual R gain - worst 5/20-day paired block
bootstrap 2.5% lower gain) / N. Same dates/resamples for both models.
This is a TEST diagnostic, not another round of threshold/model selection.

Use 20,000 paired day-block draws, 5/20-day sensitivity; compare to base,
month-count-matched expectation and the incumbent. Bonferroni-22 plus
exploratory 88 sensitivity for four candidates*22. Previous campaigns and
human trials exceed these counts; no claim of complete multiplicity repair.

Replacement is DISABLED in code for this run, including candidates with higher
PnL. Better net R alone is insufficient. Require matched PnL and DD improvement,
higher descriptive TestRobustness, pre-test stability, corrected paired evidence,
no execution regressions AND a genuinely new forward period before considering
replacement. Missing comparable incumbent optimism evidence is recorded as
unknown, never assumed to be zero. No blanket 'less overfit' certification.

## Sources

[Gu, Kelly, Xiu (2020)](https://dachxiu.chicagobooth.edu/download/ML.pdf):
regularization, nonlinear models and chronological validation/test design.

[Gelman (2006)](https://sites.stat.columbia.edu/gelman/research/published/multi2.pdf):
partial pooling to stabilize sparse-group estimates; adapted within each strategy.

[Bailey et al. (2015)](https://www.davidhbailey.com/dhbpapers/backtest-prob.pdf):
repeated selection/holdout pitfalls. No DSR/PBO certificate without full trials
and appropriate return paths. Reused years are not untouched future evidence.
