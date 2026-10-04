# Launch Prototype Validation

Checked on 2026-10-04. Website source: `web-mvp/`.
No production EA, listener, broker account, or existing dashboard files changed.

## Passed

- `node scripts/run-framework.mjs build`: static production export completed.
- `node node_modules/typescript/bin/tsc --noEmit`: exit 0.
- `node --experimental-strip-types scripts/test-demo.mjs`: deterministic data,
  chronology, causality, progress completion, counts, R accounting, position caps,
  gates, spread handling, logical operators, input validation and DATA ambiguity.
- `node --experimental-strip-types scripts/test-design.mjs`: complete scroll turn,
  staggered market-token paths, light-theme/type tokens, AA shared text contrast,
  reduced motion and instanced geometry. Intro rules prohibit sticky/fixed pinning
  and oversized scroll spacers; scene rotation follows normal viewport traversal.
- `node scripts/check-pages.mjs`: homepage, studio, artwork, favicon and benchmark
  evidence returned HTTP 200; content, disclosures, controls and anchors passed.
- Changing a replay setting invalidates the previous result and cancels its work.

## Connection Foundation

- `scripts/test-control.mjs` covers pairing expiry/single use/fingerprint,
  cross-account denial, key proofs and replay, controller fencing, entitlement
  and lease expiry, revocation, immutable/idempotent jobs, signed dispatch,
  attempt fencing, progress, cancellation, coverage/unknown-cost semantics,
  real net R/FLAT/DATA, durable restart, client ticket verification, and HTTP.
  Latest run: 25 passed, 0 failed. TypeScript check and production export passed.
- `scripts/check-control-release.mjs`: 40 static client artifacts scanned; neither
  the local private signing material nor development bearer credential appeared.
  Persistent loopback API authentication passed; live trading remained false and
  MT5 adapter state remained not_connected. Startup without --local-dev refused.
- This control-plane test suite uses fixtures, not market backtests. It is not
  MT5 parity evidence. No existing EA/EX5, bridge or broker terminal was changed.
- Studio connection controls use the loopback API, not a fake success timer.
  The development probe deliberately refuses execution with
  `MT5_ADAPTER_NOT_CONNECTED`. Real subscriber auth/billing and a connection EX5
  remain explicit production gates in `docs/CONNECTION_ARCHITECTURE.md`.

## Preview

- Homepage: http://127.0.0.1:4310/
- Studio: http://127.0.0.1:4310/studio
- Restart: `node scripts/run-framework.mjs dev --host 127.0.0.1 --port 4310`

The local server must remain running for these links to work.

## Boundaries

- Browser automation surfaces were unavailable. Screenshot-based desktop/mobile
  visual QA and interactive WebGL inspection were not performed.
- The light redesign is implemented and build-tested. A request to use local
  Playwright for screenshot and actual scroll verification is awaiting approval.
- Live forwarded browser logs exposed reduced-motion suppression and a first-render
  hydration mismatch. Preference detection now uses a stable server snapshot.
  At the user's explicit request both 3D scenes autoplay without an enable step;
  scroll adds rotation and a pause control remains available. Section reveals
  continue to respect reduced motion. Autoplay trajectories pass unit tests.
- The optional read-only WebMCP registration was not tested in a supported host.
- Replay uses explicitly synthetic OHLC data. It is not the production tick audit,
  live trading, or evidence of investment returns. Both-boundary ambiguity is DATA.
- Subscription authorization, account creation, MT5 pairing and certified EA
  delivery remain planned features, not connected services.
- Engineering claims use the curated evidence in `public/benchmark-evidence.json`.

## Cloud Publishing Blocker

The previously registered project in `.openai/hosting.json` returned
`project_not_found` / `NOT_FOUND` from the Sites connector. The current owner
inventory returned no sites. No replacement or duplicate project was created,
and no cloud deployment succeeded. Do not describe the old proposed URL as live.
Restore access to that project before requesting a repository credential and
publishing the verified static export.
