# Entry Engine Lab

Canonical source: `EntryEngineLabEA.mq5` in this folder. This fourth EA is
an isolated copy of MaCross, not a replacement for the existing three EAs.
Its existing execution, audit, NAS, order-flow, time-matrix and CSV features
remain. Research results from the original strategy library are not imported.

## Controls

- `ENGINE` opens a searchable list of all six built-in modes, ten scalper
  templates (01-10), and saved custom engines. Templates are builder rules,
  not ten separate hard-coded signal kernels. Same-name saved engines override
  their templates without silently replacing user edits.
- Empty/whitespace search shows all choices. Engine pages contain ten rows;
  use `>` for the remaining six default engines. Feature pages expose all 44
  choices, plus CONSTANT for a right operand. Searches ignore case and leading
  or trailing whitespace. No matches are explicitly identified.
- `ENTRY BUILDER` edits separate BUY, SELL, LONG EXIT and SHORT EXIT
  conditions with `+ LOGIC`.
- Each row has a left feature/period, comparator, right feature/period or
  constant threshold, AND/OR/XOR join and optional NOT.
- For example: `EMA(period=250) Cross above SMA(period=50)` AND `RSI(14)>50`.
- Feature selection is searchable. EMA, SMA, RSI, ATR, Wilder ADX and HMA have
  configurable periods. The catalog has 44 features: 32 fixed features plus
  parameterized indicators, Bollinger bands (population SD, 1.5 multiplier),
  prior-period highs/lows excluding the current candle, and body/ATR.
- `APPLY + AUDIT PREVIEW` uses the current audit window and existing filters
  without saving the engine. New native/bridge entries and new signal-driven
  exit management are blocked during preview. Broker-held SL/TP orders and
  the EA's other existing position management are not cancelled or frozen.
- `SAVE ENGINE` creates or updates that name. Select the saved engine from
  ENGINES to leave preview and use it normally, subject to NAT/PUB settings.
- The ordinary strategy save/load includes an immutable copy of its engine
  rules, even if a same-named engine is later edited.

## Semantics

In INDEPENDENT mode, MAX SERIES now means the **total simultaneously open
instance-owned native positions (BUY + SELL)**, not consecutive signals or a
separate allowance per direction. Closing a position releases one slot; changing
signal direction does not reset capacity. `OPEN n/max` beside APPLY EXIT follows
the live position book, independently of the historical audit's O count.
Changing the edit field alone does not change the applied limit: use APPLY.
A new limit below current live exposure is rejected, not implemented by forced
liquidation. Existing Independent audit metrics are invalidated because the old
series-based admission semantics were incorrect for this requested behavior.
Legacy admission behavior is unchanged.

Rules use completed candles only. Logic folds left to right: `((A OR B) AND C)`.
NOT applies to a single condition. Missing warm-up values remain unknown,
including under NOT; they are not invented zeros. Both sides true means no
entry. The default trigger is false-to-true; `EVERY BAR` is selectable.

## Ten Scalper Templates

All ten evaluate every completed M1 candle. Selecting an engine with its
policy ON sets M1, LEGACY single position, BREAK entry, fixed target, HC/BE
OFF and MA reverse exit OFF. Other user filters (NAS, regimes, OF, Time Matrix,
daily limits, inversion) remain as selected; disable them to isolate a recipe.
NAT/PUB are never enabled automatically. Original six engines are unchanged.

As of 1.06, the dashboard may switch these engines to INDEPENDENT after
selection. MAX SERIES limits total simultaneously open instance-owned native
positions. Completed exits free slots; future simulated exits never start
cooldown early. Native multi-position execution still requires a hedging account
and PUB OFF. Legacy remains the default on initial engine selection.

The ENGINES picker has an ENGINE EXITS ON/OFF button for the current custom
policy engine. OFF disables only LAB_RULE_EXIT and LAB_TIME_EXIT (maximum
bars/minutes). SL/TP, NAS and MA reverse exits are unaffected, as is entry
cooldown. The setting is included in engine/strategy snapshots and audit
cache identity. Old LAB2/LAB3/LAB4 definitions load with engine exits ON.

Original recipe metadata below defines the default target ratio (TP/SL) only.
As of 1.05, these ATR coefficients do NOT set executable SL/TP distances.
SL uses the applied pip input and subsequent R-picker changes take precedence.

| Engine | Original ATR Period | Original SL / ATR | Original TP / ATR | Cooldown Candles | Hold Limit |
| --- | ---: | ---: | ---: | ---: | --- |
| 01 Slow EMA + ADX | 14 | 0.90 | 1.20 | 5 | None |
| 02 EMA Pullback | 14 | 0.70 | 0.90 | 3 | None |
| 03 RSI 50-Line | 14 | 0.65 | 0.80 | 2 | RSI7 <48 long / >52 short |
| 04 Fast EMA + RSI | 14 | 0.55 | 0.70 | 1 | 10 candles |
| 05 Bollinger Reversion | 14 | 0.50 | 0.60 | 1 | None |
| 06 ATR Micro-Breakout | 14 | 0.45 | 0.55 | 1 | 8 candles |
| 07 EMA + RSI Re-Entry | 14 | 0.55 | 0.70 | 1 | 12 elapsed minutes |
| 08 Ultra-Fast EMA State | 10 | 0.35 | 0.40 | 0 | 6 candles or EMA3/8 reverse |
| 09 Candle Momentum | 10 | 0.30 | 0.35 | 0 | 4 candles |
| 10 Directional Flip | 7 | 0.20 | 0.25 | 0 | 3 candles |

Engine 05's default R is 0.6/0.5, not a moving middle-band
TP. Candle counts use actual completed bars, not presumed continuous market
minutes. Engine 07's 12 minutes is elapsed time; during a closure the exit
can execute only on the next available quote.

`ENTRY BUILDER > POLICY` edits SL pips, the engine's default target R, cooldown,
maximum candles and maximum minutes. `APPLY TO ENGINE DRAFT` commits the
current edit fields; PREVIEW evaluates without saving, SAVE ENGINE writes
the definition. Select the saved engine to activate it.

The pip SL input has no application-level upper ceiling (release 1.10).
This also applies to the ordinary dashboard pip SL and strategy save/load.
Broker-valid price geometry, available margin and native risk guards still apply.

Policy engines now use **PIP ON only**. Enter the stop distance and click APPLY.
The separate ATR geometry branch and forced engine-ratio target are removed.
Use the ordinary R picker to change the actual target: SL=10 pips and R=0.5
means TP is about 5 pips, subject to tick-size rounding. Engine time/rule exits
can still close a trade before its target. Pip changes invalidate the audit.

Strategies store the pip input, selected R and exit policy. LAB4 engine pip
values are imported when selecting that engine; old LAB2/LAB3 policy definitions
use the existing standard pip setting instead of ATR geometry. Old ATR audit
results are intentionally not preserved. ATR features in entry conditions
remain available; only ATR-based trade sizing was removed.

Geometry is applied relative to the executable bid/ask fill and rounded to the
instrument tick size. Unplaceable stops/targets are not silently enlarged.
Stops already inside the executable quote's spread are also rejected.
Live orders must additionally satisfy the current broker stop/freeze limits;
historical quote tests cannot reconstruct a broker's historical stop-limit
changes. A signal is not a promise of a fill. Frequency targets in the supplied
recipes are design targets, not guarantees or measured results.

Cooldown is the number of actual candle boundaries from the previous exit
to a candidate's availability; zero permits the next eligible closed-bar
event, not repeated orders on every tick of the same candle. Existing owned
positions/plans prevent switching to a different live policy.

These policy engines are **MT5-native only: PUB OFF, NAT ON**. No listener
compatibility is claimed for their new rule/time exits. The entry boundary
refuses publication rather than silently dropping required exit instructions.
Audit exits use real quote fills and signed price PnL less configured costs;
missing tick coverage remains DATA, not an invented OHLC exact exit. Market
breaks extend the existing replay search rather than fabricate a missing loss.

For policy engines, a window substantially preceding the first broker quote
now reports TICK HISTORY UNAVAILABLE with the requested start and first quote
date. It does not publish misleading zero W/L results or train/cache incomplete
metrics. Re-selecting a window rechecks coverage. Candle history alone cannot
prove exact quote fills or intrabar exit ordering. On the 2026-10-01 EURUSDm
probe, 2024/2025 ranges returned zero ticks; the first quote was 2026-01-01
22:05. This is a broker-data limitation, not a completed 1Y/2Y audit.
Old LAB2 definitions keep policy OFF and their previous serialization/results.
Strategy snapshots include all entry, exit and policy rules.

FVG predicates refer to the newest previously formed, unfilled three-bar gap
per direction. They do not enumerate all historical zones. Hour/weekday
features use the signal candle's broker timestamp. There is no automatic
access to every exported CSV column: the builder's live-causal feature catalog
is explicit and separately extendable.

Limits: 4096 rules per direction, periods 1-5000, 64 distinct parameterized
indicator/period pairs and 1024 saved engines. Large rule sets need a separate
performance benchmark; this is not an unlimited-memory promise.

## Native Margin And Minimum SL Panel (1.09)

The lower part of the right STRATEGIES panel contains BALANCE (0=ACCOUNT)
and APPLY BAL. This is percentage-risk reference capital in account currency,
not a deposit or a replacement for broker free margin. A reference of 30 and
1% risk requests 0.30 of SL risk, subject to native risk/volume constraints.
Zero restores the account-based risk budget.

Above the balance inputs, GEREKLI TEMINAT shows standalone BUY and SELL
margin in account currency. MIN LOT separately shows the broker minimum-volume
margin, even when PIP SL is off. Applied pip distance and the existing CalculateLot
helper determine volume. The native OrderCalcMargin API uses connected broker
specifications; leverage is not hardcoded to 1:500. Hover for lot, SL risk,
risk budget, account leverage and actual free margin. Orange indicates a
minimum/step-volume risk overrun or insufficient free margin; N/A indicates
  missing live quotes, connection, valid pip geometry or broker calculation.

This is an estimate before ATR/portfolio/entry caps, not a fee or guaranteed
order acceptance or minimum safe account equity. Fees, spread and a stop-out
buffer are additional considerations. Existing exposure, fill prices and broker margin changes
can alter requirements. It does not load history or submit orders. Unapplied
SL edits do not alter the preview; APPLY commits the distance. Signal kernels,
tick audit mathematics, publisher contracts and strategy definitions are
unchanged by this display-only feature.

MIN LOT SL KAYBI shows the broker minimum lot's BUY/SELL cash price loss at
the applied pip SL via OrderCalcProfit. RISK BAKIYESI shows the reference
capital needed for that loss at the applied risk percent (loss / fraction),
rounded upwards to cents. This is not a safe deposit recommendation; margin,
fees, slippage, exposure and a stop-out buffer are separate considerations.
Both rows are N/A without a valid applied pip geometry. No history is loaded
and no balances or sizing settings are changed by these display calculations.

## Isolation And Verification

Default magic: `11026004`; chart prefix: `ENTRYLAB_`.
Engine files: MT5 Common Files `EntryEngineLabEngines`.
Strategies: MT5 Common Files `EntryEngineLabStrategyLibrary`.
Publisher paths and event IDs have a separate EntryEngineLab namespace.
No new listener has been implemented or live-verified for this family.
Independent-mode publisher restrictions inherited from MaCross still apply.

Run `scripts/validate_entry_engine_lab.ps1`: compile 0 errors/0 warnings,
logic truth tables, missing-value semantics, parameterized EMA/SMA crosses,
MT5 RSI/ADX/SMA comparison, modal event handling, engine/strategy save-load,
preview entry prevention, shared live/history kernel, and warm-versus-cold
audit comparison. The six built-in kernels are compared with a test-only copy
extracted from the unmodified MaCross source. This does not substitute for
forward execution, live listener testing or visual QA on every screen size.

`scripts/validate_entry_engine_lab.ps1 -UiOnly` runs the focused picker
regression without market-data audits. It checks empty search, all engine and
feature pages, search clearing, operand selection, and unscaled modal geometry.
UI-only success does not replace a full verified release stage.

`-OfflineHistory` validates a frozen local dataset only. It never changes
production synchronization guards or tick fill/outcome calculations.

`-PipOnly` keeps the kernel/formula, UI, pip geometry, strategy restore,
exit parity and capacity checks, but skips repeating the ten-engine ATR
audit campaign. See VERIFICATION.md for full and focused release evidence.


## Exact Audit Acceleration (2026-10-03)

See `../../reports/audit_acceleration_20261003.md` for measured first/repeat/changed-target times and exact trade-trace comparisons. Canonical source and required headers remain in this folder. Signal/execution mathematics, strategy format, CSV schema and listeners are unchanged. In Orb-derived families, select the existing ADV engine for quote batching; the legacy path is unchanged. Sol accelerates its current tick replay. Available-history timings do not measure broker-download speed.

## Native Position Visuals (1.12)

Independent positions have separate entry/SL/TP segments keyed by MT5 position
identifier, including simultaneous fills. Native closed-position arrows use
actual net deal profit plus swap, commission and fee: green for positive, red
for negative, neutral for flat. OPEN markers are gold, not a profit assertion.
Closed geometry remains readable until the next owned native entry, capped
at 20 chart candles; a fast close does not collapse its reference lines.
Native and historical caps use chart TF, not signal TF. This visual width
does not change actual fill or exit timestamps. An exit X marks the actual
final deal price. Simultaneous fills can share the same visual time group.

Attach/restart restores owned native executions from account history within
the selected audit window. Archived levels require available original order
SL/TP or an existing native plan; unavailable levels are not fabricated.
Native visuals do not change simulated audit results, trading rules, risk,
strategy files or listeners. Run `scripts/validate_entrylab_native_visuals.ps1`
for the focused read-only native-history and chart-object regression. See
`../../reports/entrylab_native_visuals_20261004.md` for verification scope.

## Independent Owner Recovery (1.13)

A new chart ID changes the chart-scoped magic. Independent startup/apply now
recovers one unambiguous orphan EntryLab owner on the same account/server,
symbol and input-magic family. Its original valid Independent state must
exist and its exclusive state lock must be available. Active owners are
never taken over; multiple orphan candidates fail closed without choosing
one arbitrarily. Recovery retries briefly after attach for delayed account
synchronization. Saved owner magics use exact split 64-bit values, not a
lossy terminal double. The binding is instance-local, not a strategy field.

The native OPEN counter and entry capacity include recovered plus current
positions. Existing native TP/SL and position identifiers are unchanged;
new entries retain the current chart's magic. The counter tooltip names the
recovered owner. Historical audit O counts remain simulated open positions,
not a claim about actual account positions. See
`../../reports/entrylab_native_recovery_20261004.md` for focused verification.
