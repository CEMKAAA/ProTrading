# Executable 1R inverse parity study

This is a diagnostic, not a strategy backtest or a recommended live setting.
No production EA or listener was changed in this study.

## Method

- Source: EURUSDm broker Bid/Ask ticks, 2026-09-21 through 2026-09-25.
- Entry samples: first valid tick every 15 minutes, Monday through Thursday. At each sample, simulate both source BUY/inverse SELL and source SELL/inverse BUY.
- Geometry: each position has its own executable Ask or Bid entry, equal stop distance, and 1R fixed target. BUY closes against Bid; SELL closes against Ask.
- Exit: first SL or TP tick. Any position still open after 24 hours closes at the last valid Bid/Ask tick near that deadline. If deadline coverage is missing, the pair stays unresolved.
- Costs: spread is intrinsic to the two quotes. Commission, slippage, latency and bridge-broker price differences are **not** simulated.
- The 766 pairs below come from 383 timestamps with two directions each; they are correlated, not 766 independent strategy trades.

| Stop | Pairs with coverage | Opposite W/L | Both loss | Missing coverage | Pairs where both hit SL/TP |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 3 pip | 766 | 526 (68.7%) | 240 | 0 | 766 |
| 10 pip | 766 | 662 (86.4%) | 104 | 0 | 766 |
| 15 pip | 766 | 686 (89.6%) | 80 | 0 | 766 |
| 20 pip | 766 | 730 (95.3%) | 36 | 0 | 728 |
| 30 pip | 762 | 746 (97.9%) | 16 | 4 | 548 |
| 50 pip | 742 | 728 (98.1%) | 14 | 24 | 196 |

An entry-spread cap of 10% of stop distance admitted 734 of the 766 10-pip pairs. Their opposite W/L rate was 652/734 (88.8%), versus 86.4% without the cap. It did not solve 10-pip parity. At 20 pip the same cap did not improve the rate.

## Interpretation

The two executable positions are not exact negatives. With a simultaneous mark-to-market exit, the sum of a BUY and SELL gross PnL per unit is `-(entry_spread + exit_spread)`. This creates a region where both are losing. Independent broker SL/TP triggers can also occur at different times. An audit that forcibly swaps W/L would conceal these actual losses.

Wider stops reduced double losses in this short sample, but also changed the strategy and increased time exits. For 30 pip, 214 covered pairs required the hypothetical 24-hour close instead of both reaching SL/TP. A 10-pip strategy cannot be silently converted to 20 or 30 pip without fresh signal-level and out-of-sample evaluation. Four days of grid-sampled entries are not evidence that any of these rates will hold for ORB, MaCross or Sol Advanced signals.

The realistic next validation is a paired tick replay of *actual accepted EA signals* over multiple periods and symbols, with each EA's real stop, exit modes, commissions, data gaps, and live/bridge quote differences. Until then, no new inverse spread or stop filter should be enabled by default.

## Reproduce

`tests/mql5/InverseTickParityProbe.mq5` compiles as an MT5 script. Its inputs control dates, sampling interval, horizon, coverage tolerance, and six stop distances. The raw output from the run above is `EURUSDm_2026-09-21_4d_15m_24h.csv` in this directory.

MQL5 reference: [CopyTicksRange](https://www.mql5.com/en/docs/series/copyticksrange), [trading price sides](https://www.mql5.com/en/docs/trading).
