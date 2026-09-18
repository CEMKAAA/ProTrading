# MA independent native entries

Scope: `macrossover_orb/MaCrossOverOrbEA.mq5`. The default is LEGACY;
signal kernels, ORB production EAs, and listener sources are not changed.

## Controls

Beside the MA pair buttons: LEGACY / INDEPENDENT, MAX SERIES, APPLY.
Inputs also expose InpIndependentEntries (false) and
InpMaxConsecutiveEntries (1; allowed range 1..1000).

With MAX SERIES=3, up to three accepted BUY entries can open in succession.
Further BUY candidates are blocked. An eligible SELL starts a new series.
Closing a position by SL/TP does not restore an allowance. Decreasing the
limit does not close positions; increasing it retains the existing count.
The limit is not a maximum concurrent-position or daily trade count.
Controls are per instance, not part of the existing saved-strategy schema.

## Supported configuration

- MT5 hedging account, native execution enabled, PUB OFF.
- Single-order execution, fixed R-leg TP, ordinary/current-equity risk.
- HCBE/BE, time/dynamic exits, NAS opposite exits, filtered-window exits,
  delayed-entry confirmation, and fixed-reference risk must be OFF.
- Existing entry filters and signal kernels remain upstream of execution.

Unsupported configurations block entries rather than falling back to legacy
close/reverse behavior. Switching between LEGACY and INDEPENDENT requires
no owned exposure, bridge plan or pending lifecycle. Broker SL/TP and account
risk guards still apply. A new opposite signal does not close older positions.
Netting accounts and cTrader/NinjaTrader/Quantower publication are deliberately
not enabled for this mode: the existing lifecycle protocols are single-trade.
The LEGACY mode retains the existing publisher and listener behavior.

## Persistence and failure semantics

The series ledger is scoped by broker server, account, symbol and native magic.
An exclusive lifetime lock prevents a second owner of that same scope. An
atomic replacement snapshot stores direction, consumed allowance and signal
timestamp before any order is submitted. A restart retains the allowance and
deduplication timestamp. The small state file is overwritten, not appended.
Changing chart identity/magic defines a different instance, not a continuation.

Definite order rejections release their reservation. Timeouts, lost connections,
accepted-but-not-confirmed orders and crashes retain it conservatively; this
can reduce later entries, but does not authorize a duplicate order. Corrupt or
unwritable state blocks new entries. Never delete a live instance's ledger to
reset the limit. No unprotected/naked retry or close-all reversal is used.
Unacknowledged order intent also blocks new entries and changing back to LEGACY
after restart. There is deliberately no automatic reset: broker order/deal
reconciliation is required before clearing that safety state. Pending orders
also prevent switching modes. This conservative recovery is not an automatic
order-reconciliation service.

Audit applies the same series cap to eligible simulated entries and does not
force an older independent position closed on a reverse signal. Broker rejects,
margin limits and outage reservations are not reproduced by historical audit.
This is not a portfolio-margin simulator.

## Verification limits

Compile and order-free regression probes cover input parsing, series changes,
restart persistence, exclusive locking, corrupt-state rejection, disabled global
reverse/NAS closes, and Pine signal parity. A real demo hedging-account order,
restart and partial-fill acceptance test remains required before production.

2026-09-18 verification: main EA and three probes compiled with zero errors
and warnings. 12,483 kernel checks and 89 integration checks passed; independent
Pine reference comparison: 84,000 comparisons, zero mismatches. Real-data legacy
history fixture: 59 source events, 59 audited trades, zero invalid outcomes.
These are order-free tests, not live trading certification. 35 MA DEMO files
were copied with backup and SHA-256 verification; no running chart was restarted.

## Early audit pruning (2026-09-18)

Exhausted same-direction candidates now return before historical entry resolution
and lifecycle replay. Single-mode occupied candidates also return before replay.
Raw streams remain available for causal direction/reversal detection; provisional
grey PREP and live-observation markers are no longer created. Only audited trade
outcomes are drawn. Skipped candidates no longer contribute hypothetical outcome
calculations to the diagnostic panels either.

94 integration checks passed, including zero replay/memo calls for exhausted and
occupied candidates and reversal after 8 entries with a limit of 12. Kernel and
Pine reference checks still passed (12,483 / 84,000). No full-window speedup factor
is claimed. Updated binary and sources match all 35 DEMO files by SHA-256.
