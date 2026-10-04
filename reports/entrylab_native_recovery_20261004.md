# EntryLab Native Ownership And Geometry

Build: `EntryEngineLab-1.13-NativeRecovery`. Date: 2026-10-04.

## Evidence And Root Cause

The user's old Independent state belongs to runtime magic
`4000011026004262155`. The new BTCUSDm chart ID in today's terminal log is
`64752800638164`, producing magic `4000011026004638164`. The old counter
matched only the current chart magic. Closed/reopened terminal on the same
preserved chart was already supported; recreating the chart changed its
identity and excluded previous exposure. Position age or the 1.12 visual
update date was not the cause.

Historical geometry used 20 signal-TF bars, not chart bars. Thus M5 signals
displayed on an M1 chart could draw 100 chart bars. Native geometry lacked
a next-entry cutoff, causing overlapping Independent reference segments.

## Scope Of Patch

- `EntryEngineLabEA.mq5`: build, recovered ownership integration, startup
  retry, current chart-TF historical visual cap and stale old EXEC cleanup.
- `MaIndependentEntries.mqh`: bounded orphan-owner recovery using existing
  state identity/files and exclusive locks; combined native count/capacity.
- `LabNativeTradeVisuals.mqh`: sorted native fill-time groups, next-entry
  clipping, 20 chart-bar cap, explicit disabled rays and endpoint fingerprint.
- Matching EX5, README, focused probe and runner.

Only EntryLab is changed. Signal generation, price geometry, simulated
outcomes, risk math, CSV contracts and listeners are not modified.

## Recovery Safeguards

Candidate must have an Independent MAI position comment, matching
account/server/symbol/input-magic family and a valid old state without an
uncertain order reservation. Active chart and exclusive lock checks prevent
stealing another running instance. More than one eligible orphan owner is
ambiguous: no arbitrary adoption and no new entry on that failed check.
New entries keep their current chart magic. Recovery holds the old owner's
state lock for this EA lifetime; current state remains separate. The exact
64-bit previous magic is retained as two 32-bit terminal-global values so
its closed-history visuals survive later reattachment of the same chart.

Original broker stops, fills and tickets are not rewritten. A recovered
position participates in existing instance management and MAX capacity.
If native history/orders or original state are missing, ownership/levels
are not invented. Recovery does not migrate other terminals' state files.
Independent-to-Legacy switches with real exposure remain prohibited.

## Geometry

Each entry/SL/TP reference segment ends at the earlier of the next distinct
owned native fill and 20 current-chart candles. Completed trades retain
readable reference lines regardless of very short holding time. Equal-time
fills remain separate position-ID objects but share a chronological group.
An actual exit X and final net color still reflect broker deals, not the
reference segment's display endpoint. Historical segments use the same
chart-bar cap with their existing signal/lifecycle cutoffs.

## Verification

First focused run: production 0 errors/0 warnings; probe 0 errors/0 warnings;
93 checks, 0 failures. Read-only account probe recovered the old owner and
counted six actual open positions: four previous-chart SELLs plus two current
chart fills. Seventeen positive closed native positions retained correct net
colors and original levels. Counts are account snapshots, not permanent totals.

Tests include exact previous-magic restoration, combined BUY+SELL capacity,
counter rendering, original lock exclusion, saved-owner restoration after old
exposure closes, ambiguous orphan rejection, simultaneous fills, next-entry
trimming and M5-on-M1 20-chart-bar cap. Tests submit no orders or position closes.
The final run additionally checks each restored line's cap and next-entry bound.

One existing worker and fixed small logs/configuration are reused. Only small
native state records are copied to that isolated worker, never terminal/history
trees or live production global variables.

Final production compile: **0 errors, 0 warnings**, 58,552 ms.
Final probe compile: **0 errors, 0 warnings**, 4,350 ms.
Final probe: **142 checks, 0 failures**. At that snapshot, the old owner had
four open SELL positions and the new owner had three open positions; the
native counter rendered **OPEN 7/10**. All 24 restored owned entries passed
the 20-chart-bar and next-distinct-entry endpoint checks. Seventeen native
positions were fully closed and profitable; seven remained open.

Deployment completed after the user closed DEMO. Updated only
`C:\MT5\DEMO\MQL5\Experts\EntryEngineLab` main source/EX5, the two changed
headers and README. All five copied files matched source SHA256; recursive
quoted-include comparison also matched all 59 source/header files. The
terminal was not restarted and the other three EA families were not deployed.

Final EX5 SHA256:
`9408A83129D530B8645A4B16CA2A1475167509D9DD8CA77AF0D26552C1ADC9ED`.
