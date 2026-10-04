# Stratum / Launch Experience

A new, isolated website prototype. Production EA code, listeners, trading accounts,
root dashboard, and proprietary entry-engine implementations are not modified.

## Direction

Revised after the user's BrightFunded reference: open sky-blue surfaces, navy text,
yellow actions and a bright metallic gold coin. Not a clone of either reference.
Manrope / IBM Plex Mono, a shared readable type scale (18px body, 16px controls,
14px captions), and consistent surfaces, radii and buttons across both routes.
Design variance 7, motion intensity 7, visual density 3 on the landing page.
Theme is deliberately light, as requested. It does not follow OS dark preference.

## Implemented

- Landing: a normal-flow scroll-driven 3D coin without an intro hold, a second staggered
  3D market-token scene, section-aware navigation and restrained reveal motion,
  interactive strategy preview, measured engineering benchmarks, workflow,
  authorization concept, accessible FAQ, evidence modal, and complete footer.
- `/studio`: local condition editing, AND/OR/XOR/NOT, synthetic candle visualization,
  Single/Independent position cap, configurable R/spread, real batched fixture replay,
  progress measured by examined bars, cumulative R, trade log, local save/load and
  JSON configuration download.
- Browser-local saves are explicitly identified as such. Same-name saves update.
- Responsive desktop/mobile layouts, reduced-motion behavior, local bundled fonts,
  dynamic Three.js import, instanced engraving and offscreen rendering suppression.
  Both scenes have a pause control. Continuous scroll stays outside React state.
  At the user's explicit request the 3D scenes autoplay, even with reduced motion
  enabled on the device. Section reveals still honor that preference. Hydration
  reads the preference through `useSyncExternalStore`, not client-only markup.
- Connection architecture: the Studio MT5 connection dialog now talks to a real
  loopback control service. It supports reviewed one-use installation pairing,
  one active controller generation, signed immutable research jobs, work-based
  progress, ownership-scoped results, revocation, and durable SQLite state.
  This is explicitly local development, not subscriber/billing authentication.

## Not Implemented Or Claimed

There is no production subscription/login integration, real market-data feed,
live strategy execution, actual MT5 execution adapter, downloadable certified EX5,
or production audit engine connected to this website. Protocol pairing can be
tested locally, but the development probe is not an EA. Synthetic results are not investment-performance
evidence. The demo mirrors BUY logic for SELL; the intended full builder must
support independent BUY/SELL sequences and stateful engines.

The fixture replay is OHLC-based, not tick-based. It marks both-boundary candle
ambiguity DATA. Example spread is included in fill geometry; commission, swap,
gaps/slippage and broker-specific execution are not modeled. Never use this demo
to select a live strategy or claim a live fill.

## Evidence

Engineering measurements were read from `../reports/audit_acceleration_20261003.md`.
Only a small curated, non-credentialed summary is shipped under
`public/benchmark-evidence.json`. Proprietary EA sources and private strategy
recipes are not shipped.

## Local Development

```powershell
npm install
node scripts/run-framework.mjs dev --host 127.0.0.1 --port 4310
node node_modules/typescript/bin/tsc --noEmit
node --experimental-strip-types scripts/test-demo.mjs
node --experimental-strip-types scripts/test-design.mjs
node --experimental-strip-types --test scripts/test-control.mjs
# Separate loopback process; refuses production startup:
node --experimental-strip-types control-service/start.mjs --local-dev
node scripts/run-framework.mjs build
```

The Site manifest is `.openai/hosting.json`. This checkout is the future website
source of truth; do not merge it into the existing EA dashboard unintentionally.
Local-only experimentation can use it without touching the trading environment.

## Design Source Of Truth

`app/globals.css` defines the palette, type, spacing and shape tokens. New sections
must reuse those tokens and `.section-heading`, `.surface`, `.primary-btn`,
`.secondary-btn`, and `.icon-btn`; do not append another miniature font scale or
section-specific color theme. `lib/scene-motion.ts` owns the tested scene paths.

Reference source inspected: https://brightfunded.com/ (HTML/CSS on 2026-10-04).
Browser screenshot inspection was unavailable in the connected UI tool. Local
Playwright screenshot testing requires the user's separately requested approval.

## Single-EA Architecture

See `docs/CONNECTION_ARCHITECTURE.md` for source boundaries, protocol, run commands,
threat model, actual implementation status and MT5 parity gates. The four existing
EAs remain reference implementations; subscribers will receive ONE authorized
connection EA. No existing EA/bridge files were changed for this foundation.
Development `.state` keys/tokens must never be shipped or committed.
