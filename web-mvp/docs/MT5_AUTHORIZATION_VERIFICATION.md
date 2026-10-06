# Universal MT5 Authorization

The connection EX5 contains the existing ORB, MaCross, Sol Advanced and EntryLab
calculation implementations. Canonical production sources are not changed by
the connection authorization work. The browser sends immutable configuration
snapshots, not arbitrary MQL code. Apply requests research only.

## Authority Chain

1. A subscriber approves the installation public-key fingerprint.
2. An authenticated browser activates one controller generation per account.
3. Device requests use Ed25519 signatures over method, route, payload hash,
   timestamp, nonce and the random process-scoped agent ID.
4. Only one active agent ID may use an installation at a time. Its lease expires
   after 15 seconds without renewal; a replaced controller fences old agents.
5. The service signs the **exact EA command** using RSA-2048/SHA-256,
   PKCS1-v1_5. The private key remains server-side. The public modulus is pinned
   into the compiled EX5, not loaded from the subscriber's files.
6. The EA itself verifies signature, installation, MT5 account login, broker,
   symbol, expiry and an increasing server sequence. The verified command is
   cached only until its original monotonic deadline, never extended by replay.
7. A locally readable HMAC key authenticates terminal/result IPC and can request
   STOP; it cannot grant audit or live authority. Subscriber-controlled results
   are explicitly labelled `client_reported`, not independent attestation.
8. Live authority requires an explicit Trading ON request following a complete
   matching audit. Apply, OFF, logout, revocation, subscription expiry and lease
   failure prevent fresh authority. Already-issued grants can survive for up to
   15 seconds; zero-latency remote revocation is not claimed.
   Changing the reported broker/account/symbol turns Trading OFF and cancels
   in-flight work instead of silently carrying the old authority to a new context.

## Repeatable Tests

`node --experimental-strip-types --test scripts/test-control.mjs`

`node --experimental-strip-types scripts/prepare-ea-authority.mjs` writes only
the public pin header. Rebuild EX5 whenever this deployment key changes.

`node --experimental-strip-types scripts/prepare-ea-proof-probe.mjs` creates
the native MQL5 probe: valid and invalid signatures, strict padding, Unicode,
wrong device/account/market, expiry and replay scope. It contains no private key.

From the workspace, `scripts/validate_universal_connection.ps1` compiles and
launches only the existing isolated demo worker; it never copies broker history.
`web-mvp/scripts/test-mt5-roundtrip.mjs` exercises the actual HTTP API, companion,
EX5 and four audit engines. Terminal Algo Trading remains disabled throughout.
It tests permission transitions, not actual order execution or fills.

### Original-EA Comparison

`node scripts/prepare-canonical-parity.mjs` generates a bounded test-only setting
capture. `scripts/validate_canonical_parity.ps1` compiles a probe which includes
the **unmodified canonical MaCross source**, applies a compatible saved strategy
through its own strategy loader, and runs its normal historical audit. Its clock
is fixed at 2026-10-05 00:00; native trading and bridge publication are disabled.
The probe does not call the universal implementation to produce its baseline.

`node --experimental-strip-types scripts/test-canonical-mt5-parity.mjs` sends the
captured effective inputs/runtime/time masks through the real HTTP API, helper
and subscriber EX5. It compares raw signal/entry/exit times, direction, prices,
SL/TP, net R, validity, closed state, reason and entry spread. Numeric tolerance
is 1e-10; records and chronology are not reordered to manufacture a match.
The named `TP025` and custom `TP_R0.25000000` label alias is recorded separately;
it does not exempt any price/time/PnL field. This validates the tested preset,
not every saved strategy or live fills.

### Subscriber Chart

The only connection panel controls are read-only greeting, subscription status
and continuously refreshed connection health. Identity is separately signed
and **cannot grant trading authority**. Expired subscribers can receive an
inactive identity certificate, but cannot claim audit/live commands.

History arrows and entry/SL/TP lines use the canonical audit records. Lines are
bounded to 1..20 chart bars and clipped at the next signal/known closure.
All audit records are drawn, including OPEN/DATA; no result is fabricated from
chart appearance. Native coordinate checks cover every record for audits up to
150 rows and evenly spaced samples (at most 64) for larger audits. The latter
is explicitly sampling, not exhaustive visual validation.

Artifacts are overwritten in `tmp/universal_connection_validation`; private
installation/service state remains ignored under `control-service/.state`.

## Production Gates

This local pilot is **not yet a production deployment**. Required before public
release: a real TLS control-service domain and proxy policy, production billing
credentials/webhook tests, protected server key storage/rotation, verified
installer/update signing, restore/recovery tests and independent security review
of the native signature verifier. Local startup cannot grant production access.

The device private key is currently a software key. Agent fencing prevents
ordinary simultaneous use of copied files, but does not prove motherboard/TPM
identity or defeat an administrator copying process secrets or patching EX5.
Hardware-backed non-exportable keys/attestation require a separate installer
implementation. No uncrackable client-side licensing guarantee is claimed.

The current result transport has explicit limits of 10,000 trades and 4 MiB.
Oversized results fail with a visible error, never a truncated winning result.
Chunked export is needed before high-frequency, multi-year public workloads.
The original audit's data-coverage semantics remain unchanged: unavailable data
is not fabricated into a win/loss, and commission/slippage are unknown when the
underlying engine does not supply them.
Sol's existing audit records do not always fill an observed closing price. Those
prices are sent as `null`, never inferred from net R or an OHLC candle. Its known
closure time, reason and canonical audit R are preserved. A report claiming the
`real_ticks` transport policy must instead provide observed closing prices.
