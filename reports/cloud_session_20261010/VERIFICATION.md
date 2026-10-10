# Cloud Session Availability Fix

Date: 2026-10-10

## Confirmed Cause

Supabase function logs recorded `stratum-request-failed` for `/v1/session`
with PostgreSQL error `55P03` (lock timeout). Browser session, library and job
polls share an account-scoped transaction lock. Repeated sequential authority
writes and account/access reads extended the locked transaction enough for
concurrent requests to exceed the 10-second lock wait. Login itself succeeded.

## Changes

- `web-mvp/control-service/control-plane.mjs`: join account/access queries and
  support a single-query session snapshot without changing authorization rules.
- `web-mvp/control-service/supabase-auth.mjs`: use the batched authority adapter;
  retain the canonical SQLite path and access/trading revocation semantics.
- `web-mvp/control-service/cloud/postgres-store.mjs`: batch verified authority
  persistence into one SQL statement; obtain the session DTO in one query.
- `web-mvp/components/universal-dashboard.tsx`: separate polling failures from
  action failures; clear the former only after a successful refresh.
- `web-mvp/components/connection-panel.tsx`: separate polling failures and prevent
  the periodic timer from overlapping the initial connection refresh.
- `web-mvp/lib/studio-help.ts`: add the temporary cloud-service error explanation.
- `web-mvp/scripts/test-cloud-control.mjs`: optimized/fallback parity and SQL
  batching regression coverage.
- `web-mvp/scripts/test-cloud-session-poll.mjs`: authenticated concurrent read
  reproduction and verification using an isolated existing QA account.
- Regenerated the cloud policy sources, source hashes and Edge Function bundle
  using the existing build script. No schema migration was required.

The account lock, authority freshness limits, owner scoping, session revocation,
disabled-account checks and fail-closed authorization are retained. Errors are
not converted into successful actions. No native EA, trade engine, campaign,
strategy configuration or user grant was changed.

## Verification

| Check | Result |
| --- | --- |
| Pre-fix concurrent reads | 9 requests, 3 HTTP 500 `CLOUD_SERVICE_UNAVAILABLE` |
| Post-fix concurrent reads | 18 requests, 18 HTTP 200, zero failures |
| Mean concurrent read duration | 15,469 ms before; 9,599 ms after |
| Maximum concurrent read duration | 20,126 ms before; 13,088 ms after |
| Login and logout | Successful before and after |
| Automated regression suite | 90 passed, 0 failed |
| Actual PostgreSQL batch/snapshot SQL | Executed and checked in a rolled-back transaction |
| Static production build | Compilation, TypeScript and export validation passed |
| Published public assets | 56/56 HTTP responses and SHA-256 hashes match the build |
| Existing catalogue/campaign count | 191 active strategies, 188 campaigns retained |
| Native trading requested by test | No |

Evidence: `before.json`, `after.json`, `tests.log`, `publication.json` and
`live-deployment-check.json` in this directory. The suite covers control,
Supabase auth, cloud adapters/entrypoint, native catalogue, campaign metrics and
Pages paths.

## Deployment

- Supabase `stratum-control`: version 7, ACTIVE.
- GitHub Pages commit: `688e45844570dc3736ab4e2e5194ee7411d07f51`.
- Public Studio: https://cemkaaa.github.io/CemkaCapital/studio/
- GitHub Pages build status: built; live asset hash verification completed.

## Limitations

This finite test reproduced and then eliminated the observed failure; it does
not guarantee that every future infrastructure outage or workload will be
error-free. Requests still take several seconds in this environment. Account
serialization remains intentional, and unrelated long-running operations were
not benchmarked here. No visual browser interaction test was performed; the
frontend was type-checked, built and its deployed assets were hash-verified.
