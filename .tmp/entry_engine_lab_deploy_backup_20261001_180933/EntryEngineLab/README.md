# Entry Engine Lab

Canonical source: `EntryEngineLabEA.mq5` in this folder. This fourth EA is
an isolated copy of MaCross, not a replacement for the existing three EAs.
Its existing execution, audit, NAS, order-flow, time-matrix and CSV features
remain. Research results from the original strategy library are not imported.

## Controls

- `ENGINES` opens a searchable list of all six built-in modes and saved engines.
- `ENTRY BUILDER` edits separate BUY and SELL conditions with `+ LOGIC`.
- Each row has a left feature/period, comparator, right feature/period or
  constant threshold, AND/OR/XOR join and optional NOT.
- For example: `EMA(period=250) Cross above SMA(period=50)` AND `RSI(14)>50`.
- Feature selection is searchable. EMA, SMA, RSI, ATR, Wilder ADX and HMA have
  configurable periods. There are also 32 fixed features, including candles,
  volume ratios, EMA states and bullish/bearish FVG contact/inside states.
- `APPLY + AUDIT PREVIEW` uses the current audit window and existing filters
  without saving the engine. New native/bridge entries and new signal-driven
  exit management are blocked during preview. Broker-held SL/TP orders and
  the EA's other existing position management are not cancelled or frozen.
- `SAVE ENGINE` creates or updates that name. Select the saved engine from
  ENGINES to leave preview and use it normally, subject to NAT/PUB settings.
- The ordinary strategy save/load includes an immutable copy of its engine
  rules, even if a same-named engine is later edited.

## Semantics

Rules use completed candles only. Logic folds left to right: `((A OR B) AND C)`.
NOT applies to a single condition. Missing warm-up values remain unknown,
including under NOT; they are not invented zeros. Both sides true means no
entry. The default trigger is false-to-true; `EVERY BAR` is selectable.

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

`-OfflineHistory` validates a frozen local dataset only. It never changes
production synchronization guards or tick fill/outcome calculations.
