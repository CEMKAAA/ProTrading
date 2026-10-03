# MA CrossOver ORB Clone

Canonical development source: `MaCrossOverOrbEA.mq5` in this folder. Edit and
compile this file, not an older root-level MaCross EA. The time-matrix module
is the local `TradeCalendarMatrix.mqh`; keep it synchronized with the ORB and
Sol Advanced copies when changing shared calendar logic.

Experimental, isolated MA-signal implementation built from the current ORB
execution framework. The production ORB sources are not modified.

## Compile targets

- MT5 EA: `MaCrossOverOrbEA.mq5`
- Optional order-flow worker indicator: `MaCrossOrderFlowWorker.mq5`
- cTrader cBot: `MaCrossOver_cTrader_Listener.cs`

Compile the worker MQ5 first, then the EA MQ5, keeping both EX5 files in the
same folder. The worker is loaded automatically by the EA when order-flow is
enabled; do not attach it as an EA. MQH files are include dependencies and must
not be compiled independently.

## Order-flow preview (0.13)

Default OFF; existing strategies without OF metadata load OFF. The dashboard
header `OF` button cycles BREAK / REJECT / EITHER / OFF. Other parameters are
in Inputs / ORDER FLOW. Saving a strategy saves these settings too.

This is bid-tick quote activity, not real exchange buy/sell volume. The EA waits
for the private indicator's data response without calling tick-history retrieval
in its own order-flow path. Missing data blocks entry and prevents a complete
historical result being reported. No silent OHLC fallback.

This feature is still a preview, not a production deployment. See
`../OrderFlow/MA_ORDER_FLOW_IMPLEMENTATION.md` for validation evidence and
remaining release gates. Existing non-MaCross binaries in this folder are not
order-flow build targets.

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
- Audited trade arrows and executed-trade arrows use the fill candle on the
  displayed chart, with BUY below its low and SELL above its high. Entry lines
  start at the fill timestamp. Tooltips retain the source signal timeframe and
  bar timestamp, so an M15 signal shown on M1 cannot imply an early entry.
  Raw signal generation, fill prices, SL/TP and audit outcomes are unchanged.
- Live indicator state advances on new closed bars. Repeated ticks reuse the
  previous result, including negative results. Dashboard rebuilding is
  timer-throttled; risk and position management remain tick-driven.
- Event lookup uses binary search at the requested start; event arrays grow
  in reserved blocks. Missing MA data no longer falls back to ORB breakouts.

Match **Signal TF**, not just chart TF, to TradingView when comparing. This
EA applies execution geometry and explicitly enabled filters downstream of
the raw Pine candidate stream. All raw candidates remain visible; accepted
trades alone contribute to trade statistics. Label text is descriptive.

## Event history correction (0.12)

- History preparation and calculation visit every MA event, not one event
  per ORB day. Same-day, same-direction events have unique timestamp IDs.
- Persistent source markers survive live-position cleanup, then are replaced
  by the completed historical snapshot. Rejected candidates remain neutral
  with their rejection reason; RAW and trade counts are reported separately.
- MA execution no longer waits for an ORB opening range or enforces one entry
  per day. ORB range-ATR, opening-delay and UTC-opening controls are detached.
  Explicit user entry windows, volume/regime/FVG filters and ATR sizing remain.
- Signal TF defaults to chart TF and is still selectable. Match the listener's
  Source TF to this value. Pip SL is unchanged; non-pip base stops use the
  generating candle's high/low instead of an unrelated opening range.
- Accepted opposite signals can close/reverse within the same day. A new
  calendar day no longer discards open-position/bridge/HCBE state.
- The isolated event probe checks 12 same-day candidates and replays real
  JP225 M5 candles through preparation and trade calculation. This tests
  OHLC replay, not live fills, bridge delivery or TradingView feed parity.

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

## Audit CSV

Open TIME MATRIX and click EXPORT AUDIT CSV after the audit completes.
The exporter uses entry-time closed-bar data, never future candle values.
Feature extraction runs only on export, not during normal audit. One accepted
audit trade produces one row; OPEN and DATA remain explicit, not fake losses.
MT5 shows the full Common/Files/AuditExports output path when finished.
Source mapping and validation: `../../research/kivanc/README.md`.


## Exact Audit Acceleration (2026-10-03)

See `../../reports/audit_acceleration_20261003.md` for measured first/repeat/changed-target times and exact trade-trace comparisons. Canonical source and required headers remain in this folder. Signal/execution mathematics, strategy format, CSV schema and listeners are unchanged. In Orb-derived families, select the existing ADV engine for quote batching; the legacy path is unchanged. Sol accelerates its current tick replay. Available-history timings do not measure broker-download speed.
