# Regime Leaderboard

EA: `OrbUltimateEA_StrategyLibrary.mq5`, version 3.53.

1. Open LEADERBOARD.
2. The model button cycles VANILLA / LEGACY / R7 as before.
3. The new REGIME button cycles ALL / TREND LOW VOL / TREND HIGH VOL /
   RANGE LOW VOL / RANGE HIGH VOL / TRANSITION PENDING / TRANSITION FRESH.
4. Rows are reranked for that model + regime. N, W/L, WR, net R and closed DD R
   are shown. Flat count and the R7 package revision appear in the row tooltip.
5. Click a row to apply its strategy using the existing guarded application path.

The selected leaderboard regime is DISPLAY-ONLY: it does not enable/block any
live regime or change ML generation/ON/OFF. Existing execution settings remain
controlled by their original dashboard controls. Browsing modes cannot send orders.

Score remains `100 * Wilson lower WR / (1 + closed-trade DD R)`. In regime views,
N >= 30 is ranked before LOW N. No trades is shown explicitly, not as a loss/zero WR.
The ALL view retains the previous comparison behavior. Reopen the popup or cycle
a selector to refresh reports after deploying a newly evaluated model package.

## Campaign Scope

- 53 strategies, 53 Vanilla + 50 Legacy + 52 R7 = 155 available strategy/mode pairs.
- 930 six-regime cells, plus ALL and UNKNOWN reconciliation cells.
- Same 5Y completed candidate CSVs: 2021-09-15 to 2026-09-09 (broker time).
- Original signal-feature regime is used, including for delayed execution.
- Same existing model weights and thresholds; no new training or promotion.
- Detailed symbol-specific leaders and annual diagnostics:
  `logs/OrbRegimeLeaderboard_20260912/Results.md`.
- All metrics/provenance: `logs/OrbRegimeLeaderboard_20260912/campaign.json`.

**ML comparisons include training data; these are NOT OOS results.** This is
retrospective filtering of completed candidate trades, not a fresh MT5 tick replay.
Selecting the best among hundreds of cells adds selection bias. Neither N>=30 nor
the Wilson/DD score proves future profitability or independence of correlated trades.
Use the leaders as research candidates, not automatic production regime allocation.
Existing preset regime exclusions can leave zero candidates in a regime; such a cell
does not tell us how the unrestricted strategy would perform there.

## Model Swap Compatibility

Reports live in Common Files `OrbML/RegimeLeaderboard/` and bind strategy, config,
dataset, model SHA, mode, feature schema and dates. R7 reads the currently assigned
slot's hash; a swapped artifact cannot inherit the previous model's regime metrics.
Until a matching report exists, the popup shows unavailable. Legacy artifacts are
also hash-checked before using their regime report.

Regenerate without retraining or activating a model:

```powershell
python scripts/orb_regime_leaderboard.py
python scripts/verify_orb_regime_leaderboard.py
```

This evaluates current assigned slot packages against the frozen strategy datasets.
It aborts on a strategy/config/dataset mismatch or inputs changing during the run.
New CSV campaigns require a matching base leaderboard snapshot as well.

Models, listener protocols, channels, live regime math and signal-generation code
were not modified for this feature. Reports are cached when the popup is refreshed;
no new per-tick inference or historical audit work was added.
