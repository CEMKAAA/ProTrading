# ORB All-Strategies ML Campaign

## Frozen Scope

- [x] Identify both supplied Scholar authors using their public profile HTML.
- [x] Inventory: 46 built-in presets and 7 saved custom strategies (53 total).
- [x] Read and catalogue relevant primary publications, separating full text from abstracts.
- [x] Snapshot sources/presets and generate a no-order batch export script.
- [x] Export 260-week trade CSVs for all 53 presets, or record explicit history/configuration blockers.
- [x] Validate hashes, closed-bar features, outcome coverage and sample counts.
- [x] Train one v6.84 purged walk-forward MLP experiment per eligible dataset.
- [x] Run the predeclared expected-return challenger and interpretation diagnostics.
- [x] Evaluate frozen decisions on final test; report every strategy, including failures.
- [x] Assess family-wide selection uncertainty and create a reproducible report.

## Completion Evidence (2026-09-09)

Final report: [ORB_ML_Campaign_20260909.md](ORB_ML_Campaign_20260909.md).
Literature/access notes: [ORB_ML_Literature_Review_20260909.md](ORB_ML_Literature_Review_20260909.md).

Final export is `OrbMLCampaign_20260909_v3`: 53 datasets, 48,744 trades,
zero invalid labels. The v6.84 training protocol was retained; an export-only
entry-clock/cutoff correction was carried into workspace StrategyLibrary v6.85.
No signal, execution or listener changes were needed for that correction.

All 53 training attempts are reported: 48 MLP and 50 return models were saved.
Three datasets were below the 300-trade minimum for both families; two more
could not select an admissible inner-validation MLP threshold. These are
explicit blockers, not silently omitted strategies. Interpretation diagnostics
are ridge coefficients and year/regime breakdowns, not neural attribution,
causal explanations or newly validated regime rules.

Fourteen models improved their temporal test net R; zero passed the family-wide
uncertainty gate, and zero MLPs passed their local publication gate. No model
was activated. The improvement objective is not established as a production
edge. A new, frozen forward period remains necessary and is not marked complete.

No changes to live EA settings, signal generation, execution, listeners, risk or
automatic model activation. Every output is a research artifact until reviewed.
The batch uses the existing exact audit engine, not a new approximate backtest.
Built-ins use the M5 chart context of the earlier preset campaign and their own
stored signal TF. Custom presets must match their saved chart TF and input signature.
Costs are captured in each dataset/manifest; they are not optimized after test results.

## Experiment Registration

Freeze this protocol before inspecting campaign test outcomes. Keep the newest
20% test untouched during fitting/selection, preceding 20% for threshold
validation, oldest 60% for expanding-fold development. Purge labels crossing
future boundaries with a 24-hour gap. No random train/test shuffling.

Baseline experiment: current v6.84, 40 closed-bar features, 16-unit ReLU MLP,
three fixed L2 candidates (1, 10, 100), chronological checkpoint selection,
logistic/tree comparison and paired block-bootstrap diagnostics.

Predeclared challenger: predict realized net R rather than binary win, because
small-target and early-exit trades have unequal payoffs. Compare regularized
linear ridge and shallow histogram gradient boosting regressors. Use only the
same available features plus fixed direction-aligned price/trend interactions;
do not mine future labels or calendar rules. Regularization candidates and
thresholds must be fixed in code before test evaluation. Select by purged
development-fold net-R uplift, then threshold validation; include unfiltered
baseline as a legitimate fallback. Report selected and unselected families.

The final test is not an optimization target. Publication gates and selecting
among 53 strategies still create selection risk. Apply a conservative family-wide
multiple-comparison diagnostic to reported uplift. Require new forward data
before calling any result a production edge. Do not repeatedly tune failed
strategies until a favorable final-test result appears.

The current MQL neural loader cannot directly load arbitrary regression models.
Challenger artifacts must be clearly marked research-only; no silent format
conversion or cross-build configuration rebinding is allowed.

## Reproducibility

Save per-strategy configuration, source hash, preset snapshot, dataset checksum,
as-of timestamp, partitions, costs, model selection, predictions and failures.
Checkpoint completed exports/training so interruption does not delete prior work.
No strategy disappears from the denominator merely because it has too few trades
or missing history. Full five-year data must not be claimed for incomplete exports.
