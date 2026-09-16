# MA Crossover EA

Compile `MaCrossOverEA.mq5`, not an individual `.mqh`. All six source files and
the compiled `.ex5` are supplied together in this directory. Root-level files
are canonical; `scripts/validate_macrossover.ps1` refreshes this grouped copy.

## Use

1. Attach to the desired symbol/timeframe. Native execution starts OFF.
2. Set EMA/HMA lengths and crossover pair. The starting values are EMA9,
   EMA27, HMA200 and a confirmed H4 HMA200 trend filter.
3. Choose PERCENT SL/TP, ATR SL + R, or PIP SL + R. Set fields and APPLY ALL.
4. Optional filters: six production ORB/Liq macro regime buckets, tick volume
   versus the prior 20-bar average, ADX minimum 0-100, confirmed RSI divergence,
   ATR percentage range, recent directional FVG and body/ATR displacement.
5. STRATEGIES opens the initially empty library. Apply the fields, enter a name,
   SAVE CURRENT SETTINGS. Clicking a saved row applies it. Search and favorites
   are available. Profiles are specific to the exact broker symbol and chart TF.
6. To test native trading, use a hedging demo account, set
   `InpAllowNativeTrading=true`, then click EA ON after history is ready.
   Use a different positive `InpMagic` for every concurrently trading instance.
   EA OFF blocks new entries but does not abandon management of owned positions.

Strategy files are stored in Terminal Common Files / `MaCrossOverStrategies`.
All dashboard signal/filter/geometry values are saved. Account risk, fee,
broker-time offset, magic and other execution Inputs are deliberately not
copied with a strategy. Risk uses this MT5 account's balance, or the fixed
reference capital when `InpFixedRiskCapital>0`. Broker volume steps are rounded
down. Gaps and slippage mean monetary loss cannot be guaranteed to equal budget.

## Audit

- Historical execution uses M1 bid OHLC and recorded spread, not tick history.
- SL/TP ambiguity in one M1 candle, unknown spread and missing M1 intervals are
  DATA, never fabricated wins/losses. DATA is excluded from reported WR/PnL.
- W/L uses realized net R; reverse exits use their actual exit price. Partials
  contribute proportionally, not a full target R. Open trades are O.
- An optional round-trip notional commission assumption is deducted. It defaults
  to zero; supply realistic broker costs before evaluating performance.
- MinCum and peak-to-trough closed-trade DD are shown. They do not measure
  intratrade equity or an account-wide prop-firm trailing drawdown rule.
- The first build loads up to `InpAuditYears` (default 5). 2W through 5Y buttons
  then slice cached trades by entry time without re-running the simulator.
  Changing strategy settings invalidates the cache. Restart rebuilds it.
- Short windows are cohorts of the broad replay, not separate simulations
  started flat at each window boundary. This avoids silently changing trade
  ownership at every window selection.
- Broker history coverage is reported; this EA cannot manufacture unavailable
  five-year history. REFRESH DATA explicitly rebuilds after history corrections.
- Broker GMT offset is explicit and fixed. A broker with historical DST changes
  needs an offset schedule before historical GMT-window results can be exact.

## Scope and differences from Pine

This is a separate, compact implementation, not a copy of the entire ORB EA.
It reuses the existing regime classifier unchanged and adds a separate replay,
dashboard and strategy store. Existing production EAs/listeners are not modified.

The EMA/HMA crossover formula is ported from `MaCrossOver.pine` by yigdeli
(MPL-2.0, https://mozilla.org/MPL/2.0/). There are deliberate execution adaptations:

- Only completed HTF bars are used to avoid forming-HTF repainting. Pine's
  unconfirmed HTF `request.security` values can differ in realtime.
- ATR stop/target distances are frozen when a trade starts instead of moving
  every bar with ATR. BE/partial/trailing triggers use completed chart bars.
- Native initial SL/TP protection is submitted with the order. Fills, spread,
  volume rounding and rejected modifications can differ from replay estimates.
- Added FVG is a recent directional gap-presence filter, not ORB's breakout
  session or a new FVG retest entry rule. RSI divergence is confirmed with a
  left/right pivot, so it cannot predict the exact market top or bottom.
- Pine's separate ten-symbol screener and decorative MA ribbons are not ported.
- ML, prop-firm account guards and cTrader/NinjaTrader/Quantower/MT5 listener
  publication are NOT included. Do not attach existing ORB listeners expecting
  signals from this EA. That integration remains separate work.

Therefore neither identical TradingView backtest results nor complete ORB
feature parity is claimed. Automated no-order tests cover core mathematics,
causality, actual-R exits, UI apply/modal behavior and window reuse. Live broker
fills and restart/reconnect scenarios still require demo forward validation.
