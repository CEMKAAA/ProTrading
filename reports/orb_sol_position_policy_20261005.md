# ORB / SolAdvanced Position Policy

## Scope

Canonical sources only: `IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5`
and `IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5`.
MaCross, EntryLab, channel variants and listeners are not modified.
No replacement signal engine, audit engine, CSV schema or bridge protocol.

## Behavior

- ORB right panel: Legacy/Independent, MAX OPEN, OPEN total/MAX counter,
  NEXT DAY EXIT ON/OFF, MA REV EXIT ON/OFF, WAIT HH:MM, APPLY EXIT.
- SolAdvanced NAS / POSITIONS: existing mode/cap fields and reverse control
  now labelled MA REV EXIT. Reuses its existing policy/strategy format.
- Legacy is one active position/lifecycle across both directions.
- Independent caps simultaneous OPEN native positions in TOTAL (BUY + SELL),
  matching MaCross. MAX=10 allows six BUY plus four SELL, not ten of each.
  Completing a position releases its slot, including an exit at the next
  signal timestamp. Direction changes never reset the count.
  Sol inversion capacity now follows the selected mode's actual audit exits,
  not a second uninverted simulation's exit calendar.
- Reverse events must occur strictly after entry. During grace the latest
  direction decides whether to close at expiry; same-side cancels an earlier
  opposite. New opposite events after grace can close immediately.
  Timing is compared against `MaKernelExitAt` extracted directly from the
  existing MaCross source, with identifiers changed only. Reverse duration
  supports 00:00 through 99:59 and positive MAX supports 1 through 1000,
  like MaCross. Sol's existing MAX=0 unlimited setting is retained.
- ORB defaults: Legacy, Next Day ON, general reverse OFF, MAX 10, wait 00:00.
  General reverse takes precedence over Next Day and never bypasses its wait.
  Both OFF disables ORB reverse exits; SL/TP and other enabled exits remain.
- Sol has no next-day special behavior. Its existing Opposite Signal target
  is intrinsically reverse-driven and rejects incompatible policy settings.
- User strategy records preserve the new ORB policy in optional POS1 metadata.
  Old records/built-ins restore defaults, not previously selected values.
- ORB Independent runs the existing native manager per ticket, preserving its
  trailing/half/time state in the existing professional position plan.
  Fixed-reference post-fill risk verification is scoped to the new ticket.

## Files Changed

- `IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5`
- `IndicatorCodeExamples/orb/OrbPositionPolicy.mqh` (new)
- `IndicatorCodeExamples/orb/OrbPositionRuntime.mqh` (new)
- `IndicatorCodeExamples/orb/OrbUltimate_ProfessionalPipeline.mqh`
- `IndicatorCodeExamples/orb/OrbStrategyUserLibrary.mqh`
- `IndicatorCodeExamples/orb/OrbStrategyUserMetrics.mqh`
- `IndicatorCodeExamples/orb/OrbStrategyMLConfig.mqh`
- `IndicatorCodeExamples/orb/README.md`
- `IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5`
- `IndicatorCodeExamples/SolAdvanced/LiqSolAdvancedNas.mqh`
- `IndicatorCodeExamples/SolAdvanced/AuditTradeCsvAdapter.mqh`
- `IndicatorCodeExamples/SolAdvanced/README.md`
- `scripts/validate_orb_sol_position_policy.ps1`
- `scripts/deploy_orb_sol_position_policy.ps1`
- `tests/mql5/orbPositionPolicyProbe.mq5`
- `tests/mql5/SolAdvancedPositionPolicyProbe.mq5`
- `tests/mql5/orbPositionReplayProbe.mq5`
- `tests/mql5/SolAdvancedPositionReplayProbe.mq5`

Compiled `.ex5` files in the two canonical folders are updated only after
verification. Other EA binaries are not rebuilt or deployed by this task.

## Verification

The TOTAL capacity correction passed 49,195/49,195 ORB checks and
24,606/24,606 SolAdvanced checks (73,801 total, zero failures). Both main EAs
and all four probes compiled with 0 errors and 0 warnings. Direct MaCross
reverse-reference and mixed-direction capacity checks are included.
The final baseline/candidate replay passed for both EAs with the results
listed below. ORB full trace SHA256:
`80eec1ff55a3c6827374776254583db680c138cbb8cc0d1d628176744ed5f408`.
Sol full trace SHA256:
`1cf7dffd3d031728bcf4ffa3701b4092457219b078b4c665342b64febf1866d1`.

Deployment completed to `C:\MT5\DEMO\MQL5\Experts\orb` (47 files) and
`C:\MT5\DEMO\MQL5\Experts\SolAdvanced` (23 files). Every deployed file
matched its verified SHA256. Canonical workspace EX5 binaries are updated.
No root-level duplicate EA, channel variant or listener was overwritten.

Commands:

```powershell
& scripts/validate_orb_sol_position_policy.ps1 -RunProbes -RunReplay -CandidateOnly
& scripts/deploy_orb_sol_position_policy.ps1
```

Tests run as scripts with Experts disabled, without calling EA OnInit/OnTick
and without sending orders or publishing signals. One fixed, small staging
directory is reused: `tmp/position_policy_20261004`.

Behavior probes cover defaults, strict policy round-trip, HH:MM validation,
post-entry causality, latest grace-period state, delayed/fresh reverse exits,
total concurrent caps, mixed-direction slot release, legacy single-position protection,
uncertain capacity remaining DATA, next-day toggle, combined historical/live
grace state, Apply reading current edits, runtime restore, user strategy apply,
no inheritance from a previous strategy, and edit-field rendering.

Baseline/candidate replay freezes the audit date at 2026-10-02 22:00 on JP225m
M5 for two weeks. The first complete comparison produced:

| EA | Trades | W | L | O | DATA | Net R |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| ORB baseline/candidate | 10 | 6 | 4 | 0 | 0 | -1.00000000 |
| SolAdvanced baseline/candidate | 6 | 5 | 0 | 1 | 0 | +8.30550000 |

Complete trade traces matched, not only totals: signal/entry/exit timestamps,
direction, entry/SL/TP geometry, outcomes and per-trade net R. A subsequent
run hit an Exness disconnect and was rejected rather than treated as parity
evidence. Final build evidence is `verification.json` plus probe outputs;
deployment evidence is `deployment.json` with SHA256 checks against those
verified exact source/include/binary files. Deployment aborts if sources
changed after verification or the DEMO terminal is running.

This bounded replay is not proof that every existing strategy/market and live
broker execution has been tested. No funded or demo market orders are opened
by the probes. Policy serialization/application tests are not a complete
interactive strategy-save UI campaign.

### TOTAL Capacity Correction

The earlier per-direction implementation was wrong and is superseded.
`maxSameOpen` remains an internal stored field name only, to preserve strategy
and runtime formats; its meaning is total owned OPEN BUY + SELL positions.
Native counting, audit counting, labels, counters and CSV exclusion of
capacity-rejected entries all use the total limit. ORB independent cached
metrics/model contracts are versioned to avoid reuse of old directional
capacity results. Default keys and old strategy defaults remain unchanged.

The reference fixture is generated from the current MaCross functions by
`validate_orb_sol_position_policy.ps1`; it is not a rewritten approximation.
Each EA checks 24,576 combinations of event direction sequences, inversion,
BUY/SELL positions, opening timestamps, waits and query cutoffs against the
actual MaCross reverse function. ORB additionally checks the same 24,576
cases with events split across its live and history streams. Cases include
pre-entry/equal-entry events, equal-deadline events, cancellation of a waiting
reverse by a newer same-side signal, deadline close without a new event and
a fresh reverse after the deadline. Signal-generation mathematics remain
engine-specific; these comparisons establish timing-policy parity, not
identical ORB/Liq/MaCross setups or live broker fill guarantees.

The correction also tests total MAX=1, a mixed six-BUY/four-SELL MAX=10,
slot release at the exact exit timestamp, capacity-rejected entries not
occupying slots, inverse-mode occupancy, uncertain exits remaining DATA,
strategy round-trip, Apply fields and the updated UI label.

## Limits

- Live ORB Independent requires NAT ON, PUB OFF, hedging and SINGLE execution.
  Current bridge listeners are not asserted to track independent tickets.
  Independent partial-three-leg audit reports DATA because aggregate replay
  does not expose exact per-leg open-position release times.
- Sol new timed NAS/Liq reverse exits are native MT5 only. The existing
  listener close capability for its mandatory opposite-signal target is not
  redesigned. ORB Legacy reuses its existing close-only publication capability.
- New general ORB reverse exits require tick coverage; uncertain early-exit
  PnL is DATA, not a fabricated OHLC win/loss. Legacy fallback semantics are
  unchanged when the new general reverse is OFF.
- Historical Legacy occupancy protection can suppress an overlapping setup
  that the older daily audit counted despite an earlier unresolved position.
  Default parity reported above applies to the tested dataset, not every
  possible overlap/missing-data scenario.
