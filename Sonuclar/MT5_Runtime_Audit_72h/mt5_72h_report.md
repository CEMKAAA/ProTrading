# MT5 Runtime Audit - Last 72h

- Window: 2026-06-15 14:12:23 -> 2026-06-18 14:12:23
- MT5 history deals: 221
- Parsed: 108 closed + 1 open

## Leaderboard

| Rank | EA/Symbol/TF | Config | Trades | W/L | WR | Net | PF | Avg | MaxWin | MaxLoss |
|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | NAS old/fixed/USTECm/n/a |  | 15 | 10/5 | 66.7% | 351.53 | 3.17 | 23.44 | 120.92 | -41.33 |
| 2 | GoldBO ATR/XAUUSDm/history_no_tf | Gold ISIS magic 250120 | 34 | 34/0 | 100.0% | 170.66 | 999.00 | 5.02 | 28.00 | 2.41 |
| 3 | New NAS V3/USTECm/M30 | ST+SMA13 1:2R S4 | 1 | 1/0 | 100.0% | 105.50 | 999.00 | 105.50 | 105.50 | 105.50 |
| 4 | New NAS V3/XAUUSDm/M5 | ST+SMA13 1:2R S4 | 5 | 2/3 | 40.0% | 102.08 | 2.14 | 20.42 | 96.01 | -37.96 |
| 5 | New NAS V3/XAUUSDm/M30 | ST+SMA13 1:2R S4 | 2 | 1/1 | 50.0% | 51.57 | 3.70 | 25.78 | 70.66 | -19.09 |
| 6 | Unknown/Manual/XAUUSDm/n/a |  | 1 | 1/0 | 100.0% | 50.08 | 999.00 | 50.08 | 50.08 | 50.08 |
| 7 | New NAS V3/XAUUSDm/H1 | ST+SMA13 1:2R S4 | 1 | 1/0 | 100.0% | 47.72 | 999.00 | 47.72 | 47.72 | 47.72 |
| 8 | 15MinORB/USTECm/M15 strategy | chart=M15 strategy=M15 | 3 | 2/1 | 66.7% | 34.11 | 569.50 | 11.37 | 34.13 | -0.06 |
| 9 | 15MinORB/USTECm/M15 strategy | chart=M1 strategy=M15 | 12 | 6/6 | 50.0% | 25.33 | 1.11 | 2.11 | 99.96 | -70.51 |
| 10 | New NAS V3/USTECm/M15 | ST+SMA13 1:2R S2 | 1 | 1/0 | 100.0% | 20.32 | 999.00 | 20.32 | 20.32 | 20.32 |
| 11 | New NAS V3/USTECm/M5 | ST+SMA13 1:3R S2 | 2 | 1/1 | 50.0% | 6.18 | 1.13 | 3.09 | 53.69 | -47.51 |
| 12 | New NAS V3/USTECm/H1 | ST+SMA13 1:2R S4 | 1 | 1/0 | 100.0% | 2.39 | 999.00 | 2.39 | 2.39 | 2.39 |
| 13 | New NAS V3/USTECm/M15 | ST+SMA13 1:2R S4 | 3 | 1/2 | 33.3% | -13.16 | 0.85 | -4.39 | 73.15 | -43.45 |
| 14 | New NAS V3/XAUUSDm/M15 | ST+SMA13 1:2R S4 | 1 | 0/1 | 0.0% | -40.37 | 0.00 | -40.37 | -40.37 | -40.37 |
| 15 | New NAS V3/USTECm/M5 | ST+SMA13 1:2R S4 | 8 | 2/6 | 25.0% | -50.21 | 0.83 | -6.28 | 172.68 | -191.41 |
| 16 | NAS old/fixed/XAUUSDm/n/a |  | 18 | 8/10 | 44.4% | -281.27 | 0.55 | -15.63 | 62.87 | -170.48 |

## ERL_IRL Signal Scarcity

- ERL audit events in window: {'ea_init': 61, 'backtest_start': 16, 'backtest_done': 16}
- Code path requires HTF swing -> sweep/reclaim -> FVG within max search bars -> entry-TF tap.
- Current 72h ERL rows are init/backtest rows, not live order rows; this points to sparse strategy filters rather than an execution bug.

## Audit File Cross-Check

- NAS order_sent TF counts: {'M30': 3, 'M5': 16, 'M15': 5, 'H1': 2}
- ORB open event counts: {'opened_3leg': 5}
- ERL event counts: {'ea_init': 61, 'backtest_start': 16, 'backtest_done': 16}
