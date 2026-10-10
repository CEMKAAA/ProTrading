# Approved Device Connection Timeout

Date: 2026-10-10

## Cause

The reported BAT state combined an approved device with a network timeout.
Read-only database inspection confirmed approval and browser controller
activation, completed identity sequence writes, but no agent session or uploaded
terminal status for the new installation. This was not an expired pairing code.

The project's database DNS address matches AWS's published IPv6 range for
`ap-southeast-1` (Singapore). Default function invocations from this location
were executed in `eu-central-1` (Frankfurt). Sequential SQL round trips across
regions extended device identity requests close to the existing 10-second
helper timeout, preventing the subsequent connect/heartbeat handshake.

A controlled session comparison using the same existing isolated QA account:

- Explicit Singapore invocation: login 1,604 ms; session 672 ms.
- Automatic Frankfurt invocation: session 6,364 ms.
- Singapore repeat: session 670 ms; logout 780 ms.

## Fix

Changed only the Edge entrypoint runtime and tests:

- `web-mvp/supabase/functions/stratum-control/index.mjs`: after local path,
  origin and preflight checks, forward off-region requests to the same API
  endpoint with `x-region: ap-southeast-1`. The database-region handler runs the
  existing canonical authentication and transaction policy. A streamed Request
  clone preserves the method, body, browser credential and signed device proof.
  Forwarding cannot follow redirects, has a bounded timeout and preserves an
  upstream failure status rather than fabricating success.
- `web-mvp/scripts/test-cloud-entrypoint.mjs`: preservation, no routing loop,
  local CORS/path validation and fail-closed network regression tests.
- `web-mvp/scripts/test-cloud-device-latency.mjs`: use the real DeviceClient
  with its unchanged 10-second timeout and exercise six complete standby cycles.

No native EA, binary, helper artifact, pairing ID, user grant, strategy or audit
engine changed. The browser controller, agent lease, proof freshness and native
command expiration durations were not extended. The existing account lock was
not removed. Existing downloaded ZIPs remain compatible.

## Verification

- Supabase `stratum-control` version 8 deployed ACTIVE.
- 93 automated tests passed, zero failures.
- Existing QA account login, signed ZIP, owner-bound enrollment, review,
  approval and controller activation succeeded.
- Real DeviceClient: 31/31 device calls successful, longest 1,179 ms.
- Identity, connect, heartbeat, status, claim and standby command paths passed
  across six cycles with two-second waits. Trading stayed OFF.
- The isolated QA installation was revoked and QA session logged out afterward.
- Concurrent browser reads: 9/9 HTTP 200; mean 837 ms, maximum 1,150 ms.

Evidence: `device-latency.json`, `tests.log`, and
`../cloud_session_20261010/regional.json`.

Deployment bundle digest:
`62dde44470552b2e8a4ae9327c93a143787d6f772bd976465adff0fea24ade77`.

## User Recovery

Restart the same extracted `start_connection.bat`. Do not create a new pairing
or installation. In Studio select this approved device and authorize the
current browser again: the earlier 90-second controller lease may have expired
during the failed connection. Keep BAT and the EA open.

## Limitations

The other computer is not remotely accessible here. This verifies the public
service and actual helper transport, not that computer's MT5 installation or
native chart. Regional routing is intentionally tied to the current project's
database location; update it if the database is migrated. A regional/internet
outage can still fail explicitly; this fix does not promise universal uptime.
