# Published Cloud Authentication Verification

Date: 2026-10-10
Studio: https://cemkaaa.github.io/CemkaCapital/studio/
GitHub Pages commit: db38cb61c6182887aee5df686fc3624c115b3208
Supabase function: stratum-control, version 6, ACTIVE

## Root Causes And Fixes

- Browser requests used cookie credentials against a cloud bearer-token API without credentialed CORS preflight headers. Cloud clients now omit cookies; loopback clients retain their HttpOnly-cookie policy.
- Cloud cold starts loaded every private EA binary even for login/session requests. Artifacts now load only for health/package/download routes and retain SHA-256 verification.
- The ten-second frontend timeout was shorter than observed cloud responses. Cloud control requests now allow 45 seconds; local requests keep their shorter timeout.
- Concurrent dashboard requests serialized on the account advisory lock; PostgreSQL logs confirmed 55P03 lock timeouts. GET requests now reuse the existing server-verified three-second authority window. Mutations still force authority revalidation; the account lock and scope checks remain.
- Email confirmation used /studio without the GitHub Pages project prefix. The server now pins redirect_to to https://cemkaaa.github.io/CemkaCapital/studio/ with an operator-defined, validated base path.
- Deno exposes a window alias without browser location. The shared endpoint module now tolerates that environment; the deployable bundle has a dedicated boot regression test.
- Error messages distinguish the online service from the local pilot. Website sign-in does not require the MT5 helper or local launcher.

## Verified

- 50 local regression tests passed: credentials/timeouts, download verification, Supabase ownership/revocation, cloud policy, CORS, lazy artifacts, Deno boot and guidance.
- Production Next.js build and TypeScript checks passed. Static export validation found no private server keys, EA sources or binaries in the public build.
- GitHub Pages reported the new commit as built. Live Studio HTML SHA-256 matched the local export: c6ba90b597d313fe07504bbf6509b1e5cb3a70f6cd03596e798b7563aeb8bc7c.
- Real Chromium requests from the published origin: health 200, unauthorized session 401, invalid registration 400, valid existing-QA registration 201 with confirmationRequired, existing-QA login 200, authenticated session 200.
- Published UI login/session/logout passed with no localhost auth calls, CORS errors or server 5xx responses in that observation. QA logout returned 200.
- No Trading ON, MT5 research jobs, pairing changes or live trade requests were submitted by these tests.
- No canonical EA sources, strategy settings, audit campaign scripts or audit results were changed as part of this work.

## Limits

- Registration testing reused an existing QA identity; it is not proof of a new mailbox receiving a confirmation email or clicking its link.
- Supabase Auth management configuration was not changed: the authorized MCP OAuth scope did not permit reading auth configuration (HTTP 403). The application callback is tested, but the provider's redirect allowlist and SMTP delivery were not independently verified.
- These checks verify authentication behavior, not every MT5 execution or subscription/payment scenario.
