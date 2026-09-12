# ORB Target R6: Frozen Objective Ablation

2026-09-11. Research only. No employer-affiliation or scientific-discovery claim.
Current deployed models, EAs, terminal files and listeners remain untouched.

## Hypothesis And Data

Does separating probability of positive net return from gain/loss magnitude
produce more stable out-of-time filtering than direct net-R regression?
Use all 22 verified USDJPY strategy joins, each trained independently with the
same existing 50 return-design features. No new indicator or signal mathematics.
Do not choose the best-looking R4/R5 strategies or age windows.

Four annual tests start September 9 in 2022, 2023, 2024, 2025; last ends 2026-09-09.
Each training set starts 2018-01-01 and ends before the preceding calibration
year. Calibration halves split at March 9. 24h label purge at every boundary.
The first fold has about 3.7 training years, last about 6.7; SAME history across
all model targets within a fold. Six-day 2021 export gap disclosed, not filled.
All test years are reused historical research, NOT pristine holdouts.

## Fixed Models

1. direct: R4 ALL HGB net-R regressor (7 leaves, 80 iterations, minimum leaf 30,
   L2=10, early stopping off, seed42). Last two years must reproduce R4 scores.
2. logistic_mean: StandardScaler + LogisticRegression(C=.1, max_iter=2000,
   no class weighting), label = net_r > 0. Convert probability into expected R
   using training-only positive/nonpositive mean magnitudes.
3. hgb_mean: same classifier HGB complexity as direct, label net_r >0; same
   training-only mean magnitudes. No probability balancing or oversampling.
4. hgb_two_part: SAME hgb_mean probability model plus positive/nonpositive
   magnitude regressors of same HGB size. If a class has fewer than 60 rows,
   use its training mean. Otherwise shrink predicted magnitude to that class
   mean with weight n/(n+100), fixed before testing. Clip magnitude predictions
   below zero only; do not clip labels, winsorize losses or ignore costs.

Expected R = p(win)*expected_positive_R - (1-p(win))*expected_nonpositive_loss.
Flat net returns belong to the nonpositive class with zero magnitude. Single-
class training uses deterministic probability and records the fallback. No
NaN or unsupported identity can silently pass as a valid forecast.

This is a conditional-expectation decomposition, not a new financial theorem.
Global training means are an explicit approximation in *_mean models. HGB
two-part is more complex, not automatically better. Use conditional-head fallbacks.

## Policies And Diagnostics

- fixed_zero: predicted expected net R >=0 passes. No threshold search.
- confirmed_zero: same fixed threshold only if BOTH calibration halves have
  positive net gain and monthly-count-matched selection skill, >=40% retention,
  >=20 kept and >=10 rejected; otherwise NO_VETO. No search over these constants.
- Record discovery/confirmation/test score quintiles using discovery-only edges,
  Spearman and top-bottom mean R; no retrospective ranking-gate tuning.
- Record Brier score/log loss for probability models versus training prevalence,
  and net-R MSE versus training-mean predictor. Missing probability for direct
  regression is NA, never fabricated from a regression output.
- Freeze artifacts, rules and probability/magnitude constants BEFORE test.
- No post-test best-family selection, export or live replacement.

## Four-Year Evaluation

Concatenate each fixed family's chronological annual predictions per strategy;
annual retraining uses only information available at that point. Preserve annual
results and purge gaps. Compare on identical rows against base and SAME-policy
direct regression. No aggregate across correlated strategies as portfolio R.
Registered incumbents only on final-year information-safe common rows.

Paired circular blocks of 5/20 calendar days, 20,000 draws, zero-trade days,
identical resamples across strategies. Approximate stationarity under drift.
Primary challenger family: 22*3*2=132 combined-history comparisons for each of
base gain, monthly skill, and direct-model difference. Incumbent family 132.
Report per-family Bonferroni and joint528 sensitivity. Annual results descriptive,
no multiple trial loophole by marketing one selected year. Duplicate series noted.

Historical screen (not promotion): positive gain vs base in at least 3/4 years,
positive four-year gain/skill, four-year DD no worse than base, and both block
lengths' corrected evidence for gain/skill and improvement vs direct model.
Still require fair incumbent PnL/DD comparison, stateful execution replay and NEW
prospective shadow evidence before any future live replacement. No trial-count
adjustment can erase earlier human strategy selection or reused test exposure.

Descriptive score: 100*[min(gain,skill)/N + .25*DD_gain/N - quarterly_edge_std -
mean(max(0,discovery_edge-confirmation_edge)) -
max(0,gain-worst_bootstrap_lower_gain)/N]. Not probability of overfit or PBO/DSR.

## Integrity

Save source/data/production hashes, all models/predictions/negative results,
verify original input replay and future-outcome independence, use resumable
hash-verified checkpoints. Outputs only logs/OrbTarget_R6_20260911.

## References

[Gu/Kelly/Xiu](https://dachxiu.chicagobooth.edu/download/ML.pdf): comparative
regularized financial prediction; not evidence of profitability in our strategy.
[Bailey et al.](https://www.davidhbailey.com/dhbpapers/backtest-prob.pdf): repeated
backtest selection risk and limits of retrospectively optimized results.
[HGB classifier documentation](https://scikit-learn.org/stable/modules/generated/sklearn.ensemble.HistGradientBoostingClassifier.html):
classification probabilities and explicit complexity controls. No default random
early-stopping validation is used in this time-series experiment.
