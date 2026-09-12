# Regime x Strategy x Model Campaign

Protocol fixed before running: 2026-09-12.

- Universe: all 53 completed strategy CSV exports in the existing 5Y campaign.
- Window: 2021-09-15 to 2026-09-09, broker timestamps, 1820 days.
- Modes: Vanilla, registered Legacy, current assigned R7-slot artifact.
- No retraining, threshold fitting, model promotion or live regime-permission changes.
- Regime assignment uses the six exclusive one-hot features already captured at
  the original signal feature snapshot, not today's regime or exit-time regime.
  A delayed execution can occur in a different regime. This analysis does not
  relabel it. Unknown buckets are retained separately, never forced into a class.
- Names/order match OrbRegimeBucket: TLV, THV, RLV, RHV, TR PEND, TR FRESH.
- All modes use the same closed, feature-valid source candidates. Invalid/missing
  features on a closed trade abort the campaign rather than silently improve WR.
- ML leaderboard inference is retrospective: latest fixed model/state applied to
  the whole source CSV. Includes training data, NOT OOS or execution replay.
- Reconcile N/W/L/flat and net R: six buckets + UNKNOWN must equal ALL for each mode.
  Drawdown is recomputed per subset by exit timestamp (same-time exits grouped),
  not added across buckets. It is closed-trade peak-to-trough R, not floating/EOD DD.
- Ranking keeps the existing formula: 100 * Wilson lower WR / (1 + closed DD R).
  N < 30 is flagged LOW N and sorted below adequate samples. No-data is not a loss.
  Compare winners separately per symbol; a global comparison is only descriptive.
- Report the top score, highest net R, sample size, and yearly results. A leading
  retrospective cell is NOT proven deployable alpha. Searching hundreds of cells
  adds selection bias; candidates require independent forward validation.
- Runtime report identity binds strategy/config/dataset/model hash/window/schema.
  A swapped champion cannot inherit a previous artifact's regime results. Rerun
  the campaign to populate the new model's report; until then show unavailable.
- Popup mode/regime changes are display-only. Existing strategy row application
  retains lifecycle checks and preserves live ML ON/OFF and model selection.

## Tasks

- [x] Generate all strategy/mode/regime cells and per-year diagnostics.
- [x] Independently reconcile mask totals and validate model hashes.
- [x] Add display-only regime selector and identity-bound report loader.
- [x] Test parsers/UI guards, compile and run no-order MQL validation.
- [x] Deploy verified reports and EA to DEMO; preserve models/listeners/signals.
