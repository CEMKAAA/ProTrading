# IQ Capital MT5-to-MT5 Pipeline

## Architecture

DEMOMT5 remains the only signal source. IQ Capital MT5 does not recalculate SolVersion, SolAdvanced, or ORB from the IQ `JPN225` feed.

```text
DEMOMT5 JP225m producer -> Terminal Common\Files scoped CSV -> IQ Capital JPN225 listener
```

This preserves the DEMOMT5 signal direction and source SL/TP/HCBE distances. The IQ listener rebases those distances around the actual IQ fill and calculates volume from IQ account equity using the bridge `risk_pct`.

## Shared files

```text
C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\LiqNarrativeSolBridge_Latest_JP225m_60.csv
C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\LiqNarrativeSolAdvancedBridge_Latest_JP225m_60.csv
C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\OrbUltimateBridge_Latest_JP225m_15.csv
```

## DEMOMT5 source

Keep the existing production EAs on `JP225m`:

- `LiqNarrativeSolVersion.mq5`: bridge publication ON, entry/source TF `60`.
- `LiqNarrativeSol_Advanced.mq5`: bridge publication ON, entry/source TF `60`.
- `OrbUltimateEA.mq5`: bridge publication ON, signal TF `15`.

Do not change their validated strategy settings for the IQ pipeline.

## IQ Capital destination

Open three separate `JPN225` charts. Chart timeframe is not used as the source TF because every listener has an explicit filter.

Attach:

```text
LiqNarrativeSol_IQCapital_MT5_Listener_EA.ex5
LiqNarrativeSolAdvanced_IQCapital_MT5_Listener_EA.ex5
OrbUltimate_IQCapital_MT5_Listener_EA.ex5
```

Defaults are already production-scoped:

| Listener | Source TF | Source filter | Magic | Scoped latest file |
|---|---:|---|---:|---|
| SolVersion | 60 | `LiqNarrativeSol|` | 9810601 | `LiqNarrativeSolBridge_Latest_JP225m_60.csv` |
| SolAdvanced | 60 | `LiqNarrativeSolAdvanced|` | 9810602 | `LiqNarrativeSolAdvancedBridge_Latest_JP225m_60.csv` |
| ORB | 15 | `OrbUltimate|` | 9811503 | `OrbUltimateBridge_Latest_JP225m_15.csv` |

Required defaults:

```text
Use Common Files = true
Source Login Filter = 260460316
Symbol Map CSV = JP225m=JPN225,JP225=JPN225,JPN225m=JPN225,JPN225=JPN225
Rebase Mapped Levels To Live Entry = true
Rebase Only When Source Differs = true
Require Mapped Symbol Equals Chart = true
Default Source TF To Chart Period = false
Require Hedging Account = true
Destination Server Filter = BeyondIQCapital
Use Risk Lot = true
Post Fill Risk Guard = true
Fail Closed On Risk Error = true
Fail If Exact Protection Fails = true
Ignore Existing Signal On Init = true
```

Enable Algo Trading in IQ MT5. Do not attach the signal-producing Sol/ORB EAs to IQ charts.

## Startup behavior

The listener intentionally ignores the already-existing latest signal when first attached. It starts with the next fresh source event; this prevents an old signal from opening late after restart.

Open positions are isolated by destination symbol, source TF, unique magic, event lock, and position state namespace. The IQ account must remain hedging mode; listeners fail initialization on a netting account.

## Execution invariants

- Source lot is never copied.
- Risk budget uses IQ `ACCOUNT_EQUITY * bridge risk_pct`.
- SL/TP/HCBE distances are measured from the DEMOMT5 bridge entry and rebased to the actual IQ fill.
- Post-fill risk is recalculated and oversized volume is reduced or the position is closed fail-safe.
- SL/TP are verified after fill. Failed protection triggers emergency close and retry-close management.
- HCBE partial close is restart-safe; a completed half close is not repeated while BE modification is pending.
- Reverse signals close only positions owned by that listener magic and source TF.

## Expected differences

Signal identity and R-distance geometry match DEMOMT5. Fill price, spread, slippage, commission, contract conversion, and therefore realized dollar PnL can differ between brokers. IQ historical chart arrows/audit are not reconstructed from IQ candles; authoritative strategy history remains on DEMOMT5.
