# Sol Advanced Tick Replay Optimization

Measured on 2026-09-26, JP225m/M5 chart, 20W audit, 68 source trades.
The isolated probe uses the production default H2/H1 signal settings.

## Root Cause

The previous replay copied the complete tick interval before looking for a
TP/SL. With native reverse exits disabled that interval can end at the current
time. Ticks after a terminal exit were copied but never used.

The replay now reads non-overlapping one-hour chunks chronologically and stops
at the first terminal tick. Entry coverage, bid/ask fills, slippage, commission,
HC/BE state and the existing incomplete-data fallback are preserved. A cached
tick-confirmed TP/SL can also be reused for a different exit boundary only if
the terminal exit precedes that boundary. OHLC and forced exits are excluded.

## Measurements

| Scenario | Previous ms | Updated ms | Outcome |
| --- | ---: | ---: | --- |
| Reverse ON, cold cache | 3500 | 4016 | 42W / 25L / 1O, +53.1275R |
| Reverse OFF, cold cache | 36438 | 4015 | 39W / 28L / 1O, +50R |
| Reverse OFF, reused cache | 109 | 78 | 39W / 28L / 1O, +50R |
| Reverse OFF, HC/BE | 35828 | 2485 | 56W / 11L / 1O, +26.25R |
| Reverse OFF, inversion | 35750 | 4031 | 27W / 40L / 1O, -26.5R |

All 340 exported rows matched byte-for-byte, including validity, W/L/O,
per-trade R, exit timestamp/reason and entry/SL/TP geometry. The ordinary
reverse-enabled case was not faster in this run; the gain targets extended
lifespans and duplicate terminal replay. These are measured results, not a
runtime guarantee for every broker/instrument or unavailable tick history.

Evidence: `.tmp/sol_tick_stream_20260926_120545/{candidate,baseline}/outcomes.csv`.
Probe: `tests/mql5/LiqSolAdvancedTickStreamProbe.mq5`.
Runner: `scripts/validate_liq_tick_stream.ps1`.
Pre-change source: `.tmp/sol_adv_tick_before/LiqNarrativeSol_Advanced.mq5`.

Signal generation, live execution, bridge schema and listeners are unchanged.
