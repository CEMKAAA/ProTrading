# SolAdvanced Screenshot Presets

The 17 additional SEARCH presets below were transcribed from screenshots in
`IndicatorCodeExamples/OptimalSettingsForLiqNarrative`. `Legacy_` means a
dashboard-settings migration from the original Liquidity Narrative EA, not a
claim that SolAdvanced produces the same signals, win rate, or PnL. Existing
SolAdvanced presets remain unchanged.

| Preset | Screenshot (relative to the archive) |
|---|---|
| SolAdvanced_JP225_H2H1_2R | Muhteşem4lü/RealDeals/SolAdvanced.png |
| SolVersion_JP225_H2H1_2R | Muhteşem4lü/RealDeals/SolVersion.png |
| Legacy_JP225_H2M30_2R | jp225OptimalLiqNarrative.png |
| Legacy_JP225_H2H1_2R | Winners/jp225MostOptimal.png |
| Legacy_US500_H2M15_1R | LiqNarrativeSP500.png |
| Legacy_US500_H2M15_2R | LiqNarrativesp500Optima.png |
| Legacy_US500_H2M15_05R_DUP | Winners/US500LIQNarrative.png |
| Legacy_US500_H2M15_2R_DUP_2500 | Muhteşem4lü/US500DupOnHasPotential.png |
| Legacy_US500_H2M15_1R_DUP | Winners/US500_DUP_ON_IS_GOOD.png |
| Legacy_USTEC_H2M15_1R_15000 | LiqNarrativeUstec.png |
| Legacy_USTEC_H2M15_1R_30000 | US100USTEC_OptimalSettings.png |
| Legacy_USTEC_H2M15_1R_DUP | Winners/US100USTEC_DUP_ON_Mode_Is_Solid.png |
| Legacy_USTEC_H2M15_2R_DUP | Muhteşem4lü/USTEC2R.png |
| Legacy_USTEC_H2M30_2R | UstecOptimal.png |
| Legacy_US30_H2M15_1R_DUP | Winners/US30_BEST_SOFAR.png |
| Legacy_EURUSD_H2M30_05R | Invertable_EURUSD_HAS_POTENTIAL.png |
| Legacy_UKOIL_H2H1_1R | Winners/UKOIL_MOST_OPTIMAL.png |

The SolAdvanced JP225 screenshot additionally has RF master ON, RF10 allowed,
and macro TR PEND blocked. The SolVersion screenshot has TR PEND and TR FRESH
blocked. All other new presets use Advanced's inactive RF master, allowed macro
buckets, and blocked RF rules as a safe default.

The preset lookup requires an exact EA family and photographed MT5 symbol
(`JP225m` is distinct from `JP225s`). It changes only the visible dashboard
settings represented in `LiqImagePresets.mqh`; it does not import hidden Inputs,
risk percentage, channel, bridge path, or listener state. Re-audit a migrated
preset on the actual broker feed before considering live use.
