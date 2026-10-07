# Studio Guidance And MVP Readiness

Updated: 2026-10-07.

## Delivered In This UI Pass

- Guided first-run view: account, MT5 connection, configure/audit, review.
- Expert view retains the existing engine controls. Switching views changes no configuration values.
- Question-mark help for each exposed catalog field, displaying its name, original default, current draft value, explanation, example and caution.
- Candlestick teaching boards, not a single generic workflow animation. 25 effect families cover target, stop, sizing, capacity, reverse/wait/inverse/cost, NAS state/flow, clock, timeframe aggregation, averages, oscillators, range/retest, FVG/sweep, activity/profile, regimes, cooldown, holding, custom logic, evidence processing and drawing.
- Equivalent controls share a visual model. There are 742 catalog entries across the four engine families, not 742 independently authored mathematical simulators. Each lesson is bound to the selected control key/value. Some complex engine effects are schematic and explicitly described as such.
- EMA/SMA demonstration traces and Wilder-smoothed RSI/ADX/ATR examples use synthetic candles. They are not claimed as production-core parity data. Large parameter values are bounded for legibility and the lesson discloses that bound.
- Real Three.js teaching robot, pointing toward the board. Low-power rendering stops offscreen/hidden and stops redrawing a paused static scene. WebGL failure has an animated CSS robot fallback. The renderer has no credential access, command execution or network calls.
- Lessons autoplay, can be paused or stepped manually, and respect reduced-motion preference. Animation never changes settings, grants authority or executes trades.
- Explicit engine-family reset confirmation; an editable, clearly labeled RSI teaching draft; labeled rule-row inputs and left-to-right gate explanation.
- Device-fingerprint acknowledgment before approval; developer-token setup removed from subscriber UI.
- Trading ON requires a separate review/acknowledgment and a complete current audit matching the selected installation, instrument and broker. Dirty settings, missing DATA, stale/offline authority and running audits block the request. Server checks remain authoritative.
- Trading OFF remains directly reachable and stops new entries, not protective management of existing positions.
- Built-in EN/TR/DE core interface and lessons; unknown dynamic/technical strings remain English, and user names, strategy names, symbols and configuration identifiers are not translated.
- Reworked light/chrome/gold homepage: entry workshop, MT5 connection, market coverage, internal evidence, control rooms and seven post-hero scroll chapters. The product animations are explicitly synthetic, not live audit results.
- One-click conversational guide with OpenRouter as the first choice and an optional local Qwen/Ollama endpoint. Tool proposals are schema-validated, previewed, bound to the current draft and require confirmation. It cannot enable live trading. An operator-provided key is configured privately for DeepSeek V4 Flash.
- Optional browser voice: explicit microphone consent, dictation review by default, optional send-on-finish and reply playback. Mouth motion follows actual synthesis events; closing/hiding chat or changing language/provider stops owned speech activity. Browser speech may use an online provider even when the model is local.

## Current Offline Verification

Commands re-run after the conversational/voice changes on 2026-10-07:

```text
node --experimental-strip-types --test scripts/test-studio-agent-transport.mjs scripts/test-studio-agent.mjs scripts/test-studio-agent-client.mjs scripts/test-studio-agent-config.mjs scripts/test-agent-voice.mjs scripts/test-studio-guidance.mjs scripts/test-ui-locales.mjs scripts/test-design.mjs
73 tests passed, 0 failed.

node node_modules/typescript/bin/tsc --noEmit --incremental false
Passed.

npm run build
Passed, including prerendering / and /studio.
Existing warnings remain about large client chunks and plugin timings.
The first sandboxed build failed with spawn EPERM; the approved local rerun succeeded.
```

The current run covers mocked provider responses, in-memory authenticated route
handlers, exact strategy-evidence matching, schema validation, authority limits,
robot poses, deterministic speech-service mocks, and React SSR in EN/TR/DE.
It does not prove real microphone/speaker output, WebGL appearance, broad OpenRouter
model quality, local Qwen compatibility, real database authentication or MT5 parity.
Two real model conversation regressions were separately run below. See
`docs/STUDIO_AGENT.md` for configuration, privacy and the remaining release gates.

## OpenRouter Connection Follow-Up

The operator's key is stored only in the ignored server state directory and
loaded only by the control process. On 2026-10-07, real key validation returned
HTTP 200 and DeepSeek V4 Flash produced a Turkish answer plus a schema-valid
risk-change tool proposal through the existing adapter. No proposal was applied,
MT5 test executed or trade opened. The Supabase control service was restarted and
confirmed the model as configured; the web service was left running.

The current eight offline suites pass 73 tests, including real-component handler
mocks, private configuration loading, strict proposal validation, pending-review
continuity, bounded HTTPS/backpressure and distinct provider 401/402/404 errors.
TypeScript passed again. Browser voice/visual testing and end-to-end authenticated
MT5 workflows remain separate gates.

Real `scripts/probe-studio-agent.mjs --live` and `--live --case=orb` each completed
three replies against the configured DeepSeek model via the real control HTTP
handler and an isolated mock cookie/account. EURUSD preset 4/M1/5W/1R/pip 10/
Independent/MAX 3 matched exactly; USDJPY ORB/0.10R generated both required calls.
The personalized EA workflow and 30-pip stop/0.10R = 3-pip unit explanation were
correct. Explanations did not modify settings; nothing was applied or traded.
These are NOT real-user auth or MT5 parity tests. Natural-language guidance remains
probabilistic and is not an expert/financial guarantee.

Intermittent early POST resets were reproduced, including a TLS record-integrity
alert. The final six responses with the updated bounded/fresh HTTPS transport
succeeded without retry. Earlier failures remain documented: do not treat this
small sample as an availability SLA. See `docs/STUDIO_AGENT.md` for exact limits.

## Earlier Verification, Before The Current Pass

These earlier results are retained as history, not claimed as freshly re-run
after the conversational/voice changes. Commands were run in `web-mvp`:

```text
node --experimental-strip-types --test scripts/test-control.mjs scripts/test-supabase-auth.mjs scripts/test-trial-delivery.mjs
65 tests passed, 0 failed.

node --experimental-strip-types scripts/test-studio-guidance.mjs
15 tests passed, 0 failed.

node --experimental-strip-types scripts/test-design.mjs
Passed shared styling, motion model, switch and modal-source assertions.

node --experimental-strip-types scripts/check-pages.mjs
Local pages/assets return HTTP 200; guided Studio markup renders.

node node_modules/typescript/bin/tsc --noEmit
Passed.

npm run build
Passed. Existing warning remains about chunks over 500 kB.
```

Guidance tests cover immutable configuration conversion, HH:MM validation, all catalog entries' finite/deterministic teaching frames, target versus stop invariance, capacity, NAS stream separation, entry age versus exit wait, actual OHLC aggregation, regime observer non-blocking, valid custom-rule draft, authority/readiness gates and React server rendering.

These tests are **not** interactive browser or WebGL tests. Computer-use inventory returned no enabled app/browser. Actual animation visibility, keyboard focus, nested-modal click blocking, responsive screenshots and touch usability still require a browser verification pass. Do not describe those as passed.

## Existing Native Evidence, Not Re-run By This UI Pass

The following earlier reports remain the source of native MT5 verification:

- `tmp/universal_connection_validation/roundtrip-report.json`: four engine-family audit roundtrips, native compile and chart/authority checks.
- `tmp/universal_connection_validation/canonical-parity-report.json`: production versus universal MaCross comparison for one 41-trade JP225 setup. This is not exhaustive parity for all strategies.
- `tmp/universal_connection_validation/supabase-api-report.json` and `supabase-security-report.json`: earlier real-provider/private-database checks.

No production EA signal mathematics, audit engine, bridge schema, native executable or database schema was changed in this teaching-UI pass. No live orders were placed.

## Release Decision

Usable local research pilot, **not a public-production release**. This UI is a guidance layer, not proof that a novice cannot make an unsafe financial decision.

Remaining public-release gates include trusted paid-billing reconciliation, password recovery, MFA policy, HTTPS/Secure cookies, distributed abuse protections, key rotation, tested backup/recovery and installer/signing support. See `control-service/TRIAL_AND_DELIVERY.md` and `docs/MT5_AUTHORIZATION_VERIFICATION.md` for the security/deployment boundaries.

Do not replace unknown market costs or missing history with teaching-animation values. Teaching candles never enter terminal requests, audit results or live execution.
