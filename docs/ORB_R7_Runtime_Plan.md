# Legacy / R7 Runtime And Follow-up Research

2026-09-12. User-requested opt-in integration; legacy remains default.

- [x] Export strategy-bound R7 logistic/probability archives, historical vintages and current refit; no best-final-year model selector.
- [x] Independently compare portable predictions and decisions against research models.
- [x] Add persistent chart-local Legacy/R7 toggle, distinct from ML ON/OFF; guard active/pending trades and exports.
- [x] Use the same inference for live and historical entries; no future vintage on older bars, no silent fallback.
- [x] Compile and run no-order MQL parity probes; document coverage and monthly expiry.
- [x] Stage and install current sources/binary/models with explicit approval; no process restart requested (EX5 replacement can trigger terminal reload).
- [x] Continue a preregistered, research-only champion-calibration pilot; preserve old artifacts.
- [x] Add Vanilla / Legacy / R7 five-year retrospective leaderboard, all 53 strategies, explicit in-sample warning.

R7 choice means logistic_mean + probability for all strategies. HGB/magnitude/
regime_both remain research arms, not silently selected from the best test result.
Historical archives have actual dated calibration states. Current forward state
expires at the next scheduled monthly update. Missing/expired models fail closed
only when ML is enabled. Existing positions continue normal exit management.

Research contracts from previous runs are immutable snapshots. Authorized new
runtime source edits will differ from those snapshots; do not rewrite their
integrity reports to pretend production sources never changed. No source signal
mathematics, publisher CSV contract or listener changes are in scope.

Validation: 161 tests; EA/probe 0 errors, 0 warnings; 4,111 MQL parity vectors;
637 independently replayed R8 states. See ORB_Legacy_R7_Usage.md and
ORB_ChampionCalibration_R8_Results.md. No R8 promotion or live account test.
