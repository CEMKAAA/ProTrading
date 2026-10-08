# Native Strategy Audit Campaign

The campaign inventory contains 188 records: ORB 70, MaCross 81, Sol Advanced 28,
EntryLab 9. Saved records, canonical ORB built-ins, and screenshot-derived Sol
presets are audited without changing their signal mathematics or stored settings.

## Execution

- The isolated terminal is `.tmp/orb_jp225_full_worker/terminal64.exe`.
- The user's `C:/MT5/DEMO/terminal64.exe` is not stopped or reconfigured.
- Algo trading and DLL import are disabled. The research script also denies
  `OrderSend` and `OrderSendAsync`; an attempted order invalidates the result.
- Shared libraries are read-only. Only validated `WindowMetrics` files are
  written to the native MT5 Common Files directory.
- A single bounded source snapshot is reused. No broker-data directory is copied.

## Windows And Provenance

Requested windows in priority order: 260, 208, 156, 104, 52, 20, 10, 5, 2 weeks.
Each window calls the original EA audit engine. Smaller windows may reuse that
engine's internal caches, but are not reconstructed by slicing final trade rows:
position availability, daily quotas, and boundary states must be re-evaluated.

`manifest.private.json` records source hashes, native record hashes, original
verified base-input profiles, chart timeframes, and job identities. Inputs are
not inferred from strategy names. Native files are checked for changes before
each job. Runtime settings, NAS, order flow, inversion, position limits, and time
matrix masks are loaded from the actual saved record. LAB policy precedence is
preserved, including its optional pip stop override.

Results use the native engine's existing data semantics. A complete audit is not
a claim that five years of exact historical ticks exist. Explicit DATA outcomes,
short required signal-series coverage, pending regime data, or incomplete jobs
are never relabeled as wins/losses or published as ready metrics.

## Outputs

- `progress.json`: campaign process, current strategy, and completion counters.
- `results/<catalog-id>.csv`: one row per audited time window, including W/L/O,
  net R, minimum cumulative R, broker as-of timestamp, data status, and elapsed
  milliseconds. Completed valid rows survive retries.
- `summary.csv`: aggregate results when the selected run finishes.
- Native `WindowMetrics/*.swm`: checksum-protected, settings-keyed results used
  by the strategy search screen. Every successful write is read back and checked.

`AUDITED` and `AUDITED_OPEN` are ready results. Other statuses are diagnostics,
not valid empty audits. `APPLY_FAILED` is a setup validation failure;
`METRIC_WRITE_FAILED` is a persistence failure, not a trading-performance result.
Symbols are not silently substituted for another broker's suffix/feed.

## Authorized JP225 Feed Migration

On 2026-10-09 the user explicitly authorized auditing the two archived
`Legacy_JP225_H2M30_2R` and `Legacy_JP225_H2H1_2R` presets on `JP225m`.
The current Exness account has no `JP225s` symbol. The manifest retains
`sourceSymbol=JP225s` and records `symbol=JP225m` as the actual audited feed.
All strategy inputs, entry/stop/target settings, IDs and requested windows remain
unchanged. This is a fresh audit on JP225m, not a claim of equal historical prices.

`scripts/complete_jp225_campaign.ps1` uses the existing dedicated test terminal,
leaving the active main worker untouched. Its source graph is copied from the
frozen campaign snapshot; only image-symbol compatibility is adapted. It denies
native orders, publishing and shared strategy writes just like the main wrapper.
The authorization, original source hashes, compile log and separate progress are
under `jp225-remap/`. Results join the main campaign only after identity and
native metric readback checks. The production SolAdvanced image lookup also
accepts these archived JP225s presets on JP225m; original JP225s support remains.

## Resume

Run `scripts/run_strategy_window_campaign.ps1 -Mode Run`. It skips complete
window rows and retries missing/incomplete rows without deleting older results.
Compile the four wrappers first with `-Mode Compile` when the snapshot changes.
The worker must not already be occupied by another research task.
