# Verification: 2026-10-01

Latest normal broker-data run:
`.tmp/entry_engine_lab_20261001_180040/result.txt`

```
checks=10236 failed=0 trades=351 audit_same=true
rsi_error=0.0000000000 adx_error=0.0000000000
history_source=BROKER_SYNCHRONIZED
```

EA and full-EA probe both compiled with 0 errors and 0 warnings.
The isolated worker connected to Exness-MT5Trial15. No native orders or
publisher messages were submitted by the probe.

For the deliberately unoptimized test engine (RSI14 crosses 50), USDJPYm M5,
fixed 30-pip SL and the inherited 2R target, the final 2W audit contained
351 trades. This is a functionality fixture, not a profitable strategy
recommendation. Warm 5W-to-2W and forced-cold 2W hashes
matched counts, signal/entry/exit times, direction, geometry and net R.

Parameterized EMA9/SMA50 crossover was checked on 10000 recorded bars.
The six built-in kernels, with all three pairing choices, were compared on
the same bars with an extracted unmodified MaCross kernel. Directions and
marker prices matched. Fixed RSI/ADX values matched native MT5 indicators;
parameterized SMA was also checked against native iMA.

Other checks cover gate truth tables, unknown values, independent BUY/SELL
conditions, cross semantics, FVG chronology, serialization, same-name engine
update, modal event interception/current edit values, preview entry guard,
live/history custom signal kernel, and strategy engine snapshot restoration.

The ten scalper recipes were independently evaluated on 10000 bars. Checks
include entry and separate long/short exit predicates, Wilder ATR snapshots,
population Bollinger deviation and previous-five-bar extrema excluding the
current bar. Each recipe also completed a USDJPYm M1 2W tick audit with zero
DATA results; see SCALPER_AUDIT.md for the measured, negative outcomes.

Policy checks cover single-position occupancy, cooldown candle boundaries,
ATR geometry, all ten ON/OFF serialization round trips, current modal edits,
modal object click priority above the dashboard, and strategy restoration of
all policy fields. A separate wide-ATR fixture exercises rule/time exits:
recorded net R equals actual signed fill-to-exit R less configured costs,
native/audit helper exit clocks agree, and ADV/legacy audit hashes match.
The campaign cutoff is frozen only in the test probe so differential runs
compare the same window; production clocks, prices and fills are unchanged.

Publisher-enabled and NAT-disabled policy entries are rejected by the native
guard. These tests did not submit real orders: broker execution, latency,
slippage, and historical broker stop/freeze-limit changes remain unverified.
New policy engines require PUB OFF and NAT ON; no listener exit support is
implied. Missing exact tick coverage is not converted into invented outcomes.

All three original production source folders remained unchanged. Before
copying the final EX5 to the workspace family, the staged MQ5 and required
MQH files were hash-compared to canonical sources.

Not verified: live order submission, new-family listener execution, every
filter combination, very large custom engines, or visual layout on all
resolutions. Those are not implied by these regression results.
