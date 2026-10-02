# Minimum Lot SL Cash Loss And Percentage-Risk Reference

## Scope

All four main EAs use their existing applied native pip SL geometry and
SYMBOL_VOLUME_MIN to calculate the cash loss through OrderCalcProfit.
No signal, audit, risk sizing, order placement or publisher code is changed.

- Orb: `IndicatorCodeExamples/orb/OrbUltimateEA_StrategyLibrary.mq5`
- MaCross: `IndicatorCodeExamples/macrossover_orb/MaCrossOverOrbEA.mq5`
- EntryLab: `IndicatorCodeExamples/entry_engine_lab/EntryEngineLabEA.mq5`
- SolAdvanced: `IndicatorCodeExamples/SolAdvanced/LiqNarrativeSol_Advanced.mq5`
- Shared calculations: `IndicatorCodeExamples/NativeMarginQuote.mqh`
- Orb/MaCross/EntryLab display: `IndicatorCodeExamples/NativeMarginPreview.mqh`
- Sol display: `IndicatorCodeExamples/SolAdvanced/LiqStrategyLibrary.mqh`
- Orb ML positioning: `IndicatorCodeExamples/orb/OrbStrategyMLPipeline.mqh`

## Meaning

MIN LOT SL KAYBI is the minimum volume's cash price loss at the applied SL,
using BUY ask / SELL bid for entry. It is not margin. Commission, swap and
slippage are not included. Broker minimum stop-distance rules still apply.

RISK BAKIYESI is loss / (applied percent / 100), rounded upwards to cents.
For example, a 0.60 loss at 1% requires 60 of reference capital. This does not
promise order acceptance or recommend a safe deposit: free margin, costs,
portfolio exposure and stop-out cushion must be considered separately.
Orb MONEY mode displays N/A for the percentage-based reference capital.

MIN LOT margin remains separate and available even without pip mode. Cash
SL/reference values are N/A if applied geometry or live broker quotes are
unavailable. Draft edits do not affect the displayed applied values.

## Layout

Orb/MaCross/EntryLab: right STRATEGIES column, above BALANCE. The margin
section moves up 40 pixels to accommodate the two extra readable rows.
SolAdvanced: right strategy panel, below BALANCE. The panel and strategy save
controls extend by another 40 pixels; popup cleanup includes both new rows.
Orb's complete ML section moves into the previously unused right-panel space
above the margin rows; its audit-progress label sits above the ML section.

## Account Units And Cent Accounts

Balance/percentage risk calculations use native account units and broker
symbol tick values. Profit/margin estimates use the broker APIs. There is
no USD-only or cent-account rejection added by this feature. On a USC account,
30 USD is 3000 USC: manual BALANCE values must use the account's unit, not
whole dollars. Cent lots may also have a different contract size; no standard
lot contract is assumed in the new minimum-SL calculation.

Real cent-account order execution has not been tested in this release.
Existing risk/margin guards are not bypassed. Exness Standard Cent's supported
instrument list does not include JP225; instrument availability is a broker
constraint, not an EA currency rejection.
Reference: https://get.exness.help/hc/en-us/articles/17537782786588-Standard-Cent-account

## Verification

Validator: `scripts/validate_native_balance.ps1`, with real broker APIs and
a test-only 1600x900 viewport fixture. The isolated worker sends no orders.
Checks cover broker minimum lot, exact cash API comparison, tenfold SL
reduction, risk-reference math, upwards rounding, unavailable input handling,
UI refresh, layout, unapplied edits and existing balance/default/bridge parity.

Stage: `.tmp/native_balance_20261002_222144`.
Four production and four full-EA probe logs are retained. Symbol-suffixed
reports distinguish USDJPYm and JP225m runs. A diagnostic script also records
JP225 minimum-lot loss 6.61 USD at 348 price units and 0.66 USD at 34.8 units.
OrderCalcProfit rounds cash amounts: the proportionality test uses the
account-currency rounding bound (5.5 cash steps for a tenfold comparison),
not an assumed exact floating-point ratio. Display uses the actual API amount.

Deployment: `scripts/deploy_native_balance.ps1`, after clean compile and
four-family verification. Existing files are backed up and copies checked
with SHA256. Only the two known prior shared margin headers may be replaced
when their destination hashes match the previous verified release.

Final result: four production EAs and all full-EA probes compile with
0 errors and 0 warnings. Per symbol: Orb 69/0, MaCross 67/0, EntryLab 67/0,
SolAdvanced 61/0 (checks/failed); 528 passed across USDJPYm and JP225m.
All four screenshot layouts were inspected; complete Orb ML/job controls
and audit-progress text do not overlap the new minimum-SL panel.

Published to DEMO on 2026-10-02: four families, 173 files, SHA256 verified.
Backup: `.tmp/native_balance_deploy_backup_20261002_233134`.
