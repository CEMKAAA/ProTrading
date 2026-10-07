# Studio Guide: Bounded Conversational Control

Status: two real OpenRouter conversation/proposal regressions verified; browser voice and end-to-end MT5 integration remain separate verification gates.
Updated: 2026-10-07.

## User Flow

The floating animated robot opens a private conversation in one click. The guide
can explain existing settings, prepare a strategy, propose BUY/SELL rules, load a
saved configuration, save it, request an audit, navigate controls, and open the
existing live-trading review. It cannot enable trading or acknowledge risk.

OpenRouter is selected by default; local Qwen/Ollama is an alternative. The user
must separately consent to cloud sharing. The provider receives conversation,
strategy draft, private strategy names, instrument, and real audit summaries.
Account identifiers, passwords, tokens, broker login/server, device fingerprints
and raw trade rows are excluded from the application-generated model context.
Never paste credentials into chat. The app cannot prevent someone deliberately
putting private information into their own message.

Unsaved chat stays in component memory and is not written to browser storage.
The user can explicitly click **Save conversation** to store a named snapshot in
their Supabase account, then reopen or delete it from **Chat history**. There is
no automatic save on send, modal close, logout, or provider switch. Provider
switching preserves visible messages but clears pending proposals and cloud
consent. Account logout clears the component. Save again updates that same chat.
Only sent user/assistant text is saved, not unsent text, tool calls, proposals,
configuration snapshots, credentials or execution grants. Reopening a chat does
not alter the current strategy or enable trading; it can be continued against the
current desk. All visible messages are kept; only the last 12 (2,000 characters
each) are sent as model conversation context. Saved chat limits: 512 messages,
6,000 characters/message and 1 MB per snapshot; history pages contain 25 records.
A model provider can retain messages according to its own policy. This is not a
zero-retention claim.

History endpoints use the existing HttpOnly session, live Supabase session checks,
origin/CSRF protection and an authenticated user's JWT (no service-role bypass).
`stratum_conversations` RLS requires ownership and a valid, non-disabled provider
session, but not an active subscription to retrieve the user's own data. No
account id is accepted from the browser. Creation time is preserved by a private
timestamp trigger even on upsert. The SQLite adapter is local QA only. Apply
`control-service/supabase-conversations.sql` once to an existing configured project.

## Actual Responsibilities

```text
User sentence
  -> authenticated, entitled control API
  -> sanitized current context + existing typed control catalog
  -> OpenRouter or local model: explanation + proposed function calls
  -> strict tool/schema validation (server)
  -> same validation again (browser)
  -> before/after preview bound to the draft and selected connection
  -> explicit user confirmation
  -> existing configuration/library/audit UI actions
  -> existing authenticated MT5 job pipeline
  -> real result cards and the existing detailed trade table
```

There is no new execution engine, broker protocol, audit mathematics or generic
MCP bridge. No generated code runs. The guide addresses the 742 entries in the
four current input/runtime catalogs, the existing EntryLab builder and day/hour
masks. The tool schema does not invent features missing from the native adapter.

Engine selection resets the draft, rather than inheriting settings. A requested
engine switch and target override are composed in the same review proposal.
Explanatory follow-ups retain that proposal; validated pending calls are sent
separately from the current draft. Pending review never counts as applied settings
or audit evidence. Full settings and the before/after diff are collapsed by default.
Saved-strategy
loading must use an exact private library name. Edits are validated as one complete
configuration. Unknown keys, types/enums/invalid waits, extra arguments, duplicate
audit actions and more than eight calls are rejected. HH:MM is expressed as integer
minutes in tool calls. A stale draft/connection invalidates a proposal.

Undo restores only the draft; it does not cancel jobs or undo library saves.
Library save, refresh and audit requests are distinct operations, not a distributed
transaction. If one fails after another succeeded, inspect the actual library/job
state before retrying. Server idempotency/authorization remain the authority.

The agent has no subscription, pairing, device-approval, SQL, shell, URL or direct
trading tools. Live-review acknowledgments always start unchecked. Existing
installation/controller/current-audit/live checks remain in place. Model errors
never produce a canned success answer. Local application limits: 12 requests per
account/minute, one active per account, two overall, 60-second provider timeout,
bounded conversation/body/response, no redirects. Browser disconnect propagates
an abort to a cooperative fetch provider; this is not a billing/refund guarantee.

## Strategy Suggestions And Evidence

The guide gets private strategy names plus up to ten most recent account-owned
jobs from the existing service. Only completed jobs whose entire configuration
matches an existing saved strategy are included as saved-strategy evidence.
Numbers are server-derived, not user-supplied result summaries. Each includes
symbol, window/dates, W/L/OPEN/DATA, percentage WR, net R, and closed drawdown.

This is not an exhaustive leaderboard. A name match alone is insufficient; a
strategy edited since that audit does not inherit its metrics. Models are told
not to manufacture missing stats or call a high WR proof of an edge. Natural
language remains probabilistic: inspect the independently rendered real-result
cards and trade table. A language-model explanation is not a financial validation
or a guarantee against hallucination/overfitting. A proper recommendation test
must compare like-for-like symbols/windows and include unseen evidence.

## Server Configuration

The control service also reads its ignored, server-only
`control-service/.state/assistant.env` on startup. Only the four assistant
variables below are accepted; explicit process environment values take precedence.
This file is not loaded by the web process or bundled into browser assets.
Restart the control service after updating it.

Set these **only in the control-service environment**, never `NEXT_PUBLIC_*`,
browser storage, the EA download or a committed file:

```powershell
$env:STRATUM_AI_OPENROUTER_KEY = '<your provider key>'
$env:STRATUM_AI_OPENROUTER_MODEL = '<exact verified OpenRouter model ID>'
# Optional local alternative; use the exact installed Ollama model tag.
$env:STRATUM_AI_LOCAL_MODEL = 'qwen3.5:9b'
$env:STRATUM_AI_LOCAL_URL = 'http://127.0.0.1:11434/v1'
```

On 2026-10-07 the operator-provided key was configured privately for
`deepseek/deepseek-v4-flash`. The live OpenRouter catalog reported tool support,
key validation returned HTTP 200, and the existing adapter returned a real Turkish
answer plus a schema-valid `edit_settings` proposal for `InpRiskPerTradePct=0.5`
on a synthetic EntryLab draft. No proposal was applied, strategy saved, MT5 audit
run or live trade opened by this probe. The running Supabase control service was
restarted and confirmed this model as configured. These are point-in-time checks,
not a future availability guarantee. Changing the model ID
does not alter the agent/tools/UI. A model that cannot call tools correctly fails
validation rather than receiving arbitrary execution access.

Restart the project's local launcher from that environment. A pre-existing control
service must be restarted to receive new environment variables; the launcher does
not replace unrelated processes. The status UI distinguishes configuration from
successful connection. The configured key is never returned in status responses.

The local adapter uses an OpenAI-compatible non-streaming `/v1/chat/completions`
endpoint on literal `127.0.0.1` only. Its compatibility with the user's installed
Qwen/Ollama build remains untested. OpenRouter uses a fixed HTTPS endpoint. Users
and models cannot supply arbitrary endpoint URLs. Tool definitions/catalogs can
be substantial; context/pricing must be evaluated with the actual model, not guessed.

## Conversation Regression, 2026-10-07

The reported conversation exposed three genuine grounding/planning defects:
the guide denied the personalized EA download, described R as ORB range, and
proposed only the family switch without the requested 0.10R override. Product
facts, the stop-risk unit definition, proposal-vs-execution semantics and tool
descriptions are now explicit. Runtime target overrides are distinguished from
startup input defaults. No native geometry was changed to achieve these checks.

The model also receives source-reviewed descriptions of all ten EntryLab presets,
their independent BUY/SELL conditions, cooldown/holding/rule exits, builder
semantics, application operation help, and each documented control's guide.
The preset source hash is pinned in tests. Undocumented exact formulas must not
be invented. This is a knowledge reference, not a claim of model infallibility.

Real `scripts/probe-studio-agent.mjs --live` results through the actual control
HTTP/cookie handler, with an isolated mock account and the real configured model:

- EURUSD: requested preset 4, M1, 5W, 1R, pip stop 10, Independent, MAX 3,
  existing risk 1%. The validated proposal matched all requested values. Three
  replies returned HTTP 200 (6.6, 13.6, 39.4 seconds), without transport retries.
- `--case=orb`: personalized EA workflow was correctly supported; ORB plus
  `runtime.targetR=0.1` were proposed together. An explanation-only follow-up
  correctly calculated 30 pip stop x 0.10 = 3 pip before costs and returned no
  edit calls. Three replies returned HTTP 200 (12.8, 17.1, 10.7 seconds), without
  transport retries. Current and pending drafts remained distinct.

No proposal was applied, strategy saved, MT5 audit executed or order opened in
these probes. They do not test Supabase identity, a real user's installation or
market profitability. Earlier failed probes are not counted as successful ones.
Prose can still drift (jargon or suggesting another preparation step); validated
review cards and server results, not prose, remain authoritative.

## Transport Findings

Earlier real POST requests intermittently failed before any HTTP response with
`UND_ERR_SOCKET`/`ECONNRESET`; fresh native HTTPS also surfaced
`ERR_SSL_SSLV3_ALERT_BAD_RECORD_MAC`. Public model-catalog GETs succeeded. This
locates a transport failure, not an invalid strategy or provider HTTP rejection;
it does not establish which network component caused it.

OpenRouter alone now uses verified HTTPS with a fresh connection, bounded 4096-byte
TLS/upload chunks, backpressure and short pacing. TLS version negotiation and
certificate/hostname verification are not disabled. Redirects are not followed.
Local Qwen and Supabase transports are unchanged. The transport uses Node's
[documented TLS fragment API](https://github.com/nodejs/node/blob/v22.x/doc/api/tls.md#tlssocketsetmaxsendfragmentsize).
One fresh-connection retry is allowed for the observed early reset/record error;
HTTP errors, partial responses, cancellation and certificate failures are not
retried. Both attempts share the original 60-second budget. A retry can incur
provider cost but never executes a tool. Diagnostics contain allowlisted error
codes/timing only, not chats, exception messages or secrets.

The final six replies above succeeded on their first attempts. An earlier paced
connection also failed, so universal availability or elimination of every network
failure is NOT claimed. No fallback answer, fabricated success or certificate
bypass masks failures.

## Personality And Lessons

Blinking/idle looking, listening/nodding, narrow-eyed thinking with a hand near
the chin, curious upward gaze and board-pointing are deterministic local animation
states. They follow typing, pending requests, proposals, applying and error state;
they are not simulated proof that an LLM is reasoning. CSS fallback remains animated
if WebGL is unavailable. Hidden/offscreen rendering and reduced-motion limits apply.

Lessons expose the actual control key/current/default value, optional default
comparison, three chart stages and an explicit OFF warning. They are synthetic
teaching diagrams across 25 effect families, not 742 individual EA simulators.
Complex engine formulas are not falsely replicated by the tutorial. No tutorial
changes a draft, sends orders or fabricates an audit. Bundled EN/TR/DE cover the
core interface; unknown dynamic/technical strings remain English. User names,
strategy names, symbols and configuration identifiers are not translated.
Model response language is requested but depends on the actual model.

## Voice Conversation

Voice is optional and OFF by default. An explicit browser-speech consent is
separate from OpenRouter consent. The microphone starts only after pressing its
button; it is not continuously open. Speech recognition can be an online browser
service, including when the language model is local. No app audio recorder or
audio upload endpoint is used, but the browser's provider can process audio.

Default dictation fills the text box, so numbers/pips can be checked. Optional
"Send when dictation ends" enables conversational turns. All resulting model
tool proposals still require the usual visual confirmation. No recognized speech
can acknowledge live trading or create orders directly.

Replies can be read automatically or via "Read last answer". Speech synthesis
selects a matching EN/TR/DE voice, preferring an installed local voice; absent
language support is reported, never silently replaced with the wrong language.
Closing chat, leaving the tab, logging out or changing provider/language stops
owned microphone/playback activity. Stop-voice and finish-dictation buttons exist.

The robot's mouth moves between actual synthesis `onstart` and `onend`, with word
boundary pulses where available, plus a bounded fallback rhythm. This is not
audio-derived phoneme/viseme lip synchronization. The text transcript is always
retained even if audio fails. Browser voice capability, microphone permission,
audio startup, OS voices and cloud STT latency still need actual browser testing.
HTTPS (or localhost) and appropriate browser permissions are deployment requirements.

## Verification Boundary

Offline tests cover strict proposals, catalog access, known builder IDs, minutes,
day masks, provider selection/secret exclusion, invalid/truncated/oversized output,
rate/concurrency limits, in-memory HTTP authorization/ownership, saved-strategy
evidence and robot poses. Mock providers and streams are used, not real services.

Current local verification: 73 tests passed across guidance, agent, real component
handler mocks, transport, voice, server configuration, language SSR and design
suites; TypeScript passed. Tests cover combined ORB/0.10R proposals, pending-review
continuity, UTF-8 chunk/backpressure integrity and unchanged confirmation authority.
The final build completed, and running `/`, `/studio` and checked static assets
returned HTTP 200. Only the verified Supabase control-service process was restarted
to load this pass; the web service and MT5 were not stopped. Refresh Studio to
clear the earlier, incorrect in-memory conversation and load the updated UI.
Voice tests use deterministic browser-service mocks, including
duplicate final segments, permission/start errors, missing language support,
stop/unmount/locale changes and synthesis-event mouth timing. They are not
real microphone, speaker or WebGL tests. Build warnings about large chunks and
plugin timings remain. See `docs/STUDIO_MVP_READINESS.md` for exact commands.

Still required before release: broader OpenRouter/DeepSeek tool quality and local Qwen compatibility;
browser visual/mobile/focus testing; real account auth; end-to-end draft/audit parity
against MT5; save/reload/undo/stale-proposal interactions; prompt-injection red-team;
public deployment controls, distributed budgets and monitoring. Current server is
the existing loopback pilot, not a publicly deployed production SaaS.
