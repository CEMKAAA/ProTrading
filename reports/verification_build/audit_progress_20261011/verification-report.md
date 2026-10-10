# Audit Progress / Temporary Authority Recovery

## Observed User Job

- Strategy: `btcusd0.01MaMtfHighWR`, BTCUSDm, 2W.
- Job: `0082b056-f90f-49af-9db2-8949e97c780d`.
- Created UTC: 2026-10-10 21:23:14.769; completed UTC: 21:25:25.883.
- Elapsed: 131.114 seconds. Download versus computation timing was not recorded separately; the whole duration must not be attributed to downloading.
- Stored result: 7 WIN, 0 LOSS, 1 OPEN, 0 DATA, +0.07R, WR 100%, coverageComplete=true, failureCode=null.
- Last stored progress was replaying 38/100 even though the job was completed.
- The old installed native adapter continued reporting AUDIT_AUTHORITY_EXPIRED after completion. These observations were verified with scoped, read-only Supabase queries.

## Fix

Native EA 1.05 clears this specific stale pause only on a verified signed renewal matching jobId, attemptId, configurationHash and requestHash, or successful result emission. Authority expiry still pauses research. Signature checks, leases, entitlement checks and Trading ON authorization are unchanged.

The web progress panel displays preparing/downloading, native calculation and result-receipt stages; elapsed time; and the native preparation diagnostic. Unknown broker download totals use an animated indeterminate bar, not an invented percentage. Measured native calculation progress is displayed as a percentage. A completed job displays 100% regardless of its last intermediate progress. Failure/cancellation is never converted to completion. The labels are bundled in English, Turkish and German. Mobile result-panel shrink/wrapping was fixed as part of the browser checks.

No signal mathematics, trade geometry, fill rules, costs, W/L classification, strategy settings or broker history were changed by this fix.

## Verification

- Native compile: 0 errors, 0 warnings.
- Unit/regression suite: 67 tests passed, 0 failed.
- Actual MT5 roundtrip: ORB, MaCross, Sol Advanced and EntryLab completed with DATA=0; chart-coordinate checks and authorization/fail-closed checks passed. Terminal Algo Trading was disabled during these tests.
- Reference parity: `jp225Close/Reverse0.25R`, JP225m, 41 rows. No entry/exit-time, price, direction, geometry, spread, validity, net-R or normalized-result differences. Named TP025 versus custom TP_R0.25000000 is the sole accepted label alias.
- Actual native authority renewal: an isolated QA forwarder deliberately withheld audit commands for 20 seconds while retaining signed identity, heartbeat and progress. The native audit paused with AUDIT_AUTHORITY_EXPIRED, recovered on a fresh signed command for the same job/attempt, and completed without a stale error. No native trading was requested. This checks the native adapter, not arbitrary network outages or helper process restarts.
- Built UI with mocked API: animated indeterminate preparation, real replay percentage, temporary pause, completed-state override, elapsed time, native detail and 390px mobile width passed without runtime errors. Desktop/mobile screenshots were visually inspected.
- Auth-loading and strategy-library browser regressions passed. These are mocked-API UI checks, not broker audit evidence.
- Live Supabase test: login/demo entitlement, bearer/origin isolation, non-admin denial, strategy persistence, private package, owner-bound enrollment, signed pairing/replay rejection, controller activation, authority refresh, audit job, Trading ON denial without a result, revocation and logout passed. No broker backtest was claimed by this cloud protocol test.
- Live downloaded package: all four signed artifact hashes verified. Its EX5 exactly matches the locally tested EA 1.05.
- Live Pages: 68 public asset hashes matched; cloud health, CORS preflight, anonymous-session denial and foreign-origin denial passed.

## Deployment

- Public Studio: https://cemkaaa.github.io/CemkaCapital/studio/
- Public build commit: `28ee6e372649e4aff3ab082614bbd999cbde8062`.
- Native EX5 SHA256: `c7435543b2e4285f4ae14711880184efffd4b5f18b3568c41e383450e63e6a7f`.
- 19 verified native source/binary/dependency files copied to `C:\MT5\DEMO\MQL5\Experts\StratumUniversal`.
- Private cloud download artifacts updated with owner-signed, hash-verified upload. No database migration, key rotation, service bootstrap or cloud-function redeployment was required.

Existing installations do not silently replace a loaded EX5. Download the current personal ZIP and replace/reload only `MQL5/Experts/StratumUniversal/UniversalConnectionEA.ex5` for this fix. Preserve the existing `.state`, installation ID and pairing. The companion program was not changed in this turn.

## Changed Source / Test Files

- `IndicatorCodeExamples/universal/UniversalConnectionEA.mq5`
- `IndicatorCodeExamples/universal/UniversalRuntime.mqh`
- `web-mvp/components/universal-dashboard.tsx`
- `web-mvp/components/audit-progress.tsx` (new)
- `web-mvp/app/globals.css`
- `web-mvp/lib/audit-progress.ts` (new)
- `web-mvp/lib/audit-progress-messages.ts` (new)
- `web-mvp/lib/messages.ts`
- `web-mvp/lib/studio-help.ts`
- `web-mvp/scripts/test-audit-progress.mjs` (new)
- `web-mvp/scripts/test-audit-progress-ui.mjs` (new)
- `web-mvp/scripts/test-native-audit-renewal.mjs` (new)
- `web-mvp/scripts/test-mt5-roundtrip.mjs` (clean-completion assertion and atomic report writing)
- `web-mvp/scripts/test-canonical-mt5-parity.mjs` (atomic report writing)
- `web-mvp/scripts/verify-pages-live.mjs` (atomic report writing)

Generated EX5, public build files, deployment manifests, verification JSON and screenshots accompany these sources. Existing unrelated worktree changes were preserved.

## Evidence Files

- `tmp/universal_connection_validation/compile.log`
- `tmp/universal_connection_validation/roundtrip-report.json`
- `tmp/universal_connection_validation/canonical-parity-report.json`
- `tmp/universal_connection_validation/authority-renewal-report.json`
- `reports/verification_build/audit_progress_20261011/ui-report.json`
- `reports/verification_build/audit_progress_20261011/cloud-delivered-build.json`
- `reports/web_publish_20261009/live-verification.json`
