# ORB Veto R5: Frozen Policy Experiment

2026-09-11. No claimed employer affiliation or scientific discovery. Research only.
No terminal, EA, listener, registry or current model modifications.

## Scope

Use the R4 ALL-history Ridge/HGB models, not retrospectively best age windows.
22 USDJPY strategies, own-data models, fixed original 50 features. 88 frozen
model/fold pairs. Two test years begin 2024-09-09 and 2025-09-09. Reused historical
tests, not pristine holdouts. Retain R3/R4 six-day September 2021 data-gap disclosure.
Data, code and artifact hashes verified. No retraining or signal/geometry change.

Training ends before the previous September 9. Split the following calibration
year at March 9: discovery six months, confirmation six months. Purge all labels
crossing boundaries and an additional 24h, including the March split. No retuning
on confirmation or test. Existing R4 max-calibration-PnL threshold remains a
comparator (it uses all 12 calibration months, unlike the new split policies).
Registered incumbent comparison only on final-year common information-safe rows.

## Score Diagnostics

Discovery-score quintile edges are fixed for confirmation and test; tied values
stay together. Report bin N, mean net R, WR, score/return Spearman, and top-minus-
bottom mean R. Empty bins remain missing, not zero. A ranking gate requires
positive top-bottom difference and positive Spearman in BOTH calibration halves.
Never use test diagnostics to authorize a policy.

## Four Policies And One Control

1. fixed_zero: predicted net R below 0 is vetoed. Mechanical comparator, no fitted
   threshold or ranking gate. It may be economically wrong; report all results.
2. plateau: threshold grid [-.10,-.05,0,.025,.05,.10,.15,.20]. Discovery candidates
   require >=40% retention, >=20 kept, >=10 rejected. Score each threshold as
   min(net gain, monthly-count-matched skill)/N. Choose an interior threshold
   whose own and adjacent grid scores are positive; maximize the MIN of those
   three scores, ties favor more retained trades then lower threshold. Freeze
   threshold. On confirmation require positive gain AND monthly skill, >=20 kept,
   >=10 rejected and >=40% retention, plus ranking gate. Otherwise NO_VETO.
3. bad_tail: freeze discovery-score 20th percentile, veto strictly lower scores
   only if ranking gate passes AND rejected outcomes have negative upper 90%
   block-bootstrap mean in both halves. Discovery requires >=15 rejected,
   confirmation >=10. Otherwise NO_VETO. No quantile search.
4. regime_tail: same frozen 20th percentile. For each of six valid regimes, shrink
   local tail mean toward the strategy's global tail mean with fixed prior mass
   20: (sum_local + 20*mean_global)/(N_local+20). Jointly block-resample both means.
   Require local raw mean negative, shrunken upper 90% bound negative, at least
   8 discovery / 5 confirmation rejected observations, ranking gate, and positive
   calibration gain AND monthly skill for the regime-specific veto in each half.
   No/invalid/unsupported regime -> no extra veto. No global-tail fallback.
5. regime_only control: same shrinkage and support/bound checks on all regime
   trades, without model scores or ranking gate. Diagnose whether regime alone
   explains improvement. NOT a fifth live candidate or a new regime formula.

Mean uncertainty uses 2,000 circular calendar-day bootstrap draws, blocks 5 and
20, zero-trade days included, upper bound = worst 90th percentile. Empty-resample
denominators count against confidence, never silently omitted; >10% empty makes
the upper bound unavailable and rejects the gate. Same seed/resamples for joint
local/global estimates. Approximate stationarity; not a Bayesian posterior.
Ranking gate and confirmation can reject useful but noisy rules. All diagnostics
are saved so conservative selection is not confused with a broken predictor.

## Test And Robustness

Freeze model references and all policy choices before test scoring. Compare on
identical rows: base, old R4 threshold, four policies, regime-only control, and
registered incumbent on final year only. No post-test winner deployment.
Track actual net R, closed-trade DD, retention, monthly-matched selection skill,
quarterly variability and accepted/rejected regime counts. WR is not the target.

Paired calendar-day block diagnostics, 20,000 draws, lengths 5 and 20. Share draws
across strategies. Family: 352 policy/fold cases for each of base gain, monthly
skill, old-threshold difference; 176 final-year incumbent differences. Report
per-family Bonferroni and combined 1,232 sensitivity. Unrecorded historical human
searches remain uncorrected. Regime-only contrasts are descriptive controls.

Score (fixed before test): 100*[min(gain,monthly_skill)/N + .25*DD_gain/N -
quarterly_edge_std - max(0,discovery_edge-confirmation_edge) -
max(0,gain-worst_bootstrap_lower_gain)/N]. Engineering utility, NOT P(overfit).
No-veto score zero is zero intervention, not a perfect model. Existing model's
old selection optimism is unknown, not assumed zero for a superiority claim.

Final-year improvements must also be checked for gains versus regime-only and
for actual veto activity (do not market NO_VETO as ML success). Duplicate strategy
signal sequences are reported, never counted as independent evidence or summed
as portfolio R. Frozen-row veto is NOT stateful execution replay. Before any
future live promotion require execution replay plus prospective shadow outcomes.
This experiment does not claim those latter stages have run.

## References

[Gu, Kelly, Xiu](https://dachxiu.chicagobooth.edu/download/ML.pdf): regularized
financial prediction with chronological train/validation/test separation.
[Bailey et al.](https://www.davidhbailey.com/dhbpapers/backtest-prob.pdf): repeated
backtest selection risk; reused historical periods cannot become pristine again.
[Gelman](https://sites.stat.columbia.edu/gelman/research/published/multi2.pdf):
partial pooling motivates shrinkage. Our fixed-mass rule is not a fitted Bayesian
model and its bootstrap bound is not a posterior probability of profit.
