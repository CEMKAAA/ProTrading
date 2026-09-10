# Strategy-Local Regime Campaign R2

Frozen before training. Research only; no production model or EA changes.

## Question

Can a strategy learn its OWN regime-dependent expected net R more reliably
when low-sample regime effects shrink toward that strategy's common model?
No other strategy's rows or labels may enter its fit, scaler or calibration.
Existing datasets already contain six regimes, age, transition, depth and RF.
No CSV regeneration or additional indicators are required for this experiment.

## Fixed Experiment

- Same 53 hash-verified CSVs and 2024/2025/partial-2026 outer periods as R1.
- All results are reused historical research, not fresh independent holdouts.
- Four candidates only: local_base, local_flat_regime, local_hier_100,
  local_hier_400. No extra seed/feature/threshold search after seeing outcomes.
- Base: R1's regime-free Ridge, alpha=100. Flat regime: R1's local regime
  Ridge with age/depth/RF features, alpha=100.
- Hierarchical candidates: per-strategy shared slopes with penalty 100;
  six sets of regime-specific intercept/slope deviations with penalty 100
  or 400. This is penalized partial pooling, NOT fitted full Bayesian MCMC.
- Regime-specific slopes cover eight fixed quantities: aligned return5,
  aligned EMA20-50, SL/ATR, spread/SL, age, transition confidence,
  trend depth and volatility depth. An intercept deviation is also included.
- Shared hierarchy design excludes categorical regime/RF indicators;
  it retains continuous age/transition/depth context and fixed interactions.
  Flat regime remains the richer categorical/RF benchmark.
- Fit scaler on training only; gate standardized shared covariates by regime
  WITHOUT restandardizing sparse gated columns. Rare regimes must not get
  inflated to unit variance. Unseen regime deviations are exactly zero.
- Unknown/invalid regime falls back to shared strategy prediction. No special
  rule is learned from an all-zero/invalid categorical state.
- All models bind strategy id, symbol, broker, source/config/dataset identity.
  Mixed-strategy training or scoring is rejected.

## Selection And Audits

Use R1's shared chronological boundaries, 24h label purge, train-only scaling,
H1 threshold calibration, H2 family selection, final refit before H2 and H2
threshold recalibration. Freeze models/choices BEFORE each outer-year score.

Fixed thresholds: no veto, 0, .025, .05, .10R. Calibration/selection require
20 selected trades, >=50% retention, improved total R and positive improvement
over month-count-matched random expectation. Otherwise NO_VETO.

Keep all failed candidates and unchanged baselines. Compare selected policy
against base, flat regime and local no-regime on the same rows. Report candidate
ablations separately from pre-test-selected policy; no post-test promotion.

Pair 20,000 daily-block resamples across strategies at 5/20 calendar days.
Report Bonferroni-53 and conservative Bonferroni-530 sensitivity for the four
R2 plus six R1 candidate families across 53 strategies. Neither correction
accounts for all prior human research or magically restores a fresh holdout.

Do not report a DSR/PBO certificate: complete historical trial inventory and
appropriate synchronized account-return paths are absent. Closed-trade R is
not an account's daily total return or floating/EOD trailing drawdown.

## Literature Basis

Partial pooling toward shared estimates limits implausibly extreme estimates
in sparsely observed groups. Here the groups are regimes WITHIN one strategy,
not multiple strategies. This adaptation is our engineering choice, not a
claim that the cited authors tested ORB or certified this model.

- Andrew Gelman (2006), [Multilevel (Hierarchical) Modeling: What It Can and Cannot Do](https://sites.stat.columbia.edu/gelman/research/published/multi2.pdf).
- Gu, Kelly, Xiu (2020), [Empirical Asset Pricing via Machine Learning](https://dachxiu.chicagobooth.edu/download/ML.pdf): regularization and temporal training/validation/test separation.
- Bailey et al. (2015), [The Probability of Backtest Overfitting](https://www.davidhbailey.com/dhbpapers/backtest-prob.pdf): repeated selection and holdout limitations.

## Checklist

- [x] Verify existing strategy-local CSV/model training and existing regime features.
- [x] Freeze model/feature/selection budget before training.
- [ ] Implement isolated local-regime models and boundary/identity tests.
- [ ] Run all 53 strategies and all chronological folds.
- [ ] Audit selection uncertainty, rare-regime behavior and production hashes.
- [ ] Report outcomes and limitations without an overfit-free claim.
