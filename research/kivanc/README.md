# Kivanc source review and audit CSV contract

The 24 local Pine files under `IndicatorCodeExamples/KivancOzbilginc` were read in full, including their calculation functions, signal conditions, screener code and plotting offsets. `source_manifest.json` records their exact SHA-256 hashes and line counts. The local files supplied by the user are the reviewed versions; this is not a claim that every publication on TradingView has been reviewed.

## Implemented source families

| Local file(s) | Source calculations retained | Defaults / interpretation |
|---|---|---|
| AlphaTrend, AlphaTrend2 | SMA true range, MFI/RSI branch, trailing line, lag-2 trigger, raw crosses, alternating-event filter | Period 14, coefficient 1; tick-volume and real-volume MFI reported separately; RSI branch also exported |
| BollingerOTT | VAR basis, population standard deviation, upper/lower VAR, both trailing stops, both OTT lines | Basis 2, OTT 2, percent 10, displayed lines use `[2]` |
| followline | Bollinger breakout state, persistent follow line, trend state, flips | BB 21 / 1 sigma, Wilder ATR 5, ATR filter ON |
| HighAndLowOptimizedTrend | Rolling high/low, two VARs, HOTT/LOTT, stops and direction, price breakouts | High/low 10, VAR 2, percent 0.6, `[2]` lines |
| Laguerre | L0-L3, CU/CD, RSI and CU/CD crossings | Alpha 0.2 (gamma 0.8); plot scale 0-100 |
| MacdCrossover, MacdReloaded | VAR fast/slow, difference, VAR trigger, histogram, crossings | 12 / 26 / 9, default VAR; not a replacement with standard EMA MACD |
| MavilimScreener | Six WMA stages, final line, slope and price crosses | 3 / 5 / 8 / 13 / 21 / 34; old and default new version have the same lengths |
| MovingAverage | Default VAR, percent trailing long/short stops, MOST, direction and crossings | VAR 3, percent 2 |
| OptimizedTrend | Three VIDYA/VAR values, corrected ratio, second VAR, OTT, lagged crossing | 12.5 / 25 / 250; correcting constant 100000; OTT 2 / 0.6 |
| PmaxOnRsi | Zero-seeded WWMA gains/losses, custom RSI high/low, RSI true range and SMA, six EMA T3 stages, PMax stops and direction | RSI 14, T3 8 / 0.7, ATR 10 / multiplier 3; source `src=hl2` does not drive its custom RSI, which uses close/high/low |
| Quantitative, QuantitativeEstimation | Smoothed RSI, RSI movement, two zero-seeded WWMAs, upper/lower bands, QQES, crosses and regions | RSI 14, smoothing 5, factor 4.236; nQQE is QQE minus 50 |
| StochasticOtt, StochasticTrend | Raw stochastic, VAR smoothing, +1000 source, second VAR, OTT, lagged cross | 250 / 50 / 3 / 0.618; these two supplied files are identical |
| Stop | Long and short percentage trailing levels, exit crossings | Percent 3, unit 0; both long/short branches retained |
| SuperTrendExplorer, SuperTrendExplorerFirst40 | Regular SuperTrend bands, direction and flip | ATR 10 / 3, hl2, Wilder ATR default; differing external symbol lists are not extra current-symbol indicators |
| SuperTrendS | Regular ST, RSX recursive stages and warmup counter, confirmed pivots/support/resistance, weighted pivot center/ST, confirmed older ZigZag segment and its ST stops/direction | RSX 14 on hlc3; pivot 2+2; ZigZag 5, history 2, confirmation ON, close ON, ATR 22 / 1 |
| TillsonMa | Six EMA stages, T3, Fibonacci T3, slope/price crossings | hlcc4; 8 / 0.7 and 5 / 0.618; factor is a smoothing coefficient, not traded volume |
| TrendMagic | CCI on close, SMA true range, trailing MagicTrend, price/low/high crosses | CCI 20, ATR 5 / 1; not CCI on typical price |
| Turtle | Entry/exit channels, trend/exit lines, raw break/exit events, bars-since and entry/exit event ordering | Entry 20, exit 10; equal-level touches retained |
| TwinRange | Two double EMA ranges, filter, up/down counters, final bands, TRF branch ordering, close crossings | 27 / 1.6 and 55 / 2 |

The CSV also retains the intermediate series as `f_kiv_source_*`. These are calculated at the supplied files' defaults. The optional MA-type dropdowns are not all enumerated as separate parameter-sweep features. Display labels, colors, backtest date limits, strategy equity curves and unrelated foreign-symbol screeners are not entry features. Foreign-symbol columns would require their own historical, synchronized source feeds; broker symbols are not silently substituted for the BIST/Binance/NASDAQ lists.

## Source vs derived features

`f_kiv_source_*` and explicitly named line/state/event values follow source calculations. Names containing `derived_` are additional research transformations: slopes, close-minus-line normalized by Wilder ATR 10, direction alignment, band width and channel position. Event ages use the source event definition, updated on every closed bar, not just on bars containing trades. Raw AlphaTrend crossings are distinct from its filtered alternating signals.

The state and age fields are useful for asking whether a setup appears during an established trend, at a fresh transition, near a trailing level, inside a channel, or after a prolonged one-sided run. They do not require that the indicator itself generates the EA trade.

## Entry-time contract

All calculations are triggered by **EXPORT AUDIT CSV** in **TIME MATRIX**, after a completed audit. Normal audit only stores its already-produced trade record and exact entry trace. Indicator handles, rolling windows, MTF features and the Kivanc history replay start on export.

One row corresponds to one accepted audit trade record, including closed and OPEN records. DATA records retained by the audit are exported as DATA with no invented win/loss or PnL. Rejected setups/capacity/quota blocks do not become extra trades. The row count must equal the audit's trade total. An empty completed audit exports a header with zero trade rows.

The cutoff is the simulator's captured entry time. If unavailable, `entry_time_basis` identifies that limitation and the scheduled availability time is used. Technical features use only bars whose `bar_open + timeframe_seconds <= cutoff`. For example, an entry at 10:05 cannot use the eventual high/low/close of the 10:05 M5 bar. Regime and cached NAS information must have become available no later than the entry cutoff. `feature_last_closed_bar`, timeframe staleness fields, seed time, seed bar count and status expose timing and coverage.

Recursive calculations start from the oldest locally available source-timeframe bar once per export and proceed chronologically. Trade cutoffs are sorted, then sampled as that replay reaches them. Future bars cannot affect an earlier sample. `SEEDED_LOCAL_HISTORY` means at least 500 preceding bars were processed; it is not a claim that MT5 and TradingView have identical history starts or quotes. `WARMUP` identifies shorter history. `[2]` OTT delays are retained. Pivot information becomes available two bars after the pivot, not on the negatively-offset plotted candle. The mutable latest ZigZag leg does not enter confirmed-level features.

## Data provenance and training

- `label_*` columns contain post-entry outcomes and must be excluded from the prediction feature matrix. Outcome, exit time, holding duration, realized PnL, exit price and reported cost are targets/diagnostics.
- `entry_spread_points` is the captured bid/ask difference when the audit used exact ticks. A bar-model status is explicit where that quote is absent. Bar spread is an OHLC feed field, not a fabricated quote.
- Historical simulations cannot measure a real order's slippage. The measured-slippage value stays blank with `NOT_MEASURED_HISTORICAL_SIMULATION` status. Simulator configuration fields are recorded separately.
- `label_cost_r_reported` retains the existing engine's cost field. It is not universally an independently measured all-in spread-plus-commission-plus-slippage total.
- Tick-volume MFI/AlphaTrend and candle-direction volume calculations are named proxies. Real volume zero is not proof that there was zero exchange trading. Real-volume MFI remains missing without usable volume.
- OF cache values are labeled quote proxies, not exchange aggressor/L2/L3 data. Missing/off/evicted cached NAS/OF values have explicit status and are not replaced with invented zeros.
- Missing indicator history or unready buffers are blank/status-marked. Buffer preparation is bounded; an absent feature must not silently acquire a numerical zero.
- More features increase model-selection risk. Use causal time splits with purge/embargo, fit transformations/feature selection on training folds only, and report untouched holdout results. No new model is trained or promoted by this export change.

Files are written to `Terminal Common Data/Files/AuditExports`. The terminal prints and displays the full local path. UTF-8 CSV uses RFC4180 quoting. A `.partial` becomes a final `.csv` only after completion. Changing/restarting the audit cancels an active export to avoid mixing settings/results. The progress line shows processed feature bars, then written trade rows.

## Validation scope

The MQL fixture and independent Python batch reference compare source equations on the same 700 synthetic OHLC bars. This tests numerical translation and initialization, not broker-feed equivalence with TradingView. A separate EA probe tests real chart events, feature replay, row count, CSV schema and unmodified fixture PnL. Production EA compile logs and test outcomes are recorded in `validation.json` after final checks.

MPL-2.0 attribution is retained for adaptations of sources declaring that license. Other authors named by the supplied files are credited in the implementation. The source manifest does not assert an additional redistribution license for files without a license declaration.
