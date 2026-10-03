# EntryLab Native Position Visuals

Date: 2026-10-04. Build: `EntryEngineLab-1.12-NativeVisuals`.

## Root Causes

- The inherited live-level renderer intentionally kept only the newest
  position's fixed entry/SL/TP set. That is unsuitable for Independent mode.
- Accepted setup arrows were green BUY/red SELL direction markers; broker
  close transactions did not update them to net-result colors.
- Native execution markers used client timestamps rather than a unique broker
  position identifier. Actual closed geometry was not restored from history.

## Changes

- `IndicatorCodeExamples/entry_engine_lab/EntryEngineLabEA.mq5`: native visual
  callbacks, history restoration, all-position Independent rendering and build.
- `IndicatorCodeExamples/entry_engine_lab/MaIndependentEntries.mqh`: refresh
  owned native visuals after confirmed fill instead of a timestamp-keyed mark.
- `IndicatorCodeExamples/entry_engine_lab/LabNativeTradeVisuals.mqh`: per-position
  geometry, net-result colors, actual final-exit marker and bounded history queue.
- Matching `EntryEngineLabEA.ex5` rebuilt; README updated.
- `tests/mql5/EntryLabNativeVisualProbe.mq5` and
  `scripts/validate_entrylab_native_visuals.ps1`: focused regression.

There are no signal, entry, exit, geometry, risk, simulated audit, strategy,
CSV schema or listener mathematics changes. Other EA families are unchanged.

## Verification

Final production compile: **0 errors, 0 warnings** (79,281 ms).
Probe compile: **0 errors, 0 warnings** (3,394 ms).
Probe result: **62 checks, 0 failures**.

Synthetic chart-object checks include concurrent positions with identical fill
timestamps, foreign-position exclusion, separate numeric levels, profitable
SELL recoloring, one-candle minimum width, closed-visual retention, flat result,
and positive gross profit becoming a red result when total costs exceed it.

Read-only broker history: Exness-MT5Trial15, BTCUSDm, the user's runtime magic
`4000011026004262155`. Restored 21 owned identifiers: **11 closed positive
positions and 10 still-open positions**. All closed positions retained their
separate geometry and positive result color; all open positions had separate
entry/SL/TP objects. This probe submitted no orders and closed no positions.

Four SELL positions closed by broker TP at server time 2026-10-03 21:05:18
(2026-10-04 00:05:18 Istanbul). Actual net results: +15.13, +15.19, +14.13,
and +14.36 account-currency units. The reported examples therefore include
confirmed profitable broker closes, not evidence that those TP orders failed.

The runner reuses one existing worker and fixed small logs/configuration; it
does not clone terminal/history trees or initiate multi-year tick downloads.

## Scope And Limitations

- Net color uses actual trading-deal profit + swap + commission + fee, not a
  promised target R. Separate balance-only charges cannot be attributed to a
  position without a broker-provided link.
- Original archived SL/TP must exist in native order history or an existing
  position plan; missing values are not invented. Later stop modifications
  are not reconstructed as a full time-varying stop history.
- A partial close is not marked as a final WIN/LOSS while exposure remains.
- Native fill markers correspond to actual broker execution, which can differ
  from the originating closed signal candle. This does not shift audit entries.
- Tests cover chart-object properties and this account's history, not visual
  screenshots on every chart layout or a newly submitted forward order.

## Deployment

Target: `C:\MT5\DEMO\MQL5\Experts\EntryEngineLab`.
Completed with DEMO closed: rebuilt main `.mq5`/`.ex5`, changed
`MaIndependentEntries.mqh`, new `LabNativeTradeVisuals.mqh`, and README copied.
SHA256 matched for every copied file. Recursive quoted-include verification
also matched all 59 source/header files already in the destination.
The trading terminal was not restarted and other EA families were not deployed.
