# Ten Scalper Recipes: Functionality Audit

Build: EntryEngineLab-1.01, 2026-10-01.
Evidence: `.tmp/entry_engine_lab_20261001_180040/scalpers.txt` and `result.txt`.
Instrument: Exness USDJPYm. Signal timeframe: M1. Window: 2W ending at the
probe's frozen 2026-10-01 15:01 broker-time cutoff. Broker-synchronized bars
and tick fills were used. The probe submitted no orders or bridge messages.

The supplied recipes were implemented without profitability-driven retuning.
This is a correctness and execution-policy test, NOT out-of-sample evidence
of an edge. All ten measured outcomes are negative on this instrument/window.

| Engine | Trades | W | L | Open | DATA | Net R | Rule Exits | Time Exits | Audit Seconds |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 01 Slow EMA + ADX | 974 | 244 | 729 | 1 | 0 | -403.4615 | 0 | 0 | 6.719 |
| 02 EMA Pullback | 1747 | 360 | 1387 | 0 | 0 | -924.3430 | 0 | 0 | 11.984 |
| 03 RSI 50-Line | 1022 | 197 | 825 | 0 | 0 | -582.2792 | 1 | 0 | 6.688 |
| 04 Fast EMA + RSI | 6211 | 1078 | 5132 | 1 | 0 | -3761.3127 | 0 | 1 | 26.954 |
| 05 Bollinger Reversion | 935 | 170 | 765 | 0 | 0 | -560.8566 | 0 | 0 | 6.312 |
| 06 ATR Micro-Breakout | 1782 | 330 | 1452 | 0 | 0 | -1048.6919 | 0 | 0 | 12.640 |
| 07 EMA + RSI Re-Entry | 5285 | 942 | 4343 | 0 | 0 | -3145.1105 | 0 | 1 | 24.843 |
| 08 Ultra-Fast EMA State | 3822 | 603 | 3219 | 0 | 0 | -2532.3795 | 0 | 0 | 30.500 |
| 09 Candle Momentum | 1482 | 224 | 1258 | 0 | 0 | -997.1178 | 0 | 0 | 22.360 |
| 10 Directional Flip | 654 | 115 | 539 | 0 | 0 | -395.1991 | 0 | 0 | 30.906 |

Counts refer to accepted audited trades, not every raw state signal. Invalid
tick-size geometry, stops inside the executable spread, occupancy and cooldown
can reject entries. Tiny M1 ATR distances are especially sensitive to spread.
No future outcome was used to select a fill. These recipes' turnover targets
are not measured guarantees. Timings include the local probe's audit work;
they are not a worst-case latency bound or a five-year performance benchmark.

Only a few early exits occur with the supplied narrow ATR distances. A separate
wide-ATR verification fixture therefore exercises numerous rule/time exits
and checks their actual exit-price R, native/audit exit-clock agreement and
ADV/legacy audit identity. That fixture is not a replacement template.

The frozen cutoff prevents warm/cold comparisons drifting during the test.
It exists only in the probe; production time handling remains unchanged.
The complete probe passed 10236 checks with zero failures. Both EA and probe
compiled with zero errors and zero warnings. Original six MaCross kernels
retain their independently checked signal and marker parity.

## Execution Boundary

New policy engines require MT5-native operation: PUB OFF, NAT ON. Their rule
and time exits are not claimed to be supported by existing listeners. Live
order submission and execution slippage were not tested. Current broker stop
and freeze constraints are checked before native orders, but historical
changes to these limits are unavailable and are not fabricated in this audit.
Missing real tick coverage stays incomplete/DATA; no exact OHLC exit is invented.
