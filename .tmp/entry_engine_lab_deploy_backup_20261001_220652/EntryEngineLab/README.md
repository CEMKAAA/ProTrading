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

| Engine | ATR Period | SL / ATR | TP / ATR | Cooldown Candles | Hold Limit |
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

Engine 05 uses the supplied **0.6 ATR alternative**, not a moving middle-band
TP. Candle counts use actual completed bars, not presumed continuous market
minutes. Engine 07's 12 minutes is elapsed time; during a closure the exit
can execute only on the next available quote.

`ENTRY BUILDER > POLICY` edits Wilder ATR period, SL/TP multipliers, cooldown,
maximum candles and maximum minutes. `APPLY TO ENGINE DRAFT` commits the
current edit fields; PREVIEW evaluates without saving, SAVE ENGINE writes
the definition. Select the saved engine to activate it. `ENG ATR / POLICY`
in the inherited SL row opens the same controls; the old pip value is not
used while engine policy is ON.

ATR is frozen at the setup candle's close. Geometry is applied relative to
the executable bid/ask fill, rounded to the instrument tick size. Distances
that round to fewer than two ticks are rejected, never silently widened.
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
