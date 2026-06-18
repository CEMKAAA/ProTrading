# ORB Native MT5 10W 30-Combo Leaderboard

- EA: RealOrbStrategy / OrbUltimateEA
- Symbol: USTECm
- Tester timeframe: M15
- Window: 2026-04-09 -> 2026-06-18
- Model: native MT5 real/every-tick harness model=4
- Counting: position_id-based; partial closes are merged into one trade

## Top 10

| Rank | Job | Net | PF | WR% | Trades | Max Loss | Avg/Trade |
|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | `orb10w_19_sl60_tp6_hc5_d0_atr1_vol0` | 345.05 | 1.322 | 45.65 | 46 | -85.53 | 7.501 |
| 2 | `orb10w_20_sl60_tp6_hc5_d3_atr1_vol0` | 345.05 | 1.322 | 45.65 | 46 | -85.53 | 7.501 |
| 3 | `orb10w_21_sl60_tp6_hc5_d5_atr1_vol0` | 345.05 | 1.322 | 45.65 | 46 | -85.53 | 7.501 |
| 4 | `orb10w_30_sl20_tp4_hc0_d3_atr1_vol0` | 140.85 | 1.314 | 44.68 | 47 | -33.43 | 2.997 |
| 5 | `orb10w_07_sl20_tp6_hc5_d0_atr1_vol0` | 72.6 | 1.144 | 36.17 | 47 | -33.43 | 1.545 |
| 6 | `orb10w_08_sl20_tp6_hc5_d3_atr1_vol0` | 72.6 | 1.144 | 36.17 | 47 | -33.43 | 1.545 |
| 7 | `orb10w_09_sl20_tp6_hc5_d5_atr1_vol0` | 72.6 | 1.144 | 36.17 | 47 | -33.43 | 1.545 |
| 8 | `orb10w_24_sl20_tp5_hc4_d3_atr1_vol0` | 48.27 | 1.108 | 44.68 | 47 | -32.78 | 1.027 |
| 9 | `orb10w_23_sl15_tp5_hc4_d3_atr1_vol0` | 8.18 | 1.021 | 36.17 | 47 | -24.83 | 0.174 |
| 10 | `orb10w_13_sl30_tp6_hc5_d0_atr1_vol0` | -20.5 | 0.974 | 31.91 | 47 | -49.06 | -0.436 |

## Notes

- Best net result is `sl60_tp6_hc5`; d0/d3/d5 variants are identical in this sample.
- Most prop-balanced result is arguably `sl20_tp4_hc0_d3`: lower net than sl60 but much smaller max loss.
- `sl10` was not robust in native MT5 10-week testing despite looking attractive in internal/short-window testing.
- All jobs produced tester trade-audit artifacts; XML strategy report was not required for this leaderboard.