# JP225 R7 Transfer: Frozen Research Protocol

2026-09-11. No production deployment, no source EA or listener changes.

Transfer the already fixed USDJPY R7 calibration method WITHOUT retuning its
parameters. All 30 JP225m presets in the verified v3 campaign, own CSV per preset.
Do not join incompatible old exports or fabricate missing pre-2021 feature data.
Available source begins September 2021, ends as of September 9 2026.

Two historical tests: 2024-09-09 to 2025-09-09 and 2025-09-09 to 2026-09-09.
For each, base training ends one year before test start. At least 150 training
rows, 20 initial calibration rows, 20 test rows. Record every excluded fold and
its counts, not a NO_VETO success. Eligibility depends only on data coverage,
never profit. Expected: 26 eligible first folds, 29 eligible second folds.

Use identical R6 logistic_mean/hgb_mean estimators and 50 features. The existing
R6 fit helper also computes unused reference/head models; only the two specified
probability families are retained, evaluated or considered. No family selection.
Keep the same R7 raw/probability/magnitude/both/regime_both arms, monthly update
schedule, 365-day past-label window, 24h delay, intercept penalties/bounds/minimum
counts, class-magnitude prior50 and regime fallback. All accepted/rejected source
setups are eligible. Do not change signal/filter mathematics or label definitions.

At final as-of 2026-09-09, also fit a forward-only research bundle for EACH of the
30 strategies: base training before 2025-09-09, monthly correction as of 2026-09-09.
These 60 base bundles plus states have NO subsequent evaluation. Historical-fold
performance is not the performance of these newly refitted bundles. Keep them
isolated from MT5/Common Files models; no EA portable export or activation.

Validate CSV, config, registered-model and 436 production hashes. Source broker,
symbol and preset identity must match. Current registered models compare only in
the final year on rows later than their last training/selection-label time +24h.
Do not score those incumbents over their training years as out-of-sample.
Only 27 JP225 incumbents are registered. jp_2r_retest, jp_05_long_wait and
jp_05_holy have no verified registered incumbent; train research models but do
not fabricate an incumbent or count NO_VETO as their existing ML model.

Comprehensive companion comparison reports all eight adjustments, not a best-test
replacement: PnL, DD, WR, trades, average R, profit factor, quarterly deltas,
changed-decision attribution and extra-cost sensitivity. Paired 5/20-calendar-day
block bootstrap, 20,000 draws, no-trade days and shared resamples included.
JP family count conservatively 30*2*4=240, even if one strategy lacks a test.
USD family176; combined416 pairs, joint832 for net difference and count-matched
selection difference. Diagnostic multiple testing cannot erase earlier research.

Preserve negative examples, exclusions and all candidate artifacts. Post-test
Pareto membership is descriptive, not approval. No prospective shadow or stateful
position replay is claimed. R-denominated closed-trade DD is not EOD/floating DD.
No claim of overfit-free models, new theorem, institutional affiliation or profit guarantee.
