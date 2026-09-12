# R8: Fixed Registered Champion, Causal Calibration Only

2026-09-12, specified before this pilot's outcomes. Research-only; no deployment.

Keep every currently registered strategy's exact model weights, active flag and
decision threshold. Do not replace its estimator with R6 logistic/HGB. Evaluate
22 USDJPY and 27 JP225 registered strategies on their common eligible final-year
rows (2025-09-09 to 2026-09-09), purged beyond their selection-label end +24h.

Only calibration observations whose feature time is AFTER the incumbent's entire
training/selection information end +24h may enter any state. Using training-set
predictions to calibrate the champion is forbidden. This may leave little initial
calibration data; report fallback rather than relax the boundary.

Monthly updates, last 365 days, entry before update and exit strictly before
update minus 24h. All source candidate setups, including rejected ones, contribute
only once their outcomes are available. No dependence on having taken the trade.

Three arms: exact champion, champion + global correction, champion + global and
regime correction. No threshold sweep. Active=false remains no-veto in all arms.

MLP: preserve threshold; regularized logit-intercept correction as in R7,
penalty10/min40 globally, penalty25/min30 per regime, min5 each class. This is
classification probability calibration, not a change in target geometry.

RIDGE/HGB return models: preserve threshold and ranking within each monthly
global state. Add shrunk past mean prediction residual, sum(residual)/(n+50),
only at n>=40. Additional regime residual after global correction, prior100,
only n>=30. Bound each additive correction to [-0.25,+0.25]R. Insufficient data
means zero correction. Known six causal regime IDs; unknown uses global only.

Report every arm/strategy: PnL, closed DD, N, WR, correction coverage, monthly
count-matched selection delta. Shared calendar paired 5/20-day bootstrap,
20,000 draws, Bonferroni196 (49*2 adjustments*2 metrics); no automatically chosen
winner. Final year was already researched; this is not a pristine holdout.

Check temporal state boundaries, closed-label mutation invariance, unchanged base
predictions, and exact no-veto behavior. Freeze source hashes with this protocol.
No prospective shadow, stateful position replay, or overfit-free claim.
