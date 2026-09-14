# History Audit Window Reuse

## Contract

Reuse valid completed work when the requested history window is narrower and
the effective replay inputs match. Keep the original replay as the fallback.
Do not freeze OPEN/DATA, substitute one quote/fill policy for another, or reuse
an old close after the reverse-signal/hold/geometry settings changed.

## Implemented Scope

- Liq normal, invert, Sol, Advanced and the three corresponding channel source
  variants: window buttons request `RefreshAfterConfigChange(false)`. Existing
  wider raw-signal caches are sliced rather than rebuilt. Actual settings still
  take the existing invalidation route.
- Liq Advanced and Advanced Channel: closed-result cache restores direction,
  entry, SL, TP, HC level, exit time and exit reason, not just aggregate R.
- ORB main and StrategyLibrary: valid closed full `HistResult` objects are
  memoized with exact geometry, fill/cost settings and forced exit identity.
  Completed daily PREP snapshots and their window/accepted/reference signal
  streams are reusable. The original preparation and replay math is preserved.
- NAS StrategyLibrary: strict replay caches complete exit price/time/reason,
  gross R and excursion bounds. It is shared by dashboard and CSV replay.
  Aggregate statistics and commission are recalculated for the selected window.

## Important Limits

This is not a promise of zero-time 5Y rendering on every chart. Drawing objects,
classifying signals, evaluating models, data synchronization and open trades
still cost time. NAS raw signal calculation is not replaced with a different
warm-up origin just to reuse a wider window: that could change signal math.

The original standalone NAS audit still uses its existing cache and switches
tick/M1 replay policy at 20W. It has not been relabeled as the strict library
engine. The older `OrbUltimateEA_Channel.mq5` is a structurally different source
and has not received the new ORB memo wrapper. Main ORB's existing channel
support and listener protocol are unchanged.

ORB/NAS memo indices are instance-local RAM, capped at 65,536 entries with full
key comparison after hashing. They conservatively expire on a new M1 bar,
history extension/synchronization or reinitialization. They are not persistent
cross-restart dataset caches. A broker correction that changes neither history
metadata nor the current M1 epoch requires a fresh audit/reinitialization.

## Verification

- `tests/test_audit_window_reuse.py` checks original replay and PREP bodies,
  complete trace restoration, bounded/collision-safe indexing, window keys,
  forced-exit keys and absence of order/file publication in the memo index.
- `scripts/validate_audit_window_reuse.ps1` compiles 11 source entry points.
  Transient MetaEditor EX5 write failures get at most three attempts; compile
  errors are not ignored, and failed-attempt logs remain available.
- `scripts/validate_nas_library.ps1` runs an emirsiz/no-order MQL probe: 12 exit
  scenarios, 19 preset parsing checks and 20,000 memo insert/lookup checks.
- `scripts/validate_nas_window_reuse.ps1` compares full NAS dashboard rows and
  closed-exit return sequences across 260,52,20,10,5,2,260 weeks, warm vs cold.
- `scripts/validate_orb_window_reuse.ps1` compares ORB complete per-trade traces,
  W/L/Open/DATA, net R, cumulative minimum, DD, macro and RF statistics.

NAS measured after data stabilization: 0.39-1.00 seconds per window in the
recorded run. All seven warm/cold comparisons matched. This does not include
the initial broker history download; initial cold data hydration previously
took about 28.5 seconds and changed the count of resolvable labels. Such DATA
exclusions are not wins/losses and must not be mistaken for stable full coverage.

No active production EA or listener was restarted by these tests. Do not infer
production deployment merely from successful workspace compilation.
