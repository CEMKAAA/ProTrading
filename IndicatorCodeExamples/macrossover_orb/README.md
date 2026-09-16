# MA CrossOver ORB Clone

Experimental, isolated MA-signal implementation built from the current ORB
execution framework. The production ORB sources are not modified.

## Compile targets

- MT5 EA: `MaCrossOverOrbEA.mq5`
- cTrader cBot: `MaCrossOver_cTrader_Listener.cs`

Compile the MQ5 file only. MQH files are include dependencies and must not be
compiled independently.

## Signal modes

1. `MA MTF`: the original `MaCrossOver.pine` signal kernel. Select `FAST`
   (EMA 9/27), `MED` (EMA 9/HMA 200), or `SLOW` (EMA 27/HMA 200); all retain
   the closed H4 HMA 200 trend condition.
2. `EMA 50/200`: closed-bar cross from `Crossover2.pine`.
3. `TRENDLINE`: causal pivot-confirmed trendline break. It intentionally does
   not use TradingView's delayed/backpainted visual pivot label as an entry.
4. `PIVOT ST`: pivot SuperTrend direction change.
5. `SCALP PB`: Heikin-Ashi / PAC pullback mode.

The dashboard `SIGNAL MODE / PAIR` buttons switch the kernel, invalidate the
MA history cache and schedule a complete redraw. User-saved strategies persist
that runtime mode/pair together with their remaining ORB framework settings.

## Isolation and bridge

The MT5 publisher writes only `MaCrossOverBridge` files and emits the source
namespace `MaCrossOver|...`. The cTrader listener accepts only that namespace.
Its labels, event locks, protection state and audit files use the separate
`MACROSS_CT` / `MaCrossOver_cTrader_*` namespaces.

Bridge ownership consists of full CSV path, source namespace, channel and
source timeframe. A listener may manage or close only positions carrying its
own scoped label.

Use a distinct positive channel for every independently managed MA
combination, including same-symbol/same-TF mode or pair variants. The scoped
file is `MaCrossOverBridge_Latest_C<channel>_<symbol>_<tf>.csv`; configure the
cTrader listener with the base path `MaCrossOverBridge_Latest.csv`, the same
channel, `Prefer Scoped Latest=true`, and the same source TF. The listener
must still be built in cTrader before use.

## Status

The EA and kernel probe compile cleanly. The isolated terminal worker was busy
and was deliberately not interrupted. A live-terminal run and a history/live
parity campaign are still required before any real-money deployment. Do not
replace a production ORB instance with this experimental clone yet.
