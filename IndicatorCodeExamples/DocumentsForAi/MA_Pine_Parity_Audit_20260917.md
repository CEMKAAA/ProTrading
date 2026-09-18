# MA / Pine parity audit

## Verdict

The five default signal kernels match the independent equation transcription
on the tested identical-OHLC fixtures. This is NOT proof that the complete EA
is identical to TradingView, all Pine input combinations, or Pine execution.
No MA production mathematics was changed in this review.

Sources: `MaCrossOver.pine`, `Crossover2.pine`, and
`macrossover_orb/MaCrossPineStream.mqh`, `MaCrossSignalCore.mqh`,
`MaCrossAuditCache.mqh`, `MaCrossOverOrbEA.mq5`.

## Findings requiring an explicit boundary

1. **Execution is intentionally different.** `MaCrossOver.pine:365` uses
   `strategy.entry`; its management block at lines 375-470 implements percent
   or ATR exits, Basic/BreakEven/Partial+BE/Advanced management. Our EA retains
   ORB sizing, pip SL, target legs, HCBE and its chosen exit engine. Pine ATR
   levels are recalculated from the current ATR; that is not automatically
   equivalent to a fixed entry-time stop. Identical entries do not imply
   identical W/L or PnL. Crossover2 is an indicator, not an execution strategy;
   its label text alone defines no broker fills or order-management algorithm.
2. **MTF realtime semantics differ.** Pine `request.security(...lookahead_off)`
   may expose the developing H4 value in realtime. Our kernel consumes only a
   completed H4 candle. Keep this causal protection; do not silently restore
   repainting to make a screenshot match. Historical H4 merge alignment also
   requires identical feed sessions and history origin.
3. **Input parity is limited.** Pine's HTF timeframe/length are adjustable;
   our wrapper fixes them at H4/200. The default is covered, arbitrary Pine
   HTF choices are not. Non-default odd HMA lengths and exact Pine internal
   rounding need a TradingView numerical export before claiming full parity.
4. **Trendline simultaneous-event edge.** Pine uses two independent `if`
   statements for Buy Now and Sell Now; the EA returns one integer direction
   and gives buy precedence through `if/else if`. The fixture had no divergence,
   but a dual-crossing case is not represented as two events. No unrequested
   execution policy change was made to resolve this ambiguity.
5. **Closed-bar input must stay true.** The MA kernel always reads bar 1.
   The inherited `InpUseClosedBarBreakout=false` nevertheless changes
   `OrbSignalAvailableTime`. That combination is not a faithful intrabar Pine
   mode. Use true; a later cleanup should remove/pin this inherited option.
6. **Filters alter trades, not source equations.** Regime/volume/FVG/entry
   windows, one-active-position policy and optional delayed-entry engines can
   reduce accepted trades. RAW source arrows and executable trades must not
   be conflated. BREAK/RETEST/IMB1M are execution adapters, not three Pine kernels.

## Equation-by-equation comparison

### 0: MA MTF

Pine lines 278-298, 350-369. EMA recurrence uses alpha=2/(n+1), seeded at the
first close. Default EMA9/EMA27 and local HMA200 are used. HMA is
WMA(2*WMA(close,n/2)-WMA(close,n),sqrt(n)). Pair mapping:
Fast=EMA9/EMA27; Medium=EMA9/HMA200; Slow=EMA27/HMA200.
Buy: A>B and previous A<=previous B, with close above HTF HMA200.
Sell: inverse inequalities, with close below HTF HMA200.
All three pairs are now included in the test. HTF caveat above applies.

### 1: EMA50/200

Crossover2 lines 342-349. EMA50 crosses EMA200 using strict current and
inclusive previous inequalities. The displayed rising/falling color is NOT
an additional entry condition. The EA correctly does not add that condition.

### 2: Trendline Buy Now / Sell Now

Crossover2 lines 119-169. Confirmed pivots have 24 left and 24 right bars.
Slope = Wilder ATR24 / 24 * 1.6. A new pivot resets the corresponding line;
otherwise its line advances by the stored slope. Crossings use the projected
threshold upper-slope*24 or lower+slope*24, including its previous value.
The earlier backplotted Buy OK/Sell OK marks are NOT these causal entries.
Pine deletes older labels; the EA intentionally retains its historical audit
markers. Dual-crossing edge is listed above.

### 3: Close/Reverse (Pivot SuperTrend)

Crossover2 lines 293-332. Pivot width=2, ATR length=10, factor=3.
Center=(2*previousCenter+newPivot)/3; the first pivot seeds center. When both
pivots occur, the high has precedence, matching Pine's ternary expression.
Up=center-3*ATR; Down=center+3*ATR. Bands trail according to previous close.
Trend uses previous bands, with +1 fallback; only a trend flip emits a signal.
The absolute marker is Trailingsl, NOT a fill price or necessarily candle low.
This is the large "Close Short Order / Go to Long Now" label family.

### 4: Scalp arrows

Crossover2 lines 618-686. Heikin-Ashi close=OHLC/4; HA open recursively uses
previous HA open/close. EMA12/EMA200 and PAC EMA34 on HA high/low/close define
trend. PAC crossing must occur within 3 bars of crossing its center. State
resets on the center crossing and emits only a 0 -> +/-1 transition. It is
not the large Close/Reverse label family. HA seed/session alignment still
requires the same data and origin. Default DelayArrow=false is covered.

## Verification actually performed

- MT5 kernel assertions: 12,483 passed, zero failures.
- Independent Python equation transcription: **84,000 decisions**, zero
  mismatches (5 modes plus Medium/Slow MTF pair cases, 12,000 bars each).
- Signal counts in fixture order 0,1,2,3,4,MTF-Medium,MTF-Slow:
  26,149,188,149,101,8,4. These are test data, not strategy performance.
- Existing event-history integration: 65 checks passed; real JP225 fixture
  produced 61 raw signals / 61 trades / zero DATA outcomes.
- EA and probes compile with zero errors and warnings.
- The independent test harness initially still allocated five output arrays;
  it was corrected to seven and rerun successfully. No kernel change was needed.

Reports: `logs/macross_pine_stream`. Reproduce with
`scripts/validate_macross_pine_stream.ps1`.

## What is still needed for literal TradingView parity

Export OHLC plus all five Pine signal booleans, H4 merged HMA, pivot bands and
HA series from TradingView. Compare UTC timestamps and prices against the
same imported dataset, including equal-pivot ties, initial warmup, session
gaps, non-default lengths and simultaneous trendline crossings. Then compare
orders separately with identical costs and management. This review did not
access the user's TradingView chart and must not be presented as that test.
