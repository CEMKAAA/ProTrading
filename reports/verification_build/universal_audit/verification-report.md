# Universal audit and shared strategy search verification

Verified: 2026-10-10 UTC

## Priority: stalled remote audit

The cloud received the user's ORB research request for `0.20RStarJp225`,
`JP225m`, `Exness-MT5Trial16`, two weeks. Its last recorded progress was
`downloading` with no preparation detail. Status stopped updating at approximately
18:56 UTC. Green connection text alone does not prove the native audit is advancing.

The previous Universal adapter ignored the native history hard-block flag and
retried preparation indefinitely. It also flattened native preparation failures
into a generic downloading status. Universal 1.04 now propagates hard blocks,
reports bar limits, and stops an unchanged preparation state after five minutes.
Actual tick replay is not subject to that preparation watchdog. Failures retain
their native explanation through the signed helper and cloud response; unavailable
data is never converted into a successful backtest.

The underlying cause on the other laptop is NOT conclusively established: the old
version did not send sufficient diagnostics, and that laptop has not been retested
with 1.04. A history/bar-limit failure was reproduced locally, but is not claimed
as the confirmed cause on the user's laptop.

## Verification

- Native compile: zero errors, zero warnings (`compile.log`).
- Universal binary SHA256: `eb1d851d16bce001512d3e2aaf31226bb40e2c981a653a5c3cfec3ea763ede05`.
- Exact JP225 strategy settings on isolated Trial15 worker: 8 W, 0 L, 0 O,
  zero DATA, +1.6 R. The warm audit stage took approximately three seconds.
  This is a different broker server/account from the remote laptop.
- Real terminal bar-limit test: MaxBars=5000 produced `AUDIT_HISTORY_BLOCKED`
  with the required/available bar counts, and no fabricated result. The worker's
  original MaxBars setting was restored afterwards.
- Four-family native roundtrip passed, including audit results, chart geometry,
  signed authority, expiry and revocation. No broker trade orders were requested
  by the JP225 probe; terminal trading was disabled during roundtrip testing.
- Original MaCross versus Universal parity: `jp225Close/Reverse0.25R`, 41 trade
  rows, zero numerical, timing, geometry or outcome differences. TP label aliases
  differ. This does not claim exhaustive original-EA parity for every strategy.
- Combined regression: 103 tests passed, zero failures.
- Live cloud test: login, private ZIP download, signed pairing/replay rejection,
  research progress/failure detail, Trading ON audit requirement, and revocation
  passed. This cloud test is not a broker backtest.
- Browser tests: nine windows, multi-sort priority, ascending/descending/off,
  window-specific card metrics, missing-last, desktop/mobile and no runtime errors
  passed with an explicitly mocked API. Auth loading/recovery browser tests passed.

Evidence: `jp225-probe.json`, `max-bars-probe.json`, `library-ui-report.json`,
`regression-tests.log`, and `tmp/universal_connection_validation/` reports.

## Shared strategy search

Nine selectable windows: 2W, 5W, 10W, 20W, 1Y, 2Y, 3Y, 4Y, 5Y.
Combinable sorting: WR, total trades, wins, losses, net R, minimum cumulative R.
Each criterion cycles descending, ascending, off. Selected order determines
priority; later criteria break ties. Missing values stay last in both directions.
Cards retain the selected window's total, W/L/O, WR, R, MC and position mode.
Admin-grant restrictions remain unchanged. Private unbacktested drafts do not
receive fabricated campaign metrics.

## Deployment

- Supabase `stratum-control` v11 deployed and tested. Existing signing and
  encryption keys, user records and device identity were preserved.
- Private downloadable Universal 1.04 and helper artifacts replaced through
  owner-authorized, hash-verified, atomic release configuration updates.
- Verified native package copied to `C:\MT5\DEMO\MQL5\Experts\StratumUniversal`.
- Website: https://cemkaaa.github.io/CemkaCapital/studio/
- Public commit: `934a49d0e2d540347c73ad9b14234d24067094d9`.
- GitHub Pages built; all 62 served public files matched their release hashes.
  Supabase health, CORS and anonymous/foreign-origin rejection checks passed.

## Other laptop update

Stop its old helper BAT and detach the connection EA before replacing binaries.
Download a new personal ZIP, extract it into the existing helper directory and
KEEP its `.state` directory. Replace the EX5 in that terminal's actual Data Folder,
restart the helper and attach the new EA with the existing connection.set.
Reauthorize the existing device if the controller lease expired, then retry 2W.
If preparation still fails, the displayed native diagnostic identifies the next
action; do not assume a successful audit from connection status alone.

## Source files changed

- `IndicatorCodeExamples/universal/UniversalConnectionEA.mq5`
- `IndicatorCodeExamples/universal/UniversalRuntime.mqh`
- `web-mvp/components/universal-dashboard.tsx`
- `web-mvp/components/shared-strategy-library.tsx`
- `web-mvp/app/globals.css`
- `web-mvp/lib/control-contract.ts`
- `web-mvp/lib/strategy-campaign.ts`
- `web-mvp/lib/campaign-messages.ts`
- `web-mvp/lib/connection-messages.ts`
- `web-mvp/lib/studio-help.ts`
- `web-mvp/control-service/control-plane.mjs`
- `web-mvp/control-service/http.mjs`
- `web-mvp/control-service/mt5-agent.mjs`
- `web-mvp/supabase/functions/stratum-control/index.mjs`
- `web-mvp/scripts/generate-cloud-control.mjs`
- Regression/probe/browser test scripts and generated cloud bundles.

The production signal mathematics, broker execution model and proprietary frontier
EA source files were not changed by these adapter/UI fixes.
