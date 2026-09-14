# NAS Strategy Library implementation checklist

Scope: NAS Ultimate SATS Partial No BE, reusing the ORB research infrastructure.
The production signal generator is not to be rewritten. No automatic model
promotion, order placement, account-risk changes, or listener reconfiguration.

- [x] Inspect NAS audit, ORB library/training contracts and existing listeners.
- [x] Visually inspect the 19 NAS screenshots in the requested tree.
- [x] Record visible settings, image hashes and unresolved hidden inputs.
- [x] Add an opt-in NAS library EA with shared signal/execution source.
- [x] Add search, favorites, symbol/R filters and safe strategy application.
- [x] Save named user strategies with complete configuration identity.
- [x] Share strict CLOSED/single-order/HCBE-OFF replay between dashboard and export.
- [x] Export isolated, checksummed per-strategy 5Y datasets with quality flags.
- [x] Reuse chronological purged train/validation/test ML training.
- [x] Add model jobs/progress, explicit model activation and model identity checks.
- [x] Add Vanilla/Legacy/candidate and six-regime research leaderboards.
- [x] Add versioned champion slot without overwriting an existing active champion.
- [x] Run 19-strategy campaigns and report rejected models explicitly.
- [x] Compile, test numerical inference and verify shared signal-core parity.
- [ ] Visual QA of the complete dashboard on the user's chart resolution.
- [ ] Qualified NAS model live/history lifecycle test (no model has qualified).
- [ ] Native HCBE historical replay upgrade; strict CSV export currently refuses HCBE.
- [ ] Deploy/restart production instances after acceptance. Not done implicitly.

## Evidence and restrictions

There are 12 BTC and 7 US-index NAS screenshots in `Crypto/Nas` and
`UsEquities/Nas`. A filename containing `Nas` elsewhere can describe an ORB
strategy using NAS confirmation, not a standalone NAS strategy. These must not
be silently converted. `BtcUsdH1Model.png` explicitly displays PERIOD_M5.

PNG performance numbers are not labels or validated current-engine metrics.
Settings absent from a screenshot need a declared baseline or user confirmation.
The NAS namespace must never load ORB strategy models, jobs or datasets.
W/L target-hit counts are distinct from positive/negative realized-return counts.
Open trades, incomplete history and ambiguous intrabar labels must not become
fabricated wins/losses in ML datasets.

## Status

Research implementation and no-order verification are available. This checklist
is not a guarantee of trading safety or evidence that an ML model has an edge.

## Usage

1. Use `NasUltimate_StrategyLibrary.mq5`, not the original standalone EA, for
   the new workbench. Keep its quoted `.mqh` dependencies alongside it.
2. Leave `InpNasLibraryAllowLive=false` for research. This blocks native orders
   and bridge publication even if a dashboard execution toggle is pressed.
3. Open `STRATEGIES / ML`. Search, filter by symbol/exact R, favorite a preset,
   or save a named copy of the current configuration.
4. Apply a preset on its matching symbol and TF. PNG-hidden inputs require the
   documented baseline confirmation. Account risk/PUB/ONLY/NAT are not imported.
5. `CREATE 5Y CSV` exports to `Common/Files/NasML/Datasets`. Completed exports
   have checksum/completion markers; interrupted exports cannot enter training.
6. `TRAIN MODEL` queues work for the NAS-only worker. The task
   `ProTradingSystem-NAS-ML-Worker` starts it at Windows logon. The modal shows
   job progress; the worker never submits orders.
7. `USE RESULT` requires a qualified, matching model. `ML FILTER ON` is a
   separate explicit action. A rejected model is not silently made tradable.
8. Leaderboard modes are VANILLA, LEGACY and CANDIDATE. CANDIDATE is research
   evaluation, not proof that the active champion slot contains that model.

## Campaign And Evidence

The refreshed campaign is in
`logs/NasStrategyLibrary_20260912/campaign_current/campaign.json`.
It covers 19 screenshot presets and 38 model training jobs. All 38 jobs finished
as REJECTED, not FAILED: none passed every deployment gate. Existing production
ORB models and terminal ML toggles were not changed.

- `mql_probe.json`: 19 presets, 12 synthetic exit cases, bounded memo lookup test.
- `mql_prediction_parity.json`: portable Python/MQL model probability comparison.
- `tests/test_nas_strategy_library.py`: signal-core identity, schemas, namespaces,
  temporal purging, PnL validation and safe research/execution boundaries.
- `logs/AuditWindowReuse_20260914/nas_window.jsonl`: actual dashboard window
  comparisons after data hydration; each cached result is checked against replay.

Costs use the configured NAS commission assumption, not a verified broker fee
schedule. The inherited default is 0.08% round-turn notional, also on the index
presets. Reported performance must not be interpreted without this assumption.
M1 Bid OHLC plus recorded spread estimates Ask; missing/gapped/ambiguous labels
are excluded. USTEC has substantial exclusions. Full-history ML leaderboard
scores include training observations and are retrospective candidate masks, not
an out-of-sample replay of changed replacement/exit lifecycles.

The original NAS signal core remains unchanged. The new strict audit applies
only to the opt-in library's CLOSED single-order HCBE-OFF configuration. Other
NAS configurations retain the original audit and are not claimed equivalent to
the strict training labels.

## Audit Window Reuse

See `docs/AuditWindowReuse_20260914.md` for scope and limitations. Cached PnL is
never substituted for OPEN/DATA or for a changed exit plan. This work does not
alter CSV execution channels, listeners, risk sizing or active broker positions.
