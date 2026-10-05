# ORB Strategy Library

Canonical source: `OrbUltimateEA_StrategyLibrary.mq5` in this folder.
Its quoted include dependencies are local. Edit and compile this file here,
not an archived root copy. The older `OrbUltimateEA.mq5` and channel variants
in this folder are separate legacy entry points, not aliases of the strategy
library EA.

The current time-matrix module is the local `TradeCalendarMatrix.mqh`.
After shared calendar changes, keep the three family copies and the standalone
probe copy at the source root byte-identical. Run
`scripts/validate_time_matrix.ps1 -RunProbe` before any DEMO deployment.

Do not edit MT5's Experts folder as the source repository. Deployment is a
separate, deliberate action after compile and verification.

## Position Controls (2026-10-05)

The right panel now has LEGACY/INDEPENDENT, MAX OPEN, an OPEN total/MAX counter,
NEXT DAY EXIT, MA REV EXIT, WAIT HH:MM, and APPLY EXIT.
Legacy allows one active lifecycle. Independent caps concurrently OPEN
positions in TOTAL (BUY + SELL), not consecutive setups or separate direction
caps. MAX=10 permits at most ten owned positions, e.g. six BUY plus four SELL.
Research mode can be selected with native trading disabled.
Live Independent requires NAT ON, PUB OFF, a hedging account, and SINGLE
execution. Partial-three-leg Independent is not supported: audit reports
DATA instead of pretending an aggregate trade is one native position.

Defaults remain Legacy, NEXT DAY EXIT ON, MA REV EXIT OFF, maximum 10 and
00:00 wait. General MA REV EXIT takes precedence over the special next-day
rule and applies its wait to reverse signals on any later date. To disable
all ORB reverse exits, turn both controls OFF. Only post-entry signals qualify;
the latest direction during the grace period decides whether to close at
expiry. Otherwise the next opposite signal closes the trade.
The MA REV timing is checked against the actual MaCross `MaKernelExitAt`
implementation; reverse duration accepts 00:00 through 99:59 like MaCross.
MAX accepts 1 through 1000. Independent metric keys invalidate the old,
incorrect per-direction capacity results without changing strategy records.

Saved user strategies include all these values. Older records and built-in
presets reset to defaults and do not inherit a previously selected policy.
The existing signal generator, geometry, CSV and listener protocols remain
unchanged. New timed reverse audit exits require tick data, not OHLC-derived
exact PnL. Native Independent manages each ticket through the existing manager.
Existing legacy bridge close capability is reused, not extended to multi-ticket
listeners. See `../../reports/orb_sol_position_policy_20261005.md`.

## Dashboard Layout

The right panel separates ML training, native position controls, margin,
balance and strategy save/timezone controls. It scales against a 780-pixel
logical height; ML controls repaint on resize, and TIME MATRIX / entry-direction
launchers follow the same canvas transform.
Verification: `../../reports/sol_apply_orb_layout_20261005.md`.

## Audit CSV

Open TIME MATRIX and click EXPORT AUDIT CSV after the audit completes.
Feature extraction runs only on this request, using data available at each
trade entry; normal audit does not compute the CSV feature set. Each accepted
trade contributes one row, including OPEN/DATA records with explicit status.
The full output path is shown by MT5 under Common/Files/AuditExports.
Source mapping, timing rules and test scope: `../../research/kivanc/README.md`.


## Exact Audit Acceleration (2026-10-03)

See `../../reports/audit_acceleration_20261003.md` for measured first/repeat/changed-target times and exact trade-trace comparisons. Canonical source and required headers remain in this folder. Signal/execution mathematics, strategy format, CSV schema and listeners are unchanged. In Orb-derived families, select the existing ADV engine for quote batching; the legacy path is unchanged. Sol accelerates its current tick replay. Available-history timings do not measure broker-download speed.
