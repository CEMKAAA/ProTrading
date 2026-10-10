# Studio Authentication Feedback And Session Restoration

## Findings

- The previous startup effect always requested `/v1/auth/session`, including anonymous cloud startup. Its late 401 unconditionally removed the stored handle, potentially erasing a more recent successful login. Its late success could also overwrite a newer credential.
- The dashboard displayed the login form whenever its account snapshot was absent, even after successful authentication while `/v1/session` was loading.
- The parent credential callback was recreated on each render, restarting the dashboard polling effect unnecessarily.
- Existing server policy issues a 12-hour browser session. Hourly Supabase JWT expiry is refreshed server-side; it does not itself require login. Read-only production metadata also showed expired local sessions with provider sessions still present and no provider `not_after` deadline.
- Cloud handles remain in sessionStorage, not localStorage. Closing the tab/session can therefore require another login. Neither this policy nor the 12-hour cap was changed.
- The specific historical logout the user observed cannot be reconstructed conclusively from the available response logs. The startup race is a reproduced defect, not proof that every logout had that cause.

## Changes

- `web-mvp/components/studio.tsx`: stable credential callback, restoration status and revision fence.
- `web-mvp/lib/studio-session.ts`: cloud startup restores the opaque handle without an anonymous probe; local cookie probes cannot overwrite later login/sign-out, including during JSON parsing.
- `web-mvp/components/universal-dashboard.tsx`: separate login/register pending indicators; synchronous duplicate-submit guard; locked fields/mode during submission; verified workspace loading; transient restoration retry; auth errors beside the form.
- `web-mvp/components/auth-progress.tsx`: accessible restoration/workspace loading and retry view.
- `web-mvp/app/globals.css`: scoped spinner and responsive status card, with reduced-motion support and existing design tokens.
- `web-mvp/lib/auth-messages.ts`, `web-mvp/lib/messages.ts`: bundled EN/TR/DE loading and retry text.
- `web-mvp/scripts/test-studio-session.mjs`: restoration race, stale responses, unmount, localization and accessibility tests.
- `web-mvp/scripts/test-supabase-auth.mjs`: provider outage/recovery and repeated hourly refresh/session-cap regression tests.
- `web-mvp/scripts/test-pages-auth-loading.mjs`: production-build browser scenarios with deliberately delayed/mocked responses.
- `web-mvp/scripts/test-pages-auth-ui.mjs`: real published-site login, polling and reload restoration checks.

## Verification

- 111 automated regression tests passed; 0 failed. See `tests.log`.
- Production TypeScript/static export build passed. Next emitted its existing multiple-lockfile/root warning. See `build.log`.
- Seven browser scenarios passed with no page errors: loading/duplicate suppression, saved-session reload, transient 503 recovery, real revocation handling, signup confirmation, failed-login retry and restoration retry. These scenarios intentionally mock API responses; see `browser-loading.json`.
- Desktop Turkish and mobile German loading screenshots were inspected; spinner is active by default and disabled by reduced-motion preference.
- Frontend published as `8cb67a1c05e6b92292986eada1bf53ee72ea2df1`; all 56 public files matched the verified build. See `live-deployment-check.json`.
- Real published-site Supabase login/polling/reload test passed: all 16 requests returned 200, the same stored handle survived reload, no second login or anonymous auth probe occurred, and QA logout succeeded. See `live-auth-ui.log`. Hourly renewal tests use a controlled clock, not an 11-hour production observation.

## Scope

No EA, trading engine, audit campaign, enrollment protocol, subscription duration, database schema or Edge deployment was changed. Definitively revoked/expired sessions still fail closed. Provider JWT/refresh tokens remain server-side. Temporary connection failures do not grant authority or turn trading on.
