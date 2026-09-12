# ORB Training-Age R4: Frozen Diagnostic Protocol

Date: 2026-09-11. Research only; no EA, model registry, bridge or terminal writes.
This experiment tests a hypothesis, not a claimed scientific discovery.

## Question

Holding strategy, features, model family and evaluation rows fixed, does limiting
or discounting older training observations improve out-of-time filtering?
Keep all current production models regardless of this retrospective result.

## Data And Time

- Reuse the verified R3 joins of 22 USDJPY strategy exports. Each model trains on
  its own strategy only. Do not regenerate signals, geometry, costs or labels.
- Start no earlier than 2018-01-01. Disclose the six-day September 2021 export gap.
- Two test years: [2024-09-09, 2025-09-09), [2025-09-09, 2026-09-09).
- Each test is preceded by one complete calibration year. Training ends before
  that calibration year. Remove labels crossing each boundary, with 24h purge.
- These are the two available annual folds with at least five calendar years
  before calibration. A 2023 test would NOT have a full five-year training arm.
- Last year has been inspected in earlier campaigns; not a pristine holdout.
- Registered incumbents can be compared ONLY on the last fold, after their own
  last calibration label plus 24h purge. Never score them on the earlier fold.

## Fixed Arms

Models: Ridge(alpha=100), HGB(7 leaves, 80 iterations, min leaf=30, L2=10,
early stopping off, seed=42), exactly R3's return models.
Features: the same original 50-feature return design, already including regimes.

Within each model/fold/strategy:

1. trailing_3y: training feature times within last three calendar years.
2. trailing_5y: within last five calendar years.
3. all: all eligible history from 2018.
4. decay_2y: all history, weights 2^(-age_days/730.5), age measured at fit cutoff.

Normalize weights in EVERY arm to the all-history training row count for that
strategy/fold. Thus Ridge/HGB L2 strength relative to the total weighted loss
does not change simply because fewer rows are selected. Weighted scaling uses
training data only. The all-history arm must reproduce R3 Ridge/HGB predictions
on the final fold. Record raw N, effective sample size and weight mass.
HGB minimum leaf size still counts raw rows; sample size is part of this ablation.

Minimum rows: training 150, calibration 20, test 20. Explicitly mark invalid arms;
do not silently substitute another arm or count a missing fit as successful.

## Thresholds And Selection Diagnostics

Same R3 calibration grid for every arm: NO_VETO, -.10, -.05, 0, .025, .05,
.10, .15, .20. Max calibration net R, ties favor retaining more trades; retain
at least 40% and 20 trades in calibration. Do not require this in the test.

Primary mask: frozen calibration-selected threshold, without a later selection
gate. Also retain fixed threshold=0 masks to distinguish score changes from
threshold changes, and a diagnostic gate (calibration gain AND month-matched
skill positive), otherwise NO_VETO. No threshold is chosen from test outcomes.
These secondary views are diagnostics, not extra live candidate searches.

Freeze trained artifacts, thresholds and all settings BEFORE scoring each test.
No post-test best-arm strategy is deployed or described as a preselected result.

## Evaluation

- Net R, closed-trade peak-to-trough DD R, retention and WR on identical rows.
- Monthly count-matched selection skill, quarter edge variability, training to
  calibration optimism, test MSE and R2 relative to a training-only mean baseline.
- Regime-frequency total variation and standardized feature mean shift are
  descriptive covariate-shift indicators, not evidence of causality.
- Match each alternative against all history within SAME strategy/model/fold.
- Paired 5/20-calendar-day circular block bootstrap, 20,000 draws. Common block
  draws retain cross-strategy dependence. Include zero-trade days. Approximate
  stationarity only. Bonferroni family: 22*2*3*2=264 primary comparisons, and
  22*2*4=176 incumbent comparisons as a separate descriptive family. Report
  combined 440 sensitivity; historical unrecorded searches remain uncorrected.
- Fixed descriptive score:
  100*[min(gain, monthly_skill)/N + .25*DD_gain/N - quarterly_edge_std
       - max(0, training_edge-calibration_edge)
       - max(0, gain-lower_bootstrap_gain)/N].
  It is NOT P(overfit), PBO or DSR. Do not tune weights after observing results.
- Count both per-strategy and exact-signal-sequence duplicate groups; never sum
  correlated strategy R as portfolio or account profit.
- Retrospective veto on frozen trade rows does not resimulate execution state.
  It cannot alone certify live performance or support replacing a model.

## Integrity And Deliverables

Hash source data, protocol, scripts, fitted models and the existing production
file inventory. Verify checkpoint and before/after hashes. Record all outcomes,
including negative results. Outputs stay in logs/OrbTrainingAge_R4_20260911.

## Methodological References

[Gu, Kelly, Xiu (2020)](https://dachxiu.chicagobooth.edu/download/ML.pdf):
regularized models and chronological training/validation/test separation.
Their asset-pricing results are not evidence of ORB profitability.

[Bailey et al. (2015)](https://www.davidhbailey.com/dhbpapers/backtest-prob.pdf):
repeated model selection can overfit backtests. Our reused test cannot undo it.

[StandardScaler documentation](https://scikit-learn.org/stable/modules/generated/sklearn.preprocessing.StandardScaler.html):
training sample weights supported in scaler fitting. No test statistics used.
