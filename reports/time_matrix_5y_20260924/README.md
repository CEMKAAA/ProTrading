# Five-year audit baseline (24 September 2026)

These are frozen research outputs, not a live EA result cache. Keep the trade-level CSVs together with the summaries; a summary row alone is insufficient for a correct rolling-window update.

| EA | Saved strategies audited | Exact closed/open coverage | Unavailable or short coverage | Exploratory 3Y/2Y candidates |
| --- | ---: | ---: | ---: | ---: |
| ORB | 57 | 56 / 1 | 0 | 31 |
| MaCross | 36 | 8 / 22 | 6 | 4 |
| SolAdvanced | 22 | 15 / 6 | 1 | 1 |

The audit window is 260 weeks (1,820 days), not five calendar years. Candidate hours use the first 156 weeks, at least 10 resolved trades per day-hour bucket, and a minimum win rate of `ceil(100 / (1 + target_R))` percent. The chosen hours are frozen for the full-window rerun; a candidate also needs positive full-window and final-104-week closed R, at least 30 final-period closed trades, and no unresolved selected trade. This is an exploratory holdout, not evidence that the result will persist live. Selection across many strategies/hours still creates multiple-testing risk.

## Rolling update contract

An exact update at a later date must append newly available days **and drop days leaving the 1,820-day window**. Re-evaluate every trade that was open at the previous anchor and every trade whose outcome can depend on new signals or the boundary. A saved result is reusable only when the strategy definition, source version, broker symbol/specification, execution costs, clock settings and historical price/tick data relevant to that result remain unchanged. Otherwise perform a full audit. Never classify an unresolved trade as a win or loss to make the cache fit.

The CSVs here preserve per-trade results for that future updater. They do **not** contain all signal geometry, source/data fingerprints or carry state needed to make the current EA dashboard's 5Y audit incremental. In particular, ORB/MaCross ledgers omit exit timestamps and geometry; SolAdvanced ledgers omit geometry and a unique signal ID (several signals share one timestamp). A user-facing `5Y CACHE ON` switch cannot safely use these CSVs as a substitute for a current audit. The dashboard still runs its ordinary audit when asked; it must not present this frozen snapshot as a current 5Y result. Do not enable a cache toggle against these files until an exact delta-replay path and full-vs-incremental parity test exist for all three EA engines.

To implement the switch: (1) export a versioned per-signal record including stable signal ID, available/entry/exit time, geometry, exact outcome, causal close reason, and any open carry state; (2) fingerprint source, complete strategy settings, broker symbol costs/specification, and the historical bars/ticks used; (3) on a new day retain only immutable closed records still inside the rolling window, replay unresolved and overlapping boundary cases, compute only new signal days with adequate indicator warmup, then recompute all aggregate metrics in event order; (4) rederive 3Y training picks and rerun the filtered branch when its training boundary moves; (5) run both full and incremental modes at multiple synthetic future anchors and require identical signals, W/L/O, PnL, drawdown, chart arrows and exit reasons. On any mismatch or missing fingerprint, fail closed to the full audit and label the reason.

The older `soladvanced_jp225_*` lowercase files are legacy exploratory output and are intentionally excluded from the current generated leaderboard. Two `JP225s` SolAdvanced strategies could not be audited against the available `JP225m` symbol and are not represented as 5Y results.
