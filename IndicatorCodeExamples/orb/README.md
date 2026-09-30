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

## Audit CSV

Open TIME MATRIX and click EXPORT AUDIT CSV after the audit completes.
Feature extraction runs only on this request, using data available at each
trade entry; normal audit does not compute the CSV feature set. Each accepted
trade contributes one row, including OPEN/DATA records with explicit status.
The full output path is shown by MT5 under Common/Files/AuditExports.
Source mapping, timing rules and test scope: `../../research/kivanc/README.md`.
