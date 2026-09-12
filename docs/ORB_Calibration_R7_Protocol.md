# ORB R7: Frozen Causal Calibration Experiment

2026-09-11. Research only. No production writes, no live orders, no model replacement.

## Question

Does a small causal calibration layer repair the R6 probability/decision mismatch
without retraining a larger model or selecting last-year winners?

Use all 22 verified USDJPY joins and all four R6 annual folds, 2022-09-09 through
2026-09-09. Same fixed 50 features, outcomes, geometry, sources and purge rules.
Historical periods were already researched; this is NOT a pristine holdout.
Three duplicate outcome-series pairs remain disclosed. The 2021 source gap remains.

Reuse the frozen R6 logistic_mean and hgb_mean bundles, independently per strategy
and annual fold. Base fitting ended before the preceding calibration year. No
refit, hyperparameter search, new indicator, threshold grid or best-family selector.

## Causal Monthly Updates

At test start and subsequent calendar month starts, use the trailing 365 days of
setup feature timestamps, bounded below by the base-model training cutoff.
Only entries before update time and exits strictly before update time minus 24h
are eligible. All source setups, accepted AND rejected, are eligible. This is a
counterfactual CSV replay, not a claim of completed live shadow instrumentation.
The annual base model must not have trained on these calibration rows.

Apply the frozen update to features arriving until the next update. Outcomes
from that interval cannot influence its state. Test-year labels can enter LATER
monthly states only after closing and the 24h delay, as in prequential learning.
There are 13 intervals per annual fold, not 12, because tests start September 9.

## Fixed Correction And Arms

Fit an intercept-only logit correction with slope fixed at 1. Minimize binary
negative log likelihood plus lambda*b*b/2; lambda=10, b bounded [-3,+3].
Use at least 40 rows and at least 5 positive and 5 nonpositive net outcomes;
otherwise b=0. Use 60 bisection iterations, stable logistic arithmetic and
probabilities clipped to [1e-9,1-1e-9] only for the logit transform.
No correction based on full-test mean prediction bias.

Updated class magnitudes: (recent class net-magnitude sum + 50*training class
mean)/(recent class count + 50). Use original magnitudes when fewer than 40
eligible rows. A missing class defaults to its training mean. No label clipping,
rounding a partial close to full TP/SL, or double subtraction of commission.

Five arms, same score threshold >=0, no calibration-profit gate:

1. raw: frozen R6 probabilities and training means (exact R6 fixed_zero reference).
2. probability: corrected global probability, original means.
3. magnitude: original probability, updated class means.
4. both: corrected global probability and updated means.
5. regime_both: both plus a regime-specific intercept correction.

Regime adjustment fits residual calibration around the globally adjusted logit,
lambda=25, at least 30 rows and 5 of each class, same bound. Existing six regime
identities only; no formula changes. Missing/invalid/sparse regime -> zero local
adjustment. Magnitudes remain GLOBAL, so this isolates the extra regime intercept.
Global intercept preserves within-update ranking; regime intercept may reorder.
Zero adjustments retain original probabilities exactly (including 0/1 fallback).

## Evaluation And Evidence

176 frozen base-model/year bundles; 880 arm/year outcomes; 2288 monthly states.
Four-year concatenation per fixed strategy/family/arm; no sum as portfolio profit.
Report annual results, retention, net R, closed-trade DD, Brier/log loss, mean
probability bias, and month-count-matched skill. Existing registered incumbent
comparison uses only the information-safe common rows in the final test year.

Primary challengers: 22 strategies * 2 models * 4 adjustments = 176 comparisons
for each of gain vs base, monthly count-matched skill, and gain vs raw R6.
Registered-incumbent family also 176. Paired calendar-day circular block bootstrap
5/20 days, 20,000 common resamples, no-trade days included. Bonferroni176 per family
and joint704 sensitivity. Annual/deduplicated/diagnostic comparisons descriptive.
Bootstrap stationarity is approximate; corrections do not undo past human search.

Historical screen, NOT deployment approval: positive base gain in >=3/4 years,
positive raw-relative gain in >=3/4 years, combined retention >=40%, >=20 kept
trades in each year, combined DD <=base, and corrected gain/skill/raw evidence
under BOTH block lengths. Registered-model comparison, stateful execution replay
and new prospective shadow still required; never silently deploy a post-test winner.

## Integrity And Limits

Freeze this protocol, runner/report/verifier/test source hashes and R6 contract.
Verify input, model and 436 production hashes, checkpoint states and predictions.
Replay calibration from source rows and independently solve intercept optimum;
mutate unavailable outcomes to test update invariance. Verify raw masks match R6.
All artifacts in logs/OrbCalibration_R7_20260911; all experiments preserved.
Research joblib/JSON is not a portable production filter contract.
Closed-trade R drawdown is NOT floating, EOD trailing, account risk or challenge loss.

## Method References

[Guo et al.](https://proceedings.mlr.press/v70/guo17a.html): calibration of
probability forecasts; not evidence that this ORB strategy is profitable.
[Lipton et al.](https://proceedings.mlr.press/v80/lipton18a.html): label-shift
assumptions matter. R7 does not claim constant p(x|y) or apply BBSE automatically.
[Bailey et al.](https://www.davidhbailey.com/dhbpapers/backtest-prob.pdf): selection
risk from repeated backtests. No overfit-free guarantee or probability-of-overfit score.
