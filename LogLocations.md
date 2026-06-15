# Log Locations

Last updated: 2026-06-15

This file tracks where the active EA/bridge audit files are written. Use it as the first reference before auditing runtime behavior.

## Terminal Roots

`MT4_MAIN`

`C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\50CA3DFB510CC5A8F28B48D1BF2A5702`

Used for:

- `AtomicBridge_MT4_EA`
- `SIGNATICSBridge_MT4_EA`

`MT4_SECOND`

`C:\MT4_Instances\MetaTrader 4 - Second`

Used for:

- `GannMadeEasyBridge_MT4_EA`
- Other second-terminal MT4 bridge tests

`MT5_MAIN`

`C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075`

Used for:

- `NasUltimate_SATS_PartialNoBE_EA`
- `NasUltimateEA` / NAS V3
- `RealOrbStrategy` / ORB15
- `ERL_IRL_SwingModel_EA`

## AtomicBridge MT4

Terminal:

`MT4_MAIN`

Runtime logs:

- `MT4_MAIN\MQL4\Logs\YYYYMMDD.log`
- `MT4_MAIN\logs\YYYYMMDD.log`

Primary audit files:

- `MT4_MAIN\MQL4\Files\AtomicBridge_DirectAudit_YYYYMMDD.csv`
- `MT4_MAIN\MQL4\Files\AtomicBridge_PositionProbe_YYYYMMDD.csv`
- `MT4_MAIN\MQL4\Files\AccountRiskAudit_MT4_YYYYMMDD.csv`

Regime-specific probe:

- `MT4_MAIN\MQL4\Files\AtomicBridge_RegimeSignalProbe_YYYYMMDD.csv`

What to check:

- Build line: `AtomicBridge BUILD=...`
- Risk config line: `AtomicBridge account_risk enabled=...`
- Normal Atomic executions: `direct_signal_received`, `direct_order_sent`, `direct_duplicate_suppressed`
- AtomicRegime executions: `source=AtomicRegime`, event ids starting with `atomic_regime|`
- Regime signal diagnosis: `AtomicBridge_RegimeSignalProbe_YYYYMMDD.csv`
- Position lifecycle: `direct_halfbe_trigger_seen`, `direct_sl_to_be_sent`, `direct_half_close_sent`, `direct_sl_hit`, `direct_tp_hit`, `direct_closed`

Notes:

- MT4 chart inputs can keep old values even after a new `.ex4` is deployed. If logs show old defaults, reattach EA or reload preset.
- `account_risk enabled=false` with a new build usually means old chart input state, not source default.

## SIGNATICSBridge MT4

Terminal:

`MT4_MAIN`

Runtime logs:

- `MT4_MAIN\MQL4\Logs\YYYYMMDD.log`
- `MT4_MAIN\logs\YYYYMMDD.log`

Primary audit files:

- `MT4_MAIN\MQL4\Files\SIGNATICSBridge_DirectAudit_YYYYMMDD.csv`
- `MT4_MAIN\MQL4\Files\SIGNATICSBridge_PositionProbe_YYYYMMDD.csv`
- `MT4_MAIN\MQL4\Files\AccountRiskAudit_MT4_YYYYMMDD.csv`

Extra Signatics probe files:

- `MT4_MAIN\MQL4\Files\SIGNATICSBridge_BufferProbe_YYYYMMDD.csv`
- `MT4_MAIN\MQL4\Files\SIGNATICSBridge_BufferDeepProbe_YYYYMMDD.csv`

What to check:

- Build line: `SIGNATICSBridge BUILD=...`
- Risk config line: `SIGNATICSBridge account_risk enabled=...`
- Live signal selection: `fast_buffer_selected`, `confirmed_attempt_fast_buffer`, `trade_signal_sent_fast_buffer`
- Missing live signal diagnosis: `buffer_no_live_selection`
- Stale/deep buffer clues: `SIGNATICSBridge_BufferDeepProbe_YYYYMMDD.csv`
- Object enrichment / TP-SL issues: direct audit extra fields and deep probe object rows

Notes:

- If direct audit exists but only `buffer_no_live_selection` appears, EA is alive but live fast buffer did not select a fresh signal.
- Deep probe can show old/stale buffer hits with large shifts. That is not necessarily a tradable live signal.

## GannMadeEasyBridge MT4

Terminal:

`MT4_SECOND`

Runtime logs:

- `MT4_SECOND\MQL4\Logs\YYYYMMDD.log`
- `MT4_SECOND\logs\YYYYMMDD.log`

Primary audit files:

- `MT4_SECOND\MQL4\Files\GannMadeEasyBridge_DirectAudit_YYYYMMDD.csv`
- `MT4_SECOND\MQL4\Files\GannMadeEasyBridge_AccountRiskAudit_YYYYMMDD.csv`

What to check:

- Build line: `GannMadeEasyBridge BUILD=...`
- Signal/open flow: `signal_received`, `order_sent`, `order_failed`
- Drift/pending behavior: `pendingOnDrift`, `drift`, pending-related rows
- Broker stop handling: `err=130`, stopguard/fallback rows
- Lifecycle: `closed_by_broker_sl`, `closed_by_broker_tp`, `closed_by_unknown/manual`
- Position health: `position_probe` rows in direct audit

Notes:

- `GannMadeEasyBridge_DirectAudit_YYYYMMDD.csv` is semicolon-delimited in current builds.
- Lot/risk snapshots are in the Gann account risk audit file, not the MT4 main account risk file.

## NAS Old / PartialNoBE MT5

Terminal:

`MT5_MAIN`

Runtime logs:

- `MT5_MAIN\MQL5\Logs\YYYYMMDD.log`
- `MT5_MAIN\logs\YYYYMMDD.log`

Primary audit files:

- `MT5_MAIN\MQL5\Files\NasLab_TradeAudit_YYYYMMDD.csv`
- `MT5_MAIN\MQL5\Files\NasLab_PositionProbe_YYYYMMDD.csv`
- `MT5_MAIN\MQL5\Files\NasLab_RiskAudit_YYYYMMDD.csv`
- `MT5_MAIN\MQL5\Files\AccountRiskAudit_MT5_YYYYMMDD.csv`

Backtest / brute-force files:

- `MT5_MAIN\MQL5\Files\NasLab_BruteBacktest_YYYYMMDD_HHMMSS.csv`

What to check:

- Build/init rows: `ea_init`
- Signal flow: `signal_received`, `order_sent`, `order_failed`
- Blocked signals: `signal_skip_window`, spread/risk/window skip rows
- Lifecycle: `history_close`, `position_probe`
- Advanced lot: terminal log lines with `NAS SATS advanced lot resolved`

Notes:

- Old NAS and new NAS must not be mixed in PnL analysis; use `NasLab_*` for old NAS and `NasV3Lab_*` for new NAS.

## NAS New / NAS V3 MT5

Terminal:

`MT5_MAIN`

Runtime logs:

- `MT5_MAIN\MQL5\Logs\YYYYMMDD.log`
- `MT5_MAIN\logs\YYYYMMDD.log`

Primary audit files:

- `MT5_MAIN\MQL5\Files\NasV3Lab_TradeAudit_YYYYMMDD.csv`
- `MT5_MAIN\MQL5\Files\NasV3Lab_PositionProbe_YYYYMMDD.csv`
- `MT5_MAIN\MQL5\Files\NasUltimate_V2_FilterAudit_YYYYMMDD.csv`
- `MT5_MAIN\MQL5\Files\AccountRiskAudit_MT5_YYYYMMDD.csv`

Backtest / process files:

- `MT5_MAIN\MQL5\Files\NasV3Lab_BruteBacktest_YYYYMMDD_HHMMSS.csv`
- `MT5_MAIN\MQL5\Files\NasV3Lab_BacktestProcess_YYYYMMDD.csv`

What to check:

- Build/init rows: `ea_init` with `2026-06-15.v2.2-risklot-default` or newer
- Current mode: strategy mode, RR, sensitivity, TF, FTMO flags in `ea_init`
- Signal flow: `signal_received`, `order_sent`, `order_failed`
- Filter decisions: `NasUltimate_V2_FilterAudit_YYYYMMDD.csv`
- Backtest health: process CSV and brute result CSV

Notes:

- If dashboard backtest appears to finish too fast, inspect `NasV3Lab_BacktestProcess_YYYYMMDD.csv` and brute CSV date/window columns.

## ORB15 / RealOrbStrategy MT5

Terminal:

`MT5_MAIN`

Runtime logs:

- `MT5_MAIN\MQL5\Logs\YYYYMMDD.log`
- `MT5_MAIN\logs\YYYYMMDD.log`

Primary audit files:

- `MT5_MAIN\MQL5\Files\ORB15_TradeAudit_YYYYMMDD.csv`
- `MT5_MAIN\MQL5\Files\ORB15_PositionProbe_YYYYMMDD.csv`
- `MT5_MAIN\MQL5\Files\ORB15v3_Audit_YYYYMMDD.csv`
- `MT5_MAIN\MQL5\Files\AccountRiskAudit_MT5_YYYYMMDD.csv`

Backtest / brute-force files:

- `MT5_MAIN\MQL5\Files\ORB15_BruteBacktest_YYYYMMDD_HHMMSS.csv`
- `MT5_MAIN\MQL5\Files\ORB15_BacktestProcess_YYYYMMDD.csv`

What to check:

- Build/init line: `ORB15v3.1 init ... build=...`
- Daily setup: `new_day`, `orb_ready`
- Signal/filter flow: `signal`, `filtered`, `opened_3leg`
- Historical redraw: `hist_redraw`
- Backtest completion: `OBT: COMPLETE ... -> ORB15_BruteBacktest_...`

Notes:

- ORB is usually run on USTEC M1 chart while dashboard strategy TF can be M15.
- Strategy chart TF and dashboard signal TF are separate concepts.

## ERL_IRL SwingModel MT5

Terminal:

`MT5_MAIN`

Runtime logs:

- `MT5_MAIN\MQL5\Logs\YYYYMMDD.log`
- `MT5_MAIN\logs\YYYYMMDD.log`

Primary audit files:

- `MT5_MAIN\MQL5\Files\ERL_IRL_TradeAudit_YYYYMMDD.csv`
- `MT5_MAIN\MQL5\Files\ERL_IRL_PositionProbe_YYYYMMDD.csv`
- `MT5_MAIN\MQL5\Files\ERL_IRL_FilterAudit_YYYYMMDD.csv`
- `MT5_MAIN\MQL5\Files\AccountRiskAudit_MT5_YYYYMMDD.csv`

Backtest / process files:

- `MT5_MAIN\MQL5\Files\ERL_IRL_BruteBacktest_YYYYMMDD_HHMMSS.csv`
- `MT5_MAIN\MQL5\Files\ERL_IRL_BacktestProcess_YYYYMMDD.csv`

What to check:

- Build/init line: `ERL_IRL init build=...`
- Latest expected build after 2026-06-15 patch: `2026-06-15.erl-irl-bt-process-risklot-default`
- Swing/FVG/IRL filter decisions in filter audit
- Backtest process visibility in `ERL_IRL_BacktestProcess_YYYYMMDD.csv`

Notes:

- If logs only show `2026-06-14.erl-irl-v1`, the chart is still running an old compiled/input state. Reattach EA or reload preset.

## Quick PowerShell Snippets

List active audit files:

```powershell
$mt4='C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\50CA3DFB510CC5A8F28B48D1BF2A5702'
$mt4s='C:\MT4_Instances\MetaTrader 4 - Second'
$mt5='C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075'
Get-ChildItem "$mt4\MQL4\Files","$mt4s\MQL4\Files","$mt5\MQL5\Files" -Filter "*YYYYMMDD*.csv" |
  Sort-Object LastWriteTime -Descending |
  Select-Object LastWriteTime,Length,FullName
```

Check build lines:

```powershell
Select-String -Path "$mt4\MQL4\Logs\YYYYMMDD.log" -Pattern "AtomicBridge BUILD=","SIGNATICSBridge BUILD="
Select-String -Path "$mt4s\MQL4\Logs\YYYYMMDD.log" -Pattern "GannMadeEasyBridge BUILD="
Select-String -Path "$mt5\MQL5\Logs\YYYYMMDD.log" -Pattern "ORB15v3.1 init","ERL_IRL init","NAS SIGNAL LAB","risklot-default"
```

Tail critical files:

```powershell
Get-Content "$mt4\MQL4\Files\AtomicBridge_RegimeSignalProbe_YYYYMMDD.csv" -Tail 40
Get-Content "$mt4\MQL4\Files\SIGNATICSBridge_DirectAudit_YYYYMMDD.csv" -Tail 80
Get-Content "$mt4\MQL4\Files\SIGNATICSBridge_BufferDeepProbe_YYYYMMDD.csv" -Tail 80
Get-Content "$mt4s\MQL4\Files\GannMadeEasyBridge_DirectAudit_YYYYMMDD.csv" -Tail 80
Get-Content "$mt5\MQL5\Files\NasV3Lab_TradeAudit_YYYYMMDD.csv" -Tail 80
Get-Content "$mt5\MQL5\Files\ORB15_TradeAudit_YYYYMMDD.csv" -Tail 80
Get-Content "$mt5\MQL5\Files\ERL_IRL_TradeAudit_YYYYMMDD.csv" -Tail 80
```

## Audit Interpretation Rules

- Do not trust frontend telemetry alone. Prefer terminal CSVs and terminal logs.
- Confirm build first, then signal receipt, then order execution, then lifecycle.
- For MT4 EAs, chart inputs can override source defaults. If build is new but inputs are old, reattach or reload preset.
- For duplicate trade investigations, group by `event_id`.
- For missed trade investigations, compare signal/probe timestamp, selected shift, order timestamp, bid/ask/spread, and skip reason.
- For PnL summaries, dedupe partial/remainder ticket chains before aggregating.
