# Corrected Strategy Campaign / Rolling Results

Status: MEGA 2 running in the isolated worker; not complete and not sealed yet.
Inventory: 188 strategies, 9 windows each (1,692 requested windows).

## Fixed causes
- Full TCAL was not restored by the original campaign: direction and daily quota
  fields were omitted. 25 saved strategies contained affected metadata.
- SEARCH and manual audit wrote different metric keys (record TF vs display TF).
- NAS used display chart TF even when a saved strategy came from another chart.
- A future ORB entry after a frozen endpoint could become a spurious DATA trade.
- Freshness was not checked; successful prior rows were permanently skipped.

## Guarantees enforced by publication
The original MQL5 engine, not a new simulator, calculates every result. Before
CURRENT publication every ready window is also audited via production strategy
ApplyValues with the same endpoint. Counts, R, MC, identity, TCAL and every trade
entry/exit/geometry/outcome must match. A mismatch is not published. Writes are
checksummed, atomic, exclusive-locked and cannot replace newer matching results.
Missing ticks remain incomplete, never fabricated winners or losses.

## Immutable references
Original report: reports/strategy_audit_20261008 (unchanged).
Original native archive: Common/Files/StrategyWindowArchive/20261008.
Its 1,590 originally available windows are explicitly LEGACY evidence.
MEGA 2 archive: Common/Files/StrategyWindowArchive/20261009, created only after
all requested windows have been attempted and ready windows verified. A sealed
archive cannot be replaced by rerunning the sealer. CURRENT writes never use it.
Search RESULTS cycles CURRENT -> MEGA 2 -> MEGA 1. This is a view switch only.
Legacy-vs-current corrections are not evidence of alpha decay. Compare compatible
strategy profiles and the verified MEGA 2 baseline for that research question.

## Rolling behavior and limits
Attach/timer requests launch an isolated research terminal, not the user's
trading terminal. Current windows end at their displayed ASOF. Stale family
results refresh daily; unavailable families retry hourly. Logon starts the worker
once it is installed. The user's PC, local worker and broker connection must run.
This version replays native acceptance and exits over each shifted window and
reuses existing engine caches/ADV indices. It is NOT a pure delta-only scanner.
This preserves daily quotas, legacy/Independent occupancy, OPEN exits and MC.
Saved profiles changed after inventory are quarantined pending recapture.
The configured research broker must match; unsupported brokers are not silently
used. Older Sol NAS presets are chart-specific because they store no NAS TF.

## Evidence
Unit tests: tests/test_strategy_campaign_parity.mjs,
test_strategy_window_campaign.mjs, test_strategy_window_refresh.mjs,
test_strategy_window_archive.mjs.
Native proof: parity_verified.json, with per-case geometry/outcome trace checks.
Cross-chart proof: cross_chart_verified.json (M1 saved strategy run on M5).
Production GUI controls are compiled and native probes are run separately.
The campaign dashboard proof calls production ApplyValues; it does not pretend
to be a physical UI click on the user's live terminal.

## Verified on 2026-10-09
- 25 Node regression tests and 5 workspace-only metric-writer tests passed.
- Four canonical production compiles: 0 errors, 0 warnings.
- Six native calendar/timezone/strategy probes: 343 checks, 0 failures.
- Native campaign/dashboard pilots: 5 strategies, 17 windows, exact trade traces.
- Saved M1 JP225 strategy on an M5 display: 5Y/1Y/2W exact metrics and traces.
- Four-family publication smoke: 5 verified windows saved and independently read.
- All 1,590 immutable MEGA 1 archive checksums independently verified.
- Full campaign endpoint persists in campaign-epoch.json; restart resumes it.
- Live campaign progress: progress.json and verification.json; logs: campaign.stdout.log.
- DATA_INCOMPLETE on 0.33InvUltimateSetup also existed in MEGA 1. No outcome is fabricated.
- Production deployment is deferred while the user's DEMO is open. Run
  scripts/deploy_verified_strategy_campaign.ps1 after it is closed; campaign is untouched.
- Automatic rolling worker installs only after the complete baseline passes and is sealed.
