# ML-HFT: integration review

## Decision

Use it as a research reference for microstructure features, NOT as a replacement
for our execution, risk, audit, bridge or model-promotion infrastructure.
Do not deploy its reported best classifier as a production filter.

I inspected the README and code cells of `data_process.ipynb`,
`HFT_factors.ipynb`, `feature_engineering.ipynb`, and `model_fitting.ipynb`.
Notebooks were downloaded as text, not executed; no external dependencies or
models were installed. Snapshots are in `logs/ml_hft_review`. This was source
review, not independent reproduction of its performance.

## What the repository supplies

It targets SGX China A50 futures Level-II data. The research path reconstructs
book observations, engineers depth/price features, compares classifiers and
plots results. Its own README calls the work a baseline and says the PnL and
commission methodology need improvement. This is not evidence of a live,
broker-safe HFT engine. [Repository](https://github.com/bradleyboyuyang/ML-HFT)

## Findings: do not copy unchanged

**Training labels are not safely separated from test time.** Feature labels
inspect a future ask-price interval; model training ends immediately before
the test slice. Thus training labels near that boundary can depend on prices
inside/after the test interval. The default export uses 600 seconds, while
some prose says 15 minutes. Boundary purging must use the actual label-end
timestamp, not the prose. Zero ask prices are also replaced with a whole-array
mean, potentially using future observations. Weighted depth ratios need
zero-denominator handling.
[Feature source](https://github.com/bradleyboyuyang/ML-HFT/blob/master/feature_engineering.ipynb)

**Model selection is not purged walk-forward validation.** It uses
`GridSearchCV(cv=5, scoring='accuracy')` inside adjacent rolling train/test
slices, not explicit temporal/purged folds. Early PnL visualization maps
classification outcomes to spread-based gains/losses, rather than replaying
orders. A later equity helper is long-only stock-style, with different cost
assumptions. Neither should replace our lifecycle audit. Evaluation of one
displayed trading day cannot establish multi-regime robustness.
[Model source](https://github.com/bradleyboyuyang/ML-HFT/blob/master/model_fitting.ipynb)

These are concrete methodological weaknesses, not proof that every result is
useless. They do prevent treating those results as an unbiased expected return.

## Features worth adapting

The useful idea is to measure local supply/demand with several depth weights,
not to import a particular fitted model. The repository calculates weighted
ask/bid depth ratios and normalized imbalance, together with price-change
features. Its imbalance sign is ask-minus-bid; do not silently combine it with
a dataset using bid-minus-ask.
[Factor source](https://github.com/bradleyboyuyang/ML-HFT/blob/master/HFT_factors.ipynb)

My proposed small, independent feature set:

| Feature | Proposed definition | Potential role |
|---|---|---|
| OBI-1, OBI-3 | (bid depth - ask depth)/(bid depth + ask depth) | Directional pressure |
| Microprice displacement | (microprice-mid)/tick size | Top-of-book pressure |
| Spread/SL | current spread divided by intended stop distance | Cost veto |
| Depth coverage | visible opposing volume / requested volume | Slippage warning |
| Imbalance persistence | rolling signed OBI over 1/5/30 seconds | Reject isolated spikes |
| Quote freshness | receive time minus last usable book update | Data validity gate |
| Book churn | additions/cancellations conditional on feed semantics | Instability context |

Microprice proposal: (ask*bidSize + bid*askSize)/(bidSize+askSize).
Do not fabricate missing depth as zero. Carry validity, coverage and age flags.
These definitions are my integration proposal, not claims that this repository
already implements all of them or that they improve our returns.

## Where it fits in our system

### ORB

Keep the current signal, regime selection, channel and geometry. At a valid
entry candidate, record a pre-decision book snapshot. Initially use only a
shadow score. Later test whether it improves breakout execution quality or
rejects costly entries, rather than trying to predict the entire day's trend.

### NAS / MA

These can generate more candidates and may provide more training observations.
Start with spread/SL and adverse-selection prediction. Measure whether a veto
actually improves net expectancy after lost winners, not merely WR. Do not
replace their crossover or SATS state machines.

### Liq / Sol

Sparse signals make per-strategy deep networks difficult to validate. Start
with a shared execution-cost model, keeping strategy and regime interactions
small and regularized. Deep architecture is not the first bottleneck.

### Listener boundary

Our Quantower core already exposes source, symbol, TF and channel ownership
(`ProductionFileBridgeQuantowerCore.cs`). That identity must remain the key.
The reviewed listener sources did not establish an existing Level-II capture
pipeline; add a separate observer first, not synchronous training in a robot.
The NinjaTrader/Quantower API and data subscription must be verified for the
chosen connection before implementing any depth collector.

If the feature is futures order-book pressure, collect on the actual execution
contract. CFD ticks cannot reconstruct historical exchange depth. Record
contract month, rollover, source-to-target mapping and inversion. USDJPY to
JPY futures particularly needs direction-aware normalization.

## Proposed safe architecture

1. **Observer only:** append compressed/bounded feature snapshots and source
   event IDs. No listener behaviour change and no new orders.
2. **As-of join:** accept only samples whose receive/availability time is no
   later than the decision. Store event-time and receive-time separately.
3. **Trade labels:** retain our actual close reason/net R/costs and label end.
   Add a separate short-horizon adverse-excursion target if useful.
4. **Validation:** outer chronological test blocks; inner purged temporal
   selection; purge all labels overlapping validation; fit preprocessing only
   on training. Reserve an untouched final period before research begins.
5. **Ablation:** current model vs current+spread vs current+book features,
   using exactly the same candidates, costs and folds. Log all experiments.
6. **Promotion:** paired improvement in net expectancy/drawdown with
   day/week-block uncertainty intervals and adequate trade retention. Report
   results by regime/year; reject a model whose gain is one small regime bucket.
7. **Shadow then SIM:** calibrate probability and threshold on training-side
   validation only. Test stale data, disconnects and duplicate event delivery.
8. **Optional veto:** immutable model hash/schema bound to strategy+channel.
   Timeout/invalid-data policy explicit. ML may veto a NEW entry only; it must
   never block risk exits, reverse-close, SL/TP management or emergency flatten.

## Acceptance metrics

Primary: after-cost R per original candidate, drawdown, rejected-winner cost,
slippage and retained trade count. Secondary: calibration/Brier/log-loss and
classification metrics. Use net money under the listener's contract granularity,
not only source CFD R. Stress fees, fills, disconnects and delayed features.
No method proves absence of overfitting; clean temporal separation and repeated
out-of-sample evidence can reduce and quantify that risk.

## Recommendation

First implement a tiny, bounded futures microstructure observer and shadow
report for one liquid contract. Do not re-train 50 strategies on invented L2
history. Without genuine depth data, start with our already available spread,
tick changes and realized execution costs and label those as L1 features.
Confirm licensing/permission before copying third-party implementation: no
explicit license was visible in the repository root listing reviewed here.

No ML-HFT code was integrated into production in this task.
