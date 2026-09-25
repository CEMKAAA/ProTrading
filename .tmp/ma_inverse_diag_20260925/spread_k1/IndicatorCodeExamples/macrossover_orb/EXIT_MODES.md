# MaCrossover Exit Policies

## Controls

- `MA REV EXIT ON/OFF`: reverse-MaCross exit. Older LEGACY presets default ON / 00:00; older INDEPENDENT presets default OFF / 00:00.
- `WAIT HH:MM` and `APPLY EXIT`: minimum position age, e.g. `04:00` is four hours after entry, not a clock time.
- These controls are below `INDEPENDENT / MAX SERIES`.
- `OPP EXIT` and `ADD EXIT` still use NAS signals and their separate `EXIT WAIT` / `APPLY NAS` controls.

The selected MA kernel's closed opposite-direction signals drive MA REV EXIT.
This is a signal-based exit, not a requirement that a second order actually be
opened. In LEGACY, only filter-accepted signals drive the exit, preserving the
old accepted-reverse behavior. In INDEPENDENT, explicitly enabling this optional
exit uses the kernel signal without entry filters, as in the previous patch.
Inversion is applied to the MA direction. NAS directions are compared to the
actual position direction.

Only signals available strictly after entry are eligible. During grace the
latest eligible signal determines direction. If it is opposite at expiry,
close then; otherwise wait for the first subsequent opposite signal. A later
same-side signal cancels the opposite state while still inside grace. No
requirement exists to wait for the next calendar day.

## Modes and Ownership

LEGACY ON / 00:00 uses the original accepted-reverse close/re-entry path. OFF
disables it; a nonzero wait uses the delayed position manager instead. Merely
changing the calendar date does not close a position. Explicitly configured
TIME, broker-time or EOD exit modes remain separate user-selected policies.

In MaCross, NAS OPP and ADD both monitor the full position lifetime: there is no
ORB session cutoff. They remain mutually exclusive aliases for the same NAS
exit policy here. This does not change either mode in the actual ORB EA.

INDEPENDENT evaluates every owned native ticket separately using its own
entry time and direction. Its existing native-only, hedging-account and
fixed-TP constraints remain. LEGACY's single bridge plan uses the existing
scoped close-only publisher. This patch does not enable multi-position
listener support or alter bridge channels/protocols.

Close intents are persisted before requests; failures are retried, with a
five-second backoff while pending. Position closes require the existing
symbol/magic ownership check, and target the individual ticket. Pending close
intents survive restart and are not revoked by switching the filter off.

Enabling these controls for an already open position evaluates signals since
that position's entry. Consequently an existing position may close immediately
if the newly selected rule was already satisfied. Configure on a flat/demo
instance when this is not desired.

## Audit and Saved Strategies

Historical exits use the same grace/state rule and existing forced-exit replay
at the exit timestamp, not a fabricated full target or stop R. A stop/target
reached before the forced exit still takes precedence in the replay engine.
Reverse-exit settings enter memo keys, metric identity and saved strategy
metadata (`MAEXIT2`). Records without exit metadata inherit ON for LEGACY and
OFF for INDEPENDENT, both with zero wait. Explicit metadata is respected. Files
are not rewritten. Missing mode metadata is not guessed from strategy names.
Old metrics are invalidated by a policy version.

Live MA and NAS caches are separate from the historical audit cache and refresh
on new bars/settings changes. The signal generation kernels are unchanged.

## Verification Scope

`scripts/validate_ma_exit_policy.ps1 -RunProbes` compiles the EA and runs isolated,
order-free tests for boundaries, inversion, independent ages, NAS wait logic,
save/restore and 1,000 timelines against a separate second-by-second oracle.
The existing Pine signal regression also runs. These tests do not certify broker
order fills or live listener delivery; no real positions are opened/closed by
the probes. The broader tick-audit correctness campaign remains separate work.
