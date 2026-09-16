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
4. `Close/Reverse` (stored mode 3, formerly `PIVOT ST`): Pivot SuperTrend.
   These are Pine's **Close Short Order / Go to Long Now** and
   **Close Long Order / Go to Short Now** labels. Select this button for those
   signals. The Pivot ST defaults are pivot 2, Wilder ATR 10, factor 3.
5. `Scalp arrows` (stored mode 4, formerly `SCALP PB`): the separate
   Heikin-Ashi / PAC small-arrow section of Pine. It is not the big-label
   strategy. Existing saved mode IDs are deliberately not remapped.

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

## Pine comparison and 0.11 corrections

- One chronological kernel now serves history and live calculations. EMA,
  HA/PAC, pivot state, Wilder ATR and rolling HMA are not separately rewritten
  in the historical engine. Both paths seed from the same available broker
  history. Loading earlier broker history invalidates that seed.
- ATR uses Wilder RMA with the Pine SMA seed, rather than a rolling simple
  average. Trendline crossings use the projected threshold and its actual
  previous value. Pivot-band initialization no longer compares prices to zero.
- Original MA MTF uses the independent H4 HMA 200 default and only completed
  H4 candles. The prior historical implementation could read the final close
  of the still-open containing H4 candle. No current forming signal bar is
  included in an audit.
- Signal arrows are anchored on the generating candle, not the next candle.
  Pivot ST markers use the trailing-band coordinate. Fill/SL/TP prices and
  execution timestamps are not changed to the marker's time or price.
- Live indicator state advances on new closed bars. Repeated ticks reuse the
  previous result, including negative results. Dashboard rebuilding is
  timer-throttled; risk and position management remain tick-driven.
- Event lookup uses binary search at the requested start; event arrays grow
  in reserved blocks. Missing MA data no longer falls back to ORB breakouts.

Match **Signal TF**, not just chart TF, to TradingView when comparing. This
EA still applies the selected ORB framework's sessions, daily-entry rules,
execution geometry and filters downstream of the raw Pine candidate stream.
Therefore accepted/audited trades are not an unfiltered overlay of every
Pine arrow. Label text is descriptive, not an additional close-order command.

The comparison requires identical OHLC, session boundaries, indicator inputs,
and history origin. Different broker feeds need not produce identical signals.
TradingView's developing HTF values can repaint; see its
[official HTF documentation](https://www.tradingview.com/pine-script-docs/concepts/other-timeframes-and-data/).
This EA deliberately uses confirmed HTF data. The trendline's `Buy OK` /
`Sell OK` labels backpainted by 24 bars are not executable historical entries;
its causal `Buy Now` / `Sell Now` crossings are used instead.

## Verification

Run `scripts/validate_macross_pine_stream.ps1` from the workspace. It compiles
the EA and probes, runs isolated MT5 scripts with trading disabled, checks
12,455 regression assertions and compares 60,000 candle/mode decisions to an
independent array-based Python transcription of the supplied Pine equations.
The test covers all five modes, rolling HMA, Wilder ATR, stream/batch equality,
future HTF exclusion and event-search boundaries. This is not a TradingView
export comparison and does not prove parity of different broker feeds.

Reports are in `logs/macross_pine_stream`. The market timing probe separates
data-copy time and signal-kernel time. It marks unavailable live series as
`live_ready=false`; early returns are not reported as live-cache performance.
Kernel microbenchmarks are not full EA audit/GUI timings.

`-InstallDemo` backs up the destination, copies the verified EA and includes
to `C:\MT5\DEMO\MQL5\Experts\MaCrossOverOrb`, then verifies SHA-256 equality.
It does not attach, enable or restart an EA or touch production ORB sources.
End-to-end GUI/bridge execution and a same-feed TradingView comparison remain
required before treating this experimental clone as validated for real money.
