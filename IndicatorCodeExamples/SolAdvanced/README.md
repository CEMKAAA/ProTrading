# Sol Advanced

Canonical source: `LiqNarrativeSol_Advanced.mq5` in this folder. Its quoted
`.mqh` dependencies are local, including `LiqSolAdvancedNas.mqh` and
`TradeCalendarMatrix.mqh`. Compile the `.mq5` entry point, not individual
headers. The old `IndicatorCodeExamples/liq` folder is a legacy family mirror,
not the development source for this EA.

Do not edit `C:\MT5\DEMO\MQL5\Experts` as a source repository. Changes here
must be compiled, validated, and deliberately deployed before affecting MT5.

## Audit CSV

Open TIME MATRIX and click EXPORT AUDIT CSV after the audit completes.
Feature extraction runs only on this request and never changes the audit's
trades or PnL. Closed-bar and source-state features use each trade's entry-time
cutoff. One accepted trade produces one row, including explicit OPEN/DATA.
MT5 shows the full Common/Files/AuditExports output path when finished.
Source mapping and validation: `../../research/kivanc/README.md`.
