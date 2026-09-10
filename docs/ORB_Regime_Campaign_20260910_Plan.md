# ORB Regime Campaign R1

Research only. No EA, publisher, listener, active model, or strategy setting changes.
Existing 53 completed five-year exports are the immutable input population.
Previously inspected dates are reused research walk-forward evidence, NOT a fresh holdout.

## Frozen protocol

- Shared outer test windows: calendar 2024, 2025, and 2026 through export cutoff.
- For each outer year Y: initial fit before Jan 1 Y-1, threshold calibration
  in H1 Y-1, model selection in H2 Y-1. Refit before July 1 Y-1, recalibrate
  the selected threshold on H2 Y-1, then freeze before scoring Y.
- Split by original feature-availability time; label exit must precede the next
  boundary by 24h. No prior-window pending entry or unresolved outcome in scoring.
- All strategies use the SAME boundaries. Pool weighting caps contribution of
  many related strategies on a symbol/day. Strategy-specific identity remains.
- Fixed six candidates: local ridge without regime, local ridge with regime,
  pooled ridge without regime, pooled ridge with regime, pooled payoff model,
  pooled small MLP net-R model. No hidden hyperparameter/seed search.
- Base features exclude regime and RF; regime designs include existing six
  one-hot states, transition/age/depth, RF one-hot and six prespecified interactions.
- Geometry features are planned SL/ATR, TP/SL, spread/SL, SL/price, no-TP flag.
  Never use outcome cost_r, net_r, MFE/MAE, exit_reason or label as a feature.
- Thresholds: no veto, 0, 0.025, 0.05, 0.10 net R. Validation retention >=50%,
  >=20 trades. A model must improve on base AND same-month matched random
  expectation in calibration and selection. Otherwise NO VETO.
- Pooled payoff: logistic P(netR>0), conditional positive/negative ridge magnitudes;
  chronological probability calibration. Small MLP: 16-unit ReLU, alpha=10,
  at most 200 chronological epochs, 25-epoch patience after 40, one fixed seed.
- Metrics: base and selected net R, WR, retention, closed-trade DD, matched-count
  and matched-month excess R, candidate ablations, calendar-year results.
- Approximate daily-block bootstrap with 5/20-day sensitivity; multiple-strategy
  correction. Not a proof against overfit, not floating/EOD challenge DD.
- All candidates and selection decisions logged; frozen models are .research.joblib.
- No automatic promotion. Rejects/insufficient samples remain visible.

## Tasks

- [x] Inspect existing regime features, training guards, and completed source exports.
- [x] Implement isolated reproducible campaign and validation tests.
- [x] Verify inputs, feature whitelist, date purging, weights, and no outcome leakage in the training design.
- [x] Run all outer folds and all eligible strategies with CPU limits/checkpoints.
- [x] Report regime vs no-regime ablations and matched-selection diagnostics.
- [x] Document limitations and strongest next experiment, without choosing production by test.

## Completion

53 datasets / 48,744 usable strategy-trade rows; 26,129 reused outer-test rows.
642 fitted bundles; 23 campaign/selection-diagnostic tests passed.
All three annual checkpoints were re-read and their artifact hashes verified.
436 production source, binary, listener and active-model files remained unchanged.

Summary: `docs/ORB_Regime_Campaign_20260910_Results.md`.
Artifacts: `logs/OrbRegimeCampaign_20260910_R1/`.
No deployment or automatic promotion. No strategy parameters or signal math changed.
