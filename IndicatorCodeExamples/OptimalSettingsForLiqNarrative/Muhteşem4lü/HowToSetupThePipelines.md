# Universal cTrader Pipeline Setup

All bridge files are under:

```text
C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files
```

## The Two Inputs You Normally Set

For every cTrader listener instance:

```text
Bridge Latest Path = the generic path for that EA family
Source TF Filter   = the publisher timeframe in minutes
Prefer Scoped Latest = true
```

Use one listener instance for each `EA family + cTrader symbol + source TF` combination. Do not point two different EA families at the same generic bridge path.

## Generic Paths

| MT5 publisher | cTrader listener | Bridge Latest Path |
|---|---|---|
| Normal Liq Narrative | `LiquidityNarrative_cTrader_Listener.cs` | `C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\LiquidityNarrativeBridge_Latest.csv` |
| Liq Narrative SolVersion | `LiquidityNarrative_cTrader_Listener.cs` | `C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\LiqNarrativeSolBridge_Latest.csv` |
| Liq Narrative Sol Advanced | `LiqNarrativeSolAdvanced_cTrader_Listener.cs` | `C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\LiqNarrativeSolAdvancedBridge_Latest.csv` |
| ORB Ultimate | `OrbUltimate_cTrader_Listener.cs` | `C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\OrbUltimateBridge_Latest.csv` |
| NAS Professional | `NasUltimate_cTrader_Listener.cs` | `C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\NasUltimateBridge_Latest.csv` |

With `Prefer Scoped Latest = true`, always enter the generic path above. The listener finds the matching symbol/TF scoped file automatically.

## Source TF Formula

`Source TF Filter` must equal the value written into the bridge CSV `tf` column:

```text
Normal Liq Narrative      = dashboard ENTRY TF in minutes
Liq Narrative SolVersion = dashboard ENTRY TF in minutes
Sol Advanced              = dashboard ENTRY TF in minutes
ORB Ultimate              = dashboard Signal TF in minutes # her zaman için 15
NAS Professional          = MT5 chart TF in minutes
```

Do not use the MT5 chart timeframe for Liq/ORB unless it is also the selected Entry/Signal TF.

Timeframe conversion:

| Timeframe | Source TF Filter |
|---|---:|
| M1 | `1` |
| M5 | `5` |
| M15 | `15` |
| M30 | `30` |
| H1 | `60` |
| H2 | `120` |
| H4 | `240` |
| D1 | `1440` |

Use the numeric value, especially for H2. Do not enter `H2`; enter `120`.

## Scoped Filename Formula

The universal formula is:

```text
<Common Files>\<FAMILY_PREFIX>_Latest_<MT5_SOURCE_SYMBOL>_<SOURCE_TF_MINUTES>.csv
```

Family prefixes:

```text
Normal Liq Narrative      LiquidityNarrativeBridge
Liq Narrative SolVersion LiqNarrativeSolBridge
Sol Advanced              LiqNarrativeSolAdvancedBridge
ORB Ultimate              OrbUltimateBridge
NAS Professional          NasUltimateBridge
```

Examples:

```text
LiqNarrativeSolBridge_Latest_UK100m_60.csv
LiqNarrativeSolAdvancedBridge_Latest_UK100m_60.csv
OrbUltimateBridge_Latest_DE30m_15.csv
OrbUltimateBridge_Latest_DE30m_5.csv
NasUltimateBridge_Latest_DE30m_5.csv
```

The scoped formula is mainly for verification and troubleshooting. Under normal operation, keep `Bridge Latest Path` on the generic family path and keep `Prefer Scoped Latest = true`.

## Future Setup Examples

### SolVersion on UK100, Entry TF H1

```text
cTrader robot        = LiquidityNarrative_cTrader_Listener.cs
Bridge Latest Path   = C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\LiqNarrativeSolBridge_Latest.csv
Source TF Filter     = 60
Prefer Scoped Latest = true
Expected scoped file = LiqNarrativeSolBridge_Latest_UK100m_60.csv
```

### Sol Advanced on UK100, Entry TF H1

```text
cTrader robot        = LiqNarrativeSolAdvanced_cTrader_Listener.cs
Bridge Latest Path   = C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\LiqNarrativeSolAdvancedBridge_Latest.csv
Source TF Filter     = 60
Prefer Scoped Latest = true
Expected scoped file = LiqNarrativeSolAdvancedBridge_Latest_UK100m_60.csv
```

### ORB on DE30, Signal TF M15

```text
cTrader robot        = OrbUltimate_cTrader_Listener.cs
Bridge Latest Path   = C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\OrbUltimateBridge_Latest.csv
Source TF Filter     = 15
Prefer Scoped Latest = true
Expected scoped file = OrbUltimateBridge_Latest_DE30m_15.csv
cTrader chart        = GERMANY 40
```

If ORB Signal TF is changed to M5, change only:

```text
Source TF Filter     = 5
Expected scoped file = OrbUltimateBridge_Latest_DE30m_5.csv
```

## Current Known Setups

| Pipeline | Source TF Filter |
|---|---:|
| Normal Liq, US500, Entry M15 | `15` |
| Normal Liq, US100/USTEC, Entry M15 | `15` |
| SolVersion, JPN225, Entry H1 | `60` |
| Sol Advanced, JPN225, Entry H1 | `60` |
| ORB, JPN225, Signal M15 | `15` |
| ORB, DE30, Signal M15 | `15` |
| NAS Professional, DE30 chart M5 | `5` |

## Symbol Mapping Rule

The listener resolves common aliases such as:

```text
JP225m/JP225/JPN225 -> JPN225
DE30m/GER30/GER40/DAX40 -> GERMANY 40
US500m/SPX500 -> US 500
USTECm/US100/NAS100 -> US Tech 100
US30m/DJ30 -> Wall Street 30
```

For symbols such as UK100, canonical matching normally handles spaces and the MT suffix (`UK100m` and `UK 100`). If the broker uses a materially different cTrader symbol name, set:

```text
Symbol Map CSV = <MT5_SOURCE_SYMBOL>=<EXACT_CTRADER_SYMBOL_NAME>
```

Example only if the exact cTrader tab/symbol name is `UK 100`:

```text
Symbol Map CSV = UK100m=UK 100
```

Multiple mappings are comma-separated:

```text
UK100m=UK 100,DE30m=GERMANY 40
```

## Isolation Rules

Keep these settings:

```text
Prefer Scoped Latest = true
Require Chart Symbol = true
Close Reverse Across TF = false
```

Use separate cTrader listener instances when any of these differ:

```text
EA family
cTrader chart symbol
Source TF Filter
```

That separation prevents SolVersion, Sol Advanced, Normal Liq, ORB and NAS events from claiming, closing or managing each other's positions.


-------------------------------------Şip Şap Setups-------------------------------------------------------------------------
Use these full paths:

US500 and US100 - Normal Liq Narrative

C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\LiquidityNarrativeBridge_Latest.csv

JPN225 - Liq Narrative SolVersion

C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\LiqNarrativeSolBridge_Latest.csv

JPN225 - Liq Narrative Sol Advanced

C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\LiqNarrativeSolAdvancedBridge_Latest.csv

DE30 - NAS Professional

C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\NasUltimateBridge_Latest.csv

and "source tf filter"

us500 and us100: 15, jp225 sol: 60, jp225 advanced: 60, de30 nas: 5

and thats it pipelines are set.
----------------------------------------------------------------------------------------------------------------------------
