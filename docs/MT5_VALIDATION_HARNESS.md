# MT5 Validation Harness

This harness validates our EA-side backtest engines against MT5 Strategy Tester in a repeatable way.

It does **not** use the Python `MetaTrader5` package for Strategy Tester execution because the official package does not expose the tester. Instead, it creates an MT5 tester `.ini` file and launches `terminal64.exe /config:<ini>`.

## Files

- `scripts/mt5_validation_harness.py`
- `configs/mt5_validation_jobs.example.json`
- Output default: `logs/mt5_validation`

## Job Contract

Each job describes one validation run:

```json
{
  "job_id": "nas_v3_ustec_m15_20w_1to2r",
  "ea": "NasUltimateEa",
  "ea_kind": "nas",
  "preset": "../IndicatorCodeExamples/EaPresets/NAS/V3/FTMO/RiskLotOnly/NasUltimateEA_V3_FTMO_RiskLotOnly_10k_1to2R.set",
  "symbol": "USTECm",
  "timeframe": "M15",
  "from_date": "2026.01.27",
  "to_date": "2026.06.16",
  "terminal_exe": "C:/Program Files/MetaTrader 5/terminal64.exe",
  "deposit": 10000,
  "model": 4,
  "preset_overrides": {
    "InpBacktestFillMode": "0",
    "InpBacktestSameBarPolicy": "1"
  },
  "internal_backtest_csv": "../IndicatorCodeExamples/NasV3Lab_BruteBacktest_LATEST.csv",
  "tester_trade_audit_csv": "../IndicatorCodeExamples/NasV3Lab_TesterTradeAudit_LATEST.csv",
  "combo_filter": {
    "rr_mode": "1:2R"
  }
}
```

Core parameters:

- `ea`: MT5 Expert name as Strategy Tester sees it.
- `ea_kind`: one of `nas`, `orb`, `erl`; controls parser mapping.
- `preset`: base `.set` file.
- `preset_overrides`: key/value overrides written into a copied run-specific `.set`.
- `symbol`: broker symbol.
- `timeframe`: chart/test timeframe, for example `M1`, `M15`, `H1`.
- `from_date`, `to_date`: MT5 tester window in `YYYY.MM.DD`.
- `internal_backtest_csv`: EA dashboard/internal brute-force CSV to normalize.
- `tester_trade_audit_csv`: compact Strategy Tester deal-level CSV emitted by the EA.
- `combo_filter`: optional exact-match filter to select a specific internal combo row.

## Commands

Start the local dashboard:

```powershell
python scripts/mt5_validation_dashboard.py --port 8765
```

Open:

```text
http://127.0.0.1:8765
```

Generate tester `.ini` and run-specific `.set` without launching MT5:

```powershell
python scripts/mt5_validation_harness.py run --jobs configs/mt5_validation_jobs.example.json --dry-run
```

Normalize internal EA backtest CSVs only:

```powershell
python scripts/mt5_validation_harness.py normalize --jobs configs/mt5_validation_jobs.example.json
```

Run MT5 Strategy Tester:

```powershell
python scripts/mt5_validation_harness.py run --jobs configs/mt5_validation_jobs.example.json
```

Compare one job against one MT5 report:

```powershell
python scripts/mt5_validation_harness.py compare --jobs configs/mt5_validation_jobs.example.json --job nas_v3_ustec_m15_20w_1to2r --report logs/mt5_validation/nas_v3_ustec_m15_20w_1to2r/<stamp>/reports/nas_v3_ustec_m15_20w_1to2r.xml
```

## Output Contract

The harness writes normalized results:

- `logs/mt5_validation/normalized_internal.csv`
- `logs/mt5_validation/normalized_internal.jsonl`
- `logs/mt5_validation/normalized_tester_trade_audit.csv`
- `logs/mt5_validation/normalized_tester_trade_audit.jsonl`
- `logs/mt5_validation/comparison.csv`
- `logs/mt5_validation/comparison.jsonl`
- Per-run generated tester config and copied preset under `logs/mt5_validation/<job_id>/<stamp>/`

Normalized fields include:

- `job_id`
- `engine`: `ea_internal` or `mt5_strategy_tester`
- `ea`, `ea_kind`, `preset`
- `symbol`, `timeframe`
- `from_date`, `to_date`
- `fill_mode`, `same_bar_policy`
- `combo.*`
- `metrics.total_trades`
- `metrics.wins`
- `metrics.losses`
- `metrics.win_rate`
- `metrics.net_r` for EA-internal backtests
- `metrics.net_profit` for MT5 Strategy Tester
- `metrics.profit_factor`
- `source_file`

## Important Comparison Rule

`net_r` from our internal EA backtest and `net_profit` from MT5 Strategy Tester are not directly equivalent unless we also normalize trade-level tester audit rows with risk-per-trade and lot sizing. The harness reports this as:

```text
net_r_vs_net_profit_not_directly_comparable_without_trade_level_audit
```

Directly comparable fields:

- trade count, if the selected combo matches the tester preset exactly
- direction/signal count, once trade-level audit is added to tester mode
- rough profit factor, if both sides have enough trades

Not directly comparable yet:

- `net_r` vs `net_profit`
- drawdown differences caused by lot engine, spread, commissions, broker stop levels, and real tick model

## Next Accuracy Upgrade

Each EA now has a tester-safe trade-level audit layer when `MQLInfoInteger(MQL_TESTER)` is true:

```csv
job_id,engine,ea,build,symbol,timeframe,server_time,gmt_time,deal,position_id,order,entry_type,deal_type,reason,magic,volume,price,request_price,request_sl,request_tp,profit,swap,commission,fee,retcode,comment
```

Current EA tester audit files:

- NAS V3: `NasV3Lab_TesterTradeAudit_<stamp>.csv`
- ORB: `ORB15_TesterTradeAudit_<stamp>.csv`
- ERL/IRL: `ERL_IRL_TesterTradeAudit_<stamp>.csv`

File-size controls:

- `InpTesterTradeAuditCsv=true|false`
- `InpTesterTradeAuditMaxRows=50000`
- `InpValidationJobId=<job_id>`

This logs real Strategy Tester deals only. It does **not** dump every simulated brute-force trade for every internal combo, because that would create very large files and slow the terminal. If we later need internal trade-level parity for one selected combo, add a separate single-combo export mode rather than enabling per-trade logs for the entire brute-force matrix.

## Portable Worker Notes

The dashboard defaults to:

```text
C:\Users\Cem\Desktop\DEMOMT5.lnk
```

That shortcut currently resolves to:

```text
C:\MT5\DEMO\terminal64.exe /portable
```

For fully automated Strategy Tester runs, use a dedicated portable worker terminal. If the same portable terminal is already open interactively, `terminal64.exe /config:<ini>` can return quickly without producing a tester report. In that case the harness launch is working, but the tester run did not actually execute.

Safe options:

- Keep a separate portable MT5 folder only for tester automation.
- Close the portable worker before starting a tester job.
- Set `shutdown_terminal=true` only for a dedicated worker, never for a live/manual terminal.

Space controls:

- Dashboard reads only bounded tails, default `256 KB` per file.
- Event rendering is capped to recent rows.
- Tester deal CSV cap defaults to `InpTesterTradeAuditMaxRows=50000`.
- Cleanup button removes old run directories while keeping the latest runs.
