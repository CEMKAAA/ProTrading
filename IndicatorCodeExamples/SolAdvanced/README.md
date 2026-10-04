# Sol Advanced

Canonical source: `LiqNarrativeSol_Advanced.mq5` in this folder. Its quoted
`.mqh` dependencies are local, including `LiqSolAdvancedNas.mqh` and
`TradeCalendarMatrix.mqh`. Compile the `.mq5` entry point, not individual
headers. The old `IndicatorCodeExamples/liq` folder is a legacy family mirror,
not the development source for this EA.

Do not edit `C:\MT5\DEMO\MQL5\Experts` as a source repository. Changes here
must be compiled, validated, and deliberately deployed before affecting MT5.

## Position Controls (2026-10-05)

Open NAS / POSITIONS: LEGACY/INDEPENDENT, MAX total open, MA REV EXIT, and REV WAIT
HH:MM reuse the existing NAS policy and strategy serialization. Apply commits
the current edit values. Legacy blocks a second position in either direction;
Independent caps concurrently OPEN native positions in TOTAL (BUY + SELL),
as in MaCross, not per direction. MAX=10 permits at most ten owned positions,
e.g. six BUY plus four SELL. Existing MAX=0 retains its unlimited meaning;
positive MAX values accept 1 through 1000. Hedging is required for Independent.

MA REV EXIT only considers Liq signals after a position opened. During the
wait the latest signal state wins: opposite closes at expiry, same-direction
cancels the latch; a fresh opposite after expiry closes immediately.
MA REV timing is checked against the actual MaCross `MaKernelExitAt` source.
Reverse wait accepts 00:00 through 99:59; the NAS wait range is unchanged.
No ORB next-day rule is added. Existing Opposite Signal target semantics remain a
mandatory reverse target and reject incompatible policy combinations.
New timed exits are MT5-native; listener protocols were not changed.
The all-default regression scope and tests are recorded in
`../../reports/orb_sol_position_policy_20261005.md`.

## Audit CSV

Open TIME MATRIX and click EXPORT AUDIT CSV after the audit completes.
Feature extraction runs only on this request and never changes the audit's
trades or PnL. Closed-bar and source-state features use each trade's entry-time
cutoff. One accepted trade produces one row, including explicit OPEN/DATA.
MT5 shows the full Common/Files/AuditExports output path when finished.
Source mapping and validation: `../../research/kivanc/README.md`.


## Exact Audit Acceleration (2026-10-03)

See `../../reports/audit_acceleration_20261003.md` for measured first/repeat/changed-target times and exact trade-trace comparisons. Canonical source and required headers remain in this folder. Signal/execution mathematics, strategy format, CSV schema and listeners are unchanged. In Orb-derived families, select the existing ADV engine for quote batching; the legacy path is unchanged. Sol accelerates its current tick replay. Available-history timings do not measure broker-download speed.
