# Mega Kampanya Kapanis Raporu

- 188/188 strategies accounted for; nine windows per strategy.
- 172 strategies have valid results in all nine windows.
- 1616 native campaign/dashboard-verified windows; 76 confirmed unavailable windows.
- Zero remaining integrity errors or unconfirmed windows.
- Native MQL5 reader: 3384 checks, zero failures, 1616 CURRENT and 1616 MEGA results.
- Four production builds: zero errors / zero warnings. DEMO release: 185 file hashes verified; 28 updated.
- Strategy settings, admission rules, audit mathematics, W/L/O, R and MC were not changed by this repair.

## Repairs

1. PowerShell ConvertTo-Csv used the first row schema and dropped newly added unavailable_parity_verified columns. The writer now serializes the union of all row properties. Both row-order permutations and quoted/multiline values were tested.
2. Fifteen missing proof flags were recovered only after comparing the captured campaign and dashboard executions with the existing strict native verifier. No unavailable outcome was changed to a win/loss or a ready metric.
3. Three CURRENT files had been overwritten by the old DEMO binary using SW_METRICS_1 and the prior settings key. Original files were backed up and proven SW_METRICS_2 results republished. The four updated DEMO binaries now match the campaign sources.

## Data Limits

- EntryLab M1 HISTORY_UNAVAILABLE rows include the broker first-quote timestamp. Available bars do not imply available historical bid/ask ticks.
- Additional native diagnostic: ORB 0.33InvUltimateSetup, JP225m M5, 52W produced one INVERSE_TICKS_REQUIRED and 101 POSITION_CAP_DATA records. The first unresolved inverse trade prevents proving later Legacy admissions. Treating later trades as independent or inventing the first exit would alter the saved strategy.
- Other DATA_INCOMPLETE rows retain their native status; no unobserved exact exit price was fabricated. Matching native failures prove unavailability for this run, not that a data provider can never supply the history later.

## Incomplete Strategies

| EA | Strategy | Symbol / TF minutes | Available windows (weeks) | Unavailable windows (weeks) | Status |
|---|---|---|---|---|---|
| orb | 0.33InvUltimateSetup | JP225m / 5 | 2, 5, 10, 20 | 52, 104, 156, 208, 260 | DATA_INCOMPLETE |
| macross | solfirst | SOLUSDm / 5 | 2, 5, 10, 20, 52, 104, 156, 208 | 260 | HISTORY_UNAVAILABLE |
| macross | 0.50RInversedBTCUSDStrategy | BTCUSDm / 5 | 2, 5, 10, 20 | 52, 104, 156, 208, 260 | DATA_INCOMPLETE |
| macross | usdjpyInverse1R | USDJPYm / 1 | 2, 5, 10, 20 | 52, 104, 156, 208, 260 | DATA_INCOMPLETE |
| entrylab | fastema0.01 | JP225m / 1 | 2, 5, 10, 20 | 52, 104, 156, 208, 260 | HISTORY_UNAVAILABLE |
| entrylab | BollingerBandsMeanReversionScalper0.15Rscalper | BTCUSDm / 1 | 2, 5, 10, 20 | 52, 104, 156, 208, 260 | HISTORY_UNAVAILABLE |
| entrylab | BollingerBandsMeanReversionScalper0.15RscalperVeryFrequent | BTCUSDm / 1 | 2, 5, 10, 20 | 52, 104, 156, 208, 260 | HISTORY_UNAVAILABLE |
| entrylab | BollingerBandsMeanReversionScalper0.15RscalperIndependent | BTCUSDm / 1 | 2, 5, 10, 20 | 52, 104, 156, 208, 260 | HISTORY_UNAVAILABLE |
| entrylab | FastEmaRsi0.01RIndependent | BTCUSDm / 1 | 2, 5, 10, 20 | 52, 104, 156, 208, 260 | HISTORY_UNAVAILABLE |
| entrylab | gbpusdfastemaRsi0.02R | GBPUSDm / 1 | 2, 5, 10, 20 | 52, 104, 156, 208, 260 | HISTORY_UNAVAILABLE |
| entrylab | gbpusdfastemaRsi0.02RDay | GBPUSDm / 1 | 2, 5, 10, 20 | 52, 104, 156, 208, 260 | HISTORY_UNAVAILABLE |
| entrylab | usdjpyUltraFastMachine | USDJPYm / 1 | 2, 5, 10, 20 | 52, 104, 156, 208, 260 | HISTORY_UNAVAILABLE |
| entrylab | usdjpyDailyBollinger | USDJPYm / 5 | 2, 5, 10, 20 | 52, 104, 156, 208, 260 | HISTORY_UNAVAILABLE |
| orb | jp2250.5RUltimateSetup | JP225m / 15 | 2, 5, 10, 20 | 52, 104, 156, 208, 260 | DATA_INCOMPLETE |
| orb | HolyGrail [USDJPY] | USDJPYm / 5 | 2, 5, 10, 20 | 52, 104, 156, 208, 260 | DATA_INCOMPLETE |
| orb | DISPONUsefullFirstTimeUstecOrb0.5R | USTECm / 15 | 2, 5, 10, 20 | 52, 104, 156, 208, 260 | DATA_INCOMPLETE |

## Binding And Preservation

- CURRENT is published in the original per-EA Common/Files WindowMetrics folders under the original native strategy IDs and settings keys.
- MEGA is frozen at Common/Files/StrategyWindowArchive/20261009. The prior 20261008 archive was not altered.
- Full campaign CSVs and proof metadata are retained separately in mega-baseline/; its seal records every result CSV hash. Automatic rolling work uses the mutable results/ folder, never mega-baseline/.
- Detailed missing-window list: unavailable-windows.csv.

## DEMO Binaries

- `C:\MT5\DEMO\MQL5\Experts\EntryEngineLab\EntryEngineLabEA.ex5`
- `C:\MT5\DEMO\MQL5\Experts\MaCrossOverOrb\MaCrossOverOrbEA.ex5`
- `C:\MT5\DEMO\MQL5\Experts\orb\OrbUltimateEA_StrategyLibrary.ex5`
- `C:\MT5\DEMO\MQL5\Experts\SolAdvanced\LiqNarrativeSol_Advanced.ex5`

## Verification

- 27 Node regression tests; 5 metric-writer cases; 10 report-path cases; 2 heterogeneous-CSV row orders.
- Two additional native diagnostic scripts compiled without errors/warnings. No research script placed a live order.

## Automatic CURRENT Refresh

- Installed and enabled: ProTradingSystem-StrategyWindowRefresh. Runs at user logon and currently active.
- Native paired audits publish only valid CURRENT window metrics. The separate sealed MEGA CSV and .swm snapshots are not refresh destinations.
