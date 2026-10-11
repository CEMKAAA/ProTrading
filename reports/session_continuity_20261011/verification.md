# Session continuity verification

Status: PASS. Published on 2026-10-11T11:40:33.037Z.

## Behavior
- Supabase-backed browser sessions last 604800 seconds (seven days) after a new sign-in.
- Browser restart restores only an opaque BFF handle. Supabase access/refresh tokens stay encrypted server-side.
- Explicit Trading ON consent uses the existing completed job, installation and generation. Browser timeout does not change that consent.
- Device calls revalidate the current owner, disabled/banned/deleted state and paid/demo expiry in private SQL. Signed execution grants remain short-lived.
- Trading OFF, logout, device revocation, account expiry and a new audit retain their stop behavior.
- The native EX5 and helper protocol are unchanged; no new ZIP is needed.

## Evidence
- 118 policy/auth/session tests passed; zero failures. Exact hour 168 rejects the BFF handle after 167 successful hourly refreshes.
- Production-build browser tests passed, including a new tab without sessionStorage, login loading, transient 503 recovery and revocation cleanup.
- Real native EX5 audit: JP225m M5, ORB 2W, 5W/3L, DATA 0, +2R. Algo Trading disabled throughout.
- Native helper stop expired authority; restarting restored the same approved configuration without another login or audit.
- Real Supabase API: new login exposes seven-day expiry. Expiring only the isolated QA BFF/lease rows did not prevent a new signed helper session from resuming prior consent. OFF denied subsequent live commands. Cloud audit data was a fixture, not a market result.
- Supabase stratum-control version 12 is ACTIVE. GitHub Pages commit 8e7585c96a3cddd9b29d9ae793b126ba5e43b039 is built. Public release hash checks and authorization/CORS denial checks passed.

## Changed sources
- web-mvp/control-service/control-plane.mjs
- web-mvp/control-service/supabase-auth.mjs
- web-mvp/control-service/http.mjs
- web-mvp/control-service/cloud/postgres-store.mjs
- web-mvp/lib/control-endpoint.ts
- web-mvp/components/connection-panel.tsx
- web-mvp/lib/studio-messages.ts
- web-mvp/scripts/generate-cloud-control.mjs
- web-mvp/scripts/build-cloud-control.mjs
- web-mvp/scripts/test-supabase-auth.mjs
- web-mvp/scripts/test-pages-auth-loading.mjs
- New tests: test-control-session-storage.mjs, test-persistent-execution.mjs, test-native-persistent-execution.mjs, test-cloud-persistent-execution.mjs.
- Generated cloud policy, sources manifest, bundle and build metadata were regenerated from the canonical source.

## Limits
- Seven-day expiry is verified with a simulated policy clock, not a real seven-day wait.
- Existing browser sessions retain their issued expiry; a fresh sign-in receives seven days.
- Native command/renewal testing kept MT5 Algo Trading disabled; no broker orders were placed.
- The cloud continuity test used an unattached QA installation and a clearly labeled synthetic audit result.
- Continuous live authorization still requires valid access, the approved installation, MT5 and its helper; outages expire short-lived new-entry grants.
