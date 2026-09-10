# ORB Strategy Library: ML Research and Validation

Date: 2026-09-09. Scope: experimental Strategy Library only.

## Decision

Keep the existing setup generator. Train a per-strategy veto filter, not an
alternative signal generator. A larger neural network is not automatically a
more advanced solution for roughly hundreds or a thousand dependent trades.
The main upgrade is the experiment protocol, artifact isolation and comparison
against simpler models. No claim of profitable forward performance is made.

The supplied [Scholar profile](https://scholar.google.com/citations?user=TmSsP6oAAAAJ&hl=en)
returned HTTP 429 during research. Its author identity and publication list
could not be verified; none of the conclusions below are attributed to that
profile. Research instead used the primary papers below.

## What the Literature Changes

| Evidence | Implication for this system | Implemented response |
|---|---|---|
| Optimizing the model-selection criterion can itself overfit; it is not just a problem of fitting neural weights. [Cawley and Talbot, JMLR 2010](https://www.jmlr.org/papers/v11/cawley10a.html) | Repeatedly trying architectures or thresholds against the same final test is unsafe. | Fixed small search budget; expanding folds inside development; final threshold selected before test evaluation. |
| Financial strategy selection can overfit backtests; a single holdout is not a universal cure. The paper develops CSCV/PBO. [Bailey et al., The Probability of Backtest Overfitting](https://www.davidhbailey.com/dhbpapers/backtest-prob.pdf) | Selecting among 46 strategies, features and filter runs is an additional selection layer. | Keep all run reports and disclose repeated-test risk. PBO is NOT implemented or claimed: a synchronized campaign of candidate returns is needed first. |
| Tree methods remain strong on medium-sized tabular benchmarks; feature distributions and inductive biases matter. [Grinsztajn et al., 2022](https://arxiv.org/html/2207.08815v1) | ATR/RSI/regime rows do not justify a deep sequence model by themselves. | Compare the MLP with regularized logistic regression and shallow histogram gradient boosting. |
| A broader benchmark finds the neural-net versus boosted-tree distinction is often smaller than tuning effects, with dataset-dependent exceptions. [McElfresh et al., 2023/2024](https://arxiv.org/abs/2305.02997) | Neither family should be declared the winner in advance. | The simpler benchmark is selected on validation, then compared on the frozen test. Trees are research comparators, not silently exported into the MQL neural loader. |
| Neural confidence need not be calibrated; temperature scaling helped in the paper's image/document experiments. [Guo et al., ICML 2017](https://proceedings.mlr.press/v70/guo17a.html) | A score of 0.70 must not be advertised as a guaranteed 70% trade success probability. | Record Brier score and log loss. This release does not fit a separate calibration layer or claim calibrated probabilities. |

These papers motivate engineering decisions; their benchmark results are not
evidence of an ORB trading edge.

## Data Contract

One row is one historical trade under a frozen strategy configuration. Existing
audit exit times and realized R are labels, including reverse-signal and timed
exits. Open, invalid or unresolved outcomes cannot become synthetic loss labels.
Only the fixed 40 `f_` columns are model inputs. Exit time, net R, win label and
future excursions are never inputs. Features use information available at the
original signal availability time, with bounded closed-bar indicator warmup.

CSV completion marker, content checksum, source/configuration hashes, strategy
ID, symbol, broker and TF bind the experiment. A strategy B must not list or load
strategy A's dataset/model. Recompiling a changed source contract invalidates old
bindings; generate a fresh CSV instead of renaming files to force compatibility.

## Training Protocol

1. Sort chronologically; reserve the newest 20% as final test, the preceding 20%
   as threshold validation, and the earliest 60% as development.
2. Purge earlier trades whose exits overlap the next partition, with a 24-hour
   separation. A row-count gap alone cannot handle variable trade durations.
3. Within development, use three expanding forward folds. Each fold's own early
   segment fits its scaler and MLP; its later stopping segment selects a checkpoint.
4. Fixed architecture: 40 inputs, 16 ReLU hidden units, binary output. Compare
   L2 alpha 1, 10 and 100 with seed 42. No feature mining across the final test.
5. Use chronological log-loss early stopping, at least 40 and at most 400 epochs,
   patience 30. Select alpha by median outer-fold filtered-minus-baseline net R.
6. Fit the final development model/checkpoint. Select its entry-score threshold
   on the separate validation partition, retaining at least 40% of validation
   trades and the configured minimum sample requirement.
7. Train fixed logistic and shallow boosted-tree comparators using development
   only. Choose the comparator using validation, not test.
8. Freeze weights, scaling, alpha, checkpoint, threshold and comparator. Only
   then evaluate the final test and its three chronological sub-blocks.
9. Report paired filtered-minus-unfiltered net R with a 1,000-draw moving-block
   bootstrap over exit days containing trades. Require positive improvement in
   at least two development folds, a positive lower test confidence bound, and
   test net R not below the base strategy or validation-selected comparator,
   in addition to existing positive-result/retention checks.
10. Failed quality checks produce REJECTED, not a deployed model. READY still
    requires explicit USE RESULT / LOAD MODEL / ML ON. No automatic activation.

The bootstrap is conditional on the observed sample and chosen block rule. It
does not correct the full strategy search, cover all serial dependence, or prove
future profits. The confidence unit is active exit days, not all calendar days.
Risk sizing and broker execution are not estimated by this classification model.

## What Remains Unproven

- Five years of daily signals is a small effective sample, particularly inside
  rare regimes. A longer date range is not the same as many independent samples.
- Strategies developed by visually examining these years have already used the
  period for human selection. Calling the last partition test does not erase that.
- Repeatedly inspecting test results and changing strategy/parameters creates a
  new selection loop. The report flag `test_used_for_fitting=false` refers to this
  training run, not the entire research history.
- Cost/slippage/gap assumptions and the audit's history coverage determine label
  realism. A model cannot repair incorrect labels or anticipate a broker outage.
- Passing the final-test publication gate is itself a selection decision. A new,
  genuinely future paper-trading period is needed to assess deployed behavior.
- No deployment of LSTM/Transformer/large deep ensemble was added. Complexity
  without sufficient evidence would increase the parameter/search burden.

## Operational Design

The local scheduled worker starts at Windows login and runs at current-user,
limited privileges in a hidden process. It reads only the ML job protocol and
has no trading API. The EA never launches arbitrary commands from a job file.
An OS lock enforces one worker per artifact root. Training runs outside MT5's UI
thread, reports fold/epoch progress, and checks cancellation between epochs.

Checksummed writes use atomic replacement; short Windows reader locks get a
bounded commit retry without truncating the previous complete file. Worker
diagnostic logs rotate at 1 MiB plus two backups. CSVs/models/reports deliberately
remain until archived; they are not deleted on restart. Each export/training run
adds artifacts, so repeated experiments still require deliberate retention management.

## Dashboard Semantics

Regime/RF card W/L/WR describe a reference signal universe before macro/RF
allow/block selections. Separate reference exit lists prevent changing a blocked
next-day signal from retroactively changing another regime's reference W/L.
The actual audit portfolio continues to obey the selected filters and actual
exit lists. Reference lists are not published or used for live orders.

Card statistics can legitimately change when the date window, geometry, NAS,
costs, entry filters or history changes. Only macro/RF allow/block independence
is promised, not permanent fixed WR numbers under every strategy modification.

Custom strategy records save symbol family and configuration. A verified complete
52-week audit saves W/L/WR, net R, MinCum and as-of metadata into a separate
checksummed sidecar. Missing metrics initiate a 1Y audit on save/application;
invalid/incomplete history does not create fabricated metrics. Original 46 frozen
preset metrics are not overwritten. The architecture filter uses effective R,
whereas net R and WR are measured audit outputs.

## Verification

See the versioned verification section in `ORB_Strategy_ML_Pipeline_Plan.md`.
Unit tests include purged boundaries, portable inference parity, artifact isolation,
and a test-label mutation experiment: changing only final-test outcomes cannot
change the fitted neural weights, scaler or selected threshold.

The isolated MT5 probe does not register the trading EA lifecycle handlers or
send orders. It exercises save/restore, metrics reload, reference invariance,
CSV export, dashboard job submission, training status and explicit result handling.
